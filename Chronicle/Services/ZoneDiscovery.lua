Chronicle = Chronicle or {}

-- ZoneDiscovery: descubre la zona/ciudad y la subzona en las que está el jugador, a partir de sus
-- NOMBRES (los que da el cliente, en su idioma) resueltos a IDs canónicos con Chronicle.Resolver.
-- Es independiente de Proximity: no usa coordenadas, mapas ni distancias. Los nombres los lee de
-- MapPosition (que los valida); el descubrimiento lo pide a Chronicle.Discovery; no escribe en State
-- ni en ChronicleCharDB, no muestra nada y no crea temporizadores.
--
-- REGLAS (todas para NO descubrir nada por error)
--   * Zona/ciudad y subzona se resuelven por separado y con tipo, nunca al revés:
--       zona     solo si el nombre es de UNA entidad de tipo "zone" o de tipo "city" (GetRealZoneText
--                devuelve zonas y ciudades; no se escoge entre las dos si el nombre vale para ambas).
--       subzona  solo si el nombre es de UNA entidad de tipo "subzone".
--     Un nombre de zona nunca se interpreta como subzona ni a la inversa.
--   * Solo se llama a Discover(id) si la resolución es inequívoca. Un nombre desconocido, ambiguo, vacío,
--     o que el cliente no entrega, no descubre nada. No se inventan IDs, nombres ni alias.
--   * Cada nombre se trata de forma independiente: que la zona no se reconozca no impide descubrir una
--     subzona reconocida, ni a la inversa. (No se exige que la subzona sea hija de la zona actual: un
--     nombre de subzona repetido en dos zonas ya sería "ambiguous" para el Resolver.)
--
-- Check() lee, resuelve y descubre en ese momento -> { status, zone = salida, subzone = salida }
--   status "not_ready" (sin salidas) si el servicio o sus dependencias no están listas; si no, "checked".
--   salida = { name, status, id, reason, candidates }:
--     "discovered"        descubrimiento nuevo y guardado (Discover devolvió "new").
--     "already"           ya estaba descubierto (Discover devolvió "already"): no se repite nada.
--     "unavailable"       MapPosition no entrega el nombre (nil, "", error o API ausente); `reason`.
--     "unrecognized"      el Resolver no conoce ese nombre (con ese tipo).
--     "ambiguous"         varias entidades; `candidates` = IDs ordenados. No se descubre ninguna.
--     "resolver_not_ready" el índice del Resolver no está listo.
--     "failed"            Discover rechazó el descubrimiento; `reason` = su motivo. Nunca es un éxito.
--   Llamar a Check() repetidamente (o al cambiar de zona y volver) no duplica nada: Discovery es
--   idempotente y emite su evento solo la primera vez.
--
-- CUÁNDO SE LLAMA: Init() crea un frame SIN interfaz que escucha los eventos de zona del cliente
-- (PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, ZONE_CHANGED, ZONE_CHANGED_INDOORS, los mismos que
-- usaba el addon original) y llama a Check(). Es lo único que hace falta para que funcione solo; no usa
-- temporizadores. Un fallo al registrar un evento o dentro de Check se comunica por geterrorhandler y no
-- se propaga.

local ZONE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function NewZoneDiscovery(deps)
    if type(deps) ~= "table" then
        error("Chronicle.ZoneDiscovery.New: se esperaba una tabla { mapPosition, resolver, discovery, createFrame }", 2)
    end

    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" then
            return dep()
        end
        return dep
    end

    local ready = false
    local frame = nil
    local self = {}

    local function MapPosition()
        local mp = Dep("mapPosition")
        if type(mp) == "table" and type(mp.GetZoneName) == "function" and type(mp.GetSubzoneName) == "function" then
            return mp
        end
        return nil
    end

    local function Resolver()
        local r = Dep("resolver")
        if type(r) == "table" and type(r.Resolve) == "function" and type(r.IsReady) == "function" then
            return r
        end
        return nil
    end

    local function Discovery()
        local d = Dep("discovery")
        if type(d) == "table" and type(d.Discover) == "function" and type(d.IsReady) == "function" then
            return d
        end
        return nil
    end

    -- Resuelve un nombre a un único ID del tipo pedido. Devuelve id, o nil, estado, candidatos.
    local function ResolveOne(resolver, name, typeNames)
        local found, candidates = {}, {}
        for _, typeName in ipairs(typeNames) do
            local id, why, list = resolver:Resolve(name, { type = typeName })
            if id then
                found[#found + 1] = id
            elseif why == "not_ready" then
                return nil, "resolver_not_ready"
            elseif why == "ambiguous" then
                for _, candidate in ipairs(list or {}) do
                    candidates[#candidates + 1] = candidate
                end
            end
        end
        if #candidates > 0 or #found > 1 then
            for _, id in ipairs(found) do
                candidates[#candidates + 1] = id
            end
            table.sort(candidates)
            return nil, "ambiguous", candidates
        end
        if #found == 1 then
            return found[1]
        end
        return nil, "unrecognized"
    end

    -- Procesa un nombre: lo lee de MapPosition (`getName`), lo resuelve y pide el descubrimiento.
    local function Process(getName, typeNames)
        local statusName, name = getName()
        if statusName ~= "available" then
            return { status = "unavailable", reason = tostring(name) }
        end
        local outcome = { name = name }

        local id, why, candidates = ResolveOne(Resolver(), name, typeNames)
        if not id then
            outcome.status = why
            outcome.candidates = candidates
            return outcome
        end
        outcome.id = id

        local okCall, ok, info = pcall(Discovery().Discover, Discovery(), id)
        if not okCall then
            outcome.status, outcome.reason = "failed", "discovery_error"
        elseif ok == true and info == "new" then
            outcome.status = "discovered"
        elseif ok == true and info == "already" then
            outcome.status = "already"
        else
            outcome.status, outcome.reason = "failed", tostring(info)
        end
        return outcome
    end

    function self:Check()
        local mp, resolver, discovery = MapPosition(), Resolver(), Discovery()
        if not ready or not mp or not resolver or not discovery or not discovery:IsReady() then
            return { status = "not_ready" }
        end
        return {
            status = "checked",
            zone = Process(function() return mp:GetZoneName() end, { "zone", "city" }),
            subzone = Process(function() return mp:GetSubzoneName() end, { "subzone" }),
        }
    end

    -- Comprueba las dependencias y empieza a escuchar los eventos de zona. Lanza error descriptivo si
    -- falta alguna dependencia o no se puede crear el frame.
    function self:Init()
        ready = false
        if not MapPosition() then
            error("ZoneDiscovery: MapPosition no está disponible", 0)
        end
        local resolver, discovery = Resolver(), Discovery()
        if not resolver or not resolver:IsReady() then
            error("ZoneDiscovery: el Resolver no está listo (ZoneDiscovery se inicializa después del Resolver)", 0)
        end
        if not discovery or not discovery:IsReady() then
            error("ZoneDiscovery: Discovery no está listo (ZoneDiscovery se inicializa después de Discovery)", 0)
        end

        if not frame then
            local createFrame = Dep("createFrame")
            if type(createFrame) ~= "function" then
                error("ZoneDiscovery: no se puede crear el frame de eventos (CreateFrame no está disponible)", 0)
            end
            local okFrame, created = pcall(createFrame, "Frame")
            if not okFrame or type(created) ~= "table" and type(created) ~= "userdata" then
                error("ZoneDiscovery: no se pudo crear el frame de eventos: " .. tostring(created), 0)
            end
            for _, eventName in ipairs(ZONE_EVENTS) do
                local okRegister, err = pcall(created.RegisterEvent, created, eventName)
                if not okRegister then
                    ReportError("Chronicle.ZoneDiscovery: no se pudo registrar " .. eventName .. ": " .. tostring(err))
                end
            end
            created:SetScript("OnEvent", function()
                local okCheck, err = pcall(self.Check, self)
                if not okCheck then
                    ReportError("Chronicle.ZoneDiscovery: error al comprobar la zona: " .. tostring(err))
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

-- Instancia por defecto, sobre los módulos actuales de Chronicle.* y el CreateFrame del cliente.
-- Chronicle.ZoneDiscovery.New({...}) crea otras con dependencias simuladas.
Chronicle.ZoneDiscovery = NewZoneDiscovery({
    mapPosition = function() return Chronicle.MapPosition end,
    resolver = function() return Chronicle.Resolver end,
    discovery = function() return Chronicle.Discovery end,
    createFrame = function(...) return CreateFrame(...) end,
})
Chronicle.ZoneDiscovery.New = NewZoneDiscovery
