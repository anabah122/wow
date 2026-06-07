-- ультимативный процедурный материал: высота И текстура из одного источника (fbm-шум).
-- шум по мировым координатам -> рельеф; тот же высотный профиль решает раскладку тайлов.
-- лепится кистью: высота тянется к процедурному уровню, текстура согласована с ним.
local FREQ  = 0.012      -- частота базового шума (мельче -> крупнее холмы)
local OCT   = 4          -- октавы fbm
local AMP   = 60         -- амплитуда высоты (мировые единицы)
local LOW, HIGH = 12, 42 -- пороги высот для раскладки песок/трава/скала
local TILES = { sand = 'dreamcsand01', grass = 'dreamcgrass02', rock = 'hyjalrocksmooth' }

local M = {}

function M:load(dir, tileIndex)
    self.idx = {}
    for k, name in pairs(TILES) do self.idx[k] = tileIndex(name) end
end

-- fbm-шум 0..1 в мировой точке
local function fbm(x, y)
    local v, amp, f, norm = 0, 1, FREQ, 0
    for _ = 1, OCT do
        v = v + amp * love.math.noise(x * f, y * f)
        norm = norm + amp
        amp = amp * 0.5; f = f * 2
    end
    return v / norm
end

local function clamp01(v) return math.max(0, math.min(1, v)) end

function M:apply(block, cx, cy, r, dt)
    local max = block.SIZE
    local x0 = math.max(0, math.floor(cx - r)); local x1 = math.min(max, math.ceil(cx + r))
    local y0 = math.max(0, math.floor(cy - r)); local y1 = math.min(max, math.ceil(cy + r))
    for y = y0, y1 do
        for x = x0, x1 do
            local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
            if d <= r then
                local target = fbm(x, y) * AMP                     -- процедурная высота
                local h = block:hAt(x, y)
                block:setH(x, y, h + (target - h) * math.min(1, (1 - d / r) * 4 * dt))

                -- текстура согласована с ЦЕЛЕВОЙ высотой (не текущей) -> не зависит от темпа лепки
                local sand = clamp01((LOW - target) / LOW)         -- 1 у воды -> 0 выше LOW
                local rock = clamp01((target - HIGH) / (AMP - HIGH))-- 0 ниже HIGH -> 1 на пике
                block:setMaterialWeight(x, y, self.idx.grass, 1)
                block:setMaterialWeight(x, y, self.idx.sand, sand)
                block:setMaterialWeight(x, y, self.idx.rock, rock)
            end
        end
    end
end

return M
