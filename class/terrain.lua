local Pool              = require 'class.terrainPool'
local generateChunkMesh = require 'class.util.chunkMesh'
local Timer             = require 'class.util.timer'

local HATLAS  = 2048          -- атлас высот
local HGRID   = 129           -- высот на сторону тайла
local HSTEP   = HGRID - 1
local MATLAS  = 4096          -- атлас масок
local MTILE   = 512           -- маск-окно тайла
local MAXINST   = 16384       -- вместимость инстанс-буфера (фикс, меш не растёт)
local MAXSLICES = 128         -- вместимость ArrayImage текстур (фикс, доливаем по слою)
local TEXSIZE   = 256         -- сторона текстурного тайла
local WORKERS   = 8

-- бюджет main-обработки импорта за кадр (сек) + проверка с yield
MainImportBudget   = MainImportBudget or 0.002
local mainDeadline = 0
local function checkMainBudget()
    if love.timer.getTime() >= mainDeadline then 
        coroutine.yield() 
    end
end

local INSTANCE_FMT = {
    { 'iWorldXZ',  'float', 2 },
    { 'iHeightUV', 'float', 2 },
    { 'iMaskUV',   'float', 2 },
    { 'iLayers',   'float', 4 },
    { 'iNLayers',  'float', 1 },
}

local terrainShader = LG.newShader('shader/wow.glsl')

local Terrain = {}
Terrain.__index = Terrain

function Terrain:new()
    local self = setmetatable({}, Terrain)

    -- пустые ImageData нужны только чтобы задать размер/формат текстур-атласов;
    -- реальные данные заливаются регионами через replacePixels из ImageData воркеров
    self.heightTex = LG.newImage(love.image.newImageData(HATLAS, HATLAS, 'r32f'))
    self.heightTex:setFilter('linear', 'linear'); self.heightTex:setWrap('clamp')

    self.maskTex = LG.newImage(love.image.newImageData(MATLAS, MATLAS, 'rgba8'))
    self.maskTex:setFilter('linear', 'linear'); self.maskTex:setWrap('clamp')

    self.chunkMesh = generateChunkMesh()
    -- инстанс-буфер фикс размера, пишем по одному setVertex (меш не расширяется)
    self.instanceMesh = LG.newMesh(INSTANCE_FMT, MAXINST, nil, 'dynamic')
    for _, a in ipairs{ 'iWorldXZ','iHeightUV','iMaskUV','iLayers','iNLayers' } do
        self.chunkMesh:attachAttribute(a, self.instanceMesh, 'perinstance')
    end
    self.count = 0  -- сколько инстансов реально записано

    -- ArrayImage фикс размера; слои доливаем по одному через replacePixels (без пересборки)
    local blank = {}
    for i = 1, MAXSLICES do blank[i] = love.image.newImageData(TEXSIZE, TEXSIZE, 'rgba8') end
    self.diffuse = LG.newArrayImage(blank, { mipmaps = true })
    self.diffuse:setFilter('linear', 'linear')
    self.diffuse:setWrap('repeat', 'repeat')

    self.texIndex = {}   -- путь -> слой в diffuse (дедуп: уже декодено воркером)
    self.texCount = 0

    self.modelSet    = {}  -- путь .m2 -> true (дебаг: уникальные модели)
    self.doodadCount = 0   -- дебаг: всего инстансов

    self.pool = Pool:new(WORKERS)
    self.timer = Timer:new()
    self.processor = coroutine.create(function() self:processLoop() end)
    return self
end

function Terrain:import(path)
    local paths = type(path) == 'table' and path or { path }
    for _, p in ipairs(paths) do
        local tx, ty = p:match('_(%d+)_(%d+)%.adt$')
        tx, ty = tonumber(tx), tonumber(ty)
        self.baseTx = math.min(self.baseTx or tx, tx)
        self.baseTy = math.min(self.baseTy or ty, ty)
    end
    self.expected = (self.expected or 0) + #paths
    self.importStart = self.importStart or love.timer.getTime()
    for _, p in ipairs(paths) do self.pool:submit(p) end
end

function Terrain:registerTexture(tex)
    if not self.texIndex[tex.path] then
        self.texCount = self.texCount + 1
        self.timer:start('slice replace')
        self.diffuse:replacePixels(tex.data, self.texCount)  -- залить новый слой
        self.timer:stop('slice replace')
        self.texIndex[tex.path] = self.texCount
    end
    return self.texIndex[tex.path]
end

-- разложить один результат воркера: атласы (регион) + инстансы по одному.
-- зовётся из корутины; бюджет дробит через checkMainBudget между операциями.
function Terrain:placeResult(res)
    local dtx, dty = res.tx - self.baseTx, res.ty - self.baseTy
    local hx, hy = dtx * HSTEP, dty * HSTEP
    local mx, my = dtx * MTILE, dty * MTILE

    self.timer:start('heightTex replace')
    self.heightTex:replacePixels(res.heightData, nil, nil, hx, hy)
    self.timer:stop('heightTex replace')
    self.timer:start('maskTex replace')
    self.maskTex:replacePixels(res.maskData, nil, nil, mx, my)
    self.timer:stop('maskTex replace')
    checkMainBudget()

    local remap = { [0] = 0 }
    for localI, tex in ipairs(res.names) do
        remap[localI] = self:registerTexture(tex)
        checkMainBudget()
    end

    for _, inst in ipairs(res.instances) do
        self.count = self.count + 1
        self.instanceMesh:setVertex(self.count, {
            inst[1], inst[2],
            (hx + inst[3] * HSTEP) / HATLAS, (hy + inst[4] * HSTEP) / HATLAS,
            (mx + inst[5] * MTILE) / MATLAS, (my + inst[6] * MTILE) / MATLAS,
            remap[inst[7]], remap[inst[8]], remap[inst[9]], remap[inst[10]], inst[11],
        })
        checkMainBudget()
    end

    -- дебаг: учёт doodad-инстансов и уникальных моделей тайла
    for _, d in ipairs(res.doodads) do
        self.modelSet[res.models[d.model]] = true
        self.doodadCount = self.doodadCount + 1
    end

    self.placed = (self.placed or 0) + 1
end

-- единая корутина импорта: тянет результаты из пула, раскладывает, дробит бюджетом
function Terrain:processLoop()
    while true do
        local res = self.queue[1]
        if res then
            table.remove(self.queue, 1)
            self:placeResult(res)
            checkMainBudget()
        else
            coroutine.yield()
        end
    end
end

function Terrain:update(dt)
    mainDeadline = love.timer.getTime() + MainImportBudget
    self.queue = self.queue or {}
    for _, res in ipairs(self.pool:poll()) do
        self.queue[#self.queue+1] = res
    end
    -- крутим корутину пока есть бюджет и работа
    while love.timer.getTime() < mainDeadline and (#self.queue > 0 or self.pendingWork) do
        self.timer:start('resume')
        coroutine.resume(self.processor)
        self.timer:stop('resume')
        self.pendingWork = #self.queue > 0
    end

    if self.placed == self.expected and not self.dumped then
        self.dumped = true
        self.timer:dump()
        print(string.format('import total %.1f ms', (love.timer.getTime() - self.importStart) * 1000))
        local models = 0
        for _ in pairs(self.modelSet) do models = models + 1 end
        print(string.format('doodads %d  unique models %d', self.doodadCount, models))
    end
end

function Terrain:draw(camera)
    if self.count == 0 then return end
    LG.setShader(terrainShader)
    terrainShader:send('viewproj', camera:viewproj())
    terrainShader:send('heightmap', self.heightTex)
    terrainShader:send('maskmap', self.maskTex)
    terrainShader:send('diffuse', self.diffuse)
    terrainShader:send('hTexel', 1 / HATLAS)
    terrainShader:send('hSpan', 8 / HATLAS)
    terrainShader:send('mSpan', 31 / MATLAS)
    terrainShader:send('mInset', 0.5 / MATLAS)
    terrainShader:send('texTile', 8)
    LG.drawInstanced(self.chunkMesh, self.count)
    LG.setShader()
    self.drawn = self.count
end

return Terrain
