Chronicle = Chronicle or {}

-- Options: las preferencias de Chronicle, definidas en UN solo sitio (nombre, valor predeterminado y validación) y guardadas por
-- personaje a través de State. Este módulo no toca la SavedVariable: lee y escribe solo con State:Get / State:Set. Los consumidores
-- (Trivia, el botón del minimapa, el panel de opciones) piden aquí el valor; nadie guarda una copia.
--
-- PREFERENCIAS (solo las que tienen quien las consuma; las demás del addon original están POSPUESTAS, ver docs/fase12_integraciones.md)
--   triviaEnabled   booleano, predeterminado true.  Lo lee Trivia (¿se muestran curiosidades?) y lo cambia el panel de opciones.
--   minimapAngle    número finito en grados, predeterminado 215 (el del original), siempre normalizado a [0, 360).  Lo lee y lo guarda
--                   el botón del minimapa al terminar de arrastrarlo.
--   No existe ningún «avisos automáticos» ni tema pergamino: en la reconstrucción no hay un consumidor para ellos.
--
-- ALMACENAMIENTO. Cada preferencia vive en ("options", <nombre>). State:Set crea el contenedor `options` al escribir la primera
-- (igual que Discovery crea sus entradas): NO se cambia el estado inicial de State ni schemaVersion, y no se escribe nada al arrancar;
-- un personaje que nunca toca una opción no tiene la clave. Un valor guardado que no supera la validación (tipo equivocado, NaN,
-- infinito, edición manual del fichero) se IGNORA al leer y se usa el predeterminado; no se repara ni se borra.
--
-- CONTRATO
--   Options:Get(name)          -> el valor validado o, si falta o no es válido, el predeterminado. Para un nombre desconocido: nil.
--   Options:GetDefault(name)   -> el predeterminado (copia) | nil si no existe
--   Options:GetNames()         -> lista ordenada de nombres
--   Options:Set(name, value)   -> true | false, motivo        valida, normaliza, guarda y COMPRUEBA que quedó guardado
--       "unknown_option"  el nombre no existe       "invalid_value"  el valor no cumple la validación (no se coacciona nada)
--       "not_ready"       State no está listo       "read_only"      State está en solo lectura (guardado de una versión más nueva)
--       "persist_failed"  State:Set falló o lo guardado no coincide
--   Options:Init() / IsReady() Init comprueba que State está listo y lanza un error descriptivo si no.
--   Chronicle.Options.New({ state }) crea otra instancia (pruebas); `state` es el objeto o una función que lo devuelve.

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local DEFINITIONS = {
    triviaEnabled = {
        default = true,
        validate = function(value) return type(value) == "boolean" end,
    },
    minimapAngle = {
        default = 215,
        validate = IsFinite,
        normalize = function(value)
            local angle = value % 360
            if angle < 0 then angle = angle + 360 end
            return angle
        end,
    },
}

local function NewOptions(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Options.New: se esperaba una tabla { state }", 2)
    end
    local self = {}
    local ready = false

    local function State()
        local state = deps.state
        if type(state) == "function" then
            state = state()
        end
        if type(state) == "table" and type(state.Get) == "function" and type(state.Set) == "function" then
            return state
        end
        return nil
    end

    function self:GetNames()
        local names = {}
        for name in pairs(DEFINITIONS) do names[#names + 1] = name end
        table.sort(names)
        return names
    end

    function self:GetDefault(name)
        local definition = DEFINITIONS[name]
        return definition and definition.default or nil
    end

    function self:Get(name)
        local definition = type(name) == "string" and DEFINITIONS[name] or nil
        if not definition then
            return nil
        end
        local state = State()
        if state and ready then
            local stored = state:Get("options", name)
            if stored ~= nil and definition.validate(stored) then
                return definition.normalize and definition.normalize(stored) or stored
            end
        end
        return definition.default
    end

    function self:Set(name, value)
        local definition = type(name) == "string" and DEFINITIONS[name] or nil
        if not definition then
            return false, "unknown_option"
        end
        if not definition.validate(value) then
            return false, "invalid_value"
        end
        local state = State()
        if not state or not ready or not state:IsReady() then
            return false, "not_ready"
        end
        if state:IsReadOnly() then
            return false, "read_only"
        end
        local normalized = definition.normalize and definition.normalize(value) or value
        if not state:Set(normalized, "options", name) or state:Get("options", name) ~= normalized then
            return false, "persist_failed"
        end
        return true
    end

    function self:Init()
        ready = false
        local state = State()
        if not state or not state:IsReady() then
            error("Options: State no está listo (Options se inicializa después de State)", 0)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    return self
end

Chronicle.Options = NewOptions({ state = function() return Chronicle.State end })
Chronicle.Options.New = NewOptions
