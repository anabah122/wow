
LG = love.graphics
LF = love.filesystem
LT = love.timer
LK = love.keyboard
ser = require'lib.serpent'

function math.clamp(v,min,max)
    return math.min(math.max(v, min), max)
end

function math.lerp( a, b ,t )
    return a + t * (b - a);
end 

function math.round( v )
    return math.floor( v+0.5 )
end

function math.sign(x)
    if x > 0 then
        return 1
    elseif x < 0 then
        return -1
    else
        return 0
    end
end


function table.print( t , args )
    print( ser.block( t , args or { comment = false }) )
end


function table.contains(table, element)
  for index, value in ipairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

function table.copy(t, seen)
    if type(t) ~= "table" then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local copy = {}
    seen[t] = copy
    for k, v in pairs(t) do
        copy[table.copy(k, seen)] = table.copy(v, seen)
    end
    return setmetatable(copy, getmetatable(t))
end


dict={}

function dict.size( t )
    local c = 0
    for _,_ in pairs( t ) do c = c + 1 end 
    return c 
end

function dict.names( t )
    for k,v in pairs( t ) do print( k ) end
end

function dict.namesLen( t )
    for k,v in pairs( t ) do print( k, #v ) end
end


function ThisDir(level)
    local info = debug.getinfo((level or 1) + 1, "S")
    if not info then return nil end
    local src = info.source
    if src:sub(1,1) == "@" then src = src:sub(2) end
    return src:match("(.*[/\\])") or ""
end