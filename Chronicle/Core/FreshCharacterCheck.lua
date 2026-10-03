Chronicle = Chronicle or {}

-- FreshCharacterCheck: detecta que un personaje recién creado (nivel 1, poco tiempo jugado) ya tiene progreso de Chronicle guardado. Servicio
-- aislado: no reinicia, borra ni sobrescribe nada del progreso y NO ESCRIBE NADA EN NINGÚN SITIO PERSISTENTE.
--
-- POR QUÉ EXISTE (comportamiento del addon original, leído en solo lectura). WoW guarda las SavedVariables por personaje usando
-- nombre+reino. Si se borra un personaje y se crea otro con el MISMO nombre en el mismo reino, el nuevo hereda el fichero del anterior y
-- Chronicle mostraría un progreso que no es suyo. El original lo detectaba con tres condiciones y preguntaba si reiniciar o mantener.
--
-- QUÉ DETECTA aquí (las tres condiciones del original, evaluadas en este orden)
--   1. UnitLevel("player") == 1, comprobado en PLAYER_ENTERING_WORLD.
--   2. Tiempo jugado total <= 1800 s (30 minutos). Se pide con RequestTimePlayed() y llega, asíncrono, en TIME_PLAYED_MSG (primer argumento:
--      segundos totales). NOTA: RequestTimePlayed imprime en el chat las líneas de «tiempo jugado» del cliente, como en el original.
--   3. Discovery:Count() > 0, es decir, ya hay progreso guardado. Se pregunta al servicio Discovery (no se lee la SavedVariable).
--   DESVIACIÓN respecto al original (deliberada): el original atendía CUALQUIER TIME_PLAYED_MSG, incluido un «/played» manual de un
--   personaje de cualquier nivel (el nivel solo se miraba al entrar). Aquí solo se atiende la respuesta a la petición propia, hecha
--   únicamente a nivel 1, de modo que el aviso no puede salir en un personaje que no sea nivel 1.
--
-- CUÁNTAS VECES: COMO MÁXIMO UNA POR SESIÓN, y el control vive SOLO EN MEMORIA, dentro de la instancia.
--   · NO HAY MARCA PERSISTENTE. El original guardaba «ya comprobado» en la SavedVariable, y esa marca es precisamente lo que NO puede
--     usarse aquí: se guardaría en el mismo fichero que hereda el personaje nuevo con el nombre de uno antiguo, así que si el anterior ya la
--     había escrito, el nuevo se saltaría la comprobación y nunca recibiría el aviso. Una marca en esas SavedVariables no garantiza que ESTE
--     personaje se haya comprobado. Por eso este módulo no necesita State y no escribe nada.
--   · Petición: PLAYER_ENTERING_WORLD salta en cada pantalla de carga, pero el tiempo jugado se pide UNA sola vez por sesión (aunque el
--     resultado sea desconocido: no se reintenta en la misma sesión).
--   · Comprobación completada: con una respuesta VÁLIDA (tiempo numérico finito >= 0 y Discovery listo) la comprobación se da por completada
--     en esta sesión —cumpla o no las condiciones— y no se procesa ninguna respuesta más. Con un resultado DESCONOCIDO (tiempo no válido,
--     Discovery no listo, ausente o que falla) NO se da por completada: no se afirma nada, no se avisa y no se guarda nada.
--   · Una sesión nueva (nueva instancia) vuelve a comprobar: así el personaje nuevo hereda la comprobación aunque las SavedVariables traigan
--     progreso y cualquier marca antigua (p. ej. una `freshCheck.done = true` escrita por la versión anterior de este módulo, que se ignora).
--   CONSECUENCIA ACEPTADA: mientras el personaje siga cumpliendo las condiciones (nivel 1, ≤ 30 min jugados y progreso guardado), el aviso PUEDE
--   VOLVER A APARECER en otra sesión. Es deliberado: evitarlo exigiría una marca persistente, que es lo que se ha descartado.
--
-- QUÉ HACE CON EL RESULTADO. Si las tres condiciones se cumplen: emite «Chronicle.FreshCharacter.Detected» (sin argumentos) por el bus de
-- eventos y, si hay Popup, encola un aviso informativo. El original ofrecía además «Reiniciar» o «Mantener»; REINICIAR NO SE OFRECE porque
-- Discovery no tiene (ni se le ha añadido) una operación de reinicio; el aviso lo dice con claridad (decisión pendiente del supervisor).
--
-- CONTRATO
--   FreshCharacterCheck:Evaluate(level, playedSeconds) -> "fresh" | "not_fresh" | "unknown"   (función pura sobre los datos + Discovery)
--   FreshCharacterCheck:IsCompleted() -> true si en ESTA sesión ya se procesó una respuesta válida (solo memoria)
--   FreshCharacterCheck:Init() / IsReady()   Init es idempotente: crea UN frame y registra los dos eventos UNA vez. Lanza error si falta CreateFrame.
--   FreshCharacterCheck.New({ discovery, popup, events, createFrame, unitLevel, requestTimePlayed }) crea otra instancia (pruebas).

local EVENT_DETECTED = "Chronicle.FreshCharacter.Detected"
local FRESH_LEVEL = 1
local FRESH_PLAYED_SECONDS = 30 * 60
local TITLE = "Chronicle"
local BODY = "Chronicle ha encontrado progreso guardado en este personaje, pero parece recién creado (nivel 1, poco tiempo jugado). "
    .. "Esto puede pasar si borraste un personaje y creaste otro con el mismo nombre: WoW guarda los datos del addon por nombre. "
    .. "Por ahora Chronicle no puede reiniciar ese progreso."

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function NewCheck(deps)
    if type(deps) ~= "table" then
        error("Chronicle.FreshCharacterCheck.New: se esperaba una tabla de dependencias", 2)
    end
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" and name ~= "unitLevel" and name ~= "requestTimePlayed" then
            return dep()
        end
        return dep
    end

    local self = {}
    local ready = false
    local frame
    -- Control de repetición: SOLO en memoria (ver la cabecera).
    local requested = false -- ya se pidió el tiempo jugado en esta sesión (una sola vez)
    local pending = false -- hay una petición propia sin responder
    local completed = false -- ya se procesó una respuesta válida en esta sesión

    function self:IsCompleted()
        return completed
    end

    function self:Evaluate(level, playedSeconds)
        if not IsFinite(level) or not IsFinite(playedSeconds) or playedSeconds < 0 then
            return "unknown"
        end
        if level ~= FRESH_LEVEL or playedSeconds > FRESH_PLAYED_SECONDS then
            return "not_fresh"
        end
        local discovery = Dep("discovery")
        if not IsObject(discovery) or type(discovery.IsReady) ~= "function" or type(discovery.Count) ~= "function" then
            return "unknown"
        end
        local okReady, isReady = pcall(discovery.IsReady, discovery)
        if not okReady or isReady ~= true then
            return "unknown"
        end
        local okCount, count = pcall(discovery.Count, discovery)
        if not okCount or not IsFinite(count) then
            return "unknown"
        end
        return count > 0 and "fresh" or "not_fresh"
    end

    local function Notify()
        local events = Dep("events")
        if IsObject(events) and type(events.Emit) == "function" then
            local ok, err = pcall(events.Emit, events, EVENT_DETECTED)
            if not ok then
                ReportError("Chronicle.FreshCharacterCheck: no se pudo emitir " .. EVENT_DETECTED .. ": " .. tostring(err))
            end
        end
        local popup = Dep("popup")
        if IsObject(popup) and type(popup.Enqueue) == "function" then
            pcall(popup.Enqueue, popup, { title = TITLE, body = BODY })
        end
    end

    local function OnEvent(_, event, totalTimePlayed)
        if completed then
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            if requested then
                return
            end
            local level = deps.unitLevel and deps.unitLevel("player")
            if level ~= FRESH_LEVEL then
                return
            end
            if type(deps.requestTimePlayed) ~= "function" then
                return
            end
            requested = true
            pending = true
            deps.requestTimePlayed()
        elseif event == "TIME_PLAYED_MSG" then
            if not pending then
                return
            end
            pending = false -- la respuesta a la petición propia se consume, sea válida o no
            local outcome = self:Evaluate(FRESH_LEVEL, totalTimePlayed)
            if outcome == "unknown" then
                return -- no se da por completada ni se afirma nada
            end
            completed = true
            if outcome == "fresh" then
                Notify()
            end
        end
    end

    function self:Init()
        if ready then
            return
        end
        if type(deps.createFrame) ~= "function" then
            error("FreshCharacterCheck: CreateFrame no está disponible", 0)
        end
        if not frame then
            local created = deps.createFrame("Frame")
            if not IsObject(created) then
                error("FreshCharacterCheck: CreateFrame no devolvió un frame", 0)
            end
            frame = created
            created:RegisterEvent("PLAYER_ENTERING_WORLD")
            created:RegisterEvent("TIME_PLAYED_MSG")
            created:SetScript("OnEvent", OnEvent)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    return self
end

Chronicle.FreshCharacterCheck = NewCheck({
    discovery = function() return Chronicle.Discovery end,
    popup = function() return Chronicle.Popup end,
    events = function() return Chronicle.Events end,
    createFrame = function(...) return CreateFrame(...) end,
    unitLevel = function(...) if UnitLevel then return UnitLevel(...) end end,
    requestTimePlayed = function(...) if RequestTimePlayed then return RequestTimePlayed(...) end end,
})
Chronicle.FreshCharacterCheck.New = NewCheck
Chronicle.FreshCharacterCheck.EVENT_DETECTED = EVENT_DETECTED
