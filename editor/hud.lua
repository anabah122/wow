-- HUD редактора: fps, текущий инструмент/радиус/материал, подсказки.
local hud = {}

local HELP = {
    '[1] raise  [2] lower  [3] smooth  [4] flatten  [5] paint  [6] procedural',
    'M: palette   R: reload mats   <-/->: proc mat   shift+wheel: radius   alt+wheel: strength   LMB: draw',
}

-- state: { fps, tool, radius, matName, aim }
function hud.draw(state)
    LG.setColor(1, 1, 1)
    LG.print('fps ' .. state.fps, 10, 10)
    LG.print('tool: '   .. state.tool,    10, 30)
    LG.print('radius: '   .. state.radius,   10, 50)
    LG.print('strength: ' .. state.strength, 10, 70)
    LG.print('mat: '      .. state.matName,  10, 90)

    LG.print(HELP[1], 10, LG.getHeight() - 44)
    LG.print(HELP[2], 10, LG.getHeight() - 24)
end

return hud
