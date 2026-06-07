-- mask-материал: RGBA-маска -> 4 тайла. канал R/G/B/A = вес tiles[1..4] в текселе.
-- маска тайлится по миру с шагом scale (мировых ячеек на повтор маски).
local M = {}

function M:load(dir, tileIndex, mf)
    self.scale  = mf.scale or 64
    self.height = mf.height or 0          -- амплитуда подъёма высоты по яркости маски (0 = не трогать)
    self.idx    = {}
    for i, name in ipairs(mf.tiles) do self.idx[i] = tileIndex(name) end
    self.mask  = love.image.newImageData(dir .. '/' .. mf.mask)
    self.mw, self.mh = self.mask:getWidth(), self.mask:getHeight()
end

-- вес каналов маски в мировой точке (тайлинг по scale, wrap)
function M:sample(x, y)
    local u = (x / self.scale * self.mw) % self.mw
    local v = (y / self.scale * self.mh) % self.mh
    return self.mask:getPixel(math.floor(u), math.floor(v))   -- r,g,b,a
end

function M:apply(block, cx, cy, r, dt)
    local max = block.SIZE
    local x0 = math.max(0, math.floor(cx - r)); local x1 = math.min(max, math.ceil(cx + r))
    local y0 = math.max(0, math.floor(cy - r)); local y1 = math.min(max, math.ceil(cy + r))
    for y = y0, y1 do
        for x = x0, x1 do
            local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
            if d <= r then
                local w = { self:sample(x, y) }                -- {r,g,b,a}
                for i = 1, 4 do
                    if self.idx[i] then block:setMaterialWeight(x, y, self.idx[i], w[i]) end
                end
                -- высота: целевой уровень = яркость маски * амплитуда, тянем к нему (falloff к краю)
                if self.height > 0 then
                    local target = w[1] * self.height
                    local h = block:hAt(x, y)
                    block:setH(x, y, h + (target - h) * math.min(1, (1 - d / r) * 4 * dt))
                end
            end
        end
    end
end

return M
