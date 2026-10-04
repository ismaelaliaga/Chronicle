-- Regresión: los avisos de descubrimiento. Causa: NADIE escuchaba Chronicle.Discovery.Discovered para pedir un aviso al Popup (solo el Codex), así que
-- descubrir un lugar nunca mostraba nada, mientras que /chronicle test (que llama a Popup:Show directamente) sí. Con el addon real y el mock estricto.
-- Esto NO demuestra que el aviso se vea en el cliente real.

local function Boot(prepare)
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    FireEvent("ADDON_LOADED", "Chronicle")
end
local function names(zone, subzone)
    function GetRealZoneText() return zone end
    function GetSubZoneText() return subzone end
    C_Map = {
        GetBestMapForUnit = function() return 1426 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end,
    }
end
local function reset() GetRealZoneText, GetSubZoneText, C_Map = nil, nil, nil end
local function nameOf(id) return (Chronicle.Localization:Get(id, "name")) end
local function descOf(id) return (Chronicle.Localization:Get(id, "description")) end
local function shownCount()
    local popup = Chronicle.Popup
    return (popup:IsVisible() and 1 or 0) + popup:GetQueueSize()
end

-- ===================== Arranque =====================
Boot(function() names("Dun Morogh", "Kharanos") end)
check("N0. el módulo de avisos arranca (opcional), sin fallos ni omitidos, y está listo",
    Chronicle.DiscoveryNotice ~= nil and Chronicle.DiscoveryNotice:IsReady() and Chronicle.Init.failed.DiscoveryNotice == nil and Chronicle.Init.skipped.DiscoveryNotice == nil)
check("N0b. al arrancar no hay ningún aviso pendiente", shownCount() == 0)

-- ===================== Lugares: descubrimiento NUEVO =====================
local r = Chronicle.ZoneDiscovery:Check()
check("N1. un descubrimiento NUEVO de zona y subzona llega al Popup: el primero se muestra y el segundo queda en cola (uno por entidad, ni más ni menos)",
    r.zone.status == "discovered" and r.subzone.status == "discovered" and Chronicle.Popup:IsVisible() == true and Chronicle.Popup:GetQueueSize() == 1)
check("N2. el aviso usa el contenido correcto de la entidad descubierta: su nombre como título y su descripción como cuerpo",
    (function()
        local content = Chronicle.Popup:GetContent()
        return content ~= nil and content.title == nameOf("zone:dun_morogh") and content.body == descOf("zone:dun_morogh")
    end)())
Chronicle.Popup:Close()
check("N2b. al cerrar el primero sale el de la subzona, con su propio contenido",
    (function()
        local content = Chronicle.Popup:GetContent()
        return content ~= nil and content.title == nameOf("subzone:kharanos") and content.body == descOf("subzone:kharanos")
    end)())
Chronicle.Popup:CloseAll()

-- ===================== Lugares: ya descubiertos =====================
local before = shownCount()
Chronicle.ZoneDiscovery:Check()
Chronicle.ZoneDiscovery:Check()
check("N3. un descubrimiento REPETIDO (ya descubierta) no genera ningún aviso: cambiar de zona de ida y vuelta no los repite", before == 0 and shownCount() == 0)
check("N3b. Discover de algo ya descubierto devuelve «already» y no emite el evento",
    (function()
        local emitted = 0
        local f = function() emitted = emitted + 1 end
        Chronicle.Events:Register("Chronicle.Discovery.Discovered", f)
        local ok, why = Chronicle.Discovery:Discover("zone:dun_morogh")
        Chronicle.Events:Unregister("Chronicle.Discovery.Discovered", f)
        return ok == true and why == "already" and emitted == 0 and shownCount() == 0
    end)())

-- ===================== Privacidad: nada bloqueado =====================
Boot(function() names("Dun Morogh", nil) end)
Chronicle.ZoneDiscovery:Check()
Chronicle.Popup:CloseAll()
Chronicle.Events:Emit("Chronicle.Discovery.Discovered", "zone:loch_modan") -- evento falso de algo NO descubierto
check("N4. un evento por una entidad que Discovery NO confirma como descubierta no genera aviso (no se filtra nada de lo bloqueado)", shownCount() == 0)
Chronicle.Events:Emit("Chronicle.Discovery.Discovered", "zone:no_existe")
Chronicle.Events:Emit("Chronicle.Discovery.Discovered", nil)
Chronicle.Events:Emit("Chronicle.Discovery.Discovered", 42)
check("N4b. IDs inexistentes o inválidos se ignoran sin errores ni avisos", shownCount() == 0 and #ReportedErrors == 0)
check("N4c. los avisos solo contienen texto de entidades descubiertas: tras descubrir Dun Morogh no aparece ningún nombre de lo no descubierto",
    (function()
        Chronicle.Popup:CloseAll()
        Boot(function() names("Dun Morogh", nil) end)
        Chronicle.ZoneDiscovery:Check()
        local content = Chronicle.Popup:GetContent()
        local all = (content.title or "") .. (content.body or "")
        return not all:find(nameOf("zone:loch_modan"), 1, true) and not all:find("continent:", 1, true) and not all:find("zone:", 1, true)
    end)())

-- ===================== Fallos de Popup =====================
Boot(function() names("Dun Morogh", "Kharanos") end)
local realEnqueue = Chronicle.Popup.Enqueue
Chronicle.Popup.Enqueue = function() error("popup roto") end
local rr = Chronicle.ZoneDiscovery:Check()
check("N5. un Popup que lanza error NO rompe Discovery: la zona y la subzona quedan descubiertas y guardadas, y el fallo se comunica",
    rr.zone.status == "discovered" and rr.subzone.status == "discovered" and Chronicle.Discovery:IsDiscovered("zone:dun_morogh")
        and Chronicle.Discovery:IsDiscovered("subzone:kharanos") and #ReportedErrors >= 1)
Chronicle.Popup.Enqueue = function() return false, "ui_error" end
ReportedErrors = {}
Chronicle.Discovery:Discover("subzone:thunderbrew_distillery")
check("N5b. un Popup que rechaza el aviso (false, motivo) tampoco rompe Discovery y el rechazo NO es silencioso (se comunica y se cuenta)",
    Chronicle.Discovery:IsDiscovered("subzone:thunderbrew_distillery") and #ReportedErrors >= 1
        and Chronicle.DiscoveryNotice:GetStats().failed.ui_error == 1)
Chronicle.Popup.Enqueue = realEnqueue

-- ===================== La cola no pierde avisos en silencio =====================
Boot(function() names(nil, nil) end)
local ids = {}
for _, id in ipairs(Chronicle.Registry:GetIds("subzone")) do ids[#ids + 1] = id end
local requested = 0
for _, id in ipairs(ids) do
    if requested < 53 then
        Chronicle.Discovery:Discover(id)
        requested = requested + 1
    end
end
local stats = Chronicle.DiscoveryNotice:GetStats()
local shownN, queuedN = Chronicle.Popup:IsVisible() and 1 or 0, Chronicle.Popup:GetQueueSize()
check("N6. cada descubrimiento nuevo con contenido se pide al Popup y se cuenta: pedidos = mostrados + en cola + rechazados (nada desaparece sin contarse)",
    stats.requested == requested and shownN + queuedN + (stats.failed.queue_full or 0) == requested)
Chronicle.Popup:CloseAll()
check("N6b. si la cola se llena (queue_full) los avisos perdidos se cuentan TODOS y se comunican UNA sola vez (no se pierden en silencio)", (function()
    Boot(function() names(nil, nil) end) -- estado limpio: nada descubierto
    local fakePopup = { Enqueue = function() return false, "queue_full" end }
    local notice = Chronicle.DiscoveryNotice.New({
        events = Chronicle.Events, discovery = Chronicle.Discovery, localization = Chronicle.Localization, popup = fakePopup,
    })
    -- Instancia aparte con su propio oyente: se comprueba con IDs ya descubiertos y el evento emitido a mano.
    notice:Init()
    ReportedErrors = {}
    for _, id in ipairs({ "subzone:kharanos", "subzone:coldridge_valley", "subzone:coldridge_pass" }) do
        Chronicle.Discovery:Discover(id)
    end
    local s = notice:GetStats()
    return s.requested >= 3 and s.failed.queue_full == s.requested and s.requested == 3 and #ReportedErrors == 1 and ReportedErrors[1]:find("queue_full", 1, true) ~= nil
end)())

-- ===================== Contenido y unión de módulos =====================
Boot(function() names("Dun Morogh", nil) end)
Chronicle.Popup.Init = function() error("popup no arranca") end
check("N7. con el Popup sin inicializar el arranque sigue y el aviso se cuenta como no disponible, sin romper Discovery", (function()
    Boot(function() names("Dun Morogh", nil); Chronicle.Popup.Init = function() error("popup no arranca") end end)
    local res = Chronicle.ZoneDiscovery:Check()
    return res.zone.status == "discovered" and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") and Chronicle.DiscoveryNotice:GetStats().failed.not_ready == 1
end)())
check("N8. el módulo es idempotente: Init repetido no duplica la suscripción (un descubrimiento = un aviso)", (function()
    Boot(function() names(nil, nil) end)
    Chronicle.DiscoveryNotice:Init(); Chronicle.DiscoveryNotice:Init()
    Chronicle.Discovery:Discover("zone:dun_morogh")
    return Chronicle.Popup:IsVisible() == true and Chronicle.Popup:GetQueueSize() == 0 and Chronicle.DiscoveryNotice:GetStats().requested == 1
end)())
check("N9. descubrir NO escribe nada más que el propio descubrimiento y el módulo no referencia la SavedVariable", (function()
    for _, file in ipairs(ADDON_FILES) do
        if file.name == "UI/DiscoveryNotice.lua" then
            for line in file.source:gmatch("[^\n]+") do
                if not line:match("^%s*%-%-") and (line:find("ChronicleCharDB", 1, true) or line:find(":Discover(", 1, true) or line:find(".Discover(", 1, true)) then
                    return false
                end
            end
        end
    end
    return true
end)())
reset()
