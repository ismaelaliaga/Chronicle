Chronicle = Chronicle or {}

-- Commands: los subcomandos de /chronicle de la Fase 12, registrados en Core/Slash.lua con Slash:Register. Este módulo solo traduce un
-- comando a una llamada a los servicios que ya existen (Codex, OptionsPanel, Trivia, Popup, MapPosition...); no tiene lógica propia más
-- allá de validar argumentos y dar mensajes. Los subcomandos salieron del addon original (leído en solo lectura); solo se recuperan los
-- que tienen a qué llamar en esta arquitectura.
--
-- COMANDOS (sin distinguir mayúsculas; el comando solo se despacha tal cual en Core/Slash.lua)
--   /chronicle                estado del Core (ya existía en la Fase 1; no se toca)
--   /chronicle help           lista de comandos
--   /chronicle codex          abre o cierra el Codex (Codex:Toggle)
--   /chronicle options        abre el panel de opciones (OptionsPanel:Open)
--   /chronicle trivia         muestra una curiosidad ahora, ignorando el enfriamiento (Trivia:Show(true)); respeta la preferencia y las reglas
--                             de Discovery de Trivia
--   /chronicle test           muestra un aviso de ejemplo en el Popup
--   /chronicle where          zona, subzona y posición del jugador según el servicio MapPosition
--   /chronicle npc            la ÚLTIMA unidad que observó NpcDiscovery (evento, unidad, GUID crudo, npcID, nombre, resultado) y cuántos NPC hay habilitados. Sirve para
--                             comprobar en el cliente real qué entrega WoW; no descubre nada. El ID canónico solo se muestra si la entidad está descubierta.
--   Ninguno admite argumentos: con argumentos no se ejecuta y se explica el uso. Un comando desconocido lo contesta Slash («comando
--   desconocido: x»). NO se registran /chronicle reset (Discovery no tiene reinicio: pospuesto) ni el conmutador de «avisos automáticos»
--   (no tiene consumidor en la reconstrucción) ni codex2 (era del Codex antiguo).
--
-- /chronicle where distingue tres estados por cada dato, tal como los da MapPosition:
--   disponible   «Zona: Dun Morogh»,  «Posición: mapa 1426, x=0.123 y=0.456»
--   no disponible ahora   «no disponible (motivo)»   (vale la pena volver a probar)
--   desconocido           «desconocido (motivo)»     (el cliente no puede dar este dato)
--   Nunca se inventa una ubicación. NOMBRES BLOQUEADOS: si el texto que da el cliente es el nombre o alias de una entidad del catálogo que
--   el personaje NO ha descubierto (o no se puede confirmar), se muestra «???» en lugar del nombre. Un nombre que no es de ninguna entidad
--   del catálogo se muestra tal cual. Consultar no descubre nada.
--
-- Commands.New(deps) crea otra instancia (pruebas); la instancia por defecto usa Chronicle.*.

local HELP = {
    { "/chronicle", "estado del Core" },
    { "/chronicle help", "esta lista" },
    { "/chronicle codex", "abre o cierra el Codex" },
    { "/chronicle options", "abre el panel de opciones" },
    { "/chronicle trivia", "muestra una curiosidad" },
    { "/chronicle test", "muestra un aviso de ejemplo" },
    { "/chronicle where", "tu zona, subzona y posición" },
    { "/chronicle npc", "la última unidad observada para descubrir NPC" },
}
local TEST_TITLE = "Chronicle"
local TEST_BODY = "Este es un aviso de ejemplo. Si lo ves con el estilo correcto, la interfaz de Chronicle funciona bien."
local LOCKED_LABEL = "???"

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function NewCommands(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Commands.New: se esperaba una tabla de dependencias", 2)
    end
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "print" then
            return dep()
        end
        return dep
    end
    local function Print(message)
        if type(deps.print) == "function" then deps.print(message) end
    end

    local self = {}
    local registered = false

    -- Nombre que se puede mostrar para un texto del cliente: «???» si es de una entidad no descubierta o no se puede confirmar.
    local function SafeName(rawName)
        local resolver, discovery = Dep("resolver"), Dep("discovery")
        if not IsObject(resolver) or type(resolver.Resolve) ~= "function" then
            return LOCKED_LABEL
        end
        local okReady, resolverReady = pcall(function() return resolver:IsReady() end)
        if not okReady or resolverReady ~= true then
            return LOCKED_LABEL
        end
        local ok, id, reason, candidates = pcall(resolver.Resolve, resolver, rawName)
        if not ok then
            return LOCKED_LABEL
        end
        local ids = {}
        if id then
            ids[1] = id
        elseif reason == "ambiguous" and type(candidates) == "table" then
            ids = candidates
        elseif reason ~= "not_found" and reason ~= "empty" then
            return LOCKED_LABEL -- cualquier otra razón: no se puede saber si es una entidad bloqueada
        end
        for _, candidate in ipairs(ids) do
            local okDiscovered, discovered = false, false
            if IsObject(discovery) and type(discovery.IsDiscovered) == "function" then
                okDiscovered, discovered = pcall(discovery.IsDiscovered, discovery, candidate)
            end
            if not okDiscovered or discovered ~= true then
                return LOCKED_LABEL
            end
        end
        return rawName
    end

    local function Describe(status, value, formatter)
        if status == "available" then
            return formatter(value)
        elseif status == "unavailable" then
            return "no disponible (" .. tostring(value) .. ")"
        end
        return "desconocido (" .. tostring(value) .. ")"
    end

    local function Where()
        local map = Dep("mapPosition")
        if not IsObject(map) then
            Print("where: el servicio de posición no está disponible.")
            return
        end
        local function Query(method)
            if type(map[method]) ~= "function" then return "unknown", "api_missing" end
            local ok, status, value = pcall(map[method], map)
            if not ok then return "unknown", "api_error" end
            return status, value
        end
        local zoneStatus, zone = Query("GetZoneName")
        local subStatus, subzone = Query("GetSubzoneName")
        local posStatus, position = Query("GetPosition")
        Print("Zona: " .. Describe(zoneStatus, zone, SafeName))
        Print("Subzona: " .. Describe(subStatus, subzone, SafeName))
        Print("Posición: " .. Describe(posStatus, position, function(p)
            return string.format("mapa %s, x=%.3f y=%.3f", tostring(p.mapID), p.x, p.y)
        end))
    end

    local function Npc()
        local service = Dep("npcDiscovery")
        if not IsObject(service) or type(service.GetLast) ~= "function" or type(service.IsReady) ~= "function" or service:IsReady() ~= true then
            Print("npc: el descubrimiento de NPC no está disponible.")
            return
        end
        local okT, targets = pcall(service.GetTargets, service)
        Print("NPC habilitados para descubrir: " .. ((okT and type(targets) == "table") and #targets or "?"))
        local okL, last = pcall(service.GetLast, service)
        if not okL or type(last) ~= "table" then
            Print("Aún no se ha observado ninguna unidad (ponla como objetivo, pasa el ratón por encima o habla con ella).")
            return
        end
        local known = last.status == "discovered" or last.status == "already"
        Print("Última unidad: evento=" .. tostring(last.event) .. " unidad=" .. tostring(last.unit) .. " resultado=" .. tostring(last.status)
            .. (last.reason and (" (" .. tostring(last.reason) .. ")") or ""))
        Print("GUID=" .. tostring(last.guid) .. " npcID=" .. tostring(last.npcID) .. " nombre=" .. tostring(last.name) .. " comprobación del nombre=" .. tostring(last.nameCheck))
        if known then
            Print("Entidad: " .. tostring(last.id))
        end
    end

    local function Help()
        Print("comandos disponibles:")
        for _, line in ipairs(HELP) do
            Print("  " .. line[1] .. " - " .. line[2])
        end
    end

    local function Codex()
        local codex = Dep("codex")
        if not IsObject(codex) or type(codex.Toggle) ~= "function" then
            Print("el Codex no está disponible.")
            return
        end
        local ok, result = pcall(codex.Toggle, codex)
        if not ok or result ~= true then
            Print("el Codex no está disponible.")
        end
    end

    local function Options()
        local panel = Dep("optionsPanel")
        if not IsObject(panel) or type(panel.Open) ~= "function" then
            Print("el panel de opciones no está disponible.")
            return
        end
        local ok, opened = pcall(panel.Open, panel)
        if not ok or opened ~= true then
            Print("no se ha podido abrir el panel de opciones en este cliente.")
        end
    end

    local TRIVIA_MESSAGES = {
        disabled = "las curiosidades están desactivadas (revisa /chronicle options).",
        no_content = "no hay curiosidades disponibles.",
        guarded = "no hay ninguna curiosidad que puedas ver todavía (nombran lugares o personajes que no has descubierto).",
        no_popup = "no se ha podido mostrar la curiosidad: el aviso no está disponible.",
        ui_error = "no se ha podido mostrar la curiosidad.",
        not_ready = "las curiosidades no están disponibles.",
    }
    local function Trivia()
        local trivia = Dep("trivia")
        if not IsObject(trivia) or type(trivia.Show) ~= "function" then
            Print(TRIVIA_MESSAGES.not_ready)
            return
        end
        local ok, shown, reason = pcall(trivia.Show, trivia, true)
        if not ok then
            Print(TRIVIA_MESSAGES.ui_error)
        elseif shown ~= true then
            Print(TRIVIA_MESSAGES[reason] or TRIVIA_MESSAGES.ui_error)
        end
    end

    local function Test()
        local popup = Dep("popup")
        if not IsObject(popup) or type(popup.Show) ~= "function" then
            Print("el aviso no está disponible.")
            return
        end
        local ok, shown = pcall(popup.Show, popup, { title = TEST_TITLE, body = TEST_BODY })
        if not ok or shown ~= true then
            Print("no se ha podido mostrar el aviso de ejemplo.")
        end
    end

    local HANDLERS = { help = Help, codex = Codex, options = Options, trivia = Trivia, test = Test, where = Where, npc = Npc }
    local NAMES = { "codex", "help", "npc", "options", "test", "trivia", "where" }

    function self:GetCommands()
        local list = {}
        for i, name in ipairs(NAMES) do list[i] = name end
        return list
    end

    function self:Init()
        local slash = Dep("slash")
        if not IsObject(slash) or type(slash.Register) ~= "function" then
            error("Commands: Slash no está disponible", 0)
        end
        for _, name in ipairs(NAMES) do
            local handler = HANDLERS[name]
            slash:Register(name, function(args)
                if args ~= nil and args ~= "" then
                    Print("«" .. name .. "» no admite argumentos. Uso: /chronicle " .. name)
                    return
                end
                handler()
            end)
        end
        registered = true
    end

    function self:IsReady()
        return registered
    end

    return self
end

Chronicle.Commands = NewCommands({
    slash = function() return Chronicle.Slash end,
    codex = function() return Chronicle.Codex end,
    optionsPanel = function() return Chronicle.OptionsPanel end,
    trivia = function() return Chronicle.Trivia end,
    popup = function() return Chronicle.Popup end,
    mapPosition = function() return Chronicle.MapPosition end,
    resolver = function() return Chronicle.Resolver end,
    discovery = function() return Chronicle.Discovery end,
    npcDiscovery = function() return Chronicle.NpcDiscovery end,
    print = function(message) Chronicle.Utils.Print(message) end,
})
Chronicle.Commands.New = NewCommands
