Chronicle = Chronicle or {}

-- CodexTrace: traza TEMPORAL de los clics del árbol del Codex (rama `correccion-codex-arbol`; NO debe ir en la versión final). Sirve para ver en el
-- cliente real qué botón de la fila recibe el clic y qué hace el modelo. APAGADA por defecto: no hace nada hasta que se activa.
--
--   /chronicle debug codex on       activa la traza (reinicia el contador)
--   /chronicle debug codex off      la desactiva
--   /chronicle debug codex          estado (activada o no, líneas usadas)
--
-- Una línea por CLIC en una fila del árbol (nada por fotograma, ningún temporizador), con un LÍMITE de 40 líneas por activación:
--   [clic] SELECCIÓN ...  el clic lo recibió el botón de selección (si el ratón estaba sobre el «+», ese botón le robó el clic)
--   [clic] +/- ...        el clic lo recibió el botón +/-, con el resultado de model:Toggle y las filas visibles después
-- Para retirarla: borrar este fichero, su línea del .toc y de Core/Init.lua, y las llamadas `Trace(...)` de UI/CodexNavigation.lua.

local MAX_LINES = 40

local function NewTrace(deps)
    local self = {}
    local enabled, used, capNotified = false, 0, false

    local function Print(message)
        if type(deps.print) == "function" then deps.print("[codex] " .. message) end
    end

    function self:IsEnabled() return enabled end

    function self:SetEnabled(value)
        enabled = value == true
        if enabled then used, capNotified = 0, false end
    end

    -- `build` es una función que devuelve el texto: no se evalúa nada si la traza está apagada o llena.
    function self:Log(build)
        if not enabled then
            return
        end
        if used >= MAX_LINES then
            if not capNotified then
                capNotified = true
                Print("límite de " .. MAX_LINES .. " líneas alcanzado; `/chronicle debug codex on` la reinicia")
            end
            return
        end
        local ok, text = pcall(build)
        if ok and text then
            used = used + 1
            Print(tostring(text))
        end
    end

    function self:Handle(args)
        local parts = {}
        for word in tostring(args or ""):gmatch("%S+") do parts[#parts + 1] = word end
        if parts[1] ~= "codex" then
            Print("uso: /chronicle debug codex [on|off]")
        elseif parts[2] == "on" then
            self:SetEnabled(true)
            Print("traza de clics ACTIVADA (máximo " .. MAX_LINES .. " líneas)")
        elseif parts[2] == "off" then
            self:SetEnabled(false)
            Print("traza de clics desactivada")
        elseif parts[2] == nil then
            Print("traza de clics: " .. (enabled and "ACTIVADA" or "desactivada") .. " (" .. used .. "/" .. MAX_LINES .. " líneas)")
        else
            Print("uso: /chronicle debug codex [on|off]")
        end
    end

    local initDone = false
    function self:Init()
        if initDone then
            return
        end
        local slash = type(deps.slash) == "function" and deps.slash() or deps.slash
        if type(slash) ~= "table" or type(slash.Register) ~= "function" then
            error("CodexTrace: Slash no está disponible", 0)
        end
        slash:Register("debug", function(args) self:Handle(args) end)
        initDone = true
    end

    function self:IsReady() return initDone end

    return self
end

Chronicle.CodexTrace = NewTrace({
    slash = function() return Chronicle.Slash end,
    print = function(message) Chronicle.Utils.Print(message) end,
})
Chronicle.CodexTrace.New = NewTrace
