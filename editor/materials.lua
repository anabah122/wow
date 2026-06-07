-- реестр процедурных материалов. материал = папка-модуль:
--   assets/editor/materials/<name>/material.json  { type=script|mask, main=init.lua }
--   <main>.lua  возвращает модуль { load(self,dir,tileIndex), apply(self,block,cx,cy,r,dt) }
--   модуль сам пишет веса в block через block:setMaterialWeight по глобальным индексам тайлов.
-- hot-reload по хоткею: сбросить package.loaded модулей и перечитать всё заново.
local json = require 'lib.json'

local ROOT = 'assets/editor/materials'

local Materials = {}
Materials.__index = Materials

-- загрузить один материал из папки. tileIndex(name)->globalIndex для разрешения тайлов.
local function loadOne(name, tileIndex)
    local dir  = ROOT .. '/' .. name
    local info = LF.read(dir .. '/material.json')
    if not info then return nil end
    local mf = json.decode(info)

    local mainPath = (dir .. '/' .. (mf.main or 'init.lua')):gsub('%.lua$', '')
    local chunk = mainPath:gsub('/', '.')
    package.loaded[chunk] = nil               -- сброс кэша -> hot-reload
    local ok, mod = pcall(require, chunk)
    if not ok then print('material error ' .. name .. ': ' .. tostring(mod)); return nil end

    mod.name, mod.type = name, mf.type
    if mod.load then mod:load(dir, tileIndex, mf) end
    return mod
end

-- tileIndex: function(tileName)->globalIndex (имя тайла из общей палитры -> индекс материала)
function Materials:new(tileIndex)
    local self = setmetatable({}, Materials)
    self.tileIndex = tileIndex
    self:reload()
    return self
end

function Materials:reload()
    self.list = {}
    if not LF.getInfo(ROOT) then return end
    for _, name in ipairs(LF.getDirectoryItems(ROOT)) do
        if LF.getInfo(ROOT .. '/' .. name, 'directory') then
            local mod = loadOne(name, self.tileIndex)
            if mod then self.list[#self.list + 1] = mod end
        end
    end
    self.selected = math.min(self.selected or 1, math.max(1, #self.list))
end

function Materials:current() return self.list[self.selected] end

return Materials
