Chronicle = Chronicle or {}

-- Registro central de entidades, en memoria. Guarda el catálogo (qué existe en el mundo),
-- NO el progreso del jugador: no accede a ChronicleCharDB ni guarda nada en SavedVariables.
-- El esquema (formato de IDs, tipos, campos, reglas de relación) lo pone Chronicle.Schema.
--
-- REGISTRAR Y VALIDAR SON DOS COSAS
--   Register(entity)  valida solo la ESTRUCTURA de esa entidad (Schema:Validate) y rechaza
--                     IDs duplicados. No exige que existan las entidades a las que apunta:
--                     los ficheros de datos pueden cargarse en cualquier orden.
--   Validate()        comprueba el CONJUNTO completo: que todos los IDs referenciados
--                     existan y que no haya ciclos en `parent`. Se ejecuta en Init (una vez
--                     cargados todos los datos) y puede llamarse cuando se quiera.
--   Un Register rechazado no lanza error (cargar datos no debe romper el addon): devuelve
--   false y el motivo, y además queda anotado en GetRejected(). Init usa ese registro para
--   no dar el Registry por listo si algún dato se rechazó.
--
-- POLÍTICA DE DUPLICADOS: un segundo Register con un ID ya registrado se RECHAZA siempre,
-- aunque la entidad sea idéntica; la original no se toca. Nunca se sobrescribe en silencio.
--
-- PROTECCIÓN: las tablas internas viven en variables locales (upvalues) de NewRegistry, no
-- en campos del objeto, así que desde fuera no hay forma de alcanzarlas. Register guarda
-- una COPIA de lo recibido (el llamante puede seguir usando o cambiando su tabla sin
-- afectar al Registry) y toda consulta devuelve copias. Se prefieren copias a un proxy de
-- solo lectura porque en Lua 5.1 pairs()/next() no respetan metatablas y un proxy rompería
-- la iteración. Con el volumen previsto, el coste de copiar es irrelevante.
--
-- ORDEN: todos los listados salen ordenados por ID, así que son deterministas.
--
-- RELACIONES: parent y located_in se indexan por el lado derivado (hijos, contenidos) y
-- related_to por el lado entrante; ninguna se guarda dos veces en las entidades. Ver las
-- reglas en Data/Schema.lua.

local Utils = Chronicle.Utils

local MAX_SUMMARY_PROBLEMS = 5

-- Lista ordenada con las claves de uno o más conjuntos { [id] = true }.
local function SortedUnion(...)
    local merged = {}
    for i = 1, select("#", ...) do
        local set = select(i, ...)
        if set then
            for id in pairs(set) do
                merged[id] = true
            end
        end
    end
    local ids = {}
    for id in pairs(merged) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

local function AddToIndex(index, key, id)
    index[key] = index[key] or {}
    index[key][id] = true
end

local function NewRegistry(schema)
    if type(schema) ~= "table" or type(schema.Validate) ~= "function" then
        error("Chronicle.Registry.New: se esperaba un esquema (Chronicle.Schema.New)", 2)
    end

    -- Estado privado
    local byId = {} -- id -> entidad (copia propia)
    local idsByType = {} -- tipo -> { [id] = true }
    local childrenOf = {} -- id del padre -> { [id hijo] = true }
    local locatedIn = {} -- id del lugar -> { [id colocado] = true }
    local relatedFrom = {} -- id destino -> { [id origen] = true } (related_to entrante)
    local warningsById = {} -- id -> advertencias del registro
    local rejected = {} -- { { id = ..., errors = {...} }, ... } en orden de llegada
    local sortedCache = {} -- tipo (o false = todos) -> lista de IDs ordenada
    local count = 0
    local validated = false

    local self = {}

    -- Registra una entidad. Devuelve true, report en éxito; false, report si se rechaza.
    -- report = { ok, errors = {...}, warnings = {...} }.
    function self:Register(entity)
        validated = false
        local result = schema:Validate(entity)

        local id = type(entity) == "table" and type(entity.id) == "string" and entity.id or nil
        if id and byId[id] then
            result.ok = false
            table.insert(result.errors, "entidad '" .. id .. "': id: ID duplicado, ya está registrado"
                .. " (se conserva la entidad original)")
        end

        if not result.ok then
            table.insert(rejected, { id = id, errors = Utils.DeepCopy(result.errors) })
            return false, result
        end

        local stored = Utils.DeepCopy(entity)
        byId[id] = stored
        count = count + 1
        AddToIndex(idsByType, stored.type, id)
        if stored.parent then
            AddToIndex(childrenOf, stored.parent, id)
        end
        if stored.located_in then
            AddToIndex(locatedIn, stored.located_in, id)
        end
        for _, target in ipairs(stored.related_to or {}) do
            AddToIndex(relatedFrom, target, id)
        end
        if #result.warnings > 0 then
            warningsById[id] = Utils.DeepCopy(result.warnings)
        end
        sortedCache = {}
        return true, result
    end

    function self:Has(id)
        return type(id) == "string" and byId[id] ~= nil
    end

    -- Copia de la entidad, o nil si no está registrada.
    function self:Get(id)
        if type(id) ~= "string" then
            return nil
        end
        return Utils.DeepCopy(byId[id])
    end

    local function AssertKnownType(typeName)
        if typeName ~= nil and not schema:IsValidType(typeName) then
            error("Chronicle.Registry: tipo desconocido " .. tostring(typeName), 3)
        end
    end

    -- IDs registrados, ordenados; solo los de `typeName` si se indica. Una tabla nueva en
    -- cada llamada. Lanza error si `typeName` no es un tipo del esquema (sería una errata).
    function self:GetIds(typeName)
        AssertKnownType(typeName)
        local key = typeName or false
        if not sortedCache[key] then
            local source = byId
            if typeName then
                source = idsByType[typeName]
            end
            sortedCache[key] = SortedUnion(source)
        end
        return Utils.DeepCopy(sortedCache[key])
    end

    -- Copias de las entidades, ordenadas por ID; solo las de `typeName` si se indica.
    function self:GetAll(typeName)
        local list = {}
        for _, id in ipairs(self:GetIds(typeName)) do
            list[#list + 1] = Utils.DeepCopy(byId[id])
        end
        return list
    end

    function self:Count(typeName)
        AssertKnownType(typeName)
        if not typeName then
            return count
        end
        local n = 0
        for _ in pairs(idsByType[typeName] or {}) do
            n = n + 1
        end
        return n
    end

    -- Relación derivada `contains`: IDs de las entidades cuyo parent o located_in es `id`.
    function self:GetContained(id)
        if type(id) ~= "string" then
            return {}
        end
        return SortedUnion(childrenOf[id], locatedIn[id])
    end

    -- IDs relacionados con `id` por related_to, en cualquiera de los dos sentidos.
    function self:GetRelated(id)
        if type(id) ~= "string" then
            return {}
        end
        local outgoing = {}
        for _, target in ipairs(byId[id] and byId[id].related_to or {}) do
            outgoing[target] = true
        end
        return SortedUnion(outgoing, relatedFrom[id])
    end

    -- Entidades rechazadas por Register hasta ahora: { { id = ..., errors = {...} }, ... }.
    function self:GetRejected()
        return Utils.DeepCopy(rejected)
    end

    -- Validación del conjunto completo. Devuelve { ok, errors, warnings } determinista.
    --   Errores: IDs referenciados (parent, located_in, related_to) que no están registrados,
    --            y ciclos en la jerarquía parent.
    --   Advertencias: las anotadas al registrar cada entidad.
    -- La compatibilidad de tipos de parent/located_in no se repite aquí: ya se comprobó al
    -- registrar, porque el tipo de un ID es su prefijo y coincide siempre con el declarado.
    function self:Validate()
        local errors, warnings = {}, {}
        local ids = self:GetIds()

        for _, id in ipairs(ids) do
            local entity = byId[id]
            for _, relation in ipairs({ "parent", "located_in" }) do
                local target = entity[relation]
                if target and not byId[target] then
                    errors[#errors + 1] = "entidad '" .. id .. "': " .. relation .. ": '" .. target
                        .. "' no está registrada"
                end
            end
            for index, target in ipairs(entity.related_to or {}) do
                if not byId[target] then
                    errors[#errors + 1] = "entidad '" .. id .. "': related_to[" .. index .. "]: '"
                        .. target .. "' no está registrada"
                end
            end
            for _, warning in ipairs(warningsById[id] or {}) do
                warnings[#warnings + 1] = warning
            end
        end

        -- Ciclos en parent. Cada recorrido sigue la cadena de padres desde un nodo sin
        -- visitar: 1 = en el recorrido actual, 2 = ya resuelto. Volver a topar con un nodo
        -- en 1 es un ciclo, que se informa una sola vez empezando por su menor ID.
        local state = {}
        for _, startId in ipairs(ids) do
            if not state[startId] then
                local path, position = {}, {}
                local node = startId
                while node and byId[node] and not state[node] do
                    state[node] = 1
                    path[#path + 1] = node
                    position[node] = #path
                    node = byId[node].parent
                end
                if node and state[node] == 1 then
                    local cycle = {}
                    for i = position[node], #path do
                        cycle[#cycle + 1] = path[i]
                    end
                    local smallest = 1
                    for i = 2, #cycle do
                        if cycle[i] < cycle[smallest] then
                            smallest = i
                        end
                    end
                    local ordered = {}
                    for i = 0, #cycle - 1 do
                        ordered[#ordered + 1] = cycle[((smallest - 1 + i) % #cycle) + 1]
                    end
                    ordered[#ordered + 1] = ordered[1]
                    errors[#errors + 1] = "ciclo en la jerarquía parent: " .. table.concat(ordered, " -> ")
                end
                for _, visited in ipairs(path) do
                    state[visited] = 2
                end
            end
        end

        return { ok = #errors == 0, errors = errors, warnings = warnings }
    end

    -- Inicialización del módulo (la llama Core/Init, ya cargados todos los datos). Falla con
    -- un error descriptivo si alguna entidad se rechazó al registrarla o si el conjunto no
    -- supera Validate(); en ese caso NO queda marcado como validado. Un Registry vacío es
    -- válido.
    function self:Init()
        local problems = {}
        for _, rejection in ipairs(rejected) do
            for _, message in ipairs(rejection.errors) do
                problems[#problems + 1] = message
            end
        end
        for _, message in ipairs(self:Validate().errors) do
            problems[#problems + 1] = message
        end

        if #problems > 0 then
            validated = false
            local shown = {}
            for i = 1, math.min(#problems, MAX_SUMMARY_PROBLEMS) do
                shown[i] = problems[i]
            end
            error("Registry: validación fallida (" .. #problems .. " problema(s)): "
                .. table.concat(shown, " | ")
                .. (#problems > MAX_SUMMARY_PROBLEMS and " | ..." or ""), 0)
        end
        validated = true
    end

    -- true si Init validó el conjunto y no se ha intentado registrar nada después.
    function self:IsValidated()
        return validated
    end

    return self
end

-- La instancia por defecto es Chronicle.Registry (con Chronicle.Schema);
-- Chronicle.Registry.New(schema) crea registros independientes (p. ej. para pruebas).
Chronicle.Registry = NewRegistry(Chronicle.Schema)
Chronicle.Registry.New = NewRegistry
