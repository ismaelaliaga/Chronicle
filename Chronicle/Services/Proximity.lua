Chronicle = Chronicle or {}

-- Proximity: ¿está el jugador lo bastante cerca de un objetivo espacial como para descubrirlo? Es un
-- MOTOR GENÉRICO: recibe una posición de MapPosition y una lista de objetivos, y pide el descubrimiento
-- a Chronicle.Discovery cuando se cumplen las condiciones. No guarda progreso (eso es Discovery), no
-- escribe en State ni en ChronicleCharDB, no muestra nada y NO crea temporizadores ni frames: alguien
-- tiene que llamar a Evaluate() (ver "Quién lo llama" más abajo).
--
-- ESTADO DE LOS DATOS ESPACIALES: HOY NO HAY NINGÚN OBJETIVO VERIFICADO. Las coordenadas del addon
-- original no están verificadas en el cliente real y no se han migrado; el Schema no tiene dónde
-- guardarlas; tampoco se conoce el mapID de ninguna zona. Por eso la instancia por defecto no tiene
-- proveedor de objetivos y Evaluate() devuelve "no_targets": con los datos actuales este servicio NO
-- puede descubrir ningún NPC por distancia. No se ha inventado ningún dato para disimularlo.
--
-- OBJETIVO ESPACIAL (la interfaz mínima que debe cumplir quien los proporcione)
--   { id = "npc:...", mapID = <entero>, x = <0..1>, y = <0..1>, radius = <número>, verified = true }
--   * id        ID canónico de la entidad a descubrir. Lo valida Discovery (un ID desconocido se rechaza).
--   * mapID,x,y posición del objetivo en el MISMO sistema espacial que MapPosition: coordenadas
--               normalizadas de ese mapa. Solo se compara con posiciones del mismo mapID.
--   * radius    radio de activación EN LAS MISMAS UNIDADES: normalizadas, 0 < radius <= 1.
--   * verified  debe ser exactamente true: quien proporcione el objetivo declara que x, y y radius se
--               comprobaron en el cliente real. Sin eso el objetivo se rechaza, nunca se activa.
--   Un objetivo mal formado se rechaza (aparece en `rejected`) y no impide evaluar los demás.
--   El proveedor es una función que devuelve la lista (nueva o no; Proximity no la modifica):
--   Proximity.New({ ..., targets = fn }) o Proximity:SetTargetProvider(fn).
--
-- DISTANCIA: euclídea en unidades de mapa NORMALIZADAS, dentro de un mismo mapID. NO es una distancia
-- física del mundo (no son yardas): los mapas no son cuadrados ni tienen el mismo tamaño real, así que
-- una unidad en x no equivale a una en y, y un mismo radio abarca más o menos terreno según el mapa. Es
-- una medida coherente solo para ese mapa, y el radio de cada objetivo debe haberse ajustado a él. Si
-- el cliente no da un mapID y unas coordenadas fiables, NO se calcula nada y no se activa nada.
-- Se compara con distancias al cuadrado (sin raíz) para no perder exactitud: dentro si dx²+dy² <= r²,
-- es decir, estar EXACTAMENTE en el radio cuenta como dentro.
--
-- CONTRATO, Evaluate() -> resultado (tabla nueva). Hace como mucho UNA consulta de posición y recorre
-- solo los objetivos que le da el proveedor; no busca NPC en el mundo.
--   resultado.status:
--     "not_ready"            Proximity no se ha inicializado, o falta MapPosition/Discovery.
--     "provider_error"       el proveedor lanzó error o no devolvió una lista; `reason` lo describe.
--     "no_targets"           no hay objetivos que evaluar (no se consulta la posición).
--     "position_unavailable" MapPosition no tiene la posición ahora; `reason` = su motivo.
--     "position_unknown"     la posición no es fiable/no se puede conocer; `reason` = su motivo.
--     "evaluated"            se evaluaron los objetivos.
--   resultado.discovered   IDs descubiertos POR ESTA llamada (Discover devolvió "new"), ordenados.
--   resultado.rejected     lista de { id, reason }: objetivos inválidos ("invalid_target", "invalid_id",
--                          "unverified", "invalid_map", "invalid_coordinates", "invalid_radius") o a
--                          los que Discovery rechazó (su motivo: "unknown_entity", "persist_failed",
--                          "read_only", "not_ready"...). Un rechazo NUNCA se cuenta como descubrimiento.
--   resultado.targets, .invalid, .alreadyDiscovered, .otherMap, .outside, .inside: contadores.
--   Idempotente: un objetivo ya descubierto se salta sin calcular distancia ni llamar a Discover, así
--   que repetir la evaluación no vuelve a producir ningún descubrimiento ni evento.
--
-- QUIÉN LO LLAMA: nadie todavía. Un temporizador (u otro disparador) que invoque Evaluate() es una
-- decisión de una fase posterior (ver docs): no tiene sentido hasta que haya objetivos verificados.

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsMapId(value)
    return IsFiniteNumber(value) and value >= 1 and value == math.floor(value)
end

local function InUnitRange(value)
    return IsFiniteNumber(value) and value >= 0 and value <= 1
end

-- Devuelve nil si el objetivo es válido, o el motivo de rechazo.
local function InvalidReason(target)
    if type(target) ~= "table" then
        return "invalid_target"
    end
    if type(target.id) ~= "string" or target.id == "" then
        return "invalid_id"
    end
    if target.verified ~= true then
        return "unverified"
    end
    if not IsMapId(target.mapID) then
        return "invalid_map"
    end
    if not InUnitRange(target.x) or not InUnitRange(target.y) or (target.x == 0 and target.y == 0) then
        return "invalid_coordinates"
    end
    if not IsFiniteNumber(target.radius) or target.radius <= 0 or target.radius > 1 then
        return "invalid_radius"
    end
    return nil
end

local function NewProximity(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Proximity.New: se esperaba una tabla { mapPosition, discovery, targets }", 2)
    end

    -- Cada dependencia puede ser el módulo o una función que lo devuelve.
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "targets" then
            return dep()
        end
        return dep
    end

    local provider = deps.targets
    local ready = false
    local self = {}

    local function MapPosition()
        local mp = Dep("mapPosition")
        if type(mp) == "table" and type(mp.GetPosition) == "function" then
            return mp
        end
        return nil
    end

    local function Discovery()
        local d = Dep("discovery")
        if type(d) == "table" and type(d.Discover) == "function" and type(d.IsDiscovered) == "function"
            and type(d.IsReady) == "function" then
            return d
        end
        return nil
    end

    -- Sustituye el proveedor de objetivos. Devuelve true, o false si no es una función (nil lo quita).
    function self:SetTargetProvider(fn)
        if fn ~= nil and type(fn) ~= "function" then
            return false
        end
        provider = fn
        return true
    end

    function self:Init()
        ready = false
        local mp, discovery = MapPosition(), Discovery()
        if not mp then
            error("Proximity: MapPosition no está disponible", 0)
        end
        if not discovery or not discovery:IsReady() then
            error("Proximity: Discovery no está listo (Proximity se inicializa después de Discovery)", 0)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    local function NewResult(status, reason)
        return { status = status, reason = reason, discovered = {}, rejected = {}, targets = 0, invalid = 0,
            alreadyDiscovered = 0, otherMap = 0, outside = 0, inside = 0 }
    end

    function self:Evaluate()
        local mp, discovery = MapPosition(), Discovery()
        if not ready or not mp or not discovery or not discovery:IsReady() then
            return NewResult("not_ready")
        end

        local list = {}
        if provider ~= nil then
            local ok, result = pcall(provider)
            if not ok then
                return NewResult("provider_error", tostring(result))
            end
            if type(result) ~= "table" then
                return NewResult("provider_error", "el proveedor no devolvió una lista")
            end
            list = result
        end
        if #list == 0 then
            return NewResult("no_targets")
        end

        local statusPos, position = mp:GetPosition()
        if statusPos == "unavailable" then
            return NewResult("position_unavailable", position)
        elseif statusPos ~= "available" or type(position) ~= "table" then
            return NewResult("position_unknown", type(position) == "string" and position or "invalid_position")
        end

        local result = NewResult("evaluated")
        result.targets = #list
        for _, target in ipairs(list) do
            local invalid = InvalidReason(target)
            if invalid then
                result.invalid = result.invalid + 1
                result.rejected[#result.rejected + 1] = {
                    id = type(target) == "table" and type(target.id) == "string" and target.id or nil,
                    reason = invalid,
                }
            elseif discovery:IsDiscovered(target.id) then
                result.alreadyDiscovered = result.alreadyDiscovered + 1
            elseif target.mapID ~= position.mapID then
                result.otherMap = result.otherMap + 1 -- otro sistema espacial: no se compara
            else
                local dx, dy = position.x - target.x, position.y - target.y
                if dx * dx + dy * dy <= target.radius * target.radius then
                    result.inside = result.inside + 1
                    local okCall, ok, info = pcall(discovery.Discover, discovery, target.id)
                    if not okCall then
                        result.rejected[#result.rejected + 1] = { id = target.id, reason = "discovery_error" }
                    elseif ok == true and info == "new" then
                        result.discovered[#result.discovered + 1] = target.id
                    elseif ok == true and info == "already" then
                        result.alreadyDiscovered = result.alreadyDiscovered + 1
                    else
                        result.rejected[#result.rejected + 1] = { id = target.id, reason = tostring(info) }
                    end
                else
                    result.outside = result.outside + 1
                end
            end
        end
        table.sort(result.discovered)
        return result
    end

    return self
end

-- Instancia por defecto, sobre los módulos actuales de Chronicle.*. Sin proveedor: no hay datos
-- espaciales verificados (ver la cabecera). Chronicle.Proximity.New({...}) crea otras (pruebas).
Chronicle.Proximity = NewProximity({
    mapPosition = function() return Chronicle.MapPosition end,
    discovery = function() return Chronicle.Discovery end,
})
Chronicle.Proximity.New = NewProximity
