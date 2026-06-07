-- палитра материалов: скан папки png, экран выбора сеткой превью.
-- индекс материала = позиция в отсортированном списке (1-based), как matInd в чанке.
local DIR  = 'assets/textures/tiles'
local CELL = 128
local PAD  = 12

local Palette = {}
Palette.__index = Palette

function Palette:new()
    local self = setmetatable({}, Palette)

    local files = {}
    for _, f in ipairs(LF.getInfo(DIR) and LF.getDirectoryItems(DIR) or {}) do
        if f:match('%.png$') then files[#files+1] = f end
    end
    table.sort(files)   -- индекс материала = позиция в отсортированном списке

    self.mats   = {}    -- { {name, tex}, ... } для превью
    local slices = {}   -- слои ArrayImage для рендера
    for i, f in ipairs(files) do
        local data = love.image.newImageData(DIR .. '/' .. f)
        local tex = LG.newImage(data); tex:setFilter('linear', 'linear')
        self.mats[i] = { name = f:gsub('%.png$', ''), tex = tex }
        slices[i] = data
    end

    if #slices > 0 then
        self.array = LG.newArrayImage(slices, { mipmaps = true })
        self.array:setFilter('linear', 'linear', 16)   -- mipmap + анизотропия против ряби на дали
        self.array:setMipmapFilter('linear')
        self.array:setWrap('repeat', 'repeat')
    end

    -- имя тайла -> глобальный индекс (= позиция в палитре). для процедурных материалов.
    self.indexOf = {}
    for i, m in ipairs(self.mats) do self.indexOf[m.name] = i end

    self.selected = 1
    self.open = false
    return self
end

-- глобальный индекс тайла по имени (nil если нет такого тайла в палитре)
function Palette:tileIndex(name) return self.indexOf[name] end

-- сетка: колонок по ширине окна
function Palette:cols() return math.max(1, math.floor((LG.getWidth() - PAD) / (CELL + PAD))) end

function Palette:cellAt(i)
    local cols = self:cols()
    local c = (i - 1) % cols
    local r = math.floor((i - 1) / cols)
    return PAD + c * (CELL + PAD), PAD + r * (CELL + PAD)
end

function Palette:mousepressed(mx, my, b)
    if b ~= 1 then return end
    for i = 1, #self.mats do
        local x, y = self:cellAt(i)
        if mx >= x and mx < x + CELL and my >= y and my < y + CELL then
            self.selected = i
            self.open = false
            return
        end
    end
end

function Palette:draw()
    LG.clear(0.1, 0.1, 0.12)
    for i, m in ipairs(self.mats) do
        local x, y = self:cellAt(i)
        LG.setColor(1, 1, 1)
        LG.draw(m.tex, x, y, 0, CELL / m.tex:getWidth(), CELL / m.tex:getHeight())
        if i == self.selected then
            LG.setColor(1, 0.8, 0.2); LG.rectangle('line', x, y, CELL, CELL)
        end
        LG.setColor(1, 1, 1); LG.print(m.name, x, y + CELL)
    end
    LG.setColor(1, 1, 1)
    LG.print('material palette — click to select, M to close', PAD, LG.getHeight() - 24)
end

return Palette
