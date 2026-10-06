Chronicle = Chronicle or {}

-- EraAdapter: el adaptador de cliente de Classic Era (Fase 17, abstracción INICIAL; aún NO está conectado a ningún módulo del runtime).
-- Concentra lo que depende del cliente y que `Core` no debe conocer (Fase 15.1, 5): el formato del GUID, el npcID, la lectura de la unidad y del lugar,
-- los valores secretos y las capacidades. NO se refactoriza ningún módulo existente para usarlo (NpcDiscovery, ZoneDiscovery y MapPosition siguen
-- leyendo el cliente por su cuenta): conectarlos es trabajo de una fase posterior.
--
-- CONTRATO de un adaptador (lo comparten EraAdapter y el resto; ver Services/ClientAdapter.lua)
--   adapter:GetFlavor()               -> "ERA" | "FOREVER" | "UNKNOWN"
--   adapter:Matches(signals)          -> true | false, motivo        ¿este adaptador reconoce el cliente con estas señales?
--   adapter:IsSecretValue(value)      -> bool                         se usa ANTES de comparar, operar, analizar o guardar un valor del cliente
--   adapter:GetUnitGUID(unit)         -> guid | nil, motivo            GUID crudo; NUNCA se interpreta fuera del adaptador
--   adapter:GetUnitName(unit)         -> nombre | nil, motivo
--   adapter:IdentifyUnit(unit)        -> { status, kind?, npcID?, name?, reason? }
--        status: "identified" | "not_identifiable_now" (valor secreto) | "not_creature" (jugador, mascota...) | "unavailable"
--   adapter:GetCurrentPlace()         -> { zone?, subzone? } | nil, motivo
--   adapter:GetInteractionContext()   -> { type, unit } | nil, motivo   (EraAdapter: "not_implemented"; NO se asume ningún evento del cliente)
--   adapter:GetCapabilities()         -> { [capabilityId] = { supported = bool } }   lo que el CÓDIGO sabe intentar. Si funciona de verdad en un cliente lo
--                                        dicen los datos (ClientProfile), no esta tabla.
--
-- VALORES SECRETOS: un valor secreto NO es un error del addon: se trata como «no identificable ahora». Se comprueba con issecretvalue ANTES de operar;
-- pcall es solo la última barrera. FORMATO DEL GUID de criatura: «Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID» (7 campos, sin vacíos, npcID
-- entero positivo); cualquier otro formato no identifica nada. Verificado en el cliente real en la Fase 14.
-- DETECCIÓN: Matches() exige DOS señales independientes (proyecto e Interface). Que sean las del cliente actual es [PENDIENTE EN CLIENTE] y se prueba
-- aquí solo con señales simuladas.

local FLAVOR_ERA = "ERA"

local CAPABILITIES = {
    ["unit_identity.target"] = { supported = true },
    ["unit_identity.mouseover"] = { supported = true },
    ["unit_identity.nameplate"] = { supported = true },
    ["place.zone_text"] = { supported = true },
    ["place.subzone_text"] = { supported = true },
    ["interaction.gossip"] = { supported = false },
    ["interaction.quest"] = { supported = false },
    ["interaction.merchant"] = { supported = false },
    ["interaction.trainer"] = { supported = false },
    ["interaction.flight_master"] = { supported = false },
    ["interaction.profession"] = { supported = false },
}

-- Familia de Interface de Classic Era. Rango amplio a propósito: un cambio de parche (11507 -> 11509...) no debe romper la detección.
local ERA_INTERFACE_MIN, ERA_INTERFACE_MAX = 11000, 11999

-- GUID de criatura -> npcID | nil, motivo. Separa conservando campos vacíos («--» desplazaría los campos y daría un npcID falso).
local function ParseCreatureGuid(guid)
    if guid:sub(1, 9) ~= "Creature-" then
        return nil, "not_creature"
    end
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
    return npcID
end

local function NewEraAdapter(deps)
    deps = type(deps) == "table" and deps or {}
    -- Las dependencias se resuelven en el momento de usarlas (los globales del cliente pueden no existir al cargar el fichero).
    local function Fn(name, global)
        if type(deps[name]) == "function" then
            return deps[name]
        end
        return global and _G[global] or nil
    end

    local self = {}

    function self:GetFlavor()
        return FLAVOR_ERA
    end

    function self:Matches(signals)
        if type(signals) ~= "table" then
            return false, "no_signals"
        end
        local project, classic, interface = signals.projectId, signals.classicProjectId, signals.interface
        if type(project) ~= "number" or type(classic) ~= "number" or type(interface) ~= "number" then
            return false, "signal_missing"
        end
        if project ~= classic then
            return false, "project_mismatch"
        end
        if interface < ERA_INTERFACE_MIN or interface > ERA_INTERFACE_MAX then
            return false, "interface_out_of_family"
        end
        return true
    end

    function self:IsSecretValue(value)
        local fn = Fn("issecretvalue", "issecretvalue")
        if type(fn) ~= "function" then
            return false
        end
        local ok, result = pcall(fn, value)
        return ok and result == true
    end

    -- Lee una cadena del cliente de forma segura: error de API, valor secreto o no-cadena => nil + motivo.
    local function ReadString(fn, ...)
        if type(fn) ~= "function" then
            return nil, "api_missing"
        end
        local ok, value = pcall(fn, ...)
        if not ok then
            return nil, "api_error"
        end
        if self:IsSecretValue(value) then
            return nil, "secret" -- ANTES de cualquier comparación u operación
        end
        if type(value) ~= "string" or value == "" then
            return nil, "unavailable"
        end
        return value
    end

    function self:GetUnitGUID(unit)
        if type(unit) ~= "string" or unit == "" then
            return nil, "invalid_unit"
        end
        return ReadString(Fn("unitGuid", "UnitGUID"), unit)
    end

    function self:GetUnitName(unit)
        if type(unit) ~= "string" or unit == "" then
            return nil, "invalid_unit"
        end
        return ReadString(Fn("unitName", "UnitName"), unit)
    end

    function self:IdentifyUnit(unit)
        local guid, why = self:GetUnitGUID(unit)
        if not guid then
            if why == "secret" then
                return { status = "not_identifiable_now", reason = "secret" }
            end
            return { status = "unavailable", reason = why }
        end
        -- Última barrera: el análisis va protegido aunque el valor no fuera secreto.
        local ok, npcID, reason = pcall(ParseCreatureGuid, guid)
        if not ok then
            return { status = "unavailable", reason = "api_error" }
        end
        if not npcID then
            if reason == "not_creature" then
                return { status = "not_creature", reason = reason }
            end
            return { status = "unavailable", reason = reason }
        end
        local name = self:GetUnitName(unit) -- opcional: un nombre no disponible no impide identificar por GUID
        return { status = "identified", kind = "creature", npcID = npcID, name = name }
    end

    function self:GetCurrentPlace()
        local zone = ReadString(Fn("zoneText", "GetRealZoneText"))
        local subzone = ReadString(Fn("subZoneText", "GetSubZoneText"))
        if not zone and not subzone then
            return nil, "unavailable"
        end
        return { zone = zone, subzone = subzone }
    end

    function self:GetInteractionContext()
        -- No se asume ningún evento de interacción del cliente: qué eventos existen y qué unidad usan se valida con el cliente real (Fase 15.1, 6.3).
        return nil, "not_implemented"
    end

    function self:GetCapabilities()
        local copy = {}
        for id, cap in pairs(CAPABILITIES) do
            copy[id] = { supported = cap.supported }
        end
        return copy
    end

    return self
end

Chronicle.EraAdapter = { New = NewEraAdapter, ParseCreatureGuid = ParseCreatureGuid }
