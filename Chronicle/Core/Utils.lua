Chronicle = Chronicle or {}

-- Utilidades realmente generales (no ligadas a ningún dominio de Chronicle). Si una
-- función pertenece claramente a otro módulo -- descubrimiento, datos, interfaz --
-- vive en ese módulo, no aquí.

local Utils = {}
Chronicle.Utils = Utils

local CHAT_PREFIX = "|cff3fc7ebChronicle:|r "

-- Mensaje al chat con el prefijo de Chronicle.
function Utils.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(msg))
end

-- Copia profunda de valores simples y tablas anidadas. No maneja metatablas ni
-- referencias circulares: no se necesitan para los datos de Chronicle.
function Utils.DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Utils.DeepCopy(v)
    end
    return copy
end

-- Rellena en `target` las claves que le falten según `defaults`, recursivamente. Nunca
-- sobrescribe un valor ya existente ni toca claves que `defaults` no menciona. Si en
-- `target` hay un valor que no es tabla donde `defaults` espera una, se sustituye por
-- el valor por defecto.
function Utils.FillDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        local current = target[key]
        if type(defaultValue) == "table" then
            if type(current) ~= "table" then
                target[key] = Utils.DeepCopy(defaultValue)
            else
                Utils.FillDefaults(current, defaultValue)
            end
        elseif current == nil then
            target[key] = defaultValue
        end
    end
    return target
end
