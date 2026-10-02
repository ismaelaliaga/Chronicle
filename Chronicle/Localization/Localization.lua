Chronicle = Chronicle or {}

-- Localization: textos de presentación de las entidades, por ID canónico, campo e idioma.
-- Responsabilidad única: guardar y devolver texto. No resuelve nombres a IDs (eso es
-- Chronicle.Resolver) ni conoce la interfaz. Las entidades existen en Chronicle.Registry, que
-- sigue siendo la única fuente de verdad: aquí no se duplica ninguna entidad.
--
-- DATOS: por idioma y por ID, una entrada con campos opcionales de este conjunto cerrado:
--   name, description, hint, race, role
-- Ninguna entidad tiene que tener todos. Las entradas se añaden con Localization:Add() desde
-- los ficheros de Localization/<idioma>/ y se guardan como copias privadas (closures): desde
-- fuera solo se leen cadenas, nunca tablas internas.
--
-- IDIOMAS: códigos de cuatro letras al estilo de WoW (xxXX, p. ej. "esES"). Un idioma existe
-- solo si tiene al menos una entrada: no hay registro previo de idiomas "disponibles". No se
-- considera disponible ningún idioma sin textos propios; los nombres propios ingleses del
-- conjunto actual están dentro de "esES" tal como venían, no forman un "enUS".
--
-- CONTRATO DE CONSULTA, Get(id, field, lang) -> valor, idiomaUsado
--   * lang omitido (nil)                       usa el idioma predeterminado.
--   * Orden de búsqueda, POR CAMPO:            idioma pedido, y si ahí falta ESE campo, el
--                                              idioma predeterminado. Nada más: sin cadenas
--                                              de fallback, así que no puede haber ciclos.
--   * Idioma pedido sin registrar              se comporta como un idioma sin entradas: cae
--                                              al predeterminado (no es un error).
--   * Idioma registrado pero campo ausente     cae al predeterminado; si tampoco está ahí, nil.
--   * ID que no está en el Registry            nil (aunque hubiese texto huérfano).
--   * Nombre de campo que no existe            nil (no hay error: son los datos los que se
--                                              validan, en Add y en Validate).
--   * Campo ausente en todos los idiomas       nil. Nunca se inventa ni se compone un texto.
--   * Cadena vacía ""                          es un VALOR, no una ausencia: se devuelve tal
--                                              cual y NO activa el fallback; Validate() la
--                                              avisa como advertencia para que no pase
--                                              inadvertida.
--   * Argumentos de tipo equivocado            nil (id, field o lang que no sean cadenas).
--   El segundo valor devuelto es el idioma del que salió el texto, para que quien llama sepa
--   si hubo fallback.
-- GetExact(id, field, lang) consulta SOLO ese idioma, sin fallback.
--
-- Add rechaza (devuelve false y el motivo, y lo anota en GetRejected) un código de idioma mal
-- formado, un campo desconocido, un valor que no sea cadena, una entrada vacía y un
-- (idioma, ID) ya añadido: nunca sobrescribe. Add no comprueba que el ID exista: los ficheros
-- pueden cargarse en cualquier orden; Validate (que corre en Init) detecta los huérfanos.

local Utils = Chronicle.Utils

local DEFAULT_LANGUAGE = "esES"

local FIELDS = { name = true, description = true, hint = true, race = true, role = true }
local FIELD_NAMES = { "description", "hint", "name", "race", "role" } -- orden fijo, para mensajes

local function IsLanguageCode(value)
    return type(value) == "string" and value:match("^%l%l%u%u$") ~= nil
end

local function NewLocalization(registry)
    if type(registry) ~= "table" or type(registry.Has) ~= "function" then
        error("Chronicle.Localization.New: se esperaba un Registry", 2)
    end

    -- Estado privado
    local languages = {} -- idioma -> { [id] = { campo = valor } }
    local defaultLanguage = DEFAULT_LANGUAGE
    local rejected = {} -- { { lang, id, error }, ... } en orden de llegada
    local ready = false

    local self = {}

    local function Reject(lang, id, message)
        table.insert(rejected, {
            lang = type(lang) == "string" and lang or nil,
            id = type(id) == "string" and id or nil,
            error = message,
        })
        return false, message
    end

    -- Añade la entrada de un ID en un idioma. Devuelve true, o false y el motivo.
    function self:Add(lang, id, entry)
        ready = false
        if not IsLanguageCode(lang) then
            return Reject(lang, id, "Localization:Add: código de idioma inválido " .. tostring(lang)
                .. " (se espera el formato xxXX, p. ej. esES)")
        end
        if type(id) ~= "string" or id == "" then
            return Reject(lang, id, "Localization:Add(" .. lang .. "): el ID debe ser una cadena no vacía")
        end
        local label = "Localization:Add(" .. lang .. ", " .. id .. "): "
        if type(entry) ~= "table" then
            return Reject(lang, id, label .. "la entrada debe ser una tabla")
        end

        local clean, count = {}, 0
        local keys = {}
        for key in pairs(entry) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do
            if type(key) ~= "string" or not FIELDS[key] then
                return Reject(lang, id, label .. "campo desconocido '" .. tostring(key)
                    .. "' (admitidos: " .. table.concat(FIELD_NAMES, ", ") .. ")")
            end
            if type(entry[key]) ~= "string" then
                return Reject(lang, id, label .. key .. ": debe ser una cadena (recibido: "
                    .. type(entry[key]) .. ")")
            end
            clean[key] = entry[key]
            count = count + 1
        end
        if count == 0 then
            return Reject(lang, id, label .. "la entrada no tiene ningún campo")
        end
        if languages[lang] and languages[lang][id] then
            return Reject(lang, id, label .. "entrada duplicada (se conserva la original)")
        end

        languages[lang] = languages[lang] or {}
        languages[lang][id] = clean
        return true
    end

    local function Lookup(lang, id, field)
        local entries = languages[lang]
        local entry = entries and entries[id]
        return entry and entry[field]
    end

    local function ValidQuery(id, field)
        return type(id) == "string" and type(field) == "string" and FIELDS[field] == true and registry:Has(id)
    end

    -- Texto en ESE idioma, sin fallback. nil si falta.
    function self:GetExact(id, field, lang)
        if not ValidQuery(id, field) or type(lang) ~= "string" then
            return nil
        end
        return Lookup(lang, id, field)
    end

    -- Texto con fallback por campo al idioma predeterminado. Ver el contrato de arriba.
    function self:Get(id, field, lang)
        if not ValidQuery(id, field) or (lang ~= nil and type(lang) ~= "string") then
            return nil
        end
        local requested = lang or defaultLanguage
        local value = Lookup(requested, id, field)
        if value ~= nil then
            return value, requested
        end
        if requested ~= defaultLanguage then
            value = Lookup(defaultLanguage, id, field)
            if value ~= nil then
                return value, defaultLanguage
            end
        end
        return nil
    end

    -- Idiomas con al menos una entrada, ordenados.
    function self:GetLanguages()
        local list = {}
        for lang in pairs(languages) do
            list[#list + 1] = lang
        end
        table.sort(list)
        return list
    end

    function self:HasLanguage(lang)
        return type(lang) == "string" and languages[lang] ~= nil
    end

    -- IDs con entrada en `lang`, ordenados (una lista nueva en cada llamada).
    function self:GetIds(lang)
        local list = {}
        for id in pairs(type(lang) == "string" and languages[lang] or {}) do
            list[#list + 1] = id
        end
        table.sort(list)
        return list
    end

    function self:GetDefaultLanguage()
        return defaultLanguage
    end

    -- Cambia el idioma predeterminado. Solo admite idiomas con entradas; si no, devuelve
    -- false y el motivo, y no cambia nada.
    function self:SetDefaultLanguage(lang)
        if not self:HasLanguage(lang) then
            return false, "Localization:SetDefaultLanguage: el idioma " .. tostring(lang) .. " no tiene textos registrados"
        end
        defaultLanguage = lang
        ready = false
        return true
    end

    -- Entradas rechazadas por Add hasta ahora (copia).
    function self:GetRejected()
        return Utils.DeepCopy(rejected)
    end

    -- Comprueba el conjunto. Devuelve { ok, errors, warnings } determinista.
    --   Errores:        entradas rechazadas por Add; textos de IDs que no están en el Registry;
    --                   idioma predeterminado sin textos habiendo otros idiomas registrados.
    --   Advertencias:   valores vacíos ("").
    -- Sin ningún idioma registrado es válido (no hay nada que comprobar).
    function self:Validate()
        local errors, warnings = {}, {}
        for _, item in ipairs(rejected) do
            errors[#errors + 1] = item.error
        end

        local langs = self:GetLanguages()
        if #langs > 0 and not languages[defaultLanguage] then
            errors[#errors + 1] = "Localization: el idioma predeterminado " .. defaultLanguage
                .. " no tiene textos (idiomas registrados: " .. table.concat(langs, ", ") .. ")"
        end
        for _, lang in ipairs(langs) do
            for _, id in ipairs(self:GetIds(lang)) do
                if not registry:Has(id) then
                    errors[#errors + 1] = "Localization(" .. lang .. "): texto para '" .. id
                        .. "', que no está registrada en el Registry"
                end
                for _, field in ipairs(FIELD_NAMES) do
                    if languages[lang][id][field] == "" then
                        warnings[#warnings + 1] = "Localization(" .. lang .. ", " .. id .. "): " .. field
                            .. " es una cadena vacía"
                    end
                end
            end
        end
        return { ok = #errors == 0, errors = errors, warnings = warnings }
    end

    -- Inicialización (la llama Core/Init con todos los ficheros ya cargados). Falla con un
    -- error descriptivo si Validate encuentra errores.
    function self:Init()
        local report = self:Validate()
        if #report.errors > 0 then
            ready = false
            local shown = {}
            for i = 1, math.min(#report.errors, 5) do
                shown[i] = report.errors[i]
            end
            error("Localization: validación fallida (" .. #report.errors .. " problema(s)): "
                .. table.concat(shown, " | ") .. (#report.errors > 5 and " | ..." or ""), 0)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    return self
end

-- Instancia por defecto: Chronicle.Localization, sobre Chronicle.Registry.
-- Chronicle.Localization.New(registry) crea otras independientes (p. ej. para pruebas).
Chronicle.Localization = NewLocalization(Chronicle.Registry)
Chronicle.Localization.New = NewLocalization
