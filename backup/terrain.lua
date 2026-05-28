local Importer = require 'class.terrainImporter'

local BUDGET = 0.002  -- сек на импорт за кадр

local terrainShader = LG.newShader('shader/wow.glsl')
local TEX_TILE = 16 * 8  -- повторов текстуры на весь тайл (8 на чанк)
local DRAW_DIST = 533    -- радиус отрисовки чанков вокруг игрока (метры)

local WHITE = (function()
    local d = love.image.newImageData(1, 1)
    d:setPixel(0, 0, 1, 0, 1, 1)  -- magenta = «текстуры нет»
    return LG.newImage(d)
end)()

local Terrain = {}
Terrain.__index = Terrain

function Terrain:new()
    return setmetatable({ importQueue = {}, tiles = {} }, Terrain)
end

-- поставить тайл(ы) в очередь импорта. ничего не грузит сам — это делает импортер.
function Terrain:import(path)
    if type(path) == 'table' then
        for _, p in ipairs(path) do self:import(p) end
        return
    end
    local imp = Importer:new(path)
    self.importQueue[#self.importQueue+1] = imp
    self.tiles[#self.tiles+1] = imp.tile  -- tile живёт сразу, наполняется асинхронно
end

function Terrain:update(dt)
    local imp = self.importQueue[1]
    if not imp then return end
    imp:step(BUDGET)
    if imp:done() then table.remove(self.importQueue, 1) end
end

function Terrain:draw(camera)
    local px, pz = camera.pos.x, camera.pos.z
    local d2 = DRAW_DIST * DRAW_DIST

    LG.setShader(terrainShader)
    terrainShader:send('viewproj', camera:viewproj())
    -- terrainShader:send('texTile', TEX_TILE)

    self.drawn = 0  -- дебаг: сколько чанков реально нарисовано
    for _, tile in ipairs(self.tiles) do
        for _, ch in ipairs(tile.chunks) do
            local dx, dz = ch.cx - px, ch.cz - pz
            if dx*dx + dz*dz <= d2 then
                -- ТЕСТ: без текстур/униформов, только геометрия
                -- terrainShader:send('nLayers', ch.nLayers)
                -- terrainShader:send('alphaMap', ch.alpha)
                -- local base = ch.tex[1]
                -- for L = 1, 4 do
                --     terrainShader:send('layer' .. L, ch.tex[L] or base or WHITE)
                -- end
                LG.draw(ch.mesh)
                self.drawn = self.drawn + 1
            end
        end
    end
    LG.setShader()
end

return Terrain
