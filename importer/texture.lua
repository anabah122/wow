-- кэш текстур: один love.Image на уникальный путь
-- (gltf с embedded-картинкой сам декодит байты и кладёт сюда через cache_set)

local M = {}
local cache = {}


function M.import(path, opts)
    opts = opts or {}
    local tex = cache[path]
    if not tex then
        tex = love.graphics.newImage(path, { mipmaps = opts.mipmaps ~= false })
        cache[path] = tex
    end
    tex:setFilter("linear", "linear", opts.anisotropy or 1)
    tex:setWrap(opts.wrap or "repeat")
    return tex
end

--- Получить уже закэшированную текстуру по ключу, либо nil.
function M.get(key) return cache[key] end

--- Положить готовый love.Image в кэш под ключом (для embedded glb-текстур).
function M.put(key, tex)
    cache[key] = tex
    return tex
end

return M
