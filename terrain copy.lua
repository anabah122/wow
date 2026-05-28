require 'lib.FRAMELOOP'
require 'lib.overloads'

local ffi = require 'ffi'

-- ── ADT 3.3.5a parser ──────────────────────────────────────────────────────
-- читаем один .adt: 256 MCNK (16x16), у каждого 145 высот в MCVT.
-- высота вершины = MCNK.posZ + MCVT[i].
-- держим CPU-представление (ffi float buffer) и GPU-текстуру из ОДНИХ данных.

local terrainShader = LG.newShader('shader/wow.glsl')

local WHITE = (function()
    local d = love.image.newImageData(1, 1)
    d:setPixel(0, 0, 1, 0, 1, 1)  -- magenta = «текстуры нет»
    return LG.newImage(d)
end)()

local CHUNKS   = 16          -- MCNK на сторону тайла
local UNIT     = 33.33333 / 8  -- расстояние между вершинами (yard)
local TILE     = 533.33333   -- размер тайла в ярдах
local OUTER    = 9           -- внешняя сетка MCNK
local DENSE    = OUTER        -- кладём только внешние 9x9 в текстуру -> 16*8+1 = 129
local GRID     = CHUNKS * (OUTER - 1) + 1  -- 129 вершин на сторону тайла

-- magic в файле записан реверснутым: 'MCNK' лежит как 'KNCM'
local function fourcc(s, pos)
    return s:sub(pos+3, pos+3) .. s:sub(pos+2, pos+2) .. s:sub(pos+1, pos+1) .. s:sub(pos, pos)
end

local function u32(s, pos)
    local a, b, c, d = s:byte(pos, pos+3)
    return a + b*256 + c*65536 + d*16777216
end

-- проход по top-level чанкам, возвращает { tag = { off=dataStart1based, size } }
local function scanChunks(s, from, to)
    local out = {}
    local pos = from
    while pos < to do
        local tag  = fourcc(s, pos)
        local size = u32(s, pos+4)
        out[#out+1] = { tag = tag, off = pos + 8, size = size }
        pos = pos + 8 + size
    end
    return out
end

-- 'Tileset\Hyjal\Name.blp' -> love.Image из assets/Tileset/Hyjal/Name.png (кэш)
local texCache = {}
local function loadTexture(blpPath)
    local png = 'assets/' .. blpPath:gsub('\\', '/'):gsub('%.blp$', '.png')
    if texCache[png] ~= nil then return texCache[png] or nil end
    local ok, img = pcall(function()
        local t = LG.newImage(png)
        t:setWrap('repeat', 'repeat')
        t:setFilter('linear', 'linear')
        return t
    end)
    texCache[png] = ok and img or false
    if not ok then print('no texture: ' .. png) end
    return texCache[png] or nil
end

-- MCAL: распаковать альфа-маску слоя в 64x64 байт (0..255).
-- compressed=true -> RLE (флаг MCLY 0x200); иначе uncompressed 4-бит (2048 байт).
local function readAlpha(s, off, compressed)  -- off — 1-based начало маски
    local out = {}  -- [y*64+x+1]
    if compressed then
        -- RLE: байт = (fill<<7)|count; fill -> повтор следующего, copy -> count байт подряд
        local o = 0  -- сколько байт уже записано
        local p = off
        while o < 64*64 do
            local ctl  = s:byte(p); p = p + 1
            local fill = ctl >= 0x80
            local n    = ctl % 0x80
            if fill then
                local v = s:byte(p); p = p + 1
                for _ = 1, n do out[o+1] = v; o = o + 1 end
            else
                for _ = 1, n do out[o+1] = s:byte(p); p = p + 1; o = o + 1 end
            end
        end
    else
        -- 4-бит: байт = два пикселя, младший первый, нормализация v*17
        local p = off
        for i = 0, 64*64/2 - 1 do
            local b = s:byte(p + i)
            out[i*2+1] = (b % 16) * 17
            out[i*2+2] = math.floor(b / 16) * 17
        end
    end
    return out
end

local Terrain = {}
Terrain.__index = Terrain

function Terrain:new()
    return setmetatable({ tiles = {} }, Terrain)
end

-- читает один adt, возвращает tile { heights (ffi float*), image, tx, ty }
function Terrain:loadTile(path, tx, ty)
    local s = assert(love.filesystem.read(path), 'cannot read ' .. path)

    -- top-level чанки лежат подряд от начала файла
    local top = scanChunks(s, 1, #s + 1)

    -- найдём MCNK по порядку (их 256, индекс = ty*16+tx внутри тайла)
    local mcnks = {}
    local textures = {}
    for _, c in ipairs(top) do
        if c.tag == 'MCNK' then
            mcnks[#mcnks+1] = c
        elseif c.tag == 'MTEX' then
            -- список путей .blp, разделённых \0
            local blob = s:sub(c.off, c.off + c.size - 1)
            for p in blob:gmatch('[^%z]+') do textures[#textures+1] = p end
        end
    end
    assert(#mcnks == 256, 'expected 256 MCNK, got ' .. #mcnks)

    -- плотная сетка высот 129x129, r32f
    local id  = love.image.newImageData(GRID, GRID, 'r32f')
    local ptr = ffi.cast('float*', id:getFFIPointer())

    local chunks = {}

    for ci, mc in ipairs(mcnks) do
        local hOff = mc.off
        local base = hOff - 8  -- ofs* в хедере отсчитываются отсюда (от magic)
        local posZ = ffi.cast('float*', ffi.cast('const char*', s) + (hOff - 1) + 0x70)[0]

        -- MCVT: первый под-чанк за 128-байтным хедером: 128 + magic/size(8) = 136
        local vptr = ffi.cast('float*', ffi.cast('const char*', s) + (hOff + 136 - 1))

        local nLayers = u32(s, hOff + 0x0C)
        local ofsMCLY = u32(s, hOff + 0x1C)
        local ofsMCAL = u32(s, hOff + 0x24)

        -- слои: текстуры + альфа-маска (3 наложенных слоя -> RGB одной текстуры)
        local layerTex = {}
        local alphaData = love.image.newImageData(64, 64, 'rgba8')
        for L = 0, nLayers - 1 do
            local rOff   = base + ofsMCLY + 8 + L * 16
            local texId  = u32(s, rOff)
            local flags  = u32(s, rOff + 4)
            local aOff   = u32(s, rOff + 8)
            layerTex[L+1] = loadTexture(textures[texId + 1] or '')
            local useAlpha   = math.floor(flags / 0x100) % 2 == 1
            local compressed = math.floor(flags / 0x200) % 2 == 1
            if L > 0 and useAlpha then
                -- aOff относителен данных MCAL (после его magic+size 8 байт)
                local a = readAlpha(s, base + ofsMCAL + 8 + aOff, compressed)
                for py = 0, 63 do
                    for px = 0, 63 do
                        local r, g, b, _ = alphaData:getPixel(px, py)
                        local v = a[py*64 + px + 1] / 255
                        if     L == 1 then r = v
                        elseif L == 2 then g = v
                        elseif L == 3 then b = v end
                        alphaData:setPixel(px, py, r, g, b, 1)
                    end
                end
            end
        end

        local cx = (ci - 1) % CHUNKS
        local cy = math.floor((ci - 1) / CHUNKS)

        -- высоты: внешние 9x9 в общую сетку тайла
        for row = 0, OUTER - 1 do
            for col = 0, OUTER - 1 do
                local h  = vptr[row * 17 + col]
                local gx = cx * (OUTER - 1) + col
                local gy = cy * (OUTER - 1) + row
                ptr[gy * GRID + gx] = posZ + h
            end
        end

        local alphaTex = LG.newImage(alphaData)
        alphaTex:setWrap('clamp')
        chunks[ci] = { cx = cx, cy = cy, nLayers = nLayers, tex = layerTex, alpha = alphaTex }
    end

    local img = LG.newImage(id)
    img:setFilter('linear', 'linear')
    img:setWrap('clamp')

    return { heights = ptr, imageData = id, image = img, tx = tx, ty = ty, textures = textures, chunks = chunks }
end

-- загрузить все .adt из директории по их именам <map>_<tx>_<ty>.adt
function Terrain:loadTiles(dir)
    for _, name in ipairs(LF.getDirectoryItems(dir)) do
        local tx, ty = name:match('_(%d+)_(%d+)%.adt$')
        if tx then
            local tile = self:loadTile(dir .. '/' .. name, tonumber(tx), tonumber(ty))
            self:buildMesh(tile)
            self.tiles[#self.tiles+1] = tile
        end
    end
    print('loaded tiles: ' .. #self.tiles)

    local seen, list = {}, {}
    for _, t in ipairs(self.tiles) do
        for _, p in ipairs(t.textures) do
            if not seen[p] then seen[p] = true; list[#list+1] = p end
        end
    end
    table.sort(list)
    print('unique textures: ' .. #list)
    print('  sample: ' .. (list[1] or ''))
end

-- меш на каждый MCNK: 9x9 вершин.
-- VertexTexCoord.xy = локальный UV чанка (альфа-маска),
-- VertexTexCoord.zw = непрерывный UV тайла (текстуры, тайлятся через границы).
local FMT = { { 'VertexTexCoord', 'float', 4 }, { 'VertexPosition', 'float', 3 } }

function Terrain:buildMesh(tile)
    local ptr = tile.heights
    local ox  = tile.tx * TILE
    local oz  = tile.ty * TILE

    -- индексный буфер 9x9 общий для всех чанков
    local map = {}
    for ry = 0, OUTER - 2 do
        for rx = 0, OUTER - 2 do
            local a = ry * OUTER + rx + 1
            local b = a + 1
            local c = a + OUTER
            local d = c + 1
            map[#map+1] = a; map[#map+1] = c; map[#map+1] = b
            map[#map+1] = b; map[#map+1] = c; map[#map+1] = d
        end
    end

    for _, ch in ipairs(tile.chunks) do
        local verts = {}
        for row = 0, OUTER - 1 do
            for col = 0, OUTER - 1 do
                local gx = ch.cx * (OUTER - 1) + col
                local gy = ch.cy * (OUTER - 1) + row
                local h  = ptr[gy * GRID + gx]
                -- локальный UV чанка для альфа-маски, с инсетом полтекселя
                -- (маска 64x64 покрывает чанк; без инсета края чанков рвутся)
                local au = (col / (OUTER - 1)) * (63/64) + 0.5/64
                local av = (row / (OUTER - 1)) * (63/64) + 0.5/64
                -- непрерывный UV тайла для текстур (0..1 по всему тайлу)
                local tu = gx / (GRID - 1)
                local tv = gy / (GRID - 1)
                verts[#verts+1] = { au, av, tu, tv, ox + gx * UNIT, h, oz + gy * UNIT }
            end
        end
        local m = LG.newMesh(FMT, verts, 'triangles', 'static')
        m:setVertexMap(map)
        ch.mesh = m
    end
end

local TEX_TILE = CHUNKS * 8  -- повторов текстуры на весь тайл (8 на чанк)

function Terrain:draw(camera)
    local shader = terrainShader
    LG.setShader(shader)
    shader:send('viewproj', camera:viewproj())
    shader:send('texTile', TEX_TILE)
    for _, t in ipairs(self.tiles) do
        for _, ch in ipairs(t.chunks) do
            shader:send('nLayers', ch.nLayers)
            shader:send('alphaMap', ch.alpha)
            local base = ch.tex[1]
            for L = 1, 4 do
                shader:send('layer' .. L, ch.tex[L] or base or WHITE)
            end
            LG.draw(ch.mesh)
        end
    end
    LG.setShader()
end

return Terrain
