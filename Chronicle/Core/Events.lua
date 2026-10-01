Chronicle = Chronicle or {}

-- Bus de eventos interno de Chronicle. Su única función es desacoplar módulos:
-- Services emiten ("ha pasado esto") y la UI se suscribe, sin que ninguno conozca al
-- otro. NO tiene relación con los eventos del cliente de WoW (RegisterEvent): son dos
-- mundos distintos, y los nombres de aquí son los que decida Chronicle.
--
-- Deliberadamente mínimo: Register / Unregister / Emit. Sin prioridades, sin
-- "once", sin comodines.

local Events = {}
Chronicle.Events = Events

-- eventName -> lista ordenada de callbacks
local handlers = {}

local function ReportError(eventName, err)
    local message = "Chronicle.Events: error en un callback de '" .. tostring(eventName)
        .. "': " .. tostring(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

-- Suscribe `callback` a `eventName`. Registrar dos veces la misma función al mismo
-- evento no la duplica. Devuelve true si se ha añadido.
function Events:Register(eventName, callback)
    if type(eventName) ~= "string" or eventName == "" then
        error("Chronicle.Events:Register: eventName debe ser un string no vacío", 2)
    end
    if type(callback) ~= "function" then
        error("Chronicle.Events:Register: callback debe ser una función", 2)
    end

    local list = handlers[eventName]
    if not list then
        list = {}
        handlers[eventName] = list
    end
    for i = 1, #list do
        if list[i] == callback then
            return false
        end
    end
    list[#list + 1] = callback
    return true
end

-- Quita la suscripción. Devuelve true si existía.
function Events:Unregister(eventName, callback)
    local list = handlers[eventName]
    if not list then
        return false
    end
    for i = 1, #list do
        if list[i] == callback then
            table.remove(list, i)
            if #list == 0 then
                handlers[eventName] = nil
            end
            return true
        end
    end
    return false
end

-- Llama a todos los callbacks de `eventName`, en orden de registro, con los argumentos
-- dados. Un callback que falla no impide que se ejecuten los siguientes: el error se
-- reporta y se sigue. Se itera sobre una copia, así que registrar o quitar callbacks
-- desde dentro de un callback no altera la emisión en curso (afecta a la siguiente).
-- Devuelve cuántos callbacks se han ejecutado sin error.
function Events:Emit(eventName, ...)
    local list = handlers[eventName]
    if not list then
        return 0
    end

    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end

    local succeeded = 0
    for i = 1, #snapshot do
        local ok, err = pcall(snapshot[i], ...)
        if ok then
            succeeded = succeeded + 1
        else
            ReportError(eventName, err)
        end
    end
    return succeeded
end
