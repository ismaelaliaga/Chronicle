-- Pruebas de la herramienta TEMPORAL de diagnóstico del descubrimiento (UI/Diagnostics.lua, rama `diagnostico-descubrimiento`). Con el mock: verifican que la
-- herramienta muestra lo que debe y no cambia el comportamiento. NO demuestran nada sobre el cliente real; para eso se usa en el juego.

local function Boot(preset, prepare)
    LoadAddon()
    ChronicleCharDB = preset
    if prepare then prepare() end
    FireEvent("ADDON_LOADED", "Chronicle")
end
local function slash(text)
    ChatLog = {}
    SlashCmdList["CHRONICLE"](text)
    return table.concat(ChatLog, "\n")
end
local function client(zone, subzone)
    function GetRealZoneText() return zone end
    function GetSubZoneText() return subzone end
    C_Map = {
        GetBestMapForUnit = function() return 1426 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end,
    }
end
local function resetClient() GetRealZoneText, GetSubZoneText, C_Map = nil, nil, nil end

-- ===================== arranque e instalación =====================
Boot(nil, function() client("Dun Morogh", "Kharanos") end)
check("D0. el depurador arranca (módulo opcional), con las trazas activas desde el arranque y sin fallos ni omitidos",
    Chronicle.Diagnostics:IsReady() and Chronicle.Diagnostics:IsTracing() and Chronicle.Init.failed.Diagnostics == nil and Chronicle.Init.skipped.Diagnostics == nil)
check("D0b. el comando `debug` está registrado y sin argumentos válidos explica el uso",
    slash("debug"):find("uso: /chronicle debug discovery", 1, true) ~= nil and slash("debug otracosa"):find("uso:", 1, true) ~= nil
        and slash("debug discovery raro"):find("uso:", 1, true) ~= nil)

-- ===================== instantánea =====================
local out = slash("debug discovery status")
check("D1. la instantánea muestra el estado de State, Init y los servicios",
    out:find("State: listo=true soloLectura=false schemaVersion=1", 1, true) and out:find("Init.failed (módulos relevantes): ninguno", 1, true)
        and out:find("Init.skipped (módulos relevantes): ninguno", 1, true)
        and out:find("IsReady: Resolver=true Discovery=true ZoneDiscovery=true Codex=true", 1, true))
check("D1b. muestra los valores EXACTOS que da MapPosition (estado, texto entre comillas y longitud en bytes)",
    out:find('MapPosition:GetZoneName() -> available, "Dun Morogh" (10 bytes)', 1, true) and out:find('MapPosition:GetSubzoneName() -> available, "Kharanos" (8 bytes)', 1, true))
check("D1c. muestra la respuesta del Resolver por tipo y el ID canónico",
    out:find('Resolver:Resolve("Dun Morogh" (10 bytes)) -> zone=zone:dun_morogh | city=city:nil', 1, true) == nil
        and out:find("zone=zone:dun_morogh", 1, true) and out:find("subzone=subzone:kharanos", 1, true) and out:find("city=nil,not_found", 1, true))
check("D1d. muestra Discovery:Count() y que, sin descubrir, las entidades están bloqueadas también para un modelo de Codex nuevo",
    out:find("Discovery:Count() = 0", 1, true) and out:find("Discovery:IsDiscovered(zone:dun_morogh) = false", 1, true)
        and out:find('Modelo de Codex nuevo: GetName(zone:dun_morogh) = "???" (3 bytes) bloqueada=true', 1, true))
check("D1e. la instantánea no descubre nada ni escribe en las SavedVariables", Chronicle.Discovery:Count() == 0 and next(ChronicleCharDB.discovery.entries) == nil)

-- ===================== comprobación y trazas =====================
local traced = slash("debug discovery check")
check("D2. `check` ejecuta ZoneDiscovery:Check() y muestra cada etapa: la zona y la subzona descubiertas con su ID",
    traced:find("estado=discovered nombre=\"Dun Morogh\" (10 bytes) id=zone:dun_morogh", 1, true)
        and traced:find("estado=discovered nombre=\"Kharanos\" (8 bytes) id=subzone:kharanos", 1, true) and traced:find("Count() tras la comprobación = 2", 1, true))
check("D2b. con las trazas activas se ve cada Discover y cada evento interno, con IsDiscovered, Count y el estado del Codex",
    traced:find("[discover] Discovery:Discover(zone:dun_morogh) -> true, new", 1, true) and traced:find("[discover] Discovery:Discover(subzone:kharanos) -> true, new", 1, true)
        and traced:find("[descubierto] evento Chronicle.Discovery.Discovered id=zone:dun_morogh IsDiscovered=true Count=1 Codex listo=true visible=false", 1, true))
local after = slash("debug discovery status")
check("D2c. tras descubrir, un modelo de Codex nuevo con los servicios reales ya muestra los nombres reales",
    after:find("Discovery:IsDiscovered(zone:dun_morogh) = true", 1, true) and after:find('Modelo de Codex nuevo: GetName(zone:dun_morogh) = "Dun Morogh"', 1, true)
        and after:find('GetName(subzone:kharanos) = "Kharanos"', 1, true))

-- ===================== eventos del cliente =====================
ChatLog = {}
FireEvent("ZONE_CHANGED")
local events = table.concat(ChatLog, "\n")
check("D3. un evento de zona del cliente se ve llegar al depurador y a ZoneDiscovery (línea [evento] y línea [check])",
    events:find("[evento] ZONE_CHANGED llegó al frame del depurador", 1, true) and events:find("[check] ZoneDiscovery:Check() -> zona{estado=already", 1, true))
ChatLog = {}
FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("ZONE_CHANGED_NEW_AREA"); FireEvent("ZONE_CHANGED_INDOORS")
check("D3b. los cuatro eventos de zona llegan al depurador", (function()
    local text = table.concat(ChatLog, "\n")
    return text:find("PLAYER_ENTERING_WORLD", 1, true) and text:find("ZONE_CHANGED_NEW_AREA", 1, true) and text:find("ZONE_CHANGED_INDOORS", 1, true)
end)())

-- ===================== límite y desactivación =====================
Boot(nil, function() client("Dun Morogh", "Kharanos") end)
ChatLog = {}
for _ = 1, 60 do FireEvent("ZONE_CHANGED") end
local flood = table.concat(ChatLog, "\n")
local count = 0
for _ in flood:gmatch("[^\n]+") do count = count + 1 end
check("D4. las trazas tienen un límite: 60 eventos no generan más de 41 líneas y el aviso del límite sale una sola vez",
    count <= 41 and select(2, flood:gsub("límite de 40 líneas", "")) == 1)
local originalCheck = Chronicle.ZoneDiscovery.Check
local off = slash("debug discovery off")
check("D4b. `off` desactiva las trazas y restaura las funciones originales (tras desactivar no hay ninguna traza)",
    off:find("desactivadas", 1, true) and Chronicle.Diagnostics:IsTracing() == false and Chronicle.ZoneDiscovery.Check ~= originalCheck
        and slash("debug discovery status") ~= "" and (function() ChatLog = {}; FireEvent("ZONE_CHANGED"); return #ChatLog == 0 end)())
slash("debug discovery on"); slash("debug discovery on")
ChatLog = {}
Chronicle.ZoneDiscovery:Check()
local lines = 0
for line in table.concat(ChatLog, "\n"):gmatch("[^\n]+") do if line:find("[check]", 1, true) then lines = lines + 1 end end
check("D4c. activar dos veces no envuelve las funciones dos veces: una llamada deja UNA sola línea [check]", lines == 1)

-- ===================== casos de fallo visibles =====================
Boot(nil, function() client("Zona Inventada", "Subzona Inventada") end)
local unknown = slash("debug discovery status")
check("D5. con un nombre del cliente que el catálogo no conoce, la instantánea lo muestra como not_found y nada se descubre",
    unknown:find("zone=nil,not_found", 1, true) and unknown:find("sin tipo=nil,not_found", 1, true) and unknown:find("Discovery:Count() = 0", 1, true))
check("D5b. y `check` muestra el motivo (unrecognized) sin descubrir nada",
    slash("debug discovery check"):find("estado=unrecognized", 1, true) ~= nil and Chronicle.Discovery:Count() == 0)

Boot({ schemaVersion = 99, discovery = { entries = {} } }, function() client("Dun Morogh", "Kharanos") end)
local readOnly = slash("debug discovery check")
check("D6. con State de solo lectura se ve el rechazo de Discover con su motivo (read_only) y el estado de State",
    readOnly:find("Discovery:Discover(zone:dun_morogh) -> false, read_only", 1, true) and readOnly:find("estado=failed", 1, true) and readOnly:find("motivo=read_only", 1, true)
        and slash("debug discovery status"):find("soloLectura=true", 1, true) ~= nil)

Boot(nil, function() client("Dun Morogh", "Kharanos"); Chronicle.Resolver.Init = function() error("resolver roto") end end)
local broken = slash("debug discovery status")
check("D7. con un módulo roto la instantánea nombra el fallo en Init.failed y el módulo omitido en Init.skipped",
    broken:find("Init.failed (módulos relevantes): Resolver: ", 1, true) and broken:find("resolver roto", 1, true) and broken:find("ZoneDiscovery: no se intentó", 1, true))

-- ===================== sin efectos =====================
Boot(nil, function() client("Dun Morogh", "Kharanos") end)
slash("debug discovery status"); slash("debug discovery off"); slash("debug discovery on")
check("D8. consultar, activar y desactivar no descubre nada ni toca las SavedVariables",
    Chronicle.Discovery:Count() == 0 and deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} } }))
local before = #ReportedErrors
Chronicle.Diagnostics:Init(); Chronicle.Diagnostics:Init()
check("D8b. Init es idempotente y no produce errores", #ReportedErrors == before and Chronicle.Diagnostics:IsReady())
resetClient()
Boot(nil, function() Chronicle.Slash.Init = function() error("slash roto") end end)
check("D8c. si Slash falla el depurador se omite sin romper el resto", Chronicle.Init.skipped.Diagnostics ~= nil and Chronicle.Codex:IsReady())
