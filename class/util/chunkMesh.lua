-- генератор плоской сетки чанка для инстансинга террейна.
-- VertexPosition — локальная XZ ячейки (0..CHUNK).
-- VertexTexCoord — нормализованный grid 0..1 для сэмпла карты высот.

local CHUNK = require('class.util.dims').CHUNK   -- ячеек на сторону чанка
local OUTER = CHUNK + 1                          -- вершин на сторону

local function generateChunkMesh()
    local verts = {}
    for row = 0, OUTER - 1 do
        for col = 0, OUTER - 1 do
            verts[#verts+1] = {
                col, row,                                -- локальная позиция XZ
                col / (OUTER - 1), row / (OUTER - 1),    -- grid 0..1
            }
        end
    end

    local map = {}
    for row = 0, OUTER - 2 do
        for col = 0, OUTER - 2 do
            local a = row * OUTER + col + 1
            local b, c, d = a + 1, a + OUTER, a + OUTER + 1
            map[#map+1] = a; map[#map+1] = c; map[#map+1] = b
            map[#map+1] = b; map[#map+1] = c; map[#map+1] = d
        end
    end

    local fmt = {
        { 'VertexPosition', 'float', 2 },  -- локальная XZ
        { 'VertexTexCoord', 'float', 2 },  -- grid 0..1
    }
    local mesh = LG.newMesh(fmt, verts, 'triangles', 'static')
    mesh:setVertexMap(map)
    return mesh
end

return generateChunkMesh
