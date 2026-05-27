local importer = require 'importer.importer'
local quat = require 'math.quat'

local go = {}
go.__index = go


-- args: { path, instances = { {x,y,z, ox,oy,oz}, ... } }
function go:new(args)

    local self = setmetatable({}, go)
    self.parts = importer.gltf.load{ path = args.path }

    if args.instances then 
        self:buildInstances(args.instances) 
    end

    if args.batcher then 
        self:batchRegister( args.batcher )
    end

    return self
end


function go:buildInstances(instances)
    self.instanceCount = #instances

    local data = {}
    for i, inst in ipairs(instances) do
        data[i] = {
            inst[1], inst[2], inst[3], -- pos
            quat:fromEuler(inst[4], inst[5], inst[6]):unpack() -- rot
        }
    end

    self.instanceMesh = love.graphics.newMesh({
        { 'InstancePos', 'float', 3 },
        { 'InstanceRot', 'float', 4 },
    }, data, nil, 'static')

    for _, part in ipairs(self.parts) do
        part.mesh:attachAttribute('InstancePos', self.instanceMesh, 'perinstance')
        part.mesh:attachAttribute('InstanceRot', self.instanceMesh, 'perinstance')
    end
end



function go:batchRegister(batcher)
    for _, part in ipairs(self.parts) do
        batcher:add(part.mesh, part.material.texture, self.instanceCount)
    end
end

function go:batchUnRegister(batcher)
    for _, part in ipairs(self.parts) do
        batcher:remove(part.mesh, part.material.texture)
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
