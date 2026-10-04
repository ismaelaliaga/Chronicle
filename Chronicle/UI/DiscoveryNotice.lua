Chronicle = Chronicle or {}

-- DiscoveryNotice: el aviso emergente que sale al DESCUBRIR algo por primera vez. Es el eslabón que faltaba entre Discovery y el Popup: Discovery
-- emite Chronicle.Discovery.Discovered (un argumento: el ID) y el Popup muestra lo que le dan, pero nada los unía (solo el Codex escuchaba el evento).
--
-- RECORRIDO: evento del cliente -> ZoneDiscovery -> Discovery:Discover(id) -> «new»: se emite Chronicle.Discovery.Discovered(id) -> ESTE módulo ->
-- Popup:Enqueue({ title, body }). Un descubrimiento «already» no emite el evento (Discovery solo lo emite la primera vez), así que cambiar de zona
-- hacia un sitio ya descubierto no genera ningún aviso. El descubrimiento de NPC (cuando exista) usa el mismo evento y obtiene su aviso sin cambios.
--
-- CONTENIDO: título = nombre localizado de la entidad; cuerpo = su descripción localizada (cualquiera puede faltar, pero no ambos). Nunca se usa el ID
-- como texto. PRIVACIDAD: solo se avisa de una entidad que Discovery confirma como descubierta ahora mismo; ante cualquier duda no se muestra nada.
--
-- FALLOS: un error o un rechazo del Popup nunca se propaga (Discovery ya guardó el progreso). Tampoco es silencioso: se cuenta en GetStats().failed[motivo]
-- y se comunica por geterrorhandler UNA vez por motivo. No hay temporizadores ni frames propios; no guarda nada ni escribe en State.
--
-- API: DiscoveryNotice:Init() (idempotente; se suscribe una sola vez)  :IsReady()
--      DiscoveryNotice:GetStats() -> { requested = n, queued = n, shown = n, skipped = { motivo = n }, failed = { motivo = n } } (copia)
--        requested: avisos pedidos al Popup. shown/queued: lo que respondió el Popup ("shown"/"queued"). skipped: no se pidió ("invalid_id",
--        "not_discovered", "no_content", "duplicate"). failed: el Popup no lo aceptó o falló ("not_ready", "queue_full", "ui_error", "popup_error"...).
--      DiscoveryNotice.New({ events, discovery, localization, popup }) crea otra instancia (pruebas); cada dependencia es el objeto o una función que lo devuelve.

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function NewNotice(deps)
    deps = type(deps) == "table" and deps or {}
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" then
            local ok, value = pcall(dep)
            return ok and value or nil
        end
        return dep
    end

    local self = {}
    local initDone = false
    local stats = { requested = 0, queued = 0, shown = 0, skipped = {}, failed = {} }
    local reported = {}
    local noticed = {} -- IDs cuyo aviso aceptó el Popup en esta sesión: un evento repetido no los avisa dos veces

    local function Count(bucket, reason)
        bucket[reason] = (bucket[reason] or 0) + 1
    end

    local function Fail(reason, detail)
        Count(stats.failed, reason)
        if not reported[reason] then
            reported[reason] = true
            ReportError("Chronicle.DiscoveryNotice: no se pudo mostrar un aviso de descubrimiento (" .. reason .. ")"
                .. (detail and (": " .. tostring(detail)) or "") .. ". El descubrimiento SÍ se ha guardado.")
        end
    end

    local function Text(localization, id, field)
        if not IsObject(localization) or type(localization.Get) ~= "function" then
            return nil
        end
        local ok, value = pcall(localization.Get, localization, id, field)
        if ok and type(value) == "string" and value:match("%S") then
            return value
        end
        return nil
    end

    -- Función FIJA: registrarla otra vez no la duplica.
    local function OnDiscovered(id)
        if type(id) ~= "string" or id == "" then
            Count(stats.skipped, "invalid_id")
            return
        end
        if noticed[id] then
            Count(stats.skipped, "duplicate") -- Discovery solo emite en la primera vez; esto protege de un evento repetido
            return
        end
        local discovery = Dep("discovery")
        local okD, discovered = false, false
        if IsObject(discovery) and type(discovery.IsDiscovered) == "function" then
            okD, discovered = pcall(discovery.IsDiscovered, discovery, id)
        end
        if not okD or discovered ~= true then
            Count(stats.skipped, "not_discovered") -- nunca se avisa de algo que Discovery no confirma
            return
        end
        local localization = Dep("localization")
        local title, body = Text(localization, id, "name"), Text(localization, id, "description")
        if not title and not body then
            Count(stats.skipped, "no_content")
            return
        end
        local popup = Dep("popup")
        if not IsObject(popup) or type(popup.Enqueue) ~= "function" then
            stats.requested = stats.requested + 1
            Fail("no_popup")
            return
        end
        stats.requested = stats.requested + 1
        local ok, accepted, how = pcall(popup.Enqueue, popup, { title = title or "", body = body or "" })
        if not ok then
            Fail("popup_error", accepted)
        elseif accepted ~= true then
            Fail(type(how) == "string" and how or "ui_error", how)
        else
            noticed[id] = true -- solo si el Popup lo aceptó: un aviso rechazado puede reintentarse
            if how == "shown" then
                stats.shown = stats.shown + 1
            else
                stats.queued = stats.queued + 1
            end
        end
    end

    function self:Init()
        if initDone then
            return
        end
        local events, discovery = Dep("events"), Dep("discovery")
        if not IsObject(events) or type(events.Register) ~= "function" then
            error("DiscoveryNotice: Events no está disponible", 0)
        end
        local eventName = IsObject(discovery) and discovery.EVENT_DISCOVERED or nil
        if type(eventName) ~= "string" or eventName == "" then
            error("DiscoveryNotice: Discovery no declara su evento (EVENT_DISCOVERED)", 0)
        end
        events:Register(eventName, OnDiscovered)
        initDone = true
    end

    function self:IsReady()
        return initDone
    end

    function self:GetStats()
        local copy = { requested = stats.requested, queued = stats.queued, shown = stats.shown, skipped = {}, failed = {} }
        for k, v in pairs(stats.skipped) do copy.skipped[k] = v end
        for k, v in pairs(stats.failed) do copy.failed[k] = v end
        return copy
    end

    return self
end

Chronicle.DiscoveryNotice = NewNotice({
    events = function() return Chronicle.Events end,
    discovery = function() return Chronicle.Discovery end,
    localization = function() return Chronicle.Localization end,
    popup = function() return Chronicle.Popup end,
})
Chronicle.DiscoveryNotice.New = NewNotice
