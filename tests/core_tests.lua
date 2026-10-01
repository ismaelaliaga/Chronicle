-- Escenarios de prueba del Core de Chronicle V2 (Fase 1), ejecutados contra mock.lua.
-- Comprueban que el .toc carga sin errores y en el orden correcto, y que Events, State,
-- Slash e Init se comportan como se espera. No sustituyen probarlo en el cliente real.

local passed, failed = 0, 0

local function check(name, condition, detail)
    if condition then
        passed = passed + 1
        print(string.format("[OK]   %s", name))
    else
        failed = failed + 1
        print(string.format("[FAIL] %s -- %s", name, detail or ""))
    end
end

local function contains(list, text)
    for _, s in ipairs(list) do
        if s:find(text, 1, true) then return true end
    end
    return false
end

-- ===================== Carga e inicialización =====================
ChronicleCharDB = nil -- primera vez: el cliente no tiene SavedVariables
local okLoad, errLoad = pcall(LoadAddon)
check("todos los ficheros del .toc cargan sin errores de Lua", okLoad, tostring(errLoad))

check("existe un único namespace global: Chronicle", type(Chronicle) == "table")
check("los módulos del Core están definidos tras cargar (Utils, Events, State, Slash, Init)",
    Chronicle.Utils and Chronicle.Events and Chronicle.State and Chronicle.Slash and Chronicle.Init)
check("cargar los ficheros NO inicializa nada todavía (State no está listo)",
    Chronicle.State:IsReady() == false and ChronicleCharDB == nil)
check("el comando /chronicle aún no está registrado antes de ADDON_LOADED",
    SlashCmdList["CHRONICLE"] == nil)

FireEvent("ADDON_LOADED", "OtroAddon")
check("ADDON_LOADED de otro addon se ignora",
    Chronicle.Init.initialized == false and Chronicle.State:IsReady() == false)

FireEvent("ADDON_LOADED", "Chronicle")
check("ADDON_LOADED de Chronicle inicializa el Core", Chronicle.Init.initialized == true)
check("ningún módulo falló al inicializar", next(Chronicle.Init.failed) == nil)
check("Chronicle.version se lee del .toc", Chronicle.version == "0.2.0-dev")

-- ===================== State =====================
check("State está listo tras la inicialización", Chronicle.State:IsReady() == true)
check("ChronicleCharDB se ha creado como tabla", type(ChronicleCharDB) == "table")
check("schemaVersion existe y es 1",
    ChronicleCharDB.schemaVersion == 1 and Chronicle.State:GetSchemaVersion() == 1)
check("existe discovery.entries (vacío) por defecto",
    type(ChronicleCharDB.discovery) == "table"
        and type(ChronicleCharDB.discovery.entries) == "table"
        and next(ChronicleCharDB.discovery.entries) == nil)
check("State:Get lee por camino", Chronicle.State:Get("discovery", "entries") == ChronicleCharDB.discovery.entries)
check("State:Get de un camino inexistente devuelve nil", Chronicle.State:Get("no", "existe") == nil)

check("State:Set escribe y State:Get lo lee",
    Chronicle.State:Set(true, "discovery", "entries", "zone:dun_morogh") == true
        and Chronicle.State:Get("discovery", "entries", "zone:dun_morogh") == true)
check("State:Set crea tablas intermedias que falten",
    Chronicle.State:Set(5, "settings", "a", "b") == true and ChronicleCharDB.settings.a.b == 5)
check("State:Set con nil borra la clave",
    Chronicle.State:Set(nil, "discovery", "entries", "zone:dun_morogh") == true
        and Chronicle.State:Get("discovery", "entries", "zone:dun_morogh") == nil)
check("State:Set(nil) sobre un camino inexistente no crea tablas",
    Chronicle.State:Set(nil, "fantasma", "x") == true and ChronicleCharDB.fantasma == nil)
check("State:Set no permite tocar schemaVersion",
    not pcall(function() Chronicle.State:Set(99, "schemaVersion") end)
        and ChronicleCharDB.schemaVersion == 1)
check("State:Set sin ruta lanza error", not pcall(function() Chronicle.State:Set(1) end))

-- Idempotencia: volver a inicializar no pierde datos.
Chronicle.State:Set(true, "discovery", "entries", "zone:loch_modan")
Chronicle.State:Init()
check("State:Init repetido conserva los datos existentes",
    Chronicle.State:Get("discovery", "entries", "zone:loch_modan") == true)

-- ===================== Sesiones posteriores (persistencia) =====================
local saved = ChronicleCharDB
LoadAddon()
ChronicleCharDB = saved -- el cliente restaura las SavedVariables antes de cargar ficheros
FireEvent("ADDON_LOADED", "Chronicle")
check("tras /reload el estado guardado se conserva",
    Chronicle.State:Get("discovery", "entries", "zone:loch_modan") == true
        and Chronicle.State:GetSchemaVersion() == 1)

-- Tabla guardada sin schemaVersion (p. ej. restos de una versión anterior del addon).
LoadAddon()
ChronicleCharDB = { discoveredZones = { DunMorogh = true }, enabled = false }
FireEvent("ADDON_LOADED", "Chronicle")
check("una tabla sin schemaVersion recibe schemaVersion y defaults",
    ChronicleCharDB.schemaVersion == 1 and type(ChronicleCharDB.discovery.entries) == "table")
check("State no borra claves que no conoce",
    ChronicleCharDB.discoveredZones.DunMorogh == true and ChronicleCharDB.enabled == false)

-- ChronicleCharDB corrupto (no es tabla).
LoadAddon()
ChronicleCharDB = "basura"
FireEvent("ADDON_LOADED", "Chronicle")
check("un ChronicleCharDB que no es tabla se recrea",
    type(ChronicleCharDB) == "table" and ChronicleCharDB.schemaVersion == 1)

-- Estado de una versión futura: solo lectura, intacto.
LoadAddon()
ChronicleCharDB = { schemaVersion = 99, discovery = { entries = { ["zone:x"] = true } } }
FireEvent("ADDON_LOADED", "Chronicle")
check("un schemaVersion futuro deja State en solo lectura y avisa",
    Chronicle.State:IsReadOnly() == true and contains(ChatLog, "schemaVersion 99"))
check("en solo lectura State:Set no escribe y los datos quedan intactos",
    Chronicle.State:Set(true, "discovery", "entries", "zone:y") == false
        and ChronicleCharDB.discovery.entries["zone:y"] == nil
        and ChronicleCharDB.schemaVersion == 99
        and Chronicle.State:Get("discovery", "entries", "zone:x") == true)

-- ===================== Events =====================
LoadAddon()
ChronicleCharDB = nil
FireEvent("ADDON_LOADED", "Chronicle")
local Events = Chronicle.Events

local log = {}
local function a(...) table.insert(log, { "a", ... }) end
local function b(...) table.insert(log, { "b", ... }) end

check("Register devuelve true la primera vez", Events:Register("test.evento", a) == true)
check("Register de la misma función no la duplica", Events:Register("test.evento", a) == false)
Events:Register("test.evento", b)

local count = Events:Emit("test.evento", 1, "dos")
check("Emit llama a todos los callbacks, en orden de registro, con los argumentos",
    #log == 2 and log[1][1] == "a" and log[2][1] == "b"
        and log[1][2] == 1 and log[1][3] == "dos" and log[2][3] == "dos")
check("Emit devuelve cuántos callbacks se ejecutaron", count == 2)

check("Unregister devuelve true si existía", Events:Unregister("test.evento", a) == true)
log = {}
Events:Emit("test.evento")
check("tras Unregister el callback ya no se llama", #log == 1 and log[1][1] == "b")
check("Unregister de algo que no existe devuelve false",
    Events:Unregister("test.evento", a) == false and Events:Unregister("nada", a) == false)
check("Emit de un evento sin suscriptores no falla y devuelve 0", Events:Emit("nada") == 0)

Events:Unregister("test.evento", b)
check("Register valida sus argumentos",
    not pcall(function() Events:Register("", a) end)
        and not pcall(function() Events:Register("x", "no soy función") end))

-- Un callback que falla no impide los siguientes, y el error se reporta.
local reachedAfterError = false
Events:Register("test.error", function() error("fallo de prueba") end)
Events:Register("test.error", function() reachedAfterError = true end)
ReportedErrors = {}
local okCount = Events:Emit("test.error")
check("un callback que falla no impide que se ejecuten los siguientes",
    reachedAfterError == true and okCount == 1)
check("el error de un callback se reporta con geterrorhandler",
    contains(ReportedErrors, "fallo de prueba") and contains(ReportedErrors, "test.error"))

-- Desregistrarse (o registrar) dentro de un callback no altera la emisión en curso.
local order = {}
local function selfRemoving()
    table.insert(order, "self")
    Events:Unregister("test.mutacion", selfRemoving)
end
Events:Register("test.mutacion", selfRemoving)
Events:Register("test.mutacion", function() table.insert(order, "otro") end)
Events:Emit("test.mutacion")
Events:Emit("test.mutacion")
check("quitarse dentro de un callback no salta a los demás y surte efecto en la siguiente emisión",
    table.concat(order, ",") == "self,otro,otro")

-- ===================== Init =====================
-- Evento del ciclo de vida: Init emite "Chronicle.Initialized" al terminar.
LoadAddon()
ChronicleCharDB = nil
local initializedCount = 0
Chronicle.Events:Register("Chronicle.Initialized", function() initializedCount = initializedCount + 1 end)
FireEvent("ADDON_LOADED", "Chronicle")
check("Init emite Chronicle.Initialized al terminar", initializedCount == 1)
Chronicle.Init:Run()
check("Init:Run es idempotente (no vuelve a inicializar ni a emitir)", initializedCount == 1)

-- Un módulo que falla no impide arrancar a los demás.
LoadAddon()
ChronicleCharDB = nil
Chronicle.Slash.Init = function() error("slash roto") end
FireEvent("ADDON_LOADED", "Chronicle")
check("un módulo que falla en Init se registra en Init.failed",
    Chronicle.Init.failed["Slash"] ~= nil and Chronicle.Init.failed["Slash"]:find("slash roto", 1, true) ~= nil)
check("y el resto de módulos sí se inicializan", Chronicle.State:IsReady() == true)

-- ===================== Slash =====================
LoadAddon()
ChronicleCharDB = nil
FireEvent("ADDON_LOADED", "Chronicle")
check("/chronicle queda registrado tras la inicialización",
    SLASH_CHRONICLE1 == "/chronicle" and type(SlashCmdList["CHRONICLE"]) == "function")

ChatLog = {}
local okSlash, errSlash = pcall(SlashCmdList["CHRONICLE"], "")
check("/chronicle no lanza errores de Lua", okSlash, tostring(errSlash))
check("/chronicle confirma que el Core está activo (Eventos y Estado OK, schemaVersion 1)",
    contains(ChatLog, "Core activo") and contains(ChatLog, "Eventos: OK")
        and contains(ChatLog, "Estado: OK") and contains(ChatLog, "schemaVersion 1"))

ChatLog = {}
SlashCmdList["CHRONICLE"]("   ")
check("/chronicle con solo espacios equivale a /chronicle", contains(ChatLog, "Core activo"))

ChatLog = {}
SlashCmdList["CHRONICLE"]("where")
check("un subcomando aún no implementado (where) se avisa como desconocido y no falla",
    contains(ChatLog, "comando desconocido: where"))

local received
Chronicle.Slash:Register("Eco", function(args) received = args end)
SlashCmdList["CHRONICLE"]("  ECO   hola mundo  ")
check("Slash:Register añade subcomandos (sin distinguir mayúsculas) y pasa los argumentos",
    received == "hola mundo")

-- ===================== Aislamiento de la SavedVariable =====================
-- Ningún módulo fuera de State debe referenciar ChronicleCharDB.
local offenders = {}
for _, file in ipairs(ADDON_FILES) do
    if file.name ~= "Core/State.lua" then
        -- Se ignoran las líneas de comentario: solo cuenta el código.
        for line in file.source:gmatch("[^\n]+") do
            if not line:match("^%s*%-%-") and line:find("ChronicleCharDB", 1, true) then
                offenders[#offenders + 1] = file.name
                break
            end
        end
    end
end
check("ningún fichero salvo Core/State.lua toca ChronicleCharDB en su código",
    #offenders == 0, table.concat(offenders, ", "))

print(string.format("\nResultado: %d OK, %d FAIL", passed, failed))
if failed > 0 then error("hay pruebas fallidas") end
