local importer = require 'importer.importer'

local go = {}
go.__index = go

-- q1 * q2
local function qmul(a, b)
    local ax,ay,az,aw = a[1],a[2],a[3],a[4]
    local bx,by,bz,bw = b[1],b[2],b[3],b[4]
    return {
        aw*bx + ax*bw + ay*bz - az*by,
        aw*by - ax*bz + ay*bw + az*bx,
        aw*bz + ax*by - ay*bx + az*bw,
        aw*bw - ax*bx - ay*by - az*bz,
    }
end

-- поворот на ang вокруг оси (0=x,1=y,2=z)
local function qaxis(axis, ang)
    local h = ang * 0.5
    local s, c = math.sin(h), math.cos(h)
    if axis == 0 then return { s,0,0,c } end
    if axis == 1 then return { 0,s,0,c } end
    return { 0,0,s,c }
end

-- доворот по header global_flags M2 (m2.json globalFlags): бит 0x01 flag_tilt_x,
-- бит 0x02 flag_tilt_y. x/y/z в радианах, 0 = не крутить.
local FLIP = {
    [0x01] = { x = 0, y = 0, z = math.pi },   -- tilt X
    [0x02] = { x = math.pi, y = 0, z = 0 },   -- tilt Y
}

local function flipQuat(glbPath)
    local jsonPath = glbPath:gsub('%.gltf$', '.m2.json')
    if not LF.getInfo(jsonPath) then return nil end
    local m2 = require('lib.json').decode(LF.read(jsonPath))
    local f = m2.globalFlags or 0
    for flag, r in pairs(FLIP) do
        if bit.band(f, flag) ~= 0 then
            local q = qaxis(0, r.x)
            q = qmul(q, qaxis(1, r.y))
            q = qmul(q, qaxis(2, r.z))
            return q
        end
    end
    return nil
end


-- args: { path, instances = { {x,y,z, qx,qy,qz,qw, scale}, ... } }
function go:new(args)

    local self = setmetatable({}, go)
    self.parts = importer.gltf.load{ path = args.path }

    if args.instances then
        self:buildInstances(args.instances, flipQuat(args.path))
    end

    if args.batcher then 
        self:batchRegister( args.batcher )
    end

    return self
end


function go:buildInstances(instances, flip)
    self.instanceCount = #instances

    local data = {}
    for i, inst in ipairs(instances) do
        local qx, qy, qz, qw = inst[4], inst[5], inst[6], inst[7]
        if flip then
            local q = qmul({qx,qy,qz,qw}, flip)
            qx, qy, qz, qw = q[1], q[2], q[3], q[4]
        end
        data[i] = {
            inst[1], inst[2], inst[3],          -- pos
            qx, qy, qz, qw,                     -- rot (готовый кватернион, посчитан офлайн)
            inst[8] or 1,                       -- scale
        }
    end

    self.instanceMesh = love.graphics.newMesh({
        { 'InstancePos', 'float', 3 },
        { 'InstanceRot', 'float', 4 },
        { 'InstanceScale', 'float', 1 },
    }, data, nil, 'static')

    for _, part in ipairs(self.parts) do
        part.mesh:attachAttribute('InstancePos', self.instanceMesh, 'perinstance')
        part.mesh:attachAttribute('InstanceRot', self.instanceMesh, 'perinstance')
        part.mesh:attachAttribute('InstanceScale', self.instanceMesh, 'perinstance')
    end
end



function go:batchRegister(batcher)
    for _, part in ipairs(self.parts) do
        if part.material and part.material.texture then
            batcher:add(part.mesh, part.material.texture, self.instanceCount, part.material.blendMode, part.material.twoSided)
        end
    end
end

function go:batchUnRegister(batcher)
    for _, part in ipairs(self.parts) do
        if not part.material then goto continue end
        batcher:remove(part.mesh, part.material.texture, part.material.blendMode)
        ::continue::
    end
end


-- !!! in game use batcher !!!
function go:draw()
    local shader = LG.getShader()
    for _, part in ipairs(self.parts) do
        ShaderTryUniform(shader,'MainTex', part.mesh:getTexture() )
        if self.instanceCount then
            LG.drawInstanced(part.mesh, self.instanceCount)
        else
            LG.draw(part.mesh)
        end
    end
end

return go
