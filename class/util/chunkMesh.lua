-- генератор плоской сетки 9x9 для инстансинга чанков террейна.
-- VertexPosition — локальная XZ в мировом масштабе (0..MCNK размер, шаг UNIT).
-- VertexTexCoord — нормализованный grid 0..1 для сэмпла атласа высот.
-- мировое смещение чанка и окно в атласе даёт per-instance буфер.

local OUTER = 9                -- вершин на сторону MCNK
local UNIT  = 33.33333 / 8     -- шаг вершины (yard)

local function generateChunkMesh()
    local verts = {}
    for row = 0, OUTER - 1 do
        for col = 0, OUTER - 1 do
            verts[#verts+1] = {
                col * UNIT, row * UNIT,                  -- позиция XZ (мир, локально)
                col / (OUTER - 1), row / (OUTER - 1),    -- grid 0..1 для атласа
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
        { 'VertexPosition', 'float', 2 },  -- локальная XZ в ярдах
        { 'VertexTexCoord', 'float', 2 },  -- grid 0..1
    }
    local mesh = LG.newMesh(fmt, verts, 'triangles', 'static')
    mesh:setVertexMap(map)
    return mesh
end

return generateChunkMesh
