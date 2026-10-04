Chronicle = Chronicle or {}

-- NpcDiscovery: descubre un NPC cuando el jugador lo VE de forma identificable (lo pone como objetivo, pasa el ratón por encima, sale su placa de nombre o abre su
-- conversación). La identidad sale del GUID de la unidad, NO de coordenadas: el cliente no da la posición de un NPC arbitrario (UnitPosition solo vale para el jugador y
-- su grupo), y las coordenadas de las fuentes públicas no están verificadas. Es reactivo a eventos: sin temporizadores ni trabajo por fotograma.
--
-- RESPONSABILIDADES (no duplica nada): este servicio SOLO identifica y pide `Discovery:Discover(id)`. Discovery guarda y evita duplicados; DiscoveryNotice avisa al oír el
-- evento de Discovery; el Codex se repinta con ese mismo evento. No escribe en State ni en ChronicleCharDB, no muestra nada y no toca el Popup.
--
-- FLUJO de Observe(unit)
--   1. UnitGUID(unit) -> cadena. Sin GUID: "ignored_unit".
--   2. ParseGuid: solo «Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID» (7 campos separados por «-», npcID entero positivo). Jugadores («Player-...»), mascotas
--      («Pet-...»), objetos y cualquier otro formato se descartan ("not_creature" / "invalid_guid"). Formato basado en la documentación de la comunidad: NO verificado aún en
--      el cliente 1.15.7; si no coincide, falla en seguro (no descubre nada). /chronicle npc muestra el GUID crudo para comprobarlo.
--   3. El npcID debe estar en la lista EXPLÍCITA Chronicle.NpcTargets (si no: "not_enabled").
--   4. Debe haber UNA sola entidad canónica con ese npcID en el Registry (cero: "no_entity"; varias: "ambiguous_entity"), y ser la declarada en la lista.
--   5. Nombre: UnitName(unit) pasado por Resolver (tipo npc). Solo una CONTRADICCIÓN positiva rechaza ("name_mismatch": el nombre resuelve a OTRA entidad). Un nombre que el
--      catálogo no conoce (p. ej. el nombre localizado de un cliente en español, sin alias) o aún no cargado no se puede comprobar: se acepta como «unverified» porque el GUID
--      es el dato fiable y la lista es explícita. «match» si resuelve a la misma entidad.
--   6. Discovery:Discover(id): «new» -> "discovered"; «already» -> "already"; rechazo -> "failed" (con su motivo). Una vez que Discovery responde true, el npcID se recuerda en memoria y
--      las observaciones siguientes devuelven "already" sin repetir el análisis ni llamar a Discover.
--
-- EVENTOS (cada uno se registra por separado y con pcall: si el cliente no conoce uno, los demás siguen funcionando; no se depende de las placas de nombre)
--   PLAYER_TARGET_CHANGED -> "target"      UPDATE_MOUSEOVER_UNIT -> "mouseover"      NAME_PLATE_UNIT_ADDED -> el token del evento      GOSSIP_SHOW -> "npc"
--   Disponibilidad en Classic Era según la documentación de la comunidad (sin verificar en 1.15.7 salvo lo que se confirme con /chronicle npc). Si UnitGUID("npc") no responde, se ignora.
--
-- API: NpcDiscovery:Init() (lanza error si faltan dependencias) :IsReady()
--      NpcDiscovery:Observe(unit [, eventName]) -> resultado { status, unit, event, guid, npcID, name, nameCheck, id, reason }
--      NpcDiscovery:ParseGuid(guid) -> { kind = "Creature", npcID = n } | nil, motivo  
--      NpcDiscovery:GetLast() -> copia del último resultado | nil     :GetStats() -> { status = n }     :GetTargets() -> { ids habilitados válidos }     :GetRejected() -> { { id, reason } }
--      NpcDiscovery.New({ registry, resolver, discovery, targets, createFrame, unitGuid, unitName }) crea otra instancia (pruebas).

local EVENT_UNITS = {
    PLAYER_TARGET_CHANGED = "target",
    UPDATE_MOUSEOVER_UNIT = "mouseover",
    NAME_PLATE_UNIT_ADDED = false, -- el token llega en el primer argumento del evento
    GOSSIP_SHOW = "npc",
}
local EVENT_ORDER = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "GOSSIP_SHOW" }
local KNOWN_CONFIDENCE = { source_confirmed = true, client_verified = true }

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

-- GUID de criatura: «Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID».
local function ParseGuid(guid)
    if type(guid) ~= "string" or guid == "" then
        return nil, "no_guid"
    end
    if guid:sub(1, 9) ~= "Creature-" then
        return nil, "not_creature" -- Player-, Pet-, GameObject-, Vehicle-...
    end
    -- Se separa conservando los campos vacíos: «--» desplazaría los demás campos y daría un npcID falso.
    local fields, from = {}, 1
    while true do
        local at = guid:find("-", from, true)
        if not at then
            fields[#fields + 1] = guid:sub(from)
            break
        end
        fields[#fields + 1] = guid:sub(from, at - 1)
        from = at + 1
    end
    for _, field in ipairs(fields) do
        if field == "" then
            return nil, "invalid_guid"
        end
    end
    if #fields ~= 7 or fields[1] ~= "Creature" or not fields[6]:match("^%d+$") then
        return nil, "invalid_guid"
    end
    local npcID = tonumber(fields[6])
    if not npcID or npcID < 1 or npcID ~= math.floor(npcID) then
        return nil, "invalid_guid"
    end
    return { kind = "Creature", npcID = npcID }
end

local function NewNpcDiscovery(deps)
    if type(deps) ~= "table" then
        error("Chronicle.NpcDiscovery.New: se esperaba una tabla de dependencias", 2)
    end
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" and name ~= "unitGuid" and name ~= "unitName" then
            return dep()
        end
        return dep
    end

    local self = {}
    local ready = false
    local frame
    local enabled = {} -- npcID -> { id, confidence }
    local enabledIds, rejected = {}, {}
    local done = {} -- npcID -> true: Discovery ya respondió true en esta sesión
    local last
    local stats = {}

    local function Copy(result)
        local copy = {}
        for k, v in pairs(result) do copy[k] = v end
        return copy
    end

    local function Finish(result)
        stats[result.status] = (stats[result.status] or 0) + 1
        -- Las observaciones SIN unidad (soltar el objetivo, quitar el ratón de encima) se cuentan pero no borran la última observación útil:
        -- es lo que /chronicle npc enseña para diagnosticar el cliente.
        if result.status ~= "ignored_unit" then
            last = result
        end
        return Copy(result)
    end

    -- Entidades canónicas de tipo npc con ese npcID (para exigir una coincidencia ÚNICA).
    local function EntitiesWithNpcId(registry, npcID)
        local found = {}
        for _, entity in ipairs(registry:GetAll("npc")) do
            if entity.npcID == npcID then
                found[#found + 1] = entity.id
            end
        end
        table.sort(found)
        return found
    end

    local function Observe(unit, eventName)
        local result = { unit = unit, event = eventName }
        if type(unit) ~= "string" or unit == "" then
            result.status = "ignored_unit"
            return Finish(result)
        end
        local unitGuid = deps.unitGuid
        if type(unitGuid) ~= "function" then
            result.status, result.reason = "not_ready", "no_unit_api"
            return Finish(result)
        end
        local okGuid, guid = pcall(unitGuid, unit)
        if not okGuid or type(guid) ~= "string" or guid == "" then
            result.status = "ignored_unit"
            return Finish(result)
        end
        result.guid = guid
        local parsed, why = ParseGuid(guid)
        if not parsed then
            result.status, result.reason = (why == "invalid_guid") and "invalid_guid" or "not_creature", why
            return Finish(result)
        end
        result.npcID = parsed.npcID
        local target = enabled[parsed.npcID]
        if not target then
            result.status = "not_enabled"
            return Finish(result)
        end
        result.id = target.id
        if done[parsed.npcID] then
            result.status = "already"
            result.cached = true
            return Finish(result)
        end
        local registry, resolver, discovery = Dep("registry"), Dep("resolver"), Dep("discovery")
        if not ready or not IsObject(registry) or not IsObject(discovery) then
            result.status, result.reason = "not_ready", "services"
            return Finish(result)
        end
        local entities = EntitiesWithNpcId(registry, parsed.npcID)
        if #entities == 0 then
            result.status = "no_entity"
            return Finish(result)
        elseif #entities > 1 or entities[1] ~= target.id then
            result.status = "ambiguous_entity"
            result.reason = table.concat(entities, ",")
            return Finish(result)
        end

        -- Nombre: solo una contradicción positiva rechaza.
        local name
        if type(deps.unitName) == "function" then
            local okName, value = pcall(deps.unitName, unit)
            if okName and type(value) == "string" and value ~= "" and value ~= UNKNOWNOBJECT then
                name = value
            end
        end
        result.name = name
        result.nameCheck = "unverified"
        if name and IsObject(resolver) and type(resolver.Resolve) == "function" then
            local okRes, resolved, resReason, candidates = pcall(resolver.Resolve, resolver, name, { type = "npc" })
            if okRes then
                if resolved == target.id then
                    result.nameCheck = "match"
                elseif resolved ~= nil then
                    result.status, result.reason = "name_mismatch", resolved
                    return Finish(result)
                elseif resReason == "ambiguous" and type(candidates) == "table" then
                    local includes = false
                    for _, candidate in ipairs(candidates) do
                        if candidate == target.id then includes = true end
                    end
                    if not includes then
                        result.status, result.reason = "name_mismatch", table.concat(candidates, ",")
                        return Finish(result)
                    end
                end
            end
        end

        local okDiscover, discovered, how = pcall(discovery.Discover, discovery, target.id)
        if not okDiscover then
            result.status, result.reason = "failed", tostring(discovered)
            return Finish(result)
        end
        if discovered ~= true then
            result.status, result.reason = "failed", tostring(how)
            return Finish(result)
        end
        done[parsed.npcID] = true
        result.status = (how == "new") and "discovered" or "already"
        return Finish(result)
    end

    function self:Observe(unit, eventName)
        return Observe(unit, eventName)
    end

    function self:ParseGuid(guid)
        return ParseGuid(guid)
    end

    function self:GetLast()
        return last and Copy(last) or nil
    end

    function self:GetStats()
        local copy = {}
        for k, v in pairs(stats) do copy[k] = v end
        return copy
    end

    function self:GetTargets()
        local copy = {}
        for i, id in ipairs(enabledIds) do copy[i] = id end
        return copy
    end

    function self:GetRejected()
        local copy = {}
        for i, item in ipairs(rejected) do copy[i] = { id = item.id, reason = item.reason } end
        return copy
    end

    -- Valida la lista contra el Registry: solo se habilita lo que cuadra exactamente.
    local function BuildTargets(registry, targets)
        enabled, enabledIds, rejected = {}, {}, {}
        if type(targets) ~= "table" then
            return
        end
        for _, item in ipairs(targets) do
            local id = type(item) == "table" and item.id or nil
            local reason
            if type(item) ~= "table" or type(item.id) ~= "string" or type(item.npcID) ~= "number" or item.npcID < 1 or item.npcID ~= math.floor(item.npcID) then
                reason = "invalid_target"
            elseif not KNOWN_CONFIDENCE[item.confidence] then
                reason = "unknown_confidence"
            elseif not registry:Has(item.id) or registry:Get(item.id).type ~= "npc" then
                reason = "unknown_entity"
            elseif registry:Get(item.id).npcID ~= item.npcID then
                reason = "npcid_mismatch"
            elseif enabled[item.npcID] then
                reason = "duplicate_npcid"
            else
                local entities = EntitiesWithNpcId(registry, item.npcID)
                if #entities ~= 1 then
                    reason = "ambiguous_entity"
                end
            end
            if reason then
                rejected[#rejected + 1] = { id = id, reason = reason }
            else
                enabled[item.npcID] = { id = item.id, confidence = item.confidence }
                enabledIds[#enabledIds + 1] = item.id
            end
        end
        table.sort(enabledIds)
    end

    function self:Init()
        ready = false
        local registry, discovery = Dep("registry"), Dep("discovery")
        if not IsObject(registry) or type(registry.GetAll) ~= "function" then
            error("NpcDiscovery: Registry no está disponible", 0)
        end
        if not IsObject(discovery) or type(discovery.IsReady) ~= "function" or not discovery:IsReady() then
            error("NpcDiscovery: Discovery no está listo (NpcDiscovery se inicializa después de Discovery)", 0)
        end
        if type(deps.unitGuid) ~= "function" then
            error("NpcDiscovery: UnitGUID no está disponible", 0)
        end
        BuildTargets(registry, Dep("targets"))
        for _, item in ipairs(rejected) do
            ReportError("Chronicle.NpcDiscovery: NPC no habilitado (" .. tostring(item.id) .. "): " .. item.reason)
        end

        if not frame then
            local createFrame = deps.createFrame
            if type(createFrame) ~= "function" then
                error("NpcDiscovery: no se puede crear el frame de eventos (CreateFrame no está disponible)", 0)
            end
            local okFrame, created = pcall(createFrame, "Frame")
            if not okFrame or not IsObject(created) then
                error("NpcDiscovery: no se pudo crear el frame de eventos: " .. tostring(created), 0)
            end
            for _, eventName in ipairs(EVENT_ORDER) do
                local okRegister, err = pcall(created.RegisterEvent, created, eventName)
                if not okRegister then
                    ReportError("Chronicle.NpcDiscovery: no se pudo registrar " .. eventName .. ": " .. tostring(err))
                end
            end
            created:SetScript("OnEvent", function(_, eventName, arg1)
                local unit = EVENT_UNITS[eventName]
                if unit == nil then
                    return
                end
                if unit == false then
                    unit = arg1
                end
                local okObserve, err = pcall(Observe, unit, eventName)
                if not okObserve then
                    ReportError("Chronicle.NpcDiscovery: error al observar la unidad: " .. tostring(err))
                end
            end)
            frame = created
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    return self
end

Chronicle.NpcDiscovery = NewNpcDiscovery({
    registry = function() return Chronicle.Registry end,
    resolver = function() return Chronicle.Resolver end,
    discovery = function() return Chronicle.Discovery end,
    targets = function() return Chronicle.NpcTargets end,
    createFrame = function(...) return CreateFrame(...) end,
    unitGuid = function(...) return UnitGUID(...) end,
    unitName = function(...) return UnitName(...) end,
})
Chronicle.NpcDiscovery.New = NewNpcDiscovery
