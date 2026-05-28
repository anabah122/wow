-- ── ADT 3.3.5a importer ──────────────────────────────────────────────────────
-- чистый парсинг тайла. БЕЗ love.graphics, БЕЗ глобалов — гоняется в воркер-треде.
-- importTile(path) -> { tx, ty, heightData, maskData, names, instances }
--   heightData : ImageData 129x129 r32f (высоты тайла)
--   maskData   : ImageData 512x512 rgba8 (альфа-маски, R/G/B = слои 1/2/3)
--   names      : список { path, data } текстур тайла (data = ImageData 256x256, для ArrayImage в main)
--   instances  : { {wx,wz, hu,hv, mu,mv, L1,L2,L3,L4, nLayers}, ... }
--     L1..L4 — ЛОКАЛЬНЫЕ индексы в names (0 = нет слоя); main ремапит в глобальные.
--   models     : { путь .m2, ... } — 1-based, индексируется doodad.model
--   doodads    : { {modelIdx, x,y,z, rx,ry,rz, scale}, ... } M2-инстансы (деревья/трава)
--     x,y,z — world-координаты; rx,ry,rz — поворот в радианах; scale — множитель.
-- требует в треде: require('love.image'), require('love.filesystem').

local ffi = require 'ffi'

local CHUNKS = 16
local UNIT   = 33.33333 / 8
local TILE   = 533.33333
local OUTER  = 9
local GRID   = CHUNKS * (OUTER - 1) + 1   -- 129
local MASK   = 32                          -- разрешение маски чанка
local MASKW  = CHUNKS * MASK               -- 512

-- magic в файле реверснут: 'MCNK' лежит как 'KNCM'
local function fourcc(s, pos)
    return s:sub(pos+3, pos+3) .. s:sub(pos+2, pos+2) .. s:sub(pos+1, pos+1) .. s:sub(pos, pos)
end

local function u32(s, pos)
    local a, b, c, d = s:byte(pos, pos+3)
    return a + b*256 + c*65536 + d*16777216
end

local function u16(s, pos)
    local a, b = s:byte(pos, pos+1)
    return a + b*256
end

local function f32(sp, pos)  -- pos 1-based в строке
    return ffi.cast('const float*', sp + (pos - 1))[0]
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

-- MCAL: альфа-маска слоя -> плоская таблица 64x64 (0..255)
local function readAlpha64(sp, off, compressed)
    local out = {}
    if compressed then
        local o, p = 0, off
        while o < 64*64 do
            local ctl = sp[p]; p = p + 1
            if ctl >= 0x80 then
                local v = sp[p]; p = p + 1
                for _ = 1, ctl - 0x80 do out[o+1] = v; o = o + 1 end
            else
                for _ = 1, ctl do out[o+1] = sp[p]; p = p + 1; o = o + 1 end
            end
        end
    else
        for i = 0, 64*64/2 - 1 do
            local b = sp[off + i]
            out[i*2+1] = (b % 16) * 17
            out[i*2+2] = math.floor(b / 16) * 17
        end
    end
    return out
end

-- 'Tileset\Hyjal\Name.blp' -> 'assets/Tileset/Hyjal/Name.png'
local function pngPath(blpPath)
    return 'assets/' .. blpPath:gsub('\\', '/'):gsub('%.blp$', '.png')
end

-- парсит один MCNK в общие буферы тайла
local function parseMcnk(s, sp, mc, ci, tx, ty, hp, mp, texList, texIdx, instances)
    local hOff = mc.off
    local base = hOff - 8
    local posZ = ffi.cast('float*', ffi.cast('const char*', s) + (hOff - 1) + 0x70)[0]
    local vptr = ffi.cast('float*', ffi.cast('const char*', s) + (hOff + 136 - 1))

    local nLayers = u32(s, hOff + 0x0C)
    local ofsMCLY = u32(s, hOff + 0x1C)
    local ofsMCAL = u32(s, hOff + 0x24)

    local cx = (ci - 1) % CHUNKS
    local cy = math.floor((ci - 1) / CHUNKS)

    -- высоты outer 9x9 -> окно атласа высот тайла
    for row = 0, OUTER - 1 do
        for col = 0, OUTER - 1 do
            local gx = cx * (OUTER - 1) + col
            local gy = cy * (OUTER - 1) + row
            hp[gy * GRID + gx] = posZ + vptr[row * 17 + col]
        end
    end

    -- слои: локальные индексы текстур (в texList тайла) + альфа в маск-окно
    local idx = { 0, 0, 0, 0 }
    local mx0, my0 = cx * MASK, cy * MASK
    for L = 0, nLayers - 1 do
        local rOff  = base + ofsMCLY + 8 + L * 16
        local texId = u32(s, rOff)
        local flags = u32(s, rOff + 4)
        local aOff  = u32(s, rOff + 8)
        -- регистрируем имя текстуры в локальном списке тайла
        local name = pngPath(texList.raw[texId + 1] or '')
        if not texIdx[name] then
            texList[#texList+1] = { path = name, data = love.image.newImageData(name) }
            texIdx[name] = #texList
        end
        idx[L+1] = texIdx[name]

        local useAlpha   = math.floor(flags / 0x100) % 2 == 1
        local compressed = math.floor(flags / 0x200) % 2 == 1
        if L > 0 and useAlpha then
            local a = readAlpha64(sp, base + ofsMCAL + 8 + aOff - 1, compressed)
            local ch = L - 1
            for my = 0, MASK - 1 do
                for mxi = 0, MASK - 1 do
                    local v = a[(my*2)*64 + (mxi*2) + 1]
                    mp[((my0 + my) * MASKW + (mx0 + mxi)) * 4 + ch] = v
                end
            end
        end
    end

    local ox, oz = tx * TILE, ty * TILE
    instances[#instances+1] = {
        ox + cx * (OUTER - 1) * UNIT, oz + cy * (OUTER - 1) * UNIT,
        cx * (OUTER - 1) / (GRID - 1), cy * (OUTER - 1) / (GRID - 1),
        mx0 / MASKW, my0 / MASKW,
        idx[1], idx[2], idx[3], idx[4],
        nLayers,
    }
end

-- M2-инстансы (деревья/трава/камни): MMDX(пути) + MMID(оффсеты) + MDDF(размещения)
-- модель -> локальный путь .m2; инстанс -> world-позиция + поворот(рад) + scale
local MAPHALF = 32 * TILE   -- 17066.66, центр карты для пересчёта координат
local function parseDoodads(s, sp, top)
    local mmdxOff, mmidOff, mmidN, mddfOff, mddfN
    for _, c in ipairs(top) do
        if     c.tag == 'MMDX' then mmdxOff = c.off
        elseif c.tag == 'MMID' then mmidOff, mmidN = c.off, c.size / 4
        elseif c.tag == 'MDDF' then mddfOff, mddfN = c.off, c.size / 36 end
    end

    local models = {}        -- 1-based: путь .m2 по индексу MMID
    if mmidOff then
        for i = 0, mmidN - 1 do
            local strOff = mmdxOff + u32(s, mmidOff + i * 4)
            models[i + 1] = s:match('^[^%z]*', strOff)
        end
    end

    local doodads = {}       -- { model, x,y,z, rx,ry,rz, scale }
    if mddfOff then
        local D2R = math.pi / 180
        for i = 0, mddfN - 1 do
            local r = mddfOff + i * 36
            local nameId = u32(s, r)
            local px, py, pz = f32(sp, r + 0x08), f32(sp, r + 0x0C), f32(sp, r + 0x10)
            local rx, ry, rz = f32(sp, r + 0x14), f32(sp, r + 0x18), f32(sp, r + 0x1C)
            local scale = u16(s, r + 0x20) / 1024
            doodads[#doodads+1] = {
                model = nameId + 1,
                MAPHALF - px, py, MAPHALF - pz,   -- world XYZ (формула из справки)
                rx * D2R, ry * D2R, rz * D2R,     -- поворот в радианах
                scale,
            }
        end
    end
    return models, doodads
end

-- главная: парсит .adt -> таблица результата (thread-safe для Channel)
local function importTile(path)
    local tx, ty = path:match('_(%d+)_(%d+)%.adt$')
    tx, ty = tonumber(tx), tonumber(ty)

    local s  = assert(love.filesystem.read(path), 'cannot read ' .. path)
    local sp = ffi.cast('const uint8_t*', s)

    local top = scanChunks(s, 1, #s + 1)
    local mcnks = {}
    local rawTex = {}  -- сырые пути из MTEX
    for _, c in ipairs(top) do
        if c.tag == 'MCNK' then
            mcnks[#mcnks+1] = c
        elseif c.tag == 'MTEX' then
            local blob = s:sub(c.off, c.off + c.size - 1)
            for p in blob:gmatch('[^%z]+') do rawTex[#rawTex+1] = p end
        end
    end

    local heightData = love.image.newImageData(GRID, GRID, 'r32f')
    local maskData   = love.image.newImageData(MASKW, MASKW, 'rgba8')
    local hp = ffi.cast('float*',   heightData:getFFIPointer())
    local mp = ffi.cast('uint8_t*', maskData:getFFIPointer())
    ffi.fill(mp, MASKW*MASKW*4, 0)

    local texList = { raw = rawTex }  -- локальный список png тайла (1-based)
    local texIdx  = {}
    local instances = {}

    for ci, mc in ipairs(mcnks) do
        parseMcnk(s, sp, mc, ci, tx, ty, hp, mp, texList, texIdx, instances)
    end

    local models, doodads = parseDoodads(s, sp, top)

    texList.raw = nil  -- не шлём сырьё через Channel
    return {
        tx = tx, ty = ty,
        heightData = heightData,
        maskData   = maskData,
        names      = texList,    -- список png путей тайла
        instances  = instances,
        models     = models,     -- 1-based пути .m2 для doodad-инстансов тайла
        doodads    = doodads,    -- { modelIdx, x,y,z, rx,ry,rz, scale }
    }
end

return importTile
