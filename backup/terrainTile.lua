-- ── Tile ──────────────────────────────────────────────────────────────────
-- игровой объект: один .adt. Держит свои чанки (256 MCNK).
-- наполняется асинхронно импортером.

local Tile = {}
Tile.__index = Tile

function Tile:new(tx, ty)
    return setmetatable({ tx = tx, ty = ty, chunks = {} }, Tile)
end

function Tile:addChunk(chunk)
    self.chunks[#self.chunks+1] = chunk
end

return Tile
