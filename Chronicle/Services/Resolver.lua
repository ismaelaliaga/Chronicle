Chronicle = Chronicle or {}

-- Resolver: de un nombre o alias escrito por una persona (o devuelto por el juego en cualquier
-- idioma) al ID canónico de una entidad del Registry. Responsabilidad única: resolver. No crea
-- ni modifica entidades, no escribe nada, y no guarda textos propios salvo los alias.
-- Chronicle.Registry es la fuente de verdad de qué entidades existen; Chronicle.Localization
-- aporta los nombres visibles.
--
-- DE DÓNDE SALEN LOS NOMBRES RESUELTOS
--   1. el campo `name` de cada entidad en TODOS los idiomas registrados (no solo el
--      predeterminado: el juego puede estar en cualquier idioma);
--   2. los alias añadidos con Resolver:AddAlias() (p. ej. "Forjaz" -> city:ironforge). Un alias
--      es un nombre alternativo de una entidad en un idioma; no es una entidad ni un ID.
--
-- NORMALIZACIÓN (mínima; solo para COMPARAR, nunca altera lo que se muestra)
--   1. se quitan los espacios del principio y del final y se reducen los espacios internos
--      repetidos a uno solo (espacio, tabulador, salto de línea);
--   2. se pasa a minúsculas: ASCII, más las siete mayúsculas acentuadas del español
--      (Á É Í Ó Ú Ñ Ü), porque string.lower del cliente no toca los bytes UTF-8.
--   NO se quitan acentos ("Destilería" y "Destileria" son nombres distintos), ni se unifican
--   apóstrofos o guiones, ni se ignoran palabras como "el" o "de".
--   NO hay coincidencias parciales, por prefijo ni aproximadas: o la cadena normalizada es
--   exactamente un nombre/alias conocido, o no se resuelve.
--
-- CONTRATO, Resolve(text [, opts]) -> id            si hay UNA sola entidad candidata
--                                   -> nil, razón[, candidatos]   si no
--   razones: "not_ready"  el índice aún no se ha construido (Init no se ha ejecutado)
--            "empty"      text no es una cadena, o queda vacía al normalizar
--            "not_found"  ningún nombre ni alias coincide
--            "ambiguous"  lo mismo es nombre/alias de varias entidades; el tercer valor es la
--                         lista ordenada de IDs candidatos. NUNCA se elige una arbitrariamente.
--   opts.type = "zone" (etc.) limita los candidatos a ese tipo de entidad; así "ambiguous"
--   puede resolverse cuando solo uno es del tipo buscado. Un tipo que el Registry no conoce
--   lanza error (es una errata del llamante).
--   Un ID canónico ("zone:dun_morogh") NO es un nombre: Resolve no lo acepta ni lo confunde con
--   un alias (devuelve "not_found"). Quien ya tiene un ID usa Registry:Has().
--
-- ÍNDICE: se construye en Init (y al llamar a Rebuild) a partir de Localization y de los alias;
-- las consultas solo lo leen. Un alias o nombre de un ID que no está en el Registry no se indexa
-- y se informa como error en Validate. Los resultados no dependen del orden de inserción: los
-- candidatos salen siempre ordenados.
--
-- Los alias no verificados no se marcan como verificados aquí: la procedencia de cada uno está
-- anotada junto a su definición (Localization/<idioma>/Aliases.lua).

local Utils = Chronicle.Utils

-- Mayúsculas acentuadas del español (UTF-8, 2 bytes) -> minúscula.
local UPPER_TO_LOWER = {
    { "\195\129", "\195\161" }, -- Á -> á
    { "\195\137", "\195\169" }, -- É -> é
    { "\195\141", "\195\173" }, -- Í -> í
    { "\195\147", "\195\179" }, -- Ó -> ó
    { "\195\154", "\195\186" }, -- Ú -> ú
    { "\195\145", "\195\177" }, -- Ñ -> ñ
    { "\195\156", "\195\188" }, -- Ü -> ü
}

local function Normalize(text)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    text = text:gsub("%s+", " ")
    text = text:lower()
    for _, pair in ipairs(UPPER_TO_LOWER) do
        text = text:gsub(pair[1], pair[2])
    end
    return text
end

local function TypeOf(id)
    return id:match("^([^:]+):")
end

local function NewResolver(registry, localization)
    if type(registry) ~= "table" or type(registry.Has) ~= "function" then
        error("Chronicle.Resolver.New: se esperaba un Registry", 2)
    end
    if type(localization) ~= "table" or type(localization.GetLanguages) ~= "function" then
        error("Chronicle.Resolver.New: se esperaba un Localization", 2)
    end

    -- Estado privado
    local aliases = {} -- { { lang, id, alias, key }, ... } en orden de llegada
    local aliasSeen = {} -- "lang|id|key" -> true
    local rejected = {} -- { { lang, id, alias, error }, ... }
    local index = nil -- clave normalizada -> { [id] = true }; nil hasta Init/Rebuild
    local ready = false

    local self = {}

    local function Reject(lang, id, alias, message)
        table.insert(rejected, {
            lang = type(lang) == "string" and lang or nil,
            id = type(id) == "string" and id or nil,
            alias = type(alias) == "string" and alias or nil,
            error = message,
        })
        return false, message
    end

    -- Añade un alias: `alias` es otro nombre de la entidad `id` en el idioma `lang` (que debe
    -- ser un idioma con textos en Localization; se comprueba en Validate). Devuelve true, o
    -- false y el motivo. Rechaza datos mal formados y el mismo alias repetido para el mismo
    -- (idioma, ID); no comprueba que el ID exista (lo hace Validate, así que el orden de carga
    -- de los ficheros no importa).
    function self:AddAlias(lang, id, alias)
        -- Cambiar los alias invalida el índice: hasta que se reconstruya (Init o Rebuild),
        -- Resolve devuelve "not_ready" en vez de resolver con datos desfasados.
        ready = false
        index = nil
        if type(lang) ~= "string" or lang == "" then
            return Reject(lang, id, alias, "Resolver:AddAlias: el idioma debe ser una cadena no vacía")
        end
        if type(id) ~= "string" or id == "" then
            return Reject(lang, id, alias, "Resolver:AddAlias(" .. lang .. "): el ID debe ser una cadena no vacía")
        end
        if type(alias) ~= "string" then
            return Reject(lang, id, alias, "Resolver:AddAlias(" .. lang .. ", " .. id .. "): el alias debe ser una cadena")
        end
        local key = Normalize(alias)
        if key == "" then
            return Reject(lang, id, alias, "Resolver:AddAlias(" .. lang .. ", " .. id .. "): el alias está vacío")
        end
        local seenKey = lang .. "|" .. id .. "|" .. key
        if aliasSeen[seenKey] then
            return Reject(lang, id, alias, "Resolver:AddAlias(" .. lang .. ", " .. id .. "): alias duplicado '" .. alias .. "'")
        end
        aliasSeen[seenKey] = true
        aliases[#aliases + 1] = { lang = lang, id = id, alias = alias, key = key }
        return true
    end

    -- Construye un índice nuevo. Solo indexa IDs que están en el Registry.
    local function BuildIndex()
        local built = {}
        local function Add(key, id)
            if key ~= "" then
                built[key] = built[key] or {}
                built[key][id] = true
            end
        end
        for _, lang in ipairs(localization:GetLanguages()) do
            for _, id in ipairs(localization:GetIds(lang)) do
                if registry:Has(id) then
                    local name = localization:GetExact(id, "name", lang)
                    if name then
                        Add(Normalize(name), id)
                    end
                end
            end
        end
        for _, item in ipairs(aliases) do
            if registry:Has(item.id) then
                Add(item.key, item.id)
            end
        end
        return built
    end

    local function SortedIds(set)
        local ids = {}
        for id in pairs(set) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        return ids
    end

    -- Resuelve un nombre o alias a un ID canónico. Ver el contrato de arriba.
    function self:Resolve(text, opts)
        local filterType = type(opts) == "table" and opts.type or nil
        if filterType ~= nil then
            if type(filterType) ~= "string" or not pcall(registry.Count, registry, filterType) then
                error("Chronicle.Resolver:Resolve: tipo desconocido " .. tostring(filterType), 2)
            end
        end
        if not index then
            return nil, "not_ready"
        end
        if type(text) ~= "string" then
            return nil, "empty"
        end
        local key = Normalize(text)
        if key == "" then
            return nil, "empty"
        end
        local set = index[key]
        if not set then
            return nil, "not_found"
        end
        local candidates = {}
        for _, id in ipairs(SortedIds(set)) do
            if not filterType or TypeOf(id) == filterType then
                candidates[#candidates + 1] = id
            end
        end
        if #candidates == 0 then
            return nil, "not_found"
        elseif #candidates == 1 then
            return candidates[1]
        end
        return nil, "ambiguous", candidates
    end

    -- Alias rechazados por AddAlias hasta ahora (copia).
    function self:GetRejected()
        return Utils.DeepCopy(rejected)
    end

    -- Número de alias aceptados.
    function self:CountAliases()
        return #aliases
    end

    -- Comprueba el conjunto. Devuelve { ok, errors, warnings } determinista.
    --   Errores:      alias rechazados; alias de un ID que no está en el Registry; alias en un
    --                 idioma sin textos en Localization.
    --   Advertencias: nombres o alias ambiguos (varias entidades), con sus candidatos. Se
    --                 avisan en vez de fallar: Resolve ya los trata sin elegir una al azar, y
    --                 con opts.type pueden desambiguarse.
    function self:Validate()
        local errors, warnings = {}, {}
        for _, item in ipairs(rejected) do
            errors[#errors + 1] = item.error
        end
        for _, item in ipairs(aliases) do
            if not registry:Has(item.id) then
                errors[#errors + 1] = "Resolver(" .. item.lang .. "): el alias '" .. item.alias
                    .. "' apunta a '" .. item.id .. "', que no está registrada en el Registry"
            end
            if not localization:HasLanguage(item.lang) then
                errors[#errors + 1] = "Resolver(" .. item.lang .. "): el alias '" .. item.alias
                    .. "' está en un idioma sin textos en Localization"
            end
        end

        local built = BuildIndex()
        local keys = {}
        for key in pairs(built) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local ids = SortedIds(built[key])
            if #ids > 1 then
                warnings[#warnings + 1] = "Resolver: '" .. key .. "' es ambiguo, lo comparten: "
                    .. table.concat(ids, ", ")
            end
        end
        return { ok = #errors == 0, errors = errors, warnings = warnings }
    end

    -- Vuelve a construir el índice (tras cambiar Localization o los alias). Lo usa Init.
    function self:Rebuild()
        index = BuildIndex()
    end

    -- Inicialización (la llama Core/Init con todos los ficheros ya cargados y Localization ya
    -- inicializada). Falla con un error descriptivo si Validate encuentra errores; en ese caso
    -- no se construye el índice y Resolve devuelve "not_ready".
    function self:Init()
        local report = self:Validate()
        if #report.errors > 0 then
            ready = false
            index = nil
            local shown = {}
            for i = 1, math.min(#report.errors, 5) do
                shown[i] = report.errors[i]
            end
            error("Resolver: validación fallida (" .. #report.errors .. " problema(s)): "
                .. table.concat(shown, " | ") .. (#report.errors > 5 and " | ..." or ""), 0)
        end
        self:Rebuild()
        ready = true
    end

    function self:IsReady()
        return ready
    end

    return self
end

-- Instancia por defecto: Chronicle.Resolver, sobre Chronicle.Registry y Chronicle.Localization.
-- Chronicle.Resolver.New(registry, localization) crea otras independientes (p. ej. para pruebas).
Chronicle.Resolver = NewResolver(Chronicle.Registry, Chronicle.Localization)
Chronicle.Resolver.New = NewResolver
