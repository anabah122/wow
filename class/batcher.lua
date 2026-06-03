local batcher = {}
batcher.__index = batcher

-- blendMode (EGxBlend) -> lane отрисовки, см. doc/render.md
-- 0 Opaque -> 1 | 1 AlphaKey -> 2 (cutout) | 3 (декали, пока пусто)
-- 2 Alpha -> 4 (transparent alpha) | 3..7 Add/Mod/... -> 5 (transparent add)
local function blendPass(blendMode)
    if blendMode == 0 then return 1 end
    if blendMode == 1 then return 2 end
    if blendMode == 2 then return 4 end
    return 5
end


function batcher:new()
    -- graph[lane][texture] = { {mesh, instanceCount, blendMode}, ... }
    return setmetatable({ graph = { {}, {}, {}, {}, {} } }, batcher)
end



function batcher:add(mesh, texture, instanceCount, blendMode, twoSided)
    blendMode = blendMode or 0
    local lane = self.graph[blendPass(blendMode)]
    local bucket = lane[texture]
    if not bucket then
        bucket = {}
        lane[texture] = bucket
    end
    bucket[#bucket+1] = { mesh = mesh, instanceCount = instanceCount, blendMode = blendMode, twoSided = twoSided }
end

function batcher:remove(mesh, texture, blendMode)
    local lane = self.graph[blendPass(blendMode or 0)]
    local bucket = lane[texture]
    if not bucket then return end
    for i = #bucket, 1, -1 do
        if bucket[i].mesh == mesh then
            table.remove(bucket, i)
        end
    end
    if #bucket == 0 then lane[texture] = nil end
end



-- нарисовать один пасс (lane). blend/depth настраивает вызывающий (terrain:draw)
-- кол-во мешей в lane (для дебага раскладки по пассам)
function batcher:passCount(pass)
    local n = 0
    for _, bucket in pairs(self.graph[pass]) do n = n + #bucket end
    return n
end

function batcher:drawPass(pass)
    local shader = LG.getShader()
    for _, bucket in pairs(self.graph[pass]) do
        for _, obj in ipairs(bucket) do
            LG.setMeshCullMode(obj.twoSided and 'none' or 'back')  -- cull из флага TwoSided, см. doc/render.md
            ShaderTryUniform(shader, 'MainTex', obj.mesh:getTexture())
            if obj.instanceCount then
                LG.drawInstanced(obj.mesh, obj.instanceCount)
            else
                LG.draw(obj.mesh)
            end
        end
    end
end

return batcher
