-- мини-профайлер: копит максимум времени исполнения по комментарию
local Timer = {}
Timer.__index = Timer

function Timer:new()
    return setmetatable({ max = {}, t0 = {}, calls = {} }, Timer)
end

function Timer:start(comment)
    self.t0[comment] = love.timer.getTime()
end

function Timer:stop(comment)
    local dt = love.timer.getTime() - self.t0[comment]
    if dt > (self.max[comment] or 0) then self.max[comment] = dt end
    self.calls[comment] = (self.calls[comment] or 0) + 1
end

function Timer:dump()
    print('--- timer max (ms) ---')
    for comment, dt in pairs(self.max) do
        print(string.format('%-20s %.3f  x%d', comment, dt * 1000, self.calls[comment]))
    end
end

return Timer
