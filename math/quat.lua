local quat = {}
quat.__index = quat

function quat:new(x, y, z, w)
    return setmetatable({ x or 0, y or 0, z or 0, w or 1 }, quat)
end

-- эйлеры в радианах, порядок YXZ (yaw→pitch→roll)
function quat:fromEuler(ox, oy, oz)
    local cx, sx = math.cos(ox*0.5), math.sin(ox*0.5)
    local cy, sy = math.cos(oy*0.5), math.sin(oy*0.5)
    local cz, sz = math.cos(oz*0.5), math.sin(oz*0.5)
    return setmetatable({
        sx*cy*cz + cx*sy*sz,
        cx*sy*cz - sx*cy*sz,
        cx*cy*sz - sx*sy*cz,
        cx*cy*cz + sx*sy*sz,
    }, quat)
end

function quat:unpack() return self[1], self[2], self[3], self[4] end

-- кватернион поворота на angle (рад) вокруг оси axis ('x'|'y'|'z')
function quat:axis(ax, angle)
    local h = angle * 0.5
    local s, c = math.sin(h), math.cos(h)
    if     ax == 'x' then return quat:new(s, 0, 0, c)
    elseif ax == 'y' then return quat:new(0, s, 0, c)
    else                  return quat:new(0, 0, s, c) end
end

-- произведение a*b (сначала применяется b, потом a)
function quat:mul(b)
    local ax, ay, az, aw = self[1], self[2], self[3], self[4]
    local bx, by, bz, bw = b[1], b[2], b[3], b[4]
    return quat:new(
        aw*bx + ax*bw + ay*bz - az*by,
        aw*by - ax*bz + ay*bw + az*bx,
        aw*bz + ax*by - ay*bx + az*bw,
        aw*bw - ax*bx - ay*by - az*bz)
end

return quat
