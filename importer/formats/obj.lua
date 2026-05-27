-- OBJ loader. Возвращает массив love.Mesh.
-- LOVE-индексация: одна индекс-вершина = уникальная пара (vi/ti/ni).

local M = {}

local VERTEX_FMT = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexNormal',   'float', 3 },
}

local function parseGroups(src)
    local positions, texcoords, normals = {}, {}, {}
    local groups = {}
    local cur = nil

    local function newGroup(name)
        cur = { name = name or 'default', verts = {}, indices = {}, lookup = {} }
        groups[#groups+1] = cur
    end

    local function addVert(vi, ti, ni)
        if not cur then newGroup() end
        local key = vi .. '/' .. (ti or 0) .. '/' .. (ni or 0)
        local idx = cur.lookup[key]
        if idx then return idx end
        local p = positions[vi]
        local t = ti and texcoords[ti] or { 0, 0 }
        local n = ni and normals[ni]   or { 0, 1, 0 }
        local vv = cur.verts
        idx = #vv + 1
        vv[idx] = { p[1], p[2], p[3], t[1], t[2], n[1], n[2], n[3] }
        cur.lookup[key] = idx
        return idx
    end

    for line in (src .. '\n'):gmatch('([^\n]*)\n') do
        local tag, rest = line:match('^%s*(%S+)%s*(.*)')
        if tag == 'v' then
            local x,y,z = rest:match('(%S+)%s+(%S+)%s+(%S+)')
            positions[#positions+1] = { tonumber(x), tonumber(y), tonumber(z) }
        elseif tag == 'vt' then
            local u,v = rest:match('(%S+)%s+(%S+)')
            texcoords[#texcoords+1] = { tonumber(u), 1 - tonumber(v) }
        elseif tag == 'vn' then
            local x,y,z = rest:match('(%S+)%s+(%S+)%s+(%S+)')
            normals[#normals+1] = { tonumber(x), tonumber(y), tonumber(z) }
        elseif tag == 'o' or tag == 'g' then
            newGroup(rest:match('^%s*(.-)%s*$'))
        elseif tag == 'f' then
            if not cur then newGroup() end
            local fv = {}
            for token in rest:gmatch('%S+') do
                local vi, ti, ni = token:match('^(%-?%d+)/?(%-?%d*)/?(%-?%d*)$')
                vi = tonumber(vi)
                ti = tonumber(ti) or nil
                ni = tonumber(ni) or nil
                if vi and vi < 0 then vi = #positions + vi + 1 end
                if ti and ti < 0 then ti = #texcoords + ti + 1 end
                if ni and ni < 0 then ni = #normals   + ni + 1 end
                fv[#fv+1] = addVert(vi, ti, ni)
            end
            local idxs = cur.indices
            for i = 2, #fv - 1 do
                idxs[#idxs+1] = fv[1]
                idxs[#idxs+1] = fv[i]
                idxs[#idxs+1] = fv[i+1]
            end
        end
    end

    return groups
end

function M:load(path)
    local src = assert(LF.read(path), 'OBJ not found: ' .. path)
    local groups = parseGroups(src)

    local meshes = {}
    for _, g in ipairs(groups) do
        if #g.verts > 0 and #g.indices > 0 then
            local mesh = LG.newMesh(VERTEX_FMT, g.verts, 'triangles', 'static')
            mesh:setVertexMap(g.indices)
            meshes[#meshes+1] = mesh
        end
    end
    return meshes
end

return M
