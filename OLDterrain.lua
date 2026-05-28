require 'lib.FRAMELOOP'
require 'lib.overloads'

local Terrain = require 'class.terrain'
local camera  = require 'class.camera':new{ x=512, y=400, z=1024, far=4096 }
local fps = require'class.util.fpsMean':new()

local terrain = Terrain:new()
terrain:import('assets/maps')


function love.update(dt) camera:update(dt) end

function love.draw()
    LG.clear(0.05, 0.05, 0.08)
    LG.setDepthMode('lequal', true)
    terrain:draw(camera)
    LG.setDepthMode()
    fps:add( LT.realFPS )
    LG.print(string.format('fps %.1f  near %d  far %d', fps:get(), terrain.nearCount or 0, terrain.farCount or 0), 10, 10)
end

function love.wheelmoved(x, y) camera:wheelmoved(y) end
function love.mousemoved(x, y, dx, dy) camera:mousemoved(dx, dy) end
