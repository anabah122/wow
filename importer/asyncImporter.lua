-- асинхронный импортер на пуле тредов
-- API: asyncImporter.gltf{ path = ..., onReady = function(parts) end }
-- внутри треда используется тот же importer.formats.gltf

local WORKER_CODE = [[
    require 'love.graphics'
    require 'love.image'
    require 'love.filesystem'
    require 'love.data'
    require 'love.timer'

    local id      = ...
    local jobsCh  = love.thread.getChannel('asyncImporter.jobs')
    local doneCh  = love.thread.getChannel('asyncImporter.done')

    local importer = require 'importer.importer'

    while true do
        local job = jobsCh:demand()
        if job == 'quit' then return end

        local ok, result = pcall(function()
            if job.format == 'gltf' then
                return importer.gltf.load{ path = job.path }
            end
            error('unknown format: ' .. tostring(job.format))
        end)

        doneCh:push{ jobId = job.jobId, ok = ok, result = result }
    end
]]

local M = {}

local WORKERS = 8
local workers = nil
local jobsCh, doneCh
local nextJobId = 1
local pending = {}

local function init()
    if workers then return end
    workers = {}
    jobsCh = love.thread.getChannel('asyncImporter.jobs')
    doneCh = love.thread.getChannel('asyncImporter.done')
    for i = 1, WORKERS do
        local t = love.thread.newThread(WORKER_CODE)
        t:start(i)
        workers[i] = t
    end
end

local function submit(format, args, onReady)
    init()
    local id = nextJobId
    nextJobId = nextJobId + 1
    pending[id] = onReady
    jobsCh:push{ jobId = id, format = format, path = args.path }
end

function M.gltf(args)
    submit('gltf', args, args.onReady)
end

-- вызывать каждый кадр чтобы вытаскивать готовые результаты
function M.poll()
    while true do
        local msg = doneCh:pop()
        if not msg then return end
        local cb = pending[msg.jobId]
        pending[msg.jobId] = nil
        if cb then
            if msg.ok then cb(msg.result) else print('[asyncImporter] error:', msg.result) end
        end
    end
end

function M.shutdown()
    if not workers then return end
    for _ = 1, #workers do jobsCh:push('quit') end
    for _, t in ipairs(workers) do t:wait() end
    workers = nil
end

return M
