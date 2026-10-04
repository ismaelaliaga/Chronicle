Chronicle = Chronicle or {}

-- Diagnostics: herramienta TEMPORAL de diagnóstico del descubrimiento automático (rama `diagnostico-descubrimiento`; NO forma parte de la
-- candidata original). Sirve para ver, en el cliente real, en qué etapa se corta el recorrido
--   evento del cliente -> ZoneDiscovery:Check -> MapPosition (nombres) -> Resolver (ID) -> Discovery:Discover -> evento interno -> Codex.
-- No cambia el comportamiento del addon: solo OBSERVA, salvo `check`, que ejecuta ZoneDiscovery:Check() (lo mismo que hace el evento).
--
-- COMANDOS (con el subcomando `debug`; el primer argumento es siempre `discovery`)
--   /chronicle debug discovery            instantánea: servicios listos, Init.failed/skipped, nombres que da el cliente, lo que responde el
--   /chronicle debug discovery status     Resolver por tipo, el estado de Discovery y lo que respondería un modelo de Codex nuevo
--   /chronicle debug discovery check      ejecuta ZoneDiscovery:Check() ahora y muestra el resultado de cada etapa
--   /chronicle debug discovery on         activa las trazas (reinicia el contador) — ACTIVAS DESDE EL ARRANQUE en esta rama
--   /chronicle debug discovery off        las desactiva y restaura las funciones originales
-- Trazas (una línea por suceso, con un LÍMITE de 40 líneas por activación; nada por fotograma, ningún temporizador):
--   · [evento] cada evento de zona del cliente que llega a un frame del depurador (PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, ZONE_CHANGED,
--     ZONE_CHANGED_INDOORS). Si salen estas líneas pero no las de [check], el frame de ZoneDiscovery no recibe el evento o su manejador no corre.
--   · [check] cada llamada a ZoneDiscovery:Check() y su resultado (estado, nombre, ID y motivo de la zona y la subzona).
--   · [discover] cada llamada a Discovery:Discover(id) y su resultado.
--   · [descubierto] cada evento interno Chronicle.Discovery.Discovered: el ID, Discovery:IsDiscovered(id), Count() y si el Codex está listo/visible.
--
-- Las trazas envuelven temporalmente ZoneDiscovery.Check y Discovery.Discover (que ZoneDiscovery busca en el momento de llamarlas) y se
-- restauran al desactivarlas; activarlas dos veces no las envuelve dos veces.

local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }
local EVENT_DISCOVERED = "Chronicle.Discovery.Discovered"
local MAX_TRACE_LINES = 40
local TRACE_ON_LOAD = true
local RELEVANT = { "State", "Events", "Registry", "Localization", "Resolver", "Discovery", "MapPosition", "ZoneDiscovery", "Theme", "Popup", "Codex", "Diagnostics" }

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

-- Texto de un valor que deja ver espacios y caracteres invisibles: entre comillas y con su longitud en bytes.
local function Describe(value)
    if type(value) == "string" then
        return string.format("%q (%d bytes)", value, #value)
    end
    return tostring(value)
end

local function NewDiagnostics(deps)
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "print" and name ~= "createFrame" then
            return dep()
        end
        return dep
    end
    local function Print(message)
        if type(deps.print) == "function" then deps.print("[debug] " .. message) end
    end
    local function Safe(object, method, ...)
        if not IsObject(object) or type(object[method]) ~= "function" then
            return false, "no existe " .. method
        end
        return pcall(object[method], object, ...)
    end

    local self = {}
    local lines = 0
    local tracing = false
    local frame
    local originals = {}
    local initDone = false

    local function Trace(message)
        if not tracing then return end
        if lines >= MAX_TRACE_LINES then
            if lines == MAX_TRACE_LINES then
                lines = lines + 1
                Print("(límite de " .. MAX_TRACE_LINES .. " líneas de traza alcanzado; /chronicle debug discovery on lo reinicia)")
            end
            return
        end
        lines = lines + 1
        Print(message)
    end

    local function Outcome(o)
        if type(o) ~= "table" then return tostring(o) end
        return string.format("estado=%s nombre=%s id=%s motivo=%s", tostring(o.status), Describe(o.name), tostring(o.id), tostring(o.reason))
    end

    local function CheckSummary(result)
        if type(result) ~= "table" then return tostring(result) end
        if result.status ~= "checked" then return "estado=" .. tostring(result.status) end
        return "zona{" .. Outcome(result.zone) .. "} subzona{" .. Outcome(result.subzone) .. "}"
    end

    -- ---- instantánea ----
    function self:Snapshot()
        local init = Dep("init") or {}
        local state = Dep("state")
        Print("--- instantánea del descubrimiento ---")
        local okS, stateReady = Safe(state, "IsReady")
        local _, readOnly = Safe(state, "IsReadOnly")
        local _, schema = Safe(state, "GetSchemaVersion")
        Print("State: listo=" .. tostring(okS and stateReady) .. " soloLectura=" .. tostring(readOnly) .. " schemaVersion=" .. tostring(schema))
        Print("Init: ready=" .. tostring(init.ready) .. " initialized=" .. tostring(init.initialized))
        local failed, skipped = {}, {}
        for _, name in ipairs(RELEVANT) do
            if init.failed and init.failed[name] then failed[#failed + 1] = name .. ": " .. tostring(init.failed[name]):sub(1, 160) end
            if init.skipped and init.skipped[name] then skipped[#skipped + 1] = name .. ": " .. tostring(init.skipped[name]):sub(1, 100) end
        end
        Print("Init.failed (módulos relevantes): " .. (#failed > 0 and table.concat(failed, " | ") or "ninguno"))
        Print("Init.skipped (módulos relevantes): " .. (#skipped > 0 and table.concat(skipped, " | ") or "ninguno"))

        local resolver, discovery, zd, codex, map = Dep("resolver"), Dep("discovery"), Dep("zoneDiscovery"), Dep("codex"), Dep("mapPosition")
        local function Ready(object) local ok, r = Safe(object, "IsReady"); return ok and tostring(r) or ("error: " .. tostring(r)) end
        Print("IsReady: Resolver=" .. Ready(resolver) .. " Discovery=" .. Ready(discovery) .. " ZoneDiscovery=" .. Ready(zd) .. " Codex=" .. Ready(codex))

        local okZ, zs, zv = Safe(map, "GetZoneName")
        local okB, bs, bv = Safe(map, "GetSubzoneName")
        Print("MapPosition:GetZoneName() -> " .. (okZ and (tostring(zs) .. ", " .. Describe(zv)) or ("ERROR " .. tostring(zs))))
        Print("MapPosition:GetSubzoneName() -> " .. (okB and (tostring(bs) .. ", " .. Describe(bv)) or ("ERROR " .. tostring(bs))))

        local registry, localization = Dep("registry"), Dep("localization")
        local function ResolveAll(label, name)
            if type(name) ~= "string" then
                Print("Resolver para " .. label .. ": no hay nombre (" .. tostring(name) .. ")")
                return {}
            end
            local found = {}
            local parts = {}
            for _, typeName in ipairs({ "zone", "city", "subzone" }) do
                local ok, id, why, candidates = Safe(resolver, "Resolve", name, { type = typeName })
                if not ok then
                    parts[#parts + 1] = typeName .. "=ERROR(" .. tostring(id) .. ")"
                elseif id then
                    parts[#parts + 1] = typeName .. "=" .. tostring(id)
                    found[#found + 1] = id
                else
                    parts[#parts + 1] = typeName .. "=nil," .. tostring(why) .. (candidates and ("[" .. table.concat(candidates, ",") .. "]") or "")
                end
            end
            local okAny, anyId, anyWhy = Safe(resolver, "Resolve", name)
            parts[#parts + 1] = "sin tipo=" .. (okAny and (tostring(anyId) .. (anyId and "" or ("," .. tostring(anyWhy)))) or "ERROR")
            Print("Resolver:Resolve(" .. Describe(name) .. ") -> " .. table.concat(parts, " | "))
            return found
        end
        local ids = {}
        for _, id in ipairs(ResolveAll("la zona", okZ and zs == "available" and zv or nil)) do ids[#ids + 1] = id end
        for _, id in ipairs(ResolveAll("la subzona", okB and bs == "available" and bv or nil)) do ids[#ids + 1] = id end

        local okC, count = Safe(discovery, "Count")
        Print("Discovery:Count() = " .. (okC and tostring(count) or ("ERROR " .. tostring(count))))
        local okI, listed = Safe(discovery, "GetIds")
        if okI and type(listed) == "table" then
            Print("Discovery:GetIds() = " .. (#listed > 0 and table.concat(listed, ", ", 1, math.min(#listed, 12)) or "(vacío)"))
        end
        for _, id in ipairs(ids) do
            local ok, discovered = Safe(discovery, "IsDiscovered", id)
            Print("Discovery:IsDiscovered(" .. id .. ") = " .. (ok and tostring(discovered) or ("ERROR " .. tostring(discovered))))
        end
        -- Lo que respondería un modelo de Codex NUEVO con los servicios reales (sin pasar por la ventana).
        local model = Dep("codexModel")
        if IsObject(model) and type(model.New) == "function" and IsObject(registry) and IsObject(localization) then
            local okM, m = pcall(model.New, { registry = registry, localization = localization, discovery = function() return Dep("discovery") end })
            if okM then
                for _, id in ipairs(ids) do
                    local okN, name, _, locked = pcall(m.GetName, m, id)
                    Print("Modelo de Codex nuevo: GetName(" .. id .. ") = " .. (okN and (Describe(name) .. " bloqueada=" .. tostring(locked)) or ("ERROR " .. tostring(name))))
                end
            end
        end
        Print(string.format("Trazas: %s (%d/%d líneas)", tracing and "ACTIVAS" or "desactivadas", math.min(lines, MAX_TRACE_LINES), MAX_TRACE_LINES))
    end

    -- ---- comprobación bajo demanda ----
    function self:Check()
        local zd = Dep("zoneDiscovery")
        local function Run()
            if originals.Check then return originals.Check(zd) end
            return zd:Check()
        end
        if not IsObject(zd) or type(zd.Check) ~= "function" then
            Print("ZoneDiscovery:Check no existe")
            return
        end
        local ok, result = pcall(Run)
        Print("ZoneDiscovery:Check() ejecutado a mano -> " .. (ok and CheckSummary(result) or ("ERROR " .. tostring(result))))
        local discovery = Dep("discovery")
        local okC, count = Safe(discovery, "Count")
        Print("Discovery:Count() tras la comprobación = " .. (okC and tostring(count) or "?"))
    end

    -- ---- trazas ----
    local function Install()
        local zd, discovery = Dep("zoneDiscovery"), Dep("discovery")
        if IsObject(zd) and type(zd.Check) == "function" and not originals.Check then
            originals.Check = zd.Check
            zd.Check = function(object, ...)
                local result = originals.Check(object, ...)
                Trace("[check] ZoneDiscovery:Check() -> " .. CheckSummary(result))
                return result
            end
        end
        if IsObject(discovery) and type(discovery.Discover) == "function" and not originals.Discover then
            originals.Discover = discovery.Discover
            discovery.Discover = function(object, id, ...)
                local a, b, c = originals.Discover(object, id, ...)
                Trace("[discover] Discovery:Discover(" .. tostring(id) .. ") -> " .. tostring(a) .. ", " .. tostring(b) .. ", emitido=" .. tostring(c))
                return a, b, c
            end
        end
    end

    local function Uninstall()
        local zd, discovery = Dep("zoneDiscovery"), Dep("discovery")
        if originals.Check and IsObject(zd) then zd.Check = originals.Check end
        if originals.Discover and IsObject(discovery) then discovery.Discover = originals.Discover end
        originals = {}
    end

    local function OnDiscovered(id)
        if not tracing then return end
        local discovery, codex = Dep("discovery"), Dep("codex")
        local _, discovered = Safe(discovery, "IsDiscovered", id)
        local _, count = Safe(discovery, "Count")
        local _, ready = Safe(codex, "IsReady")
        local _, visible = Safe(codex, "IsVisible")
        Trace("[descubierto] evento " .. EVENT_DISCOVERED .. " id=" .. tostring(id) .. " IsDiscovered=" .. tostring(discovered) .. " Count=" .. tostring(count)
            .. " Codex listo=" .. tostring(ready) .. " visible=" .. tostring(visible))
    end

    function self:SetTrace(enabled)
        if enabled then
            lines = 0
            tracing = true
            Install()
            Print("trazas ACTIVADAS (máximo " .. MAX_TRACE_LINES .. " líneas)")
        else
            tracing = false
            Uninstall()
            Print("trazas desactivadas; funciones originales restauradas")
        end
    end

    function self:IsTracing()
        return tracing
    end

    function self:Handle(args)
        local sub, action = (args or ""):match("^%s*(%S*)%s*(%S*)")
        sub, action = (sub or ""):lower(), (action or ""):lower()
        if sub ~= "discovery" then
            Print("uso: /chronicle debug discovery [status|check|on|off]")
            return
        end
        if action == "" or action == "status" then
            self:Snapshot()
        elseif action == "check" then
            self:Check()
        elseif action == "on" then
            self:SetTrace(true)
        elseif action == "off" then
            self:SetTrace(false)
        else
            Print("uso: /chronicle debug discovery [status|check|on|off]")
        end
    end

    function self:Init()
        if initDone then
            return
        end
        local slash = Dep("slash")
        if not IsObject(slash) or type(slash.Register) ~= "function" then
            error("Diagnostics: Slash no está disponible", 0)
        end
        slash:Register("debug", function(args) self:Handle(args) end)
        local createFrame = deps.createFrame
        if type(createFrame) == "function" and not frame then
            frame = createFrame("Frame")
            frame:SetScript("OnEvent", function(_, event)
                Trace("[evento] " .. tostring(event) .. " llegó al frame del depurador")
            end)
            for _, name in ipairs(EVENTS) do
                local ok, err = pcall(frame.RegisterEvent, frame, name)
                if not ok then Print("no se pudo registrar " .. name .. ": " .. tostring(err)) end
            end
        end
        local events = Dep("events")
        if IsObject(events) and type(events.Register) == "function" then
            pcall(events.Register, events, EVENT_DISCOVERED, OnDiscovered)
        end
        initDone = true
        if TRACE_ON_LOAD then
            self:SetTrace(true)
        end
    end

    function self:IsReady()
        return initDone
    end

    return self
end

Chronicle.Diagnostics = NewDiagnostics({
    slash = function() return Chronicle.Slash end,
    events = function() return Chronicle.Events end,
    state = function() return Chronicle.State end,
    init = function() return Chronicle.Init end,
    registry = function() return Chronicle.Registry end,
    localization = function() return Chronicle.Localization end,
    resolver = function() return Chronicle.Resolver end,
    discovery = function() return Chronicle.Discovery end,
    mapPosition = function() return Chronicle.MapPosition end,
    zoneDiscovery = function() return Chronicle.ZoneDiscovery end,
    codex = function() return Chronicle.Codex end,
    codexModel = function() return Chronicle.CodexModel end,
    createFrame = function(...) return CreateFrame(...) end,
    print = function(message) Chronicle.Utils.Print(message) end,
})
Chronicle.Diagnostics.New = NewDiagnostics
