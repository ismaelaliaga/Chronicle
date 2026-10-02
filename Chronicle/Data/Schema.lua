Chronicle = Chronicle or {}

-- Esquema de entidades de Chronicle: qué tipos existen, cómo se escribe un ID y qué forma
-- tiene una entidad válida. No guarda entidades (eso es el Registry) ni toca el estado
-- persistente: solo valida, sin modificar nunca lo que recibe.
--
-- IDENTIFICADORES
--   Formato "tipo:slug" -- p. ej. "zone:dun_morogh". El tipo es uno de los definidos en
--   el esquema; el slug va en minúsculas y snake_case ([a-z0-9] separados por "_" simples,
--   sin "_" al principio ni al final, máximo 64 caracteres). El ID NO se deriva del nombre
--   visible ni del padre: es una etiqueta estable que se elige una vez. Traducir un nombre
--   o reorganizar una zona no cambia ningún ID. El tipo declarado por la entidad debe
--   coincidir con el prefijo de su ID, así que el tipo de cualquier ID es conocido sin
--   consultar el Registry.
--
-- CONTENIDO CANÓNICO FRENTE A PRESENTACIÓN
--   Una entidad solo contiene lo que ES y cómo se relaciona: ningún texto visible. Los
--   nombres y descripciones vivirán en Localization (Fase 4), indexados por ID. Los campos
--   opcionales `nameKey` y `descriptionKey` permiten que una entidad apunte a una clave de
--   presentación distinta de su propio ID; si faltan, la clave por defecto es el ID.
--
-- RELACIONES (cada una tiene UNA fuente de verdad; el otro lado se deriva, no se guarda)
--   parent      Jerarquía geográfica. Lo declara el hijo. Árbol de un solo padre:
--                 continent -> zone | city -> subzone
--               Obligatorio en zone, city y subzone; prohibido en el resto.
--   located_in  Colocación de algo que NO forma parte de ese árbol: una ciudad dentro de una
--               zona (Forjaz está en Dun Morogh, pero es una ciudad de pleno derecho del
--               continente), un NPC o una entrada de lore en un lugar. Lo declara el
--               elemento colocado. Siempre opcional.
--   related_to  Relación libre entre cualquier par de entidades (lista de IDs). La fuente de
--               verdad es la entidad que la declara; Registry:GetRelated() la ve desde los
--               dos lados sin que nadie la duplique.
--   contains    NO es un campo: es una consulta derivada (Registry:GetContained) de los
--               parent y located_in de los hijos. Declararlo en una entidad es un error,
--               porque duplicaría la fuente de verdad.
--   Los valores son siempre IDs, nunca nombres visibles.
--
-- Por qué estas combinaciones de parent: reflejan cómo el juego organiza el mundo (una
-- subzona pertenece a una zona o a una ciudad, una zona a un continente) y mantienen el
-- árbol sin ciclos posibles con los tipos actuales. No se permite que un NPC o una entrada
-- de lore tengan parent: no son nodos de la geografía, solo están en ella (located_in).
--
-- AÑADIR UN TIPO: basta una entrada nueva en la tabla de tipos (Schema.New(defs)); ni el
-- Registry ni el validador cambian.
--
-- VALIDACIÓN: aquí solo es ESTRUCTURAL y por entidad (formato, tipos de dato, campos
-- permitidos, y que el tipo de cada ID referenciado sea el que admite la relación). Que los
-- IDs referenciados existan, y los ciclos, solo se pueden comprobar con el conjunto
-- completo: lo hace Registry:Validate().

local Utils = Chronicle.Utils

local ID_SEPARATOR = ":"
local MAX_SLUG_LENGTH = 64

-- Campos comunes a todos los tipos. Los de relación y `id`/`type` tienen validación propia;
-- el resto son claves de presentación (cadenas no vacías).
local COMMON_STRING_FIELDS = { "nameKey", "descriptionKey" }
local COMMON_FIELDS = {
    id = true, type = true, parent = true, located_in = true, related_to = true,
    nameKey = true, descriptionKey = true,
}
-- Campos que ninguna definición de tipo puede redefinir.
local RESERVED_FIELDS = { contains = true }
for name in pairs(COMMON_FIELDS) do
    RESERVED_FIELDS[name] = true
end

-- Validadores de campos específicos de tipo, por nombre de "kind".
local FIELD_KINDS = {
    string = {
        expect = "una cadena no vacía",
        check = function(v) return type(v) == "string" and v ~= "" end,
    },
    positiveInteger = {
        expect = "un entero positivo",
        check = function(v)
            return type(v) == "number" and v >= 1 and v < 4294967296 and v == math.floor(v)
        end,
    },
}

-- Tipos por defecto. `parent`/`located_in` -> { types = {...}, required = bool }; ausente =
-- el tipo no admite esa relación. `fields` -> campos específicos del tipo y su "kind".
--   npcID      ID numérico del NPC en el juego (lo usará el descubrimiento por GUID). Opcional.
--   displayID  ID del modelo 3D. Opcional; ningún sistema depende de él.
--   textKey    clave del cuerpo del artículo de lore, distinta de la descripción corta
--              (descriptionKey). Opcional.
local DEFAULT_TYPES = {
    continent = {},
    zone = {
        parent = { types = { "continent" }, required = true },
    },
    city = {
        parent = { types = { "continent" }, required = true },
        located_in = { types = { "zone" } },
    },
    subzone = {
        parent = { types = { "zone", "city" }, required = true },
    },
    npc = {
        located_in = { types = { "subzone", "zone", "city" } },
        fields = { npcID = "positiveInteger", displayID = "positiveInteger" },
    },
    lore = {
        located_in = { types = { "continent", "zone", "city", "subzone" } },
        fields = { textKey = "string" },
    },
}

-- ---------------------------------------------------------------------------
-- Auxiliares
-- ---------------------------------------------------------------------------

local function IsValidSlug(slug)
    return #slug >= 1
        and #slug <= MAX_SLUG_LENGTH
        and slug:match("^[a-z0-9_]+$") ~= nil
        and slug:sub(1, 1) ~= "_"
        and slug:sub(-1) ~= "_"
        and not slug:find("__", 1, true)
end

-- Representación determinista (nunca direcciones de memoria) para los mensajes.
local function Describe(value)
    local t = type(value)
    if t == "string" then
        return "'" .. value .. "'"
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(value)
    end
    return t
end

local function SortedKeys(set)
    local keys = {}
    for key in pairs(set) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function ToSet(list)
    local set = {}
    for _, value in ipairs(list) do
        set[value] = true
    end
    return set
end

-- Tabla usada como lista 1..n sin huecos ni claves ajenas. Devuelve (true, n) o false.
local function IsArray(t)
    local n = 0
    for key in pairs(t) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false
        end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true, n
end

-- Comprueba una definición de tipos y lanza error si no es coherente (es un error de
-- programación, no de datos).
local function AssertValidDefinitions(defs)
    if type(defs) ~= "table" or next(defs) == nil then
        error("Chronicle.Schema.New: se esperaba una tabla con al menos un tipo", 3)
    end
    for typeName, def in pairs(defs) do
        if type(typeName) ~= "string" or not typeName:match("^[a-z][a-z0-9_]*$") then
            error("Chronicle.Schema.New: nombre de tipo inválido: " .. Describe(typeName), 3)
        end
        if type(def) ~= "table" then
            error("Chronicle.Schema.New: la definición del tipo '" .. typeName .. "' debe ser una tabla", 3)
        end
        for _, relation in ipairs({ "parent", "located_in" }) do
            local rule = def[relation]
            if rule ~= nil then
                if type(rule) ~= "table" or type(rule.types) ~= "table" or #rule.types == 0 then
                    error("Chronicle.Schema.New: '" .. typeName .. "." .. relation
                        .. "' necesita una lista `types` no vacía", 3)
                end
                for _, target in ipairs(rule.types) do
                    if defs[target] == nil then
                        error("Chronicle.Schema.New: '" .. typeName .. "." .. relation
                            .. "' referencia el tipo desconocido " .. Describe(target), 3)
                    end
                end
            end
        end
        for fieldName, kind in pairs(def.fields or {}) do
            if RESERVED_FIELDS[fieldName] then
                error("Chronicle.Schema.New: '" .. typeName .. "' no puede redefinir el campo común '"
                    .. tostring(fieldName) .. "'", 3)
            end
            if FIELD_KINDS[kind] == nil then
                error("Chronicle.Schema.New: el campo '" .. tostring(fieldName) .. "' de '" .. typeName
                    .. "' tiene un kind desconocido: " .. Describe(kind), 3)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

local function NewSchema(typeDefs)
    AssertValidDefinitions(typeDefs)
    -- Copia privada: nadie puede alterar las reglas después de construir el esquema.
    local types = Utils.DeepCopy(typeDefs)
    local typeNames = SortedKeys(types)

    -- Para distinguir "campo desconocido" (aviso) de "campo de otro tipo" (error).
    local fieldOwners = {} -- campo -> lista ordenada de tipos que lo definen
    for _, typeName in ipairs(typeNames) do
        for fieldName in pairs(types[typeName].fields or {}) do
            fieldOwners[fieldName] = fieldOwners[fieldName] or {}
            table.insert(fieldOwners[fieldName], typeName)
        end
    end

    local self = {}

    -- Copia ordenada de los nombres de tipo admitidos.
    function self:GetTypes()
        return Utils.DeepCopy(typeNames)
    end

    function self:IsValidType(typeName)
        return type(typeName) == "string" and types[typeName] ~= nil
    end

    -- Descompone un ID válido: devuelve tipo, slug; o nil y un mensaje que dice qué falla.
    function self:ParseId(id)
        if type(id) ~= "string" then
            return nil, "el ID debe ser una cadena (recibido: " .. Describe(id) .. ")"
        end
        local separatorAt = id:find(ID_SEPARATOR, 1, true)
        if not separatorAt then
            return nil, "el ID " .. Describe(id) .. " no tiene el formato tipo:slug"
        end
        local typeName, slug = id:sub(1, separatorAt - 1), id:sub(separatorAt + 1)
        if slug:find(ID_SEPARATOR, 1, true) then
            return nil, "el ID " .. Describe(id) .. " tiene más de un ':'"
        end
        if not types[typeName] then
            return nil, "el ID " .. Describe(id) .. " usa un tipo desconocido (admitidos: "
                .. table.concat(typeNames, ", ") .. ")"
        end
        if not IsValidSlug(slug) then
            return nil, "el slug del ID " .. Describe(id) .. " debe estar en minúsculas y snake_case"
                .. " ([a-z0-9] separados por '_', sin '_' al principio o al final, máx. "
                .. MAX_SLUG_LENGTH .. " caracteres)"
        end
        return typeName, slug
    end

    -- true si `id` es válido (y, si se indica, del tipo `expectedType`). Si no, false y el motivo.
    function self:IsValidId(id, expectedType)
        local typeName, err = self:ParseId(id)
        if not typeName then
            return false, err
        end
        if expectedType ~= nil and typeName ~= expectedType then
            return false, "el ID " .. Describe(id) .. " es de tipo '" .. typeName
                .. "' y se esperaba '" .. tostring(expectedType) .. "'"
        end
        return true
    end

    -- Reglas de relación de un tipo: { parent = {types, required}|nil, located_in = {types}|nil }.
    -- Devuelve una copia; nil si el tipo no existe.
    function self:GetRelationRules(typeName)
        local def = self:IsValidType(typeName) and types[typeName] or nil
        if not def then
            return nil
        end
        return Utils.DeepCopy({ parent = def.parent, located_in = def.located_in })
    end

    -- Valida la estructura de UNA entidad, sin modificarla. Devuelve
    --   { ok = bool, errors = { ... }, warnings = { ... } }
    -- ok es false si hay algún error. Los errores son problemas estructurales (la entidad
    -- no debe registrarse); las advertencias son cosas sospechosas que no la invalidan
    -- (campo desconocido, relación repetida). Que falte un campo opcional no es ni lo uno
    -- ni lo otro. Cada mensaje empieza por la entidad y el campo, y el orden es siempre
    -- el mismo para la misma entrada.
    function self:Validate(entity)
        local errors, warnings = {}, {}

        if type(entity) ~= "table" then
            errors[1] = "entidad: debe ser una tabla (recibido: " .. Describe(entity) .. ")"
            return { ok = false, errors = errors, warnings = warnings }
        end

        local label = type(entity.id) == "string" and ("entidad '" .. entity.id .. "'") or "entidad sin ID válido"
        local function Fail(field, message)
            errors[#errors + 1] = label .. ": " .. field .. ": " .. message
        end
        local function Warn(field, message)
            warnings[#warnings + 1] = label .. ": " .. field .. ": " .. message
        end

        -- id y type
        local idType
        if entity.id == nil then
            Fail("id", "es obligatorio")
        else
            local parsed, err = self:ParseId(entity.id)
            if parsed then
                idType = parsed
            else
                Fail("id", err)
            end
        end

        local rules
        if entity.type == nil then
            Fail("type", "es obligatorio")
        elseif type(entity.type) ~= "string" or not types[entity.type] then
            Fail("type", "tipo desconocido " .. Describe(entity.type)
                .. " (admitidos: " .. table.concat(typeNames, ", ") .. ")")
        else
            rules = types[entity.type]
            if idType and idType ~= entity.type then
                Fail("type", "el tipo declarado '" .. entity.type
                    .. "' no coincide con el prefijo del ID ('" .. idType .. "')")
            end
        end

        -- Valida un ID referenciado: formato, que no sea la propia entidad y, si `allowed` lo
        -- indica, que su tipo sea uno de los admitidos por la relación.
        local function CheckReference(field, value, allowed)
            local refType, err = self:ParseId(value)
            if not refType then
                Fail(field, err)
                return
            end
            if value == entity.id then
                Fail(field, "una entidad no puede referenciarse a sí misma")
            end
            if allowed and not ToSet(allowed)[refType] then
                Fail(field, "debe ser de tipo " .. table.concat(allowed, " | ") .. " (recibido: "
                    .. Describe(value) .. ")")
            end
        end

        -- parent y located_in
        for _, relation in ipairs({ "parent", "located_in" }) do
            local value = entity[relation]
            local rule = rules and rules[relation]
            if value ~= nil then
                if rules and not rule then
                    Fail(relation, "el tipo '" .. entity.type .. "' no admite " .. relation)
                else
                    CheckReference(relation, value, rule and rule.types)
                end
            elseif rule and rule.required then
                Fail(relation, "es obligatorio para el tipo '" .. entity.type .. "'")
            end
        end

        -- related_to
        if entity.related_to ~= nil then
            if type(entity.related_to) ~= "table" or not IsArray(entity.related_to) then
                Fail("related_to", "debe ser una lista de IDs")
            else
                local seen = {}
                for index, value in ipairs(entity.related_to) do
                    CheckReference("related_to[" .. index .. "]", value, nil)
                    if type(value) == "string" then
                        if seen[value] then
                            Warn("related_to[" .. index .. "]", "ID repetido " .. Describe(value))
                        end
                        seen[value] = true
                    end
                end
            end
        end

        -- contains es una consulta derivada, no un campo
        if entity.contains ~= nil then
            Fail("contains", "no se declara: se deriva de los parent y located_in de los hijos"
                .. " (Registry:GetContained)")
        end

        -- claves de presentación comunes
        for _, field in ipairs(COMMON_STRING_FIELDS) do
            local value = entity[field]
            if value ~= nil and not FIELD_KINDS.string.check(value) then
                Fail(field, "debe ser " .. FIELD_KINDS.string.expect .. " (recibido: " .. Describe(value) .. ")")
            end
        end

        -- campos específicos del tipo
        local typeFields = rules and rules.fields or {}
        for _, field in ipairs(SortedKeys(typeFields)) do
            local value = entity[field]
            local kind = FIELD_KINDS[typeFields[field]]
            if value ~= nil and not kind.check(value) then
                Fail(field, "debe ser " .. kind.expect .. " (recibido: " .. Describe(value) .. ")")
            end
        end

        -- claves no reconocidas: error si pertenecen a OTRO tipo, aviso si no las conoce nadie
        local extras = {}
        for key in pairs(entity) do
            if not COMMON_FIELDS[key] and key ~= "contains" and typeFields[key] == nil then
                extras[#extras + 1] = { name = type(key) == "string" and key or Describe(key), key = key }
            end
        end
        table.sort(extras, function(a, b) return a.name < b.name end)
        for _, extra in ipairs(extras) do
            local owners = fieldOwners[extra.key]
            if owners and rules then
                Fail(extra.name, "pertenece a " .. table.concat(owners, " | ")
                    .. " y no es un campo del tipo '" .. entity.type .. "'")
            else
                Warn(extra.name, "campo desconocido (¿errata?)")
            end
        end

        return { ok = #errors == 0, errors = errors, warnings = warnings }
    end

    return self
end

-- La instancia por defecto es Chronicle.Schema; Chronicle.Schema.New(defs) crea esquemas
-- con otros tipos (lo usan las pruebas, y es el punto de extensión para tipos futuros).
Chronicle.Schema = NewSchema(DEFAULT_TYPES)
Chronicle.Schema.New = NewSchema
