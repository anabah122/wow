-- Сборка love.Mesh из данных импортёра.
-- data = { verts = {{x,y,z,u,v,nx,ny,nz}, ...}, indices = {...}?, texture = Image? }
-- Использование (одинаково для sync и async):
--   local b = MeshBuilder:new(data, budget)   -- budget сек; math.huge = sync
--   if not b.result then b:step() else go.mesh = b.result end

local vertexFmt = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexNormal',   'float', 3 },
}

MeshBuilder = {}
MeshBuilder.__index = MeshBuilder

function MeshBuilder:new(data, budget)
    local self = setmetatable({}, MeshBuilder)
    self.data   = data
    self.budget = budget or math.huge
    self.i      = 1
    self.mesh   = LG.newMesh(vertexFmt, #data.verts, 'triangles', 'static')
    self.result = nil
    return self
end

function MeshBuilder:step()
    local start = LT.getTime()
    local mesh, verts, budget = self.mesh, self.data.verts, self.budget
    local n = #verts
    local i = self.i

    while i <= n do
        mesh:setVertex(i, verts[i])
        i = i + 1
        if LT.getTime() - start > budget then
            self.i = i
            return
        end
    end

    if self.data.indices then mesh:setVertexMap(self.data.indices) end
    if self.data.texture then mesh:setTexture(self.data.texture) end
    self.result = mesh
end

return MeshBuilder
