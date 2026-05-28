local Baker = {}
Baker.__index = Baker

function Baker:new(opts)
    local self = setmetatable({}, Baker)
    self.canvas = opts.canvas
    self.tiles  = opts.tiles
    return self
end

function Baker:bake()
    LG.setCanvas(self.canvas)
    LG.clear(0, 0, 0, 1)
    for _, t in ipairs(self.tiles) do
        LG.draw(t.tex, t.x, t.y, 0, t.sx, t.sy)
    end
    LG.setCanvas()
end

return Baker
