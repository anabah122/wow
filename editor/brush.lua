-- кисти редактора. координаты центра — в текселях буфера.
local Block = require 'editor.block'
local HSIZE = Block.HSIZE
local SIZE  = Block.SIZE

local brush = {}

-- обойти тексели в круге радиуса r вокруг (cx,cy), max = граница (исключительно)
local function disc(cx, cy, r, max, fn)
    local x0 = math.max(0, math.floor(cx - r)); local x1 = math.min(max - 1, math.ceil(cx + r))
    local y0 = math.max(0, math.floor(cy - r)); local y1 = math.min(max - 1, math.ceil(cy + r))
    for y = y0, y1 do
        for x = x0, x1 do
            local d = math.sqrt((x - cx)^2 + (y - cy)^2)
            if d <= r then fn(x, y, 1 - d / r) end   -- falloff 1..0 к краю
        end
    end
end

-- высота: поднять/опустить (sign=+1/-1)
function brush.raise(block, cx, cy, r, strength, sign, dt)
    disc(cx, cy, r, HSIZE, function(x, y, f)
        block:setH(x, y, block:hAt(x, y) + sign * strength * f * dt)
    end)
end

-- среднее высот 3x3 соседей текселя (box-blur)
local function neighborAvg(block, x, y)
    local sum, n = 0, 0
    for dy = -1, 1 do
        for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if nx >= 0 and nx < HSIZE and ny >= 0 and ny < HSIZE then
                sum = sum + block:hAt(nx, ny); n = n + 1
            end
        end
    end
    return sum / n
end

-- сглаживание: каждый тексель тянется к среднему СВОИХ соседей.
-- цели считаем по исходному буферу, потом применяем (иначе правка влияет на соседей)
function brush.smooth(block, cx, cy, r, strength, dt)
    local targets = {}
    disc(cx, cy, r, HSIZE, function(x, y, f)
        targets[#targets+1] = { x, y, neighborAvg(block, x, y), f }
    end)
    for _, t in ipairs(targets) do
        local x, y, avg, f = t[1], t[2], t[3], t[4]
        local h = block:hAt(x, y)
        block:setH(x, y, h + (avg - h) * math.min(1, strength * f * dt))
    end
end

-- плоско по высоте: тянуть к целевому уровню
function brush.flatten(block, cx, cy, r, strength, level, dt)
    disc(cx, cy, r, HSIZE, function(x, y, f)
        local h = block:hAt(x, y)
        block:setH(x, y, h + (level - h) * math.min(1, strength * f * dt))
    end)
end

-- материал (карта весов HSIZE, как высота)
function brush.paint(block, cx, cy, r, strength, mat, dt)
    disc(cx, cy, r, HSIZE, function(x, y, f)
        block:paint(x, y, mat, strength * f * dt)
    end)
end

return brush
