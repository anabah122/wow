local batcher = {}
batcher.__index = batcher

function batcher:new()
    -- byTexture[texture] = { {mesh, instanceCount}, ... }
    return setmetatable({ byTexture = {} }, batcher)
end

function batcher:add(mesh, texture, instanceCount)
    local bucket = self.byTexture[texture]
    if not bucket then
        bucket = {}
        self.byTexture[texture] = bucket
    end
    bucket[#bucket+1] = { mesh = mesh, instanceCount = instanceCount }
end

function batcher:remove(mesh, texture)
    local bucket = self.byTexture[texture]
    if not bucket then return end
    for i = #bucket, 1, -1 do
        if bucket[i].mesh == mesh then table.remove(bucket, i) end
    end
    if #bucket == 0 then self.byTexture[texture] = nil end
end


function batcher:draw()
    for _, bucket in pairs(self.byTexture) do
        for _, obj in ipairs(bucket) do
            if obj.instanceCount then
                LG.drawInstanced(obj.mesh, obj.instanceCount)
            else
                LG.draw(obj.mesh)
            end
        end
    end
end

return batcher
