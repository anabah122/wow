require 'lib.FRAMELOOP'
require 'lib.overloads'

local Terrain = require 'class.terrain'
local Camera  = require 'class.camera'
local fps     = require 'class.util.fpsMean':new()

local TILE = 533.33333

local terrain = Terrain:new()

local dir, paths = 'assets/adt', {}
for _, name in ipairs(LF.getDirectoryItems(dir)) do
    if name:match('_(%d+)_(%d+)%.adt$') then paths[#paths+1] = dir .. '/' .. name end
end
terrain:import(paths)

local camera = Camera:new{
    x = 37 * TILE, y = 2500, z = 21 * TILE,
    pitch = -0.6, far = 3200,
}

function love.update(dt)
    camera:update(dt)
    terrain:update(dt)
end

function love.draw()
    LG.clear(0.5, 0.6, 0.75)
    LG.setMeshCullMode('back')
    LG.setDepthMode('lequal', true)
    terrain:draw(camera)
    LG.setDepthMode()
    fps:add(LT.realFPS)
    LG.print(string.format('fps %d  drawn chunks %d', fps:get(), terrain.drawn or 0), 10, 10)
end

function love.wheelmoved(x, y) camera:wheelmoved(y) end
function love.mousemoved(x, y, dx, dy) camera:mousemoved(dx, dy) end
function love.keypressed(k) if k == 'escape' then love.event.quit() end end
