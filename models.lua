require("lib.FRAMELOOP")
require('lib.overloads')
require('importer.importer')


local goClass      = require 'class.go'
local batcherClass = require 'class.batcher'


-- сила освещения по часам (h в [0..24])
local DAY_CYCLE = {
    { h= 0, i=0.15 }, -- полночь
    { h= 6, i=0.05 }, -- предрассветная тьма
    { h=12, i=1.00 }, -- полдень
    { h=18, i=0.40 }, -- закат
    { h=24, i=0.15 }, -- wrap
}

local function dayIntensity(t)
    t = t % 24
    for i = 1, #DAY_CYCLE - 1 do
        local a, b = DAY_CYCLE[i], DAY_CYCLE[i+1]
        if t >= a.h and t <= b.h then
            local f = (t - a.h) / (b.h - a.h)
            return a.i + (b.i - a.i) * f
        end
    end
    return DAY_CYCLE[1].i
end

local batcher = batcherClass:new()
local skyBatcher = batcherClass:new()

local shaderSky     = LG.newShader 'shader/sky.glsl'
local shaderScene   = LG.newShader 'shader/main.glsl'

local transform = require'math.mat4':new():setTransformationMatrix({0,0,0},{0,0,0,1},{1,1,1})
local camera   = require 'class.camera' :new{ x=0, y=2, z=6 , far=1024*4 }


local function makeTestGo( pathList )
    local rand = math.random
    for _,path in pairs( pathList ) do
        local instances = {}
        for i = 1,1000 do
            instances[i]= {rand(-1500,1500),0,rand(-1500,1500),0,rand(12),0}
        end

        local _t = LT.getTime()
        local obj = goClass:new{
            path = path,
            batcher = batcher,
            instances = instances
        }
        print(LT.getTime()-_t)
    end
end



makeTestGo{
    "assets/models/rocks/vfw_flatrocks_01_mossy.glb",
    "assets/models/junglebush/v4w_junglebush02.glb",
    "assets/models/junglebush/v4w_junglebush01.glb",
    "assets/models/farmcrops/v4w_farmcrops_04.glb",
    "assets/models/farmcrops/v4w_farmcrops_08.glb",
    "assets/models/cascadebush/vfw_cascadebush03.glb",
    'assets/models/cascadebush/vfw_cascadebushdark02.glb',
    'assets/models/grassclump/vfw_grassclump01.glb',
    'assets/models/jungleflower/v4w_jungleflower02.glb',
    'assets/models/jungleflower/v4w_jungleflower01.glb',
    'assets/models/jungleflower/v4w_jungleflower04.glb',
    'assets/models/junglesapling/v4w_junglesapling01.glb',
    'assets/models/epiphytetree/vfw_epiphytetree01.glb',
    'assets/models/epiphytetree/vfw_epiphytetree02.glb',
    'assets/models/epiphytetree/vfw_epiphytetree03.glb',
    "assets/models/cascadetreegold/vfw_cascadetreegold01.glb",
    "assets/models/cascadetreegold/vfw_cascadetreegold02.glb",
    "assets/models/cascadetreegold/vfw_cascadetreegold03.glb",
}



local plane = goClass:new{
    path = 'assets/models/plane.glb',
}

local sky = goClass:new{
    path = 'assets/models/skybox.glb',
}

shaderSky:send('min_alpha', 0.8)


local lutImage = LG.newImage('assets/LUT/colorgradingplaceholder_sunset.png')
lutImage:setFilter('linear', 'linear')
lutImage:setWrap('clamp')


shaderScene:send('lut', lutImage)
shaderScene:send('min_alpha',    0.95)
shaderScene:send('lightDir',     { 0.4, 0.8, 0.45 })
shaderScene:send('lightCol',     { 1.0, 0.95, 0.85 })
shaderScene:send('ambient',      { 0.25, 0.28, 0.35 })
shaderScene:send('fogColor',     { 0.55, 0.65, 0.75 })
shaderScene:send('fogDensity',   0.0015)


local ssao_samples = { }
local range = 16.0
local screen_w,screen_h = LG.getDimensions()

for i = 1, 32 do
	local r = i / 32 * math.pi * 2
	local d = (0.5 + i % 4) / 4
	ssao_samples[i] = { math.cos(r) * d * range / screen_w, math.sin(r) * d * range / screen_h, (1 - d) ^ 2 / 32 }
end


local scenecanv  = love.graphics.newCanvas()
local normalcanv = love.graphics.newCanvas(nil,nil, {format='rgba16f'})
local depthcanv  = love.graphics.newCanvas(nil,nil, {format="depth24", readable=true})
local renderSetup = { scenecanv, normalcanv, depth = true , depthstencil = depthcanv }


local time = 0
function love.draw()



    -- SCENE
    LG.setShader( shaderScene )
    LG.setCanvas( renderSetup )
    LG.clear(0,0,0,0)

    LG.setDepthMode('lequal', true)

    time = time + LT.getDelta()
    local hour     = (time * 1.0) % 24
    local intens   = dayIntensity(hour)
    local lightCol = { intens, intens, intens }
    local ambient  = { intens*0.35, intens*0.35, intens*0.35 }

    local sunAngle = (hour / 24) * math.pi * 2 - math.pi/2
    local lightDir = { math.cos(sunAngle), math.sin(sunAngle), 0.3 }

    shaderScene:send('lightDir',  lightDir)
    shaderScene:send('lightCol',  lightCol)
    shaderScene:send('ambient',   ambient)
    shaderScene:send('viewproj',  camera:viewproj())
    shaderScene:send('cameraPos', { camera.pos.x, camera.pos.y, camera.pos.z })


    plane:draw()

    shaderScene:send('transform', transform)
    batcher:draw()


    -- POST


    -- SKY
    LG.setCanvas()
    LG.setDepthMode('always', false)
    LG.setShader( shaderSky )
    shaderSky:send('skyTint', lightCol)

    shaderSky:send('posOffset', camera.pos:get())
    shaderSky:send('viewproj',  camera:viewproj())
    sky:draw()

    -- UI
    LG.setShader()
    LG.draw(scenecanv, 0, scenecanv:getHeight(), 0, 1, -1)
    
    LG.print(LT.realFPS)
end


function love.wheelmoved( x, y )
    camera:wheelmoved(y)
end
function love.mousemoved( x, y, dx, dy )
    camera:mousemoved( dx, dy )
end
function love.update( dt )
    camera:update(dt)
end
