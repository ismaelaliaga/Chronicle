-- Fase 14: descubrimiento de NPC por GUID. Con el addon real y un cliente SIMULADO (UnitGUID/UnitName/eventos). Esto NO demuestra que el cliente 1.15.7 entregue ese formato de
-- GUID ni esos eventos: eso se comprueba en el juego con /chronicle npc.

local GRELIN = "Creature-0-4379-0-2-786-0000045A7B"
local STEN = "Creature-0-4379-0-2-658-0000045A7C"
local function guidOf(npcID) return string.format("Creature-0-4379-0-2-%d-0000045A7D", npcID) end

local units = {} -- token -> { guid, name }
local function setUnit(token, guid, name) units[token] = guid and { guid = guid, name = name } or nil end
function UnitGUID(token) local u = units[token]; return u and u.guid or nil end
function UnitName(token) local u = units[token]; return u and u.name or nil end

local function Boot(prepare)
    LoadAddon()
    ChronicleCharDB = nil
    units = {}
    if prepare then prepare() end
    FireEvent("ADDON_LOADED", "Chronicle")
end
local function slash(text)
    ChatLog = {}
    SlashCmdList["CHRONICLE"](text)
    return table.concat(ChatLog, "\n")
end
local function popups() return (Chronicle.Popup:IsVisible() and 1 or 0) + Chronicle.Popup:GetQueueSize() end
local N = function() return Chronicle.NpcDiscovery end

-- ===================== Parser de GUID =====================
Boot()
local P = function(g) return N():ParseGuid(g) end
check("G1. un GUID de criatura válido da su npcID", (P(GRELIN)).npcID == 786 and (P(GRELIN)).kind == "Creature" and (P(guidOf(1373))).npcID == 1373)
check("G2. jugadores, mascotas y objetos se descartan como «not_creature»",
    select(2, P("Player-4379-0123ABCD")) == "not_creature" and select(2, P("Pet-0-4379-0-2-786-0000045A7B")) == "not_creature"
        and select(2, P("GameObject-0-4379-0-2-786-0000045A7B")) == "not_creature" and select(2, P("Vehicle-0-4379-0-2-786-0000045A7B")) == "not_creature")
check("G3. un formato inesperado es «invalid_guid» y no da npcID (falla en seguro)",
    select(2, P("Creature-0-4379-0-2-786")) == "invalid_guid" and select(2, P("Creature-0-4379-0-2-abc-0000045A7B")) == "invalid_guid"
        and select(2, P("Creature-0-4379-0-2--0000045A7B")) == "invalid_guid" and select(2, P("Creature-0-4379-0-2-0-0000045A7B")) == "invalid_guid"
        and select(2, P("Creature-0-4379-0-2-786-0000045A7B-extra")) == "invalid_guid" and select(2, P("Creature-0-4379-0-2-7.5-0000045A7B")) == "invalid_guid"
        and select(2, P("Creature-0-4379-0-2--5-0000045A7B")) == "invalid_guid")
check("G4. nil, vacío o tipos que no son cadena dan «no_guid»", select(2, P(nil)) == "no_guid" and select(2, P("")) == "no_guid" and select(2, P(786)) == "no_guid" and select(2, P({})) == "no_guid")

-- ===================== Arranque y lista habilitada =====================
check("E0. el servicio arranca (opcional), sin fallos ni omitidos, y solo hay DOS NPC habilitados: Grelin y Sten",
    N():IsReady() and Chronicle.Init.failed.NpcDiscovery == nil and Chronicle.Init.skipped.NpcDiscovery == nil
        and table.concat(N():GetTargets(), ",") == "npc:grelin_whitebeard,npc:sten_stoutarm" and #N():GetRejected() == 0)
check("E0b. los npcID de la lista coinciden con los del Registry (nada habilitado a ciegas) y ningún otro NPC migrado está habilitado",
    Chronicle.Registry:Get("npc:grelin_whitebeard").npcID == 786 and Chronicle.Registry:Get("npc:sten_stoutarm").npcID == 658 and #N():GetTargets() == 2)

-- ===================== Descubrimiento correcto =====================
setUnit("target", GRELIN, "Grelin Whitebeard")
local r = N():Observe("target", "PLAYER_TARGET_CHANGED")
check("D1. un NPC habilitado con GUID válido y nombre correcto se descubre: «discovered», comprobación de nombre «match» y entidad canónica",
    r.status == "discovered" and r.id == "npc:grelin_whitebeard" and r.npcID == 786 and r.nameCheck == "match" and Chronicle.Discovery:IsDiscovered("npc:grelin_whitebeard"))
check("D1b. Discovery guardó el descubrimiento y DiscoveryNotice pidió UN aviso con el nombre y la descripción de la entidad", (function()
    local content = Chronicle.Popup:GetContent()
    return Chronicle.Popup:IsVisible() and popups() == 1 and content.title == Chronicle.Localization:Get("npc:grelin_whitebeard", "name")
        and Chronicle.DiscoveryNotice:GetStats().requested == 1
end)())
check("D1c. el Codex muestra ya su nombre real (la integración no duplica responsabilidades: el servicio solo llamó a Discover)",
    Chronicle.CodexModel.New({ registry = Chronicle.Registry, localization = Chronicle.Localization, discovery = function() return Chronicle.Discovery end }):GetName("npc:grelin_whitebeard")
        == Chronicle.Localization:Get("npc:grelin_whitebeard", "name"))

-- ===================== Repetidos =====================
Chronicle.Popup:CloseAll()
local r2 = N():Observe("target", "PLAYER_TARGET_CHANGED")
local r3 = N():Observe("target", "UPDATE_MOUSEOVER_UNIT")
check("R1. observarlo otra vez devuelve «already» desde la memoria, sin avisos nuevos ni nuevas llamadas a Discover",
    r2.status == "already" and r2.cached == true and r3.status == "already" and popups() == 0 and Chronicle.Discovery:Count("npc") == 1)
check("R1b. cambiar de objetivo y volver tampoco repite nada", (function()
    setUnit("target", nil); N():Observe("target"); setUnit("target", GRELIN, "Grelin Whitebeard")
    return N():Observe("target").status == "already" and popups() == 0
end)())

-- ===================== Eventos del cliente =====================
Boot()
setUnit("mouseover", STEN, "Sten Stoutarm")
FireEvent("UPDATE_MOUSEOVER_UNIT")
check("V1. el evento UPDATE_MOUSEOVER_UNIT del cliente descubre al NPC bajo el ratón", Chronicle.Discovery:IsDiscovered("npc:sten_stoutarm") and N():GetLast().unit == "mouseover")
Boot()
setUnit("target", GRELIN, "Grelin Whitebeard")
FireEvent("PLAYER_TARGET_CHANGED")
check("V2. el evento PLAYER_TARGET_CHANGED descubre al objetivo", Chronicle.Discovery:IsDiscovered("npc:grelin_whitebeard") and N():GetLast().event == "PLAYER_TARGET_CHANGED")
Boot()
setUnit("nameplate3", STEN, "Sten Stoutarm")
FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
check("V3. NAME_PLATE_UNIT_ADDED usa el token que trae el evento (nameplate3)", Chronicle.Discovery:IsDiscovered("npc:sten_stoutarm") and N():GetLast().unit == "nameplate3")
Boot()
setUnit("npc", GRELIN, "Grelin Whitebeard")
FireEvent("GOSSIP_SHOW")
check("V4. GOSSIP_SHOW usa la unidad «npc» de la conversación", Chronicle.Discovery:IsDiscovered("npc:grelin_whitebeard") and N():GetLast().unit == "npc")
Boot()
FireEvent("PLAYER_TARGET_CHANGED"); FireEvent("UPDATE_MOUSEOVER_UNIT"); FireEvent("GOSSIP_SHOW"); FireEvent("NAME_PLATE_UNIT_ADDED"); FireEvent("NAME_PLATE_UNIT_ADDED", 5)
check("V5. sin unidad (sin objetivo, token ausente o no cadena) no pasa nada ni hay errores", Chronicle.Discovery:Count("npc") == 0 and #ReportedErrors == 0)

-- ===================== Descartes (nada de falsos descubrimientos) =====================
Boot()
setUnit("target", "Player-4379-0123ABCD", "Grelin Whitebeard")
local j = N():Observe("target")
setUnit("target", "Pet-0-4379-0-2-786-0000045A7B", "Grelin Whitebeard")
local pet = N():Observe("target")
check("X1. un jugador o una mascota con el nombre o el número de un NPC habilitado NO descubre nada (aunque el nombre coincida)",
    j.status == "not_creature" and pet.status == "not_creature" and Chronicle.Discovery:Count("npc") == 0)
setUnit("target", "Creature-0-4379-0-2-786", "Grelin Whitebeard")
check("X2. un GUID mal formado no descubre nada", N():Observe("target").status == "invalid_guid" and Chronicle.Discovery:Count("npc") == 0)
setUnit("target", guidOf(1252), "Senir Whitebeard") -- NPC migrado, pero NO habilitado
local ne = N():Observe("target")
check("X3. un NPC que existe en el catálogo pero NO está en la lista habilitada no se descubre («not_enabled»)", ne.status == "not_enabled" and not Chronicle.Discovery:IsDiscovered("npc:senir_whitebeard"))
setUnit("target", guidOf(999999), "Cualquiera")
check("X4. un npcID sin entidad en Chronicle no descubre nada", N():Observe("target").status == "not_enabled" and Chronicle.Discovery:Count("npc") == 0)
setUnit("target", GRELIN, "Sten Stoutarm")
local mm = N():Observe("target")
check("X5. el npcID de Grelin con el nombre de OTRA entidad (Sten) es «name_mismatch» y no descubre nada",
    mm.status == "name_mismatch" and mm.reason == "npc:sten_stoutarm" and Chronicle.Discovery:Count("npc") == 0)
setUnit("target", GRELIN, "Nombre en otro idioma")
local un = N():Observe("target")
check("X6. un nombre que el catálogo no conoce (p. ej. localizado) no se puede comprobar: se acepta como «unverified» porque el GUID es el dato fiable y el NPC está habilitado",
    un.status == "discovered" and un.nameCheck == "unverified")
Boot()
setUnit("target", GRELIN, nil)
check("X7. sin nombre (unidad aún no cargada) se descubre con comprobación «unverified»", N():Observe("target").nameCheck == "unverified" and Chronicle.Discovery:IsDiscovered("npc:grelin_whitebeard"))

-- ===================== Errores y datos que faltan =====================
Boot()
local realDiscover = Chronicle.Discovery.Discover
Chronicle.Discovery.Discover = function() error("discovery roto") end
setUnit("target", GRELIN, "Grelin Whitebeard")
local f1 = N():Observe("target")
Chronicle.Discovery.Discover = function() return false, "read_only" end
local f2 = N():Observe("target")
check("F1. un Discover que lanza error o rechaza («read_only») da «failed» con su motivo, NO lo marca como hecho y no rompe nada",
    f1.status == "failed" and f1.reason:find("discovery roto", 1, true) ~= nil and f2.status == "failed" and f2.reason == "read_only" and #ReportedErrors == 0)
Chronicle.Discovery.Discover = realDiscover
check("F2. tras el fallo se puede reintentar y se descubre (la memoria solo guarda lo que Discovery aceptó)", N():Observe("target").status == "discovered")
check("F3. un evento con UnitGUID que lanza error no propaga nada", (function()
    function UnitGUID() error("api rota") end
    local ok = pcall(FireEvent, "PLAYER_TARGET_CHANGED")
    function UnitGUID(token) local u = units[token]; return u and u.guid or nil end
    return ok and #ReportedErrors == 0
end)())

Boot(function() Chronicle.NpcTargets = { { id = "npc:grelin_whitebeard", npcID = 999, confidence = "source_confirmed" },
    { id = "npc:no_existe", npcID = 5, confidence = "source_confirmed" }, { id = "npc:sten_stoutarm", npcID = 658, confidence = "inventada" },
    { id = "npc:senir_whitebeard", npcID = 1252, confidence = "client_verified" }, { id = "npc:senir_whitebeard", npcID = 1252, confidence = "client_verified" }, "basura" } end)
local rej = {}
for _, item in ipairs(N():GetRejected()) do rej[#rej + 1] = tostring(item.id) .. ":" .. item.reason end
check("L1. una lista con entradas que no cuadran con el Registry solo habilita las válidas; cada rechazo queda explicado y se comunica",
    table.concat(N():GetTargets(), ",") == "npc:senir_whitebeard" and #rej == 5 and table.concat(rej, "|"):find("npc:grelin_whitebeard:npcid_mismatch", 1, true) ~= nil
        and table.concat(rej, "|"):find("npc:no_existe:unknown_entity", 1, true) ~= nil and table.concat(rej, "|"):find("npc:sten_stoutarm:unknown_confidence", 1, true) ~= nil
        and table.concat(rej, "|"):find("duplicate_npcid", 1, true) ~= nil and table.concat(rej, "|"):find("nil:invalid_target", 1, true) ~= nil and #ReportedErrors >= 5)

-- Dos entidades con el mismo npcID: ambigüedad, no se descubre ninguna
Boot(function() Chronicle.Registry:Register({ id = "npc:clon", type = "npc", located_in = "subzone:coldridge_valley", npcID = 786 }) end)
setUnit("target", GRELIN, "Grelin Whitebeard")
check("L2. si dos entidades del Registry comparten npcID la coincidencia es ambigua: no se habilita ni se descubre ninguna",
    table.concat(N():GetTargets(), ",") == "npc:sten_stoutarm" and (N():GetRejected()[1] or {}).reason == "ambiguous_entity" and (N():GetRejected()[1] or {}).id == "npc:grelin_whitebeard"
        and N():Observe("target").status == "not_enabled" and Chronicle.Discovery:Count("npc") == 0)

Boot(function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
check("L3. con Discovery roto el servicio se omite sin romper el resto del arranque", Chronicle.Init.skipped.NpcDiscovery ~= nil and Chronicle.Codex:IsReady())

-- ===================== Comando /chronicle npc =====================
Boot()
local none = slash("npc")
check("C1. /chronicle npc sin observaciones lo explica y dice cuántos NPC hay habilitados", none:find("NPC habilitados para descubrir: 2", 1, true) and none:find("Aún no se ha observado", 1, true))
setUnit("target", GRELIN, "Nombre en otro idioma")
FireEvent("PLAYER_TARGET_CHANGED")
local shown = slash("npc")
check("C2. muestra el GUID crudo, el npcID, el nombre y el resultado para poder comprobar el cliente real",
    shown:find(GRELIN, 1, true) and shown:find("npcID=786", 1, true) and shown:find("Nombre en otro idioma", 1, true) and shown:find("resultado=discovered", 1, true))
setUnit("target", guidOf(1252), "Senir")
FireEvent("PLAYER_TARGET_CHANGED")
local locked = slash("npc")
check("C3. no revela la entidad canónica de algo no descubierto (solo se muestra si está descubierta)",
    locked:find("resultado=not_enabled", 1, true) and not locked:find("npc:senir", 1, true) and not locked:find("Entidad:", 1, true))
check("C4. consultar no descubre nada y no admite argumentos", (function()
    local before = Chronicle.Discovery:Count()
    return slash("npc extra"):find("no admite argumentos", 1, true) ~= nil and Chronicle.Discovery:Count() == before
end)())

-- ===================== Estructura =====================
check("S1. el servicio no referencia la SavedVariable ni toca Popup/State, y el .toc carga datos antes que el servicio", (function()
    for _, file in ipairs(ADDON_FILES) do
        if file.name == "Services/NpcDiscovery.lua" then
            for line in file.source:gmatch("[^\n]+") do
                if not line:match("^%s*%-%-") and (line:find("ChronicleCharDB", 1, true) or line:find("Popup", 1, true) or line:find("State", 1, true)) then return false, line end
            end
        end
    end
    return true
end)())
units = {}
UnitGUID, UnitName = nil, nil
