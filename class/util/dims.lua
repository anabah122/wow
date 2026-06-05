-- размеры террейна в одном месте.
local CHUNK = 64   -- ячеек на сторону чанка
local BLOCK = 10   -- чанков на сторону блока

return {
    CHUNK = CHUNK,
    BLOCK = BLOCK,
    SIZE  = CHUNK * BLOCK,   -- ячеек/текселей на сторону блока
}
