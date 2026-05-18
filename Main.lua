require("lib.FRAMELOOP")
require('lib.overloads')


local meshes = importer.obj:load('untitled.obj')
local shader = LG.newShader 'shader/main.glsl'

local transform = matClass:new():setTransformationMatrix({0,0,0},{0,0,0,1},{1,1,1})
local camera   = require 'class.camera' :new{ x=0, y=2, z=6 }

function love.update( dt )
    camera:update(dt)
end

function love.draw()

    LG.setDepthMode('lequal', true)
    LG.setMeshCullMode('back')

    shader:send('viewproj',  camera:viewproj())
    shader:send('transform', transform)
    shader:send('min_alpha', 0.1)
    LG.setShader(shader)

    for _, m in ipairs(meshes) do
        LG.draw(m)
    end

    LG.setShader()
    LG.setDepthMode('always', false)
    LG.setMeshCullMode('none')
    love.graphics.setWireframe( false )

    LG.print(LT.realFPS)
end