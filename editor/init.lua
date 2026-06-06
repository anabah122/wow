-- редактор террейна: один блок чанков. кисти высоты/материала + экран палитры.
-- ставит love-колбэки; запуск из Main.lua по arg 'editor'.
require 'lib.overloads'

local Camera  = require 'class.camera'
local Block   = require 'editor.block'
local brush   = require 'editor.brush'
local picker  = require 'editor.picker'
local Render  = require 'editor.render'
local Palette = require 'editor.palette'
local hud     = require 'editor.hud'
local FpsMean = require 'class.util.fpsMean'
local dims    = require 'class.util.dims'

local SIZE = dims.SIZE



love.mouse.setVisible(false)

local palette = Palette:new()
local block   = Block:new(#palette.mats)
local render  = Render:new()
local fps     = FpsMean:new()

local camera = Camera:new{
    x = 0, y = 200, z = 0,
    pitch = -1.4, near = 1, far = 4000, speed = 60,
}

local tool   = 'raise'      -- raise / lower / smooth / flatten / paint
local radius = 8
local strength = 20
local paintStrength = 4     -- сила покраски материала
local flatLevel = 0
local aimTex                -- {tx,ty} под прицелом
local aimWorld              -- {x,y,z} мировая точка прицела

local TOOLS = { ['1']='raise', ['2']='lower', ['3']='smooth', ['4']='flatten', ['5']='paint' }

function love.update(dt)
    fps:step()
    if palette.open then return end
    camera:update(dt)

    aimTex, aimWorld = nil, nil
    local tx, ty, wx, wy, wz = picker.aim(camera, block)
    if tx then
        aimTex = { tx, ty }
        aimWorld = { wx, wy, wz }
        if love.mouse.isDown(1) then
            if tool == 'raise'  then brush.raise(block, tx, ty, radius, strength, 1, dt)
            elseif tool == 'lower'  then brush.raise(block, tx, ty, radius, strength, -1, dt)
            elseif tool == 'smooth' then brush.smooth(block, tx, ty, radius, strength, dt)
            elseif tool == 'flatten'then brush.flatten(block, tx, ty, radius, strength, flatLevel, dt)
            elseif tool == 'paint'  then
                brush.paint(block, tx, ty, radius, paintStrength, palette.selected, dt)
            end
        end
    end
    block:refresh()
end

function love.draw()
    if palette.open then palette:draw(); return end

    LG.clear(0.5, 0.6, 0.75)
    render:draw(camera, block, palette.array, #palette.mats)

    LG.setShader(); LG.setDepthMode()
    if aimWorld then
        render:drawBrush(camera, block, aimWorld[1], aimWorld[3], radius)
    end

    local mat = palette.mats[palette.selected]
    hud.draw{
        fps      = fps:get(),
        tool     = tool,
        radius   = radius,
        strength = tool == 'paint' and paintStrength or strength,
        matName  = mat and mat.name or '-',
    }
end

function love.wheelmoved(x, y)
    if palette.open then return end
    if LK.isDown('lshift', 'rshift') then
        radius = math.max(1, math.min(SIZE, radius + y))
    elseif LK.isDown('lalt', 'ralt') then
        if tool == 'paint' then
            paintStrength = math.max(0.5, paintStrength + y)
        else
            strength = math.max(1, strength + y * 2)
        end
    else
        camera:wheelmoved(y)                          -- скорость камеры
    end
end

function love.mousepressed(mx, my, b)
    if palette.open then
        palette:mousepressed(mx, my, b)
        if not palette.open then                     -- выбор материала закрыл палитру
            love.mouse.setRelativeMode(true)
            love.mouse.setVisible(false)
        end
        return
    end
    -- flatten плющит к высоте ТОЧКИ пересечения луча с террейном
    if b == 1 and aimWorld then flatLevel = aimWorld[2] end
end

function love.mousemoved(x, y, dx, dy)
    if not palette.open then camera:mousemoved(dx, dy) end
end

function love.keypressed(k)
    if k == 'escape' then love.event.quit() end
    if k == 'm' then
        palette.open = not palette.open
        love.mouse.setRelativeMode(not palette.open)
        love.mouse.setVisible(palette.open)          -- курсор только в палитре
    end
    if TOOLS[k] then tool = TOOLS[k] end
end



