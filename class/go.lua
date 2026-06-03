local importer = require 'importer.importer'

local go = {}
go.__index = go


-- args: { path, instances = { {x,y,z, qx,qy,qz,qw, scale}, ... } }
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
            inst[1], inst[2], inst[3],          -- pos
            inst[4], inst[5], inst[6], inst[7], -- rot (готовый кватернион, посчитан офлайн)
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
