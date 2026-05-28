require 'lib.overloads'

local ffi = require 'ffi'

-- ── ADT 3.3.5a importer ──────────────────────────────────────────────────────
-- один импортер = один .adt (тайл) = 16x16 MCNK.
-- step(budget) парсит MCNK по мере бюджета, отдаёт готовые чанки пачкой,
-- yield'ит когда бюджет кадра исчерпан. done() — когда все 256 готовы.
-- из каждого MCNK берём: MCVT (высоты), MCNR (нормали), MCLY/MCAL (слои+маски).

local CHUNKS = 16             -- MCNK на сторону тайла
local UNIT   = 33.33333 / 8   -- расстояние между вершинами (yard)
local TILE   = 533.33333      -- размер тайла в ярдах
local OUTER  = 9              -- внешняя сетка MCNK
local GRID   = CHUNKS * (OUTER - 1) + 1  -- 129 вершин на сторону тайла

local FMT = {
    { 'VertexTexCoord', 'float', 4 },  -- xy = альфа-UV (локальный), zw = текстур-UV (тайл)
    { 'VertexPosition', 'float', 3 },
    { 'VertexNormal',   'float', 3 },
}

-- magic в файле записан реверснутым: 'MCNK' лежит как 'KNCM'
local function fourcc(s, pos)
    return s:sub(pos+3, pos+3) .. s:sub(pos+2, pos+2) .. s:sub(pos+1, pos+1) .. s:sub(pos, pos)
end

local function u32(s, pos)
    local a, b, c, d = s:byte(pos, pos+3)
    return a + b*256 + c*65536 + d*16777216
end

local function scanChunks(s, from, to)
    local out = {}
    local pos = from
    while pos < to do
        local size = u32(s, pos+4)
        out[#out+1] = { tag = fourcc(s, pos), off = pos + 8, size = size }
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

-- MCAL: распаковать альфа-маску слоя прямо в канал dst (uint8_t*, stride 4, +ch).
-- compressed -> RLE (флаг MCLY 0x200); иначе uncompressed 4-бит (2048 байт).
local function readAlpha(sp, off, compressed, dst, ch)  -- sp: const uint8_t*, off: 0-based
    local d = dst + ch
    if compressed then
        local o, p = 0, off
        while o < 64*64 do
            local ctl = sp[p]; p = p + 1
            if ctl >= 0x80 then
                local v = sp[p]; p = p + 1
                for _ = 1, ctl - 0x80 do d[o*4] = v; o = o + 1 end
            else
                for _ = 1, ctl do d[o*4] = sp[p]; p = p + 1; o = o + 1 end
            end
        end
    else
        for i = 0, 64*64/2 - 1 do
            local b = sp[off + i]
            d[(i*2)*4]   = (b % 16) * 17
            d[(i*2+1)*4] = math.floor(b / 16) * 17
        end
    end
end

local Tile = require 'class.terrainTile'

local Importer = {}
Importer.__index = Importer

function Importer:new(path)
    local self = setmetatable({}, Importer)
    self.path = path
    local tx, ty = path:match('_(%d+)_(%d+)%.adt$')
    self.tx, self.ty = tonumber(tx), tonumber(ty)
    self.tile = Tile:new(self.tx, self.ty)  -- наполняется по мере парсинга
    self.finished = false
    self.co = coroutine.create(function() self:run() end)
    return self
end

-- парсит один MCNK, добавляет готовый чанк в self.ready
function Importer:parseMcnk(s, sp, mc, ox, oz)
    local hOff = mc.off
    local base = hOff - 8
    local posZ = ffi.cast('float*', ffi.cast('const char*', s) + (hOff - 1) + 0x70)[0]
    local vptr = ffi.cast('float*', ffi.cast('const char*', s) + (hOff + 136 - 1))

    local nLayers = u32(s, hOff + 0x0C)
    local ofsMCNR = u32(s, hOff + 0x18)
    local ofsMCLY = u32(s, hOff + 0x1C)
    local ofsMCAL = u32(s, hOff + 0x24)
    local nptr = ffi.cast('int8_t*', ffi.cast('const char*', s) + (base + ofsMCNR + 8 - 1))

    local ci = mc.index
    local cx = (ci - 1) % CHUNKS
    local cy = math.floor((ci - 1) / CHUNKS)

    -- слои: текстуры per-chunk + альфа-маска 64x64 (R/G/B = слои 1/2/3).
    -- пишем прямо в ffi-указатель ImageData, без setPixel.
    local layerTex = {}
    local alphaData = love.image.newImageData(64, 64, 'rgba8')
    local aptr = ffi.cast('uint8_t*', alphaData:getFFIPointer())
    ffi.fill(aptr, 64*64*4, 0)
    for i = 0, 64*64 - 1 do aptr[i*4 + 3] = 255 end
    for L = 0, nLayers - 1 do
        local rOff  = base + ofsMCLY + 8 + L * 16
        local texId = u32(s, rOff)
        local flags = u32(s, rOff + 4)
        local aOff  = u32(s, rOff + 8)
        layerTex[L+1] = loadTexture(self.textures[texId + 1] or '')
        local useAlpha   = math.floor(flags / 0x100) % 2 == 1
        local compressed = math.floor(flags / 0x200) % 2 == 1
        if L > 0 and useAlpha then
            readAlpha(sp, base + ofsMCAL + 8 + aOff - 1, compressed, aptr, L - 1)
        end
    end
    local alphaTex = LG.newImage(alphaData)
    alphaTex:setWrap('clamp')

    -- вершины 9x9: позиция + альфа-UV (локальный 0..1) + текстур-UV + нормаль
    local verts = {}
    for row = 0, OUTER - 1 do
        for col = 0, OUTER - 1 do
            local i = row * 17 + col
            local gx = cx * (OUTER - 1) + col
            local gy = cy * (OUTER - 1) + row
            local au = (col / (OUTER - 1)) * (63/64) + 0.5/64
            local av = (row / (OUTER - 1)) * (63/64) + 0.5/64
            local tu = gx / (GRID - 1)
            local tv = gy / (GRID - 1)
            verts[#verts+1] = {
                au, av, tu, tv,
                ox + gx * UNIT, posZ + vptr[i], oz + gy * UNIT,
                nptr[i*3] / 127, nptr[i*3+2] / 127, nptr[i*3+1] / 127,
            }
        end
    end
    local mesh = LG.newMesh(FMT, verts, 'triangles', 'static')
    mesh:setVertexMap(self.indexMap)

    -- центр чанка в мире (для дистанционного culling)
    local mcnkSize = TILE / CHUNKS
    local mx = ox + (cx + 0.5) * mcnkSize
    local mz = oz + (cy + 0.5) * mcnkSize
    self.tile:addChunk{ nLayers = nLayers, tex = layerTex, alpha = alphaTex, mesh = mesh, cx = mx, cz = mz }
end

-- тело корутины: читает файл, сканит MCNK, парсит каждый с прерыванием по бюджету
function Importer:run()
    local s = assert(love.filesystem.read(self.path), 'cannot read ' .. self.path)
    local sp = ffi.cast('const uint8_t*', s)
    coroutine.yield()  -- чтение файла = отдельный шаг

    local top = scanChunks(s, 1, #s + 1)
    local mcnks = {}
    self.textures = {}
    for _, c in ipairs(top) do
        if c.tag == 'MCNK' then
            mcnks[#mcnks+1] = c
            c.index = #mcnks
        elseif c.tag == 'MTEX' then
            local blob = s:sub(c.off, c.off + c.size - 1)
            for p in blob:gmatch('[^%z]+') do self.textures[#self.textures+1] = p end
        end
    end

    -- индексный буфер 9x9 общий для всех чанков тайла
    self.indexMap = {}
    for ry = 0, OUTER - 2 do
        for rx = 0, OUTER - 2 do
            local a = ry * OUTER + rx + 1
            local b, c, d = a + 1, a + OUTER, a + OUTER + 1
            local m = self.indexMap
            m[#m+1] = a; m[#m+1] = c; m[#m+1] = b
            m[#m+1] = b; m[#m+1] = c; m[#m+1] = d
        end
    end

    local ox, oz = self.tx * TILE, self.ty * TILE
    for _, mc in ipairs(mcnks) do
        self:parseMcnk(s, sp, mc, ox, oz)
        if love.timer.getTime() >= self.deadline then coroutine.yield() end
    end
end

-- продвинуть импорт в рамках бюджета (сек). чанки добавляются прямо в self.tile.
function Importer:step(budget)
    self.deadline = love.timer.getTime() + budget
    if coroutine.status(self.co) ~= 'dead' then
        local ok, err = coroutine.resume(self.co)
        if not ok then error(err) end
        if coroutine.status(self.co) == 'dead' then self.finished = true end
    end
end

function Importer:done()
    return self.finished
end

return Importer
