local size = 256

local FpsMean = {}
FpsMean.__index = FpsMean

function FpsMean:new(v)
    return setmetatable({}, FpsMean)
end

function FpsMean:add(v)
    table.insert(self,1,v)
    if #self > size then 
        table.remove( self )
    end
end

function FpsMean:get()
    local fps = 0 
    for _,v in ipairs( self ) do fps=fps + v end
    return math.floor( fps / size )
end

return FpsMean
