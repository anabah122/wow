-- gltf.lua — minimal glTF 2.0 / GLB loader
-- returns raw vertex/index data, no love.graphics calls
--
-- gltf.load(path) -> { [i] = { name, vertices, indices, attributes } }
--
-- vertices  : array of { x,y,z, nx,ny,nz, u,v }   (missing attrs = 0)
-- indices   : array of ints (1-based), nil if not indexed
-- attributes: { position=true, normal=true, texcoord=true } presence flags

local ffi      = require "ffi"
local matClass = require "math.mat4"

local gltf = {}

-- ── JSON ─────────────────────────────────────────────────────────────────────
-- tiny recursive-descent JSON parser (no deps)
local json = {}
do
    local function skip(s, i)
        while i <= #s and s:byte(i) <= 32 do i = i + 1 end
        return i
    end

    local parse_value  -- forward

    local function parse_string(s, i)
        assert(s:byte(i) == 34, "expected \"")
        i = i + 1
        local parts = {}
        while true do
            local j = i
            while j <= #s and s:byte(j) ~= 34 and s:byte(j) ~= 92 do j = j + 1 end
            parts[#parts+1] = s:sub(i, j-1)
            if s:byte(j) == 34 then return table.concat(parts), j+1 end
            -- escape
            local e = s:byte(j+1)
            if     e == 110 then parts[#parts+1] = "\n"
            elseif e == 116 then parts[#parts+1] = "\t"
            elseif e == 114 then parts[#parts+1] = "\r"
            elseif e == 92  then parts[#parts+1] = "\\"
            elseif e == 34  then parts[#parts+1] = "\""
            elseif e == 47  then parts[#parts+1] = "/"
            elseif e == 117 then
                local hex = tonumber(s:sub(j+2, j+5), 16) or 0
                parts[#parts+1] = utf8 and utf8.char(hex) or "?"
                j = j + 4
            end
            i = j + 2
        end
    end

    local function parse_number(s, i)
        local j = i
        if s:byte(j) == 45 then j = j + 1 end          -- -
        while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
        if j <= #s and s:byte(j) == 46 then j = j + 1  -- .
            while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
        end
        if j <= #s and (s:byte(j) == 101 or s:byte(j) == 69) then -- e/E
            j = j + 1
            if s:byte(j) == 43 or s:byte(j) == 45 then j = j + 1 end
            while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
        end
        return tonumber(s:sub(i, j-1)), j
    end

    local function parse_array(s, i)
        assert(s:byte(i) == 91)  -- [
        i = skip(s, i+1)
        local arr = {}
        if s:byte(i) == 93 then return arr, i+1 end
        while true do
            local v; v, i = parse_value(s, i)
            arr[#arr+1] = v
            i = skip(s, i)
            local c = s:byte(i)
            if c == 93 then return arr, i+1 end
            assert(c == 44, "expected , or ]")
            i = skip(s, i+1)
        end
    end

    local function parse_object(s, i)
        assert(s:byte(i) == 123)  -- {
        i = skip(s, i+1)
        local obj = {}
        if s:byte(i) == 125 then return obj, i+1 end
        while true do
            local k; k, i = parse_string(s, i)
            i = skip(s, i)
            assert(s:byte(i) == 58, "expected :")  -- :
            i = skip(s, i+1)
            local v; v, i = parse_value(s, i)
            obj[k] = v
            i = skip(s, i)
            local c = s:byte(i)
            if c == 125 then return obj, i+1 end
            assert(c == 44, "expected , or }")
            i = skip(s, i+1)
        end
    end

    parse_value = function(s, i)
        i = skip(s, i)
        local c = s:byte(i)
        if c == 34  then return parse_string(s, i)
        elseif c == 91  then return parse_array(s, i)
        elseif c == 123 then return parse_object(s, i)
        elseif c == 116 then return true,  i+4   -- true
        elseif c == 102 then return false, i+5   -- false
        elseif c == 110 then return nil,   i+4   -- null  (returns nil,pos)
        else return parse_number(s, i)
        end
    end

    function json.decode(s)
        local v = select(1, parse_value(s, 1))
        return v
    end
end

-- ── binary helpers ────────────────────────────────────────────────────────────
local COMPONENT_BYTES = { [5120]=1,[5121]=1,[5122]=2,[5123]=2,[5125]=4,[5126]=4 }
local COMPONENT_TYPE  = {
    [5120]="int8_t", [5121]="uint8_t", [5122]="int16_t",
    [5123]="uint16_t",[5125]="uint32_t",[5126]="float",
}
local TYPE_COUNT = { SCALAR=1,VEC2=2,VEC3=3,VEC4=4,MAT2=4,MAT3=9,MAT4=16 }

local function read_file(path)
    -- try love.filesystem first (relative paths inside game dir)
    local data, err = love.filesystem.read(path)
    if data then return data end
    -- fallback to io for absolute paths
    local f = assert(io.open(path, "rb"), "cannot open "..path..": "..(err or ""))
    local s = f:read("*a")
    f:close()
    return s
end

-- decode little-endian uint32 from string at byte offset (1-based)
local function u32(s, pos)
    local a,b,c,d = s:byte(pos, pos+3)
    return a + b*256 + c*65536 + d*16777216
end

-- ── GLB parser ────────────────────────────────────────────────────────────────
local function load_glb(data)
    -- header: magic(4) version(4) length(4)
    local version = u32(data, 5)
    assert(version == 2, "only glTF 2.0 GLB supported")

    local json_str, bin_data
    local pos = 13  -- first chunk starts here
    while pos <= #data do
        local chunk_len  = u32(data, pos)
        local chunk_type = u32(data, pos+4)
        local chunk_data = data:sub(pos+8, pos+8+chunk_len-1)
        if chunk_type == 0x4E4F534A then  -- JSON
            json_str = chunk_data
        elseif chunk_type == 0x004E4942 then  -- BIN
            bin_data = chunk_data
        end
        pos = pos + 8 + chunk_len
    end

    assert(json_str, "no JSON chunk in GLB")
    return json_str, bin_data
end

-- ── accessor reading ──────────────────────────────────────────────────────────
local function get_accessor_data(j, buffers, acc_idx)
    local acc = j.accessors[acc_idx + 1]
    assert(acc, "accessor "..acc_idx.." missing")

    local elem_count  = TYPE_COUNT[acc.type]
    local comp_bytes  = COMPONENT_BYTES[acc.componentType]
    local ctype       = COMPONENT_TYPE[acc.componentType]
    local total_count = acc.count  -- number of elements (vertices or indices)

    -- buffer view
    local bv_idx = acc.bufferView
    if bv_idx == nil then
        -- all zeros (sparse base)
        return nil, elem_count, ctype, total_count
    end

    local bv   = j.bufferViews[bv_idx + 1]
    local buf  = buffers[bv.buffer + 1]
    local bv_offset = bv.byteOffset or 0
    local acc_offset = acc.byteOffset or 0
    local stride = bv.byteStride or (comp_bytes * elem_count)

    -- copy data into a fresh byte string (handling stride)
    local elem_bytes = comp_bytes * elem_count
    local result
    if stride == elem_bytes then
        local start = bv_offset + acc_offset + 1
        result = buf:sub(start, start + elem_bytes * total_count - 1)
    else
        -- de-stride
        local parts = {}
        local base = bv_offset + acc_offset
        for i = 0, total_count - 1 do
            local s = base + i * stride + 1
            parts[i+1] = buf:sub(s, s + elem_bytes - 1)
        end
        result = table.concat(parts)
    end

    return result, elem_count, ctype, total_count
end

local function read_floats(raw, elem_count, count)
    local arr = ffi.cast("float*", ffi.cast("void*",
        ffi.cast("const char*", raw)))
    -- build lua table
    local out = {}
    for i = 0, count * elem_count - 1 do
        out[i+1] = arr[i]
    end
    return out
end

local function read_indices(raw, ctype, count)
    local ptr
    if ctype == "uint16_t" then
        ptr = ffi.cast("uint16_t*", ffi.cast("void*", ffi.cast("const char*", raw)))
    elseif ctype == "uint32_t" then
        ptr = ffi.cast("uint32_t*", ffi.cast("void*", ffi.cast("const char*", raw)))
    elseif ctype == "uint8_t" then
        ptr = ffi.cast("uint8_t*",  ffi.cast("void*", ffi.cast("const char*", raw)))
    else
        error("unsupported index type: "..ctype)
    end
    local out = {}
    for i = 0, count - 1 do
        out[i+1] = ptr[i] + 1  -- convert to 1-based
    end
    return out
end

-- ── main load ─────────────────────────────────────────────────────────────────
function gltf.load(args)
    local path     = args.path
    local withMesh   = args.mesh or false
    local withTex    = args.tex  or false
    local anisotropy = args.anisotropy or 1

    local data = read_file(path)

    local json_str, bin_embedded
    if data:sub(1,4) == "glTF" then
        json_str, bin_embedded = load_glb(data)
    else
        json_str = data
    end

    local j = json.decode(json_str)
    assert(j and j.asset and j.asset.version == "2.0", "not a glTF 2.0 file")

    -- load buffers
    local buffers = {}
    for i, buf in ipairs(j.buffers or {}) do
        if buf.uri == nil then
            -- GLB embedded binary
            buffers[i] = assert(bin_embedded, "GLB has no BIN chunk")
        elseif buf.uri:sub(1,5) == "data:" then
            -- data URI  base64
            local b64 = buf.uri:match("base64,(.+)$")
            assert(b64, "unrecognised data URI")
            buffers[i] = love.data.decode("string", "base64", b64)
        else
            -- external file
            local dir = path:match("(.*[/\\])") or ""
            buffers[i] = read_file(dir .. buf.uri)
        end
    end

    -- build mesh_idx -> node transform table
    local node_transforms = {}  -- [mesh_idx+1] = {t={x,y,z}, r={x,y,z,w}, s={x,y,z}}
    for _, node in ipairs(j.nodes or {}) do
        if node.mesh ~= nil then
            local trs = {}
            if node.matrix then
                trs.matrix = node.matrix
            else
                trs.t = node.translation or {0,0,0}
                trs.r = node.rotation    or {0,0,0,1}
                trs.s = node.scale       or {1,1,1}
            end
            node_transforms[node.mesh + 1] = trs
        end
    end

    local result = {}

    for mesh_i, mesh_json in ipairs(j.meshes or {}) do
        local trs = node_transforms[mesh_i] or { t={0,0,0}, r={0,0,0,1}, s={1,1,1} }
        for prim_i, prim in ipairs(mesh_json.primitives or {}) do
            local entry = {
                name       = mesh_json.name or ("mesh_"..mesh_i),
                vertices   = {},
                indices    = nil,
                attributes = {},
                trs        = trs,
            }

            local attribs = prim.attributes or {}

            -- positions (required)
            local pos_raw, pos_elems, _, pos_count
            if attribs.POSITION then
                pos_raw, pos_elems, _, pos_count =
                    get_accessor_data(j, buffers, attribs.POSITION)
                entry.attributes.position = true
            end
            if not pos_raw then
                -- skip primitives without geometry (cameras, lights, etc.)
                goto continue
            end

            local positions = read_floats(pos_raw, pos_elems, pos_count)

            -- normals (optional)
            local normals = nil
            if attribs.NORMAL then
                local raw, ne, _, nc = get_accessor_data(j, buffers, attribs.NORMAL)
                if raw then
                    normals = read_floats(raw, ne, nc)
                    entry.attributes.normal = true
                end
            end

            -- texcoords (optional)
            local uvs = nil
            if attribs.TEXCOORD_0 then
                local raw, ne, _, nc = get_accessor_data(j, buffers, attribs.TEXCOORD_0)
                if raw then
                    uvs = read_floats(raw, ne, nc)
                    entry.attributes.texcoord = true
                end
            end

            -- build interleaved vertex table
            for vi = 0, pos_count - 1 do
                local px = positions[vi*3+1] or 0
                local py = positions[vi*3+2] or 0
                local pz = positions[vi*3+3] or 0
                local nx = normals and normals[vi*3+1] or 0
                local ny = normals and normals[vi*3+2] or 0
                local nz = normals and normals[vi*3+3] or 0
                local u  = uvs and uvs[vi*2+1] or 0
                local v  = uvs and uvs[vi*2+2] or 0
                entry.vertices[vi+1] = { px, py, pz, nx, ny, nz, u, v }
            end

            -- indices (optional)
            if prim.indices ~= nil then
                local raw, _, ctype, count =
                    get_accessor_data(j, buffers, prim.indices)
                if raw then
                    entry.indices = read_indices(raw, ctype, count)
                end
            end

            -- material
            if prim.material ~= nil then
                local mat = (j.materials or {})[prim.material + 1]
                if mat then
                    local pbr = mat.pbrMetallicRoughness or {}
                    entry.material = {
                        name      = mat.name,
                        baseColor = pbr.baseColorFactor or {1,1,1,1},
                    }
                    if withTex and pbr.baseColorTexture then
                        local tex_idx = pbr.baseColorTexture.index + 1
                        local tex_json = (j.textures or {})[tex_idx]
                        if tex_json and tex_json.source then
                            local img_json = (j.images or {})[tex_json.source + 1]
                            if img_json then
                                if img_json.uri then
                                    local dir = path:match("(.*[/\\])") or ""
                                    entry.material.texturePath = dir .. img_json.uri
                                    entry.material.texture = love.graphics.newImage(entry.material.texturePath, { mipmaps = true })
                                    entry.material.texture:setFilter("linear", "linear", anisotropy)
                                elseif img_json.bufferView then
                                    local raw = get_accessor_data(j, buffers, img_json.bufferView)
                                    -- bufferView directly, not accessor — read manually
                                    local bv  = j.bufferViews[img_json.bufferView + 1]
                                    local buf = buffers[bv.buffer + 1]
                                    local bytes = buf:sub((bv.byteOffset or 0)+1, (bv.byteOffset or 0)+bv.byteLength)
                                    local fd = love.filesystem.newFileData(bytes, img_json.name or "tex")
                                    entry.material.texture = love.graphics.newImage(love.image.newImageData(fd), { mipmaps = true })
                                    entry.material.texture:setFilter("linear", "linear", anisotropy)
                                end
                            end
                        end
                    end
                end
            end

            result[#result+1] = entry
            ::continue::
        end
    end

    local withTransform = args.transform ~= false  -- default true

    for _, entry in ipairs(result) do
        if withTransform then
            local trs = entry.trs
            entry.transform = matClass:new():setTransformationMatrix(trs.t, trs.r, trs.s)
        end
        if withMesh then
            entry.mesh = gltf.to_mesh(entry)
            local tex = entry.material and entry.material.texture
            if tex then entry.mesh:setTexture(tex) end
        end
    end

    return result
end

-- ── convenience: build love.Mesh from a loaded entry ─────────────────────────
-- call inside love.load or love.draw
function gltf.to_mesh(entry, usage)
    usage = usage or "static"
    local fmt = {
        { "VertexPosition", "float", 3 },
        { "VertexNormal",   "float", 3 },
        { "VertexTexCoord", "float", 2 },
    }
    local m = love.graphics.newMesh(fmt, entry.vertices, "triangles", usage)
    if entry.indices then
        m:setVertexMap(entry.indices)
    end
    return m
end


return gltf
