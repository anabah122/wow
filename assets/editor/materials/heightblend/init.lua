-- script-материал: раскладка по высоте и уклону.
-- база — трава; песок проступает на низких высотах, скала на крутых склонах.
-- правь пороги и тайлы прямо тут (hot-reload по R).
local LOW, HIGH = 5, 30      -- ниже LOW — полностью песок, выше HIGH — без песка
local STEEP     = 0.4        -- уклон, выше которого начинается скала (0..1)
local TILES = { sand = 'dreamcsand01', grass = 'dreamcgrass02', rock = 'hyjalrocksmooth' }

local M = {}

function M:load(dir, tileIndex)
    self.idx = {}
    for k, name in pairs(TILES) do self.idx[k] = tileIndex(name) end
end

-- уклон 0..1 из разницы высот соседей текселя
local function slopeAt(block, x, y, max)
    local function h(ax, ay) return block:hAt(math.max(0, math.min(max, ax)), math.max(0, math.min(max, ay))) end
    local dx = h(x + 1, y) - h(x - 1, y)
    local dy = h(x, y + 1) - h(x, y - 1)
    local g = math.sqrt(dx * dx + dy * dy) * 0.5
    return g / (g + 1)        -- мягкая нормировка в 0..1
end

local function clamp01(v) return math.max(0, math.min(1, v)) end

-- кистью под курсором: пишем веса каждого тайла по высоте/уклону текселя
function M:apply(block, cx, cy, r, dt)
    local max = block.SIZE
    local x0 = math.max(0, math.floor(cx - r)); local x1 = math.min(max, math.ceil(cx + r))
    local y0 = math.max(0, math.floor(cy - r)); local y1 = math.min(max, math.ceil(cy + r))
    for y = y0, y1 do
        for x = x0, x1 do
            if math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) <= r then
                local h = block:hAt(x, y)
                local s = slopeAt(block, x, y, max)

                local sand = clamp01((HIGH - h) / (HIGH - LOW))   -- 1 внизу -> 0 наверху
                local rock = clamp01((s - STEEP) / (1 - STEEP))   -- 0 на пологом -> 1 на крутом

                block:setMaterialWeight(x, y, self.idx.grass, 1)  -- база
                block:setMaterialWeight(x, y, self.idx.sand, sand)
                block:setMaterialWeight(x, y, self.idx.rock, rock)
            end
        end
    end
end

return M
