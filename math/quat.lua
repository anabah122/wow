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

return quat
