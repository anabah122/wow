-- ── асинк-пул импорта ────────────────────────────────────────────────────────
-- N воркер-тредов парсят .adt в фоне. Не знает про террейн и про GPU.
-- submit(path) — поставить задачу. poll() — забрать готовые результаты (0+).
-- результат = таблица из terrainImporter (heightData/maskData/names/instances).

local WORKER = [[
require('love.image')
require('love.filesystem')
local importTile = require 'class.terrainImporter'
local jobs    = love.thread.getChannel('terrain_jobs')
local results = love.thread.getChannel('terrain_results')
while true do
    local path = jobs:demand()        -- блокируемся пока нет задачи
    if path == '__stop__' then break end
    local ok, res = pcall(importTile, path)
    if ok then
        results:push(res)
    else
        results:push({ error = tostring(res), path = path })
    end
end
]]

local Pool = {}
Pool.__index = Pool

function Pool:new(workerCount)
    local self = setmetatable({}, Pool)
    self.jobs    = love.thread.getChannel('terrain_jobs')
    self.results = love.thread.getChannel('terrain_results')
    self.threads = {}
    for i = 1, (workerCount or 4) do
        local t = love.thread.newThread(WORKER)
        t:start()
        self.threads[i] = t
    end
    return self
end

function Pool:submit(path)
    self.jobs:push(path)
end

-- вернуть все готовые результаты на этот момент (может быть пусто)
function Pool:poll()
    local out = {}
    while true do
        local r = self.results:pop()
        if not r then break end
        if r.error then
            print('import error [' .. tostring(r.path) .. ']: ' .. r.error)
        else
            out[#out+1] = r
        end
    end
    return out
end

function Pool:shutdown()
    for _ = 1, #self.threads do self.jobs:push('__stop__') end
end

return Pool
