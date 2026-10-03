-- Escenarios de prueba del Core de Chronicle V2 (Fase 1), ejecutados contra mock.lua.
-- Comprueban que el .toc carga sin errores y en el orden correcto, y que Events, State,
-- Slash e Init se comportan como se espera. No sustituyen probarlo en el cliente real.

-- `check` y `contains` los provee support.lua (comunes a todos los ficheros de pruebas).

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

-- Arranca el addon de cero: carga los ficheros, deja que `prepare` sabotee lo que haga
-- falta ANTES de ADDON_LOADED, y devuelve cuántas veces se anunció Chronicle.Initialized
-- (nil si no se pudo ni suscribir porque el bus no existe).
local function Boot(prepare)
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    if Chronicle.Events then
        Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    end
    local ok, err = pcall(FireEvent, "ADDON_LOADED", "Chronicle")
    return announced, ok, err
end
local function failedNames()
    local names = {}
    for name in pairs(Chronicle.Init.failed) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ",")
end

-- --- Arranque correcto ---
local announced = Boot()
check("arranque correcto: Init.ready es true y no hay fallos",
    Chronicle.Init.ready == true and next(Chronicle.Init.failed) == nil)
check("arranque correcto: Chronicle.Initialized se emite exactamente una vez", announced == 1)
check("arranque correcto: no se reporta ningún error", #ReportedErrors == 0)

-- --- Idempotencia: un segundo intento accidental no duplica nada ---
local slashBefore = SlashCmdList["CHRONICLE"]
Chronicle.Init:Run()
FireEvent("ADDON_LOADED", "Chronicle")
check("un segundo Init:Run / ADDON_LOADED no vuelve a emitir Chronicle.Initialized", announced == 1)
check("un segundo intento no vuelve a registrar el comando slash", SlashCmdList["CHRONICLE"] == slashBefore)
check("un segundo intento no cambia el estado de Init", Chronicle.Init.ready == true and next(Chronicle.Init.failed) == nil)

-- --- Módulo requerido que falla (State) ---
announced = Boot(function() Chronicle.State.Init = function() error("estado roto") end end)
check("State falla: se registra en Init.failed", failedNames() == "State"
    and Chronicle.Init.failed.State:find("estado roto", 1, true) ~= nil)
check("State falla: Init.ready es false", Chronicle.Init.ready == false)
check("State falla: NO se anuncia Chronicle.Initialized", announced == 0)
check("State falla: se comunica con el mecanismo de errores",
    contains(ReportedErrors, "estado roto") and contains(ReportedErrors, "State"))
check("State falla: los módulos independientes se siguen intentando (Slash registrado)",
    SlashCmdList["CHRONICLE"] ~= nil)
ChatLog = {}
SlashCmdList["CHRONICLE"]("")
check("State falla: /chronicle NO afirma que el Core está activo y nombra el fallo",
    not contains(ChatLog, "Core activo") and contains(ChatLog, "NO se ha inicializado")
        and contains(ChatLog, "State"))

-- --- Bus de eventos ausente ---
local okMissing
announced, okMissing = Boot(function() Chronicle.Events = nil end)
check("Events ausente: el arranque no lanza ningún error de Lua (ni un segundo error)", okMissing == true)
check("Events ausente: se diagnostica en Init.failed y Init.ready es false",
    Chronicle.Init.failed.Events ~= nil and Chronicle.Init.failed.Events:find("no está cargado", 1, true) ~= nil
        and Chronicle.Init.ready == false)
check("Events ausente: no se anuncia nada", announced == 0)
check("Events ausente: se intentan el resto de módulos independientes",
    Chronicle.State:IsReady() == true and SlashCmdList["CHRONICLE"] ~= nil)
check("Events ausente: se comunica por el mecanismo de errores",
    contains(ReportedErrors, "Events") and contains(ReportedErrors, "no está cargado"))

-- --- Bus de eventos presente pero inutilizable ---
Boot(function() Chronicle.Events.Init = function() error("bus roto") end end)
check("Events.Init falla: Init.ready es false y queda diagnosticado",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Events ~= nil)

-- Emit roto: el módulo se inicializa pero no puede anunciar.
local okBrokenEmit
announced, okBrokenEmit = Boot(function()
    Chronicle.Events.Emit = function() error("emit roto") end
end)
check("Emit que lanza error: no se propaga, se diagnostica y Init.ready pasa a false",
    okBrokenEmit == true and Chronicle.Init.ready == false
        and Chronicle.Init.failed.Events ~= nil and Chronicle.Init.failed.Events:find("emit roto", 1, true) ~= nil)
Boot(function() Chronicle.Events.Emit = nil end)
check("Emit inexistente: no se propaga, se diagnostica y Init.ready es false",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Events ~= nil)

-- --- Módulo no requerido (Slash) ---
announced = Boot(function() Chronicle.Slash.Init = function() error("slash roto") end end)
check("Slash (no requerido) falla: queda en Init.failed pero Init.ready sigue true",
    failedNames() == "Slash" and Chronicle.Init.ready == true)
check("Slash (no requerido) falla: el arranque se anuncia (los requeridos están bien)", announced == 1)
check("Slash (no requerido) falla: el error se comunica", contains(ReportedErrors, "slash roto"))

announced = Boot(function() Chronicle.Slash = nil end)
check("Slash ausente (no requerido): se diagnostica como no cargado y el arranque sigue",
    Chronicle.Init.failed.Slash ~= nil and Chronicle.Init.ready == true and announced == 1)

-- --- Un suscriptor roto de Chronicle.Initialized no estropea el arranque ---
LoadAddon()
ChronicleCharDB = nil
Chronicle.Events:Register("Chronicle.Initialized", function() error("suscriptor roto") end)
FireEvent("ADDON_LOADED", "Chronicle")
check("un suscriptor de Initialized que falla se reporta pero Init.ready sigue true",
    Chronicle.Init.ready == true and next(Chronicle.Init.failed) == nil
        and contains(ReportedErrors, "suscriptor roto"))

-- --- Sin geterrorhandler: el reporte tiene respaldo y no genera un segundo error ---
local savedHandler = geterrorhandler
geterrorhandler = nil
local okNoHandler
announced, okNoHandler = Boot(function() Chronicle.State.Init = function() error("sin handler") end end)
geterrorhandler = savedHandler
check("sin geterrorhandler: el fallo se registra y no se lanza ningún error de Lua",
    okNoHandler == true and Chronicle.Init.failed.State ~= nil and Chronicle.Init.ready == false)

-- --- State:Set no deja machacar schemaVersion con una ruta más profunda ---
Boot()
check("State:Set rechaza rutas que empiecen por schemaVersion, también las más profundas",
    not pcall(function() Chronicle.State:Set("x", "schemaVersion", "sub") end)
        and ChronicleCharDB.schemaVersion == 1)

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
SlashCmdList["CHRONICLE"]("reset")
check("un subcomando no implementado (reset: pospuesto, Discovery no tiene reinicio) se avisa como desconocido y no falla",
    contains(ChatLog, "comando desconocido: reset"))

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
