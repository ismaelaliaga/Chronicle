-- Mock mínimo de la API de WoW: solo lo que usa el Core de Chronicle (Fase 1).
-- Crece cuando lo haga el addon, no antes.

-- Utilidades globales del cliente (Lua 5.1 en el juego; este mock corre en 5.3).
function strlower(s) return string.lower(s or "") end
if not unpack then unpack = table.unpack end

-- Chat: se guarda lo escrito para poder comprobarlo.
ChatLog = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg)
        table.insert(ChatLog, msg)
        print("[CHAT] " .. tostring(msg))
    end,
}

SlashCmdList = {}

-- Errores reportados por geterrorhandler() (Events/Init los usan al fallar un callback).
ReportedErrors = {}
function geterrorhandler()
    return function(msg) table.insert(ReportedErrors, tostring(msg)) end
end

-- Metadatos del .toc (en el juego los lee el cliente).
function GetAddOnMetadata(addon, field)
    if addon == "Chronicle" and field == "Version" then
        return "0.2.0-dev"
    end
    return nil
end

-- Frames y eventos del cliente.
local EventRegistry = {}
local FrameMethods = {}
FrameMethods.__index = FrameMethods

function FrameMethods:RegisterEvent(eventName)
    EventRegistry[eventName] = EventRegistry[eventName] or {}
    table.insert(EventRegistry[eventName], self)
end

function FrameMethods:UnregisterEvent(eventName)
    local list = EventRegistry[eventName] or {}
    for i = #list, 1, -1 do
        if list[i] == self then table.remove(list, i) end
    end
end

function FrameMethods:SetScript(name, fn)
    self.__scripts = self.__scripts or {}
    self.__scripts[name] = fn
end

function CreateFrame()
    return setmetatable({}, FrameMethods)
end

function FireEvent(eventName, ...)
    local snapshot = {}
    for _, frame in ipairs(EventRegistry[eventName] or {}) do
        table.insert(snapshot, frame)
    end
    for _, frame in ipairs(snapshot) do
        local onEvent = frame.__scripts and frame.__scripts["OnEvent"]
        if onEvent then onEvent(frame, eventName, ...) end
    end
end

-- Vuelve a un "cliente recién arrancado": sin frames registrados, chat vacío, sin
-- comandos slash. NO toca ChronicleCharDB (es lo único que persiste entre sesiones).
function ResetMockRuntime()
    EventRegistry = {}
    ChatLog = {}
    ReportedErrors = {}
    SlashCmdList = {}
    SLASH_CHRONICLE1 = nil
end
