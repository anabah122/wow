-- пересечение взгляда камеры с террейном -> тексель буфера высоты.
-- мышь в relative-mode, прицел в центре -> марш луча камеры вперёд по высоте блока.
local dims = require 'class.util.dims'
local SIZE = dims.SIZE

local picker = {}

-- блок центрирован в нуле: мир -SIZE/2..SIZE/2 -> тексель 0..SIZE
local HALF = SIZE / 2
local function worldToTex(wx, wz) return wx + HALF, wz + HALF end

-- block:hAt по мировой точке (билинейно не нужно — кисть и так по диску)
local function heightAt(block, wx, wz)
    local tx, ty = worldToTex(wx, wz)
    local x = math.max(0, math.min(SIZE, math.floor(tx + 0.5)))
    local y = math.max(0, math.min(SIZE, math.floor(ty + 0.5)))
    return block:hAt(x, y)
end

-- вернуть тексель (tx,ty) под прицелом или nil
function picker.aim(camera, block)
    local o = camera.pos
    local d = camera:forward()
    local px, py, pz = o.x, o.y, o.z
    local step = 1.0
    for i = 1, 2000 do
        px = px + d.x * step; py = py + d.y * step; pz = pz + d.z * step
        if px < -SIZE or px > SIZE or pz < -SIZE or pz > SIZE then return nil end
        if py <= heightAt(block, px, pz) then
            local tx, ty = worldToTex(px, pz)
            return math.max(0, math.min(SIZE, tx)), math.max(0, math.min(SIZE, ty)), px, py, pz
        end
    end
    return nil
end

return picker
