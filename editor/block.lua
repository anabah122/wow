-- редактируемый блок: CPU-буферы высоты/материалов + GPU-текстуры.
-- кисть пишет в ImageData, dirty-флаг -> refresh текстуры раз в кадр.
local dims = require 'class.util.dims'
local ffi  = require 'ffi'

local SIZE  = dims.SIZE
local HSIZE = SIZE + 1          -- вершин высоты на сторону (края чанков общие)
local CHUNK = dims.CHUNK
local BLOCK = dims.BLOCK

local Block = {}
Block.__index = Block

function Block:new(matCount)
    local self = setmetatable({}, Block)
    self.matCount = math.max(1, matCount or 1)   -- для нормировки индексов в карте

    self.height   = love.image.newImageData(HSIZE, HSIZE, 'r32f')   -- per-vertex (SIZE+1)
    self.material = love.image.newImageData(HSIZE, HSIZE, 'rgba8')  -- веса 4 слоёв, как высота (HSIZE)
    self.matIndex = love.image.newImageData(BLOCK, BLOCK, 'rgba8')  -- 1 пиксель = чанк, RGBA = 4 индекса/total
    self.heightF  = ffi.cast('float*', self.height:getFFIPointer())

    -- matInd[chunk] = {i1,i2,i3,i4} индексы материалов (0 = пусто)
    self.matInd = {}
    for c = 1, BLOCK * BLOCK do self.matInd[c] = { 0, 0, 0, 0 } end

    self.heightTex   = love.graphics.newImage(self.height)
    self.materialTex = love.graphics.newImage(self.material)
    self.matIndexTex = love.graphics.newImage(self.matIndex)
    self.heightTex:setFilter('linear', 'linear');   self.heightTex:setWrap('clamp')
    self.materialTex:setFilter('linear', 'linear'); self.materialTex:setWrap('clamp')
    self.matIndexTex:setFilter('nearest', 'nearest'); self.matIndexTex:setWrap('clamp')

    self.hDirty, self.mDirty, self.iDirty = false, false, false
    return self
end

-- высота: индекс в float-буфере (x,y в текселях 0..SIZE)
function Block:hAt(x, y) return self.heightF[y * HSIZE + x] end
function Block:setH(x, y, v) self.heightF[y * HSIZE + x] = v; self.hDirty = true end

-- высота по мировой XZ (блок центрирован в нуле: мир -SIZE/2..SIZE/2)
function Block:hAtWorld(wx, wz)
    local x = math.max(0, math.min(SIZE, math.floor(wx + SIZE / 2 + 0.5)))
    local y = math.max(0, math.min(SIZE, math.floor(wz + SIZE / 2 + 0.5)))
    return self:hAt(x, y)
end

-- чанк по текселю материала -> индекс чанка, cx, cy
function Block:chunkAt(tx, ty)
    local cx = math.min(BLOCK - 1, math.floor(tx / CHUNK))
    local cy = math.min(BLOCK - 1, math.floor(ty / CHUNK))
    return cy * BLOCK + cx + 1, cx, cy
end

-- слот материала mat в чанке. 1=база (кроет весь чанк), 2/3/4=слои поверх (RGB).
-- материал занимает первый свободный слот. nil если все 4 заняты другими.
local function slotFor(ind, mat)
    for i = 1, 4 do if ind[i] == mat then return i end end
    for i = 1, 4 do if ind[i] == 0   then ind[i] = mat; return i end end
    return nil
end

-- вес материала mat в текселе ПО ИНДЕКСУ (а не по слоту): слот ищется в чанке текселя.
-- база (слот 1) = остаток 1-(r+g+b). если mat в чанке нет — 0.
function Block:materialWeight(tx, ty, mat)
    local chunk = self:chunkAt(tx, ty)
    local ind = self.matInd[chunk]
    local r, g, b = self.material:getPixel(tx, ty)
    for i = 1, 4 do
        if ind[i] == mat then
            if i == 1 then return 1 - (r + g + b) end
            return ({ r, g, b })[i - 1]
        end
    end
    return 0
end

-- выставить вес материала mat в текселе равным target (0..1), согласованно гася остальные слои.
-- слот для mat заводится в чанке (как при покраске) -> в соседних чанках слоты могут быть разными,
-- но интерполяция идёт по материалу, поэтому переход через границу непрерывен.
function Block:setMaterialWeight(tx, ty, mat, target)
    local chunk, cx, cy = self:chunkAt(tx, ty)
    local ind = self.matInd[chunk]
    local slot = slotFor(ind, mat)
    if not slot then return false end

    self.matIndex:setPixel(cx, cy,
        ind[1] / self.matCount, ind[2] / self.matCount,
        ind[3] / self.matCount, ind[4] / self.matCount)
    self.iDirty = true

    target = math.min(1, target)
    local px = { self.material:getPixel(tx, ty) }   -- r,g,b = слои 2,3,4 (база = остаток)
    -- взаимоисключение: красимый слой растёт до target, остальные гаснут на (1-target).
    for i = 1, 3 do px[i] = px[i] * (1 - target) end
    if slot > 1 then px[slot - 1] = px[slot - 1] + target end  -- для базы ничего не добавляем -> она остаток
    self.material:setPixel(tx, ty, px[1], px[2], px[3], 1)
    self.mDirty = true
    return true
end

function Block:refresh()
    if self.hDirty then self.heightTex:replacePixels(self.height);     self.hDirty = false end
    if self.mDirty then self.materialTex:replacePixels(self.material); self.mDirty = false end
    if self.iDirty then self.matIndexTex:replacePixels(self.matIndex); self.iDirty = false end
end

Block.SIZE, Block.HSIZE = SIZE, HSIZE
return Block
