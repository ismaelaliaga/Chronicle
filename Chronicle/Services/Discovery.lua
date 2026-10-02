Chronicle = Chronicle or {}

-- Discovery: qué entidades ha descubierto el personaje actual. El Registry dice qué existe en el
-- mundo; Discovery guarda cuáles de esas ha descubierto este personaje. Responsabilidad única:
-- registrar y consultar el progreso. NO detecta nada por sí mismo (ni zonas, ni NPC, ni
-- proximidad: eso serán capas posteriores que llamarán a Discover()), no muestra nada y no sabe
-- cómo se llaman las cosas (Localization): trabaja solo con IDs canónicos.
--
-- ESTADO PERSISTENTE (compatible con schemaVersion = 1; State ya crea el contenedor, no hay migración)
--   ChronicleCharDB.discovery.entries[<id canónico>] = {}
--   * Un ID está descubierto si y solo si su valor es una TABLA. La tabla está vacía a propósito:
--     es el hueco para metadatos futuros, que se añadirán como claves nuevas sin migrar nada. No
--     se guarda ningún campo hoy porque ninguno tiene todavía un uso definido.
--   * Cualquier otro valor (true, false, cadenas...) y cualquier ID que ya no esté en el Registry se
--     IGNORAN al consultar: no son un error, no cuentan y no se borran. Un guardado antiguo o
--     incompleto (sin `discovery` o sin `entries`) equivale a progreso vacío.
--   * Discovery no toca ChronicleCharDB: lee y escribe solo a través de State:Get/State:Set, y
--     nunca devuelve las tablas de State (las consultas devuelven listas nuevas).
--
-- CONTRATO
--   Discover(id) -> true, "new", emitido    descubrimiento nuevo, GUARDADO. `emitido` indica si se
--                                           pudo emitir el evento (ver más abajo); el guardado no
--                                           depende de ello.
--                -> true, "already"         ya estaba descubierta: idempotente, no se escribe nada
--                                           ni se vuelve a emitir.
--                -> false, motivo           no se ha guardado nada ni se ha emitido nada:
--       "invalid_id"       id no es una cadena no vacía
--       "unknown_entity"   id no está en el Registry (nunca se crean entidades)
--       "not_ready"        Discovery no se ha inicializado (Init), falta el Registry, o State no
--                          está listo
--       "read_only"        State está en solo lectura (guardado de una versión más nueva)
--       "persist_failed"   State:Set devolvió false: no se afirma un éxito que no se guardó
--   Orden de las comprobaciones: invalid_id, not_ready/unknown_entity, read_only, persist_failed.
--   IsDiscovered(id) -> true | false      false para un id inválido, desconocido, o si no hay estado.
--                                         Consultar NUNCA descubre nada ni emite eventos.
--   GetIds([type])   -> lista nueva, ordenada, de IDs descubiertos (solo los que existen en el
--                       Registry); `type` limita a un tipo. Vacía si no hay estado.
--   Count([type])    -> número de elementos de GetIds(type).
--   GetProgress([type]) -> descubiertos, total: descubiertos de ese tipo y entidades de ese tipo
--                       en el Registry (sin tipo, todas). Los totales salen del Registry.
--   Con un `type` que el Registry no conoce (o que no es una cadena) GetIds/Count/GetProgress lanzan
--   error, igual que el Registry: es una errata del llamante, y devolver 0 la escondería.
--   IsReady() -> true tras un Init() satisfactorio.
--   Init()    -> comprueba que State está listo y que existe el Registry; lanza un error
--                descriptivo si no. Si State está en solo lectura la inicialización tiene éxito
--                (las consultas funcionan); solo se rechazan las escrituras. El bus de eventos NO
--                se exige aquí: Core/Init ya lo verifica antes de anunciar el arranque, y Discovery
--                tolera su ausencia al emitir (ver EVENTO).
--
-- EVENTO: "Chronicle.Discovery.Discovered" (Discovery.EVENT_DISCOVERED), con UN argumento: el ID
-- canónico recién descubierto. Se emite por Chronicle.Events una sola vez por descubrimiento nuevo y
-- SOLO después de guardarlo. Nunca en consultas, intentos inválidos, fallos de persistencia ni al
-- repetir un descubrimiento. Si el bus no está disponible o falla, el descubrimiento ya guardado se
-- mantiene, el fallo se comunica por geterrorhandler y Discover devuelve `emitido = false`: no se
-- finge una emisión. (Los errores de los listeners los aísla el propio Events.)

local EVENT_DISCOVERED = "Chronicle.Discovery.Discovered"

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function TypeOf(id)
    return id:match("^([^:]+):")
end

-- `deps` = { state = ..., registry = ..., events = ... }; cada una puede ser la tabla del módulo o
-- una función que la devuelve (así la instancia por defecto ve siempre los módulos actuales de
-- Chronicle.*, y las pruebas pueden inyectar otros).
local function NewDiscovery(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Discovery.New: se esperaba una tabla { state, registry, events }", 2)
    end

    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" then
            return dep()
        end
        return dep
    end

    local ready = false
    local self = {}
    self.EVENT_DISCOVERED = EVENT_DISCOVERED

    -- Módulos disponibles y utilizables, o nil.
    local function Registry()
        local registry = Dep("registry")
        if type(registry) == "table" and type(registry.Has) == "function" then
            return registry
        end
        return nil
    end

    local function State()
        local state = Dep("state")
        if type(state) == "table" and type(state.Get) == "function" and type(state.Set) == "function"
            and type(state.IsReady) == "function" and type(state.IsReadOnly) == "function" then
            return state
        end
        return nil
    end

    -- Comprueba y valida el tipo de un filtro (nil = sin filtro).
    local function AssertType(registry, typeName)
        if typeName == nil then
            return
        end
        if type(typeName) ~= "string" or not pcall(registry.Count, registry, typeName) then
            error("Chronicle.Discovery: tipo desconocido " .. tostring(typeName), 3)
        end
    end

    -- Comprueba que las dependencias están listas. Lanza error descriptivo si no. Si State está en
    -- solo lectura NO es un error: se puede consultar.
    function self:Init()
        ready = false
        local state = State()
        if not state or not state:IsReady() then
            error("Discovery: State no está listo (Discovery se inicializa después de State)", 0)
        end
        if not Registry() then
            error("Discovery: el Registry no está disponible", 0)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    -- Lectura del contenedor sin devolverlo: solo se usa dentro de este fichero, para iterar.
    local function Entries()
        local state = State()
        if not ready or not state or not state:IsReady() then
            return nil
        end
        local entries = state:Get("discovery", "entries")
        if type(entries) ~= "table" then
            return nil
        end
        return entries
    end

    function self:IsDiscovered(id)
        local registry = Registry()
        if not registry or type(id) ~= "string" or id == "" or not registry:Has(id) then
            return false
        end
        local entries = Entries()
        return entries ~= nil and type(entries[id]) == "table"
    end

    function self:GetIds(typeName)
        local registry = Registry()
        if not registry then
            if typeName ~= nil and type(typeName) ~= "string" then
                error("Chronicle.Discovery: tipo desconocido " .. tostring(typeName), 2)
            end
            return {}
        end
        AssertType(registry, typeName)
        local ids = {}
        local entries = Entries()
        if entries then
            for id, value in pairs(entries) do
                if type(id) == "string" and type(value) == "table" and registry:Has(id)
                    and (typeName == nil or TypeOf(id) == typeName) then
                    ids[#ids + 1] = id
                end
            end
        end
        table.sort(ids)
        return ids
    end

    function self:Count(typeName)
        return #self:GetIds(typeName)
    end

    function self:GetProgress(typeName)
        local registry = Registry()
        local discovered = self:Count(typeName)
        local total = 0
        if registry then
            total = registry:Count(typeName)
        end
        return discovered, total
    end

    -- Emite el evento; devuelve true si se llamó a Emit sin error.
    local function Announce(id)
        local events = Dep("events")
        if type(events) ~= "table" or type(events.Emit) ~= "function" then
            ReportError("Chronicle.Discovery: '" .. id .. "' descubierto y guardado, pero el bus de eventos"
                .. " no está disponible: no se ha emitido " .. EVENT_DISCOVERED)
            return false
        end
        local ok, err = pcall(events.Emit, events, EVENT_DISCOVERED, id)
        if not ok then
            ReportError("Chronicle.Discovery: '" .. id .. "' descubierto y guardado, pero falló la emisión de "
                .. EVENT_DISCOVERED .. ": " .. tostring(err))
            return false
        end
        return true
    end

    -- Marca `id` como descubierto. Ver el contrato en la cabecera.
    function self:Discover(id)
        if type(id) ~= "string" or id == "" then
            return false, "invalid_id"
        end
        local registry = Registry()
        if not registry then
            return false, "not_ready"
        end
        if not registry:Has(id) then
            return false, "unknown_entity"
        end
        local state = State()
        if not ready or not state then
            return false, "not_ready"
        end
        if not state:IsReady() then
            return false, "not_ready"
        end
        if state:IsReadOnly() then
            return false, "read_only"
        end

        if type(state:Get("discovery", "entries", id)) == "table" then
            return true, "already"
        end
        if not state:Set({}, "discovery", "entries", id) then
            return false, "persist_failed"
        end
        -- Se comprueba que quedó guardado antes de afirmar nada.
        if type(state:Get("discovery", "entries", id)) ~= "table" then
            return false, "persist_failed"
        end
        return true, "new", Announce(id)
    end

    return self
end

-- Instancia por defecto: Chronicle.Discovery, sobre los módulos actuales de Chronicle.*.
-- Chronicle.Discovery.New({ state, registry, events }) crea otras (p. ej. para pruebas, o para
-- reconstruir el servicio sobre el mismo estado).
Chronicle.Discovery = NewDiscovery({
    state = function() return Chronicle.State end,
    registry = function() return Chronicle.Registry end,
    events = function() return Chronicle.Events end,
})
Chronicle.Discovery.New = NewDiscovery
