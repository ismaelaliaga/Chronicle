Chronicle = Chronicle or {}

-- Registro y despacho del comando /chronicle. En esta fase solo hay un comando de
-- comprobación (/chronicle sin argumentos): sirve para verificar que el Core está
-- activo. Los comandos de producto (where, reset, trivia...) llegarán en su fase y se
-- añadirán con Slash:Register().

local Utils = Chronicle.Utils

local Slash = {}
Chronicle.Slash = Slash

local commands = {} -- nombre en minúsculas -> manejador(args)

-- Registra un subcomando: /chronicle <name> <args>. El manejador recibe el resto del
-- texto (sin espacios sobrantes).
function Slash:Register(name, handler)
    if type(name) ~= "string" or name == "" or type(handler) ~= "function" then
        error("Chronicle.Slash:Register: se esperaba (nombre, función)", 2)
    end
    commands[strlower(name)] = handler
end

-- Mensaje de comprobación del Core.
function Slash.PrintStatus()
    local State = Chronicle.State
    Utils.Print(string.format(
        "Core activo (v%s). Eventos: %s | Estado: %s, schemaVersion %s%s.",
        tostring(Chronicle.version or "?"),
        Chronicle.Events and "OK" or "NO",
        State and State:IsReady() and "OK" or "NO",
        tostring(State and State:GetSchemaVersion() or "?"),
        State and State:IsReadOnly() and " (solo lectura)" or ""
    ))
end

local function Dispatch(msg)
    local cmd, args = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = strlower(cmd)

    if cmd == "" then
        Slash.PrintStatus()
        return
    end

    local handler = commands[cmd]
    if handler then
        handler(args)
    else
        Utils.Print("comando desconocido: " .. cmd)
    end
end

function Slash:Init()
    SLASH_CHRONICLE1 = "/chronicle"
    SlashCmdList["CHRONICLE"] = Dispatch
end
