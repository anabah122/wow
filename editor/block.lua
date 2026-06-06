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
    self.matIndex = love.image.newImageData(BLOCK, BLOCK, 'rgba8')  -- 1 пиксель = чанк, RGBA = 4 индекса/total
    self.heightF  = ffi.cast('float*', self.height:getFFIPointer())

    -- веса материалов: ОДНА альфа-карта на материал (глобальный индекс = слой ArrayImage).
    -- слой i = вес материала i по всему блоку -> на стыке чанков тот же слой -> бесшовно.
    -- слой материала-базы (1) не редактируется: база = остаток 1-(сумма накладок) в шейдере.
    self.weight = {}          -- weight[m] = ImageData r8 (HSIZE), 0 по умолчанию
    for m = 1, self.matCount do
        self.weight[m] = love.image.newImageData(HSIZE, HSIZE, 'r8')
    end

    -- matInd[chunk] = {i1,i2,i3,i4} глобальные индексы материалов в чанке.
    -- слот 1 = база (материал 1, проступает где остаток), слоты 2..4 — накладки (0 = пусто).
    self.matInd = {}
    for c = 1, BLOCK * BLOCK do self.matInd[c] = { 1, 0, 0, 0 } end
    for cy = 0, BLOCK - 1 do for cx = 0, BLOCK - 1 do
        self.matIndex:setPixel(cx, cy, 1 / self.matCount, 0, 0, 1)   -- старт: база = материал 1
    end end

    self.heightTex   = love.graphics.newImage(self.height)
    self.matIndexTex = love.graphics.newImage(self.matIndex)
    self.weightArray = love.graphics.newArrayImage(self.weight)
    self.heightTex:setFilter('linear', 'linear');   self.heightTex:setWrap('clamp')
    self.matIndexTex:setFilter('nearest', 'nearest'); self.matIndexTex:setWrap('clamp')
    self.weightArray:setFilter('linear', 'linear');  self.weightArray:setWrap('clamp')

    self.hDirty, self.iDirty = false, false
    self.wDirty = {}          -- wDirty[m] = слой требует replacePixels
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

-- зарезервировать слот накладки mat в чанке (слоты 2..4; слот 1 = база, материал 1).
-- nil если 3 слота-накладки заняты другими материалами.
local function reserveSlot(ind, mat)
    for i = 2, 4 do if ind[i] == mat then return true end end
    for i = 2, 4 do if ind[i] == 0   then ind[i] = mat; return true end end
    return nil
end

-- вес материала mat в текселе: читаем прямо из слоя материала (глобальный индекс).
function Block:materialWeight(tx, ty, mat)
    return (self.weight[mat]:getPixel(tx, ty))
end

-- выставить вес материала mat в текселе равным target (0..1). пишем ТОЛЬКО слой mat,
-- остальные не трогаем -> нет взаимного гашения и нет проступающей базы между накладками.
-- замещение даёт шейдер: накладки рисуются поверх базы по своей альфе в порядке слотов.
function Block:setMaterialWeight(tx, ty, mat, target)
    if mat == 1 then return false end               -- базу не красят (она фон)
    local chunk, cx, cy = self:chunkAt(tx, ty)
    local ind = self.matInd[chunk]
    if not reserveSlot(ind, mat) then return false end

    self.matIndex:setPixel(cx, cy,
        ind[1] / self.matCount, ind[2] / self.matCount,
        ind[3] / self.matCount, ind[4] / self.matCount)
    self.iDirty = true

    self.weight[mat]:setPixel(tx, ty, math.max(0, math.min(1, target)), 0, 0, 1)
    self.wDirty[mat] = true
    return true
end

function Block:refresh()
    if self.hDirty then self.heightTex:replacePixels(self.height);   self.hDirty = false end
    if self.iDirty then self.matIndexTex:replacePixels(self.matIndex); self.iDirty = false end
    for m in pairs(self.wDirty) do
        self.weightArray:replacePixels(self.weight[m], m)   -- обновить слой материала m
    end
    self.wDirty = {}
end

Block.SIZE, Block.HSIZE = SIZE, HSIZE
return Block
