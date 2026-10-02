-- Escenarios de prueba de ZoneDiscovery (Fase 6): descubrir la zona/ciudad y la subzona actuales a
-- partir de sus NOMBRES, resueltos con el Resolver real y los datos migrados. Los nombres los entrega un
-- MapPosition simulado (o uno real con APIs simuladas): no se ejecuta ningún cliente. Los nombres en
-- español son los que ya existen como alias en la fuente; no se ha añadido ninguno.

local EVENT = "Chronicle.Discovery.Discovered"

local function Boot(prepare)
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    if Chronicle.Events then
        Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    end
    FireEvent("ADDON_LOADED", "Chronicle")
    return announced
end

local function Listen()
    local calls = {}
    Chronicle.Events:Register(EVENT, function(id) calls[#calls + 1] = id end)
    return calls
end

-- MapPosition simulado: devuelve lo que se le diga para la zona y la subzona.
local function FakeMapPosition(zone, subzone)
    local mp = { zone = zone, subzone = subzone }
    function mp:GetZoneName() return self.zone[1], self.zone[2] end
    function mp:GetSubzoneName() return self.subzone[1], self.subzone[2] end
    function mp:GetPosition() error("ZoneDiscovery no debe usar la posición") end
    return mp
end
local function Names(zoneName, subzoneName)
    return FakeMapPosition(zoneName and { "available", zoneName } or { "unavailable", "empty" },
        subzoneName and { "available", subzoneName } or { "unavailable", "empty" })
end

-- Frames simulados: registran qué se les pide.
local function FakeFrames(opts)
    opts = opts or {}
    local made = {}
    local factory = function(kind)
        if opts.throw then error("CreateFrame roto") end
        if opts.returnNil then return nil end
        local f = { kind = kind, events = {}, scripts = {} }
        function f:RegisterEvent(name)
            if opts.failEvent == name then error("evento desconocido " .. name) end
            self.events[#self.events + 1] = name
        end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        made[#made + 1] = f
        return f
    end
    return factory, made
end

local function Service(mp, opts)
    opts = opts or {}
    local factory, made = FakeFrames(opts.frames)
    local svc = Chronicle.ZoneDiscovery.New({
        mapPosition = mp,
        resolver = opts.resolver or function() return Chronicle.Resolver end,
        discovery = opts.discovery or function() return Chronicle.Discovery end,
        createFrame = opts.createFrame or factory,
    })
    if opts.init ~= false then svc:Init() end
    return svc, made
end

-- ===================== Arranque completo =====================
local announced = Boot()
check("con el addon completo ZoneDiscovery arranca: listo, sin fallos ni omitidos, y el arranque se anuncia una vez",
    Chronicle.ZoneDiscovery:IsReady() == true and Chronicle.Init.ready == true and announced == 1
        and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)

-- ===================== Dependencias e Init =====================
check("ZoneDiscovery.New exige una tabla de dependencias", not pcall(Chronicle.ZoneDiscovery.New, nil) and not pcall(Chronicle.ZoneDiscovery.New, 5))
check("Check antes de Init devuelve 'not_ready' y no descubre nada",
    (function()
        local svc = Service(Names("Dun Morogh", "Kharanos"), { init = false })
        local r = svc:Check()
        return r.status == "not_ready" and r.zone == nil and svc:IsReady() == false and Chronicle.Discovery:Count() == 0
    end)())
check("Init falla si falta MapPosition (o no tiene las funciones de nombres)",
    (function()
        local factory = FakeFrames()
        local a = Chronicle.ZoneDiscovery.New({ resolver = Chronicle.Resolver, discovery = Chronicle.Discovery, createFrame = factory })
        local b = Chronicle.ZoneDiscovery.New({ mapPosition = {}, resolver = Chronicle.Resolver, discovery = Chronicle.Discovery, createFrame = factory })
        local ok1, e1 = pcall(a.Init, a)
        local ok2 = pcall(b.Init, b)
        return ok1 == false and tostring(e1):find("MapPosition no está disponible", 1, true) ~= nil and ok2 == false
    end)())
check("Init falla si el Resolver no está listo, y el servicio no queda listo",
    (function()
        local notReady = Chronicle.Resolver.New(Chronicle.Registry, Chronicle.Localization)
        local svc = Service(Names("Dun Morogh"), { resolver = notReady, init = false })
        local ok, err = pcall(svc.Init, svc)
        return ok == false and tostring(err):find("Resolver no está listo", 1, true) ~= nil and svc:IsReady() == false
    end)())
check("Init falla si Discovery no está listo",
    (function()
        local fake = { IsReady = function() return false end, Discover = function() end }
        local svc = Service(Names("Dun Morogh"), { discovery = fake, init = false })
        local ok, err = pcall(svc.Init, svc)
        return ok == false and tostring(err):find("Discovery no está listo", 1, true) ~= nil and svc:IsReady() == false
    end)())
check("Init falla si no se puede crear el frame (sin CreateFrame, CreateFrame que lanza error o que devuelve nil)",
    (function()
        for _, opts in ipairs({ { createFrame = "no es una función" }, { frames = { throw = true } }, { frames = { returnNil = true } } }) do
            local svc = Service(Names("Dun Morogh"), { init = false, createFrame = opts.createFrame, frames = opts.frames })
            local ok = pcall(svc.Init, svc)
            if ok or svc:IsReady() then return false end
        end
        return true
    end)())
do
    local svc, made = Service(Names("Dun Morogh"))
    check("Init crea un único frame sin interfaz, escucha exactamente los 4 eventos de zona y solo define OnEvent",
        #made == 1 and made[1].kind == "Frame" and svc:IsReady()
            and table.concat(made[1].events, ",") == "PLAYER_ENTERING_WORLD,ZONE_CHANGED_NEW_AREA,ZONE_CHANGED,ZONE_CHANGED_INDOORS"
            and type(made[1].scripts.OnEvent) == "function" and made[1].scripts.OnUpdate == nil
            and (function() local n = 0 for _ in pairs(made[1].scripts) do n = n + 1 end return n == 1 end)())
    svc:Init()
    check("Init repetido no crea otro frame ni vuelve a registrar eventos", #made == 1 and #made[1].events == 4 and svc:IsReady())
end
do
    ReportedErrors = {}
    local svc, made = Service(Names("Dun Morogh"), { frames = { failEvent = "ZONE_CHANGED_INDOORS" } })
    check("si un evento no se puede registrar se comunica, no impide el resto y el servicio queda listo",
        svc:IsReady() and #made[1].events == 3 and contains(ReportedErrors, "ZONE_CHANGED_INDOORS"))
end

-- ===================== Zona/ciudad =====================
do
    local calls = Listen()
    local svc = Service(Names("Dun Morogh", nil))
    local r = svc:Check()
    check("zona reconocida: 'discovered', con su ID, y queda descubierta en Discovery",
        r.status == "checked" and r.zone.status == "discovered" and r.zone.id == "zone:dun_morogh" and r.zone.name == "Dun Morogh"
            and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") and #calls == 1 and calls[1] == "zone:dun_morogh")
    check("la subzona sin nombre es 'unavailable' ('empty') y no se descubre nada con ella",
        r.subzone.status == "unavailable" and r.subzone.reason == "empty" and r.subzone.id == nil and Chronicle.Discovery:Count("subzone") == 0)
    local r2 = svc:Check()
    local r3 = svc:Check()
    check("repetir la comprobación: 'already', sin segundo descubrimiento ni segundo evento",
        r2.zone.status == "already" and r2.zone.id == "zone:dun_morogh" and r3.zone.status == "already" and #calls == 1
            and Chronicle.Discovery:Count() == 1)
end
do
    Boot()
    local svc = Service(Names("  dUn   MOROGH ", nil))
    check("la normalización del Resolver aplica: mayúsculas y espacios no impiden reconocer la zona",
        svc:Check().zone.id == "zone:dun_morogh")
end
do
    Boot()
    local a = Service(Names("Ciudad de Forjaz", nil)):Check()
    Boot()
    local b = Service(Names("Forjaz", nil)):Check()
    Boot()
    local c = Service(Names("Ironforge", nil)):Check()
    check("una ciudad se reconoce por su nombre y por los alias de la fuente ('Ciudad de Forjaz', 'Forjaz'): city:ironforge",
        a.zone.id == "city:ironforge" and a.zone.status == "discovered" and b.zone.id == "city:ironforge" and c.zone.id == "city:ironforge")
    Boot()
    local d = Service(Names("Loch Modan", nil)):Check()
    check("otra zona real (Loch Modan)", d.zone.id == "zone:loch_modan" and d.zone.status == "discovered")
end

-- ===================== Subzona =====================
do
    Boot()
    local calls = Listen()
    local r = Service(Names(nil, "Kharanos")):Check()
    check("subzona reconocida: 'discovered' con su ID; la zona sin nombre es 'unavailable'",
        r.subzone.status == "discovered" and r.subzone.id == "subzone:kharanos" and r.zone.status == "unavailable"
            and Chronicle.Discovery:IsDiscovered("subzone:kharanos") and #calls == 1)
    for _, case in ipairs({
        { "Destilería Cebatruenos", "subzone:thunderbrew_distillery" }, { "El Trono", "subzone:the_great_forge" },
        { "Ciudad Manitas", "subzone:tinker_town" }, { "Gol'Bolar Quarry", "subzone:golbolar_quarry" },
        { "THELSAMAR", "subzone:thelsamar" },
    }) do
        Boot()
        local out = Service(Names(nil, case[1])):Check().subzone
        check("la subzona '" .. case[1] .. "' (nombre o alias de la fuente) se descubre como " .. case[2],
            out.status == "discovered" and out.id == case[2] and Chronicle.Discovery:IsDiscovered(case[2]))
    end
end
do
    Boot()
    local r = Service(Names("Dun Morogh", "Kharanos")):Check()
    check("zona y subzona a la vez: cada una se descubre con su propio ID y se emiten dos descubrimientos",
        r.zone.id == "zone:dun_morogh" and r.subzone.id == "subzone:kharanos" and Chronicle.Discovery:Count() == 2)
end

-- ===================== No se interpreta un nombre como el tipo equivocado =====================
for _, case in ipairs({
    { "un nombre de zona en la subzona", nil, "Dun Morogh" }, { "un nombre de ciudad en la subzona", nil, "Ironforge" },
    { "un nombre de subzona en la zona", "Kharanos", nil }, { "otro nombre de subzona en la zona", "Ironforge Airfield", nil },
    { "un alias de subzona en la zona", "El Trono", nil },
}) do
    Boot()
    local r = Service(Names(case[2], case[3])):Check()
    local out = case[2] and r.zone or r.subzone
    check(case[1] .. ": 'unrecognized' y NO se descubre nada",
        out.status == "unrecognized" and out.id == nil and Chronicle.Discovery:Count() == 0 and ChronicleCharDB.discovery.entries["zone:dun_morogh"] == nil)
end

-- ===================== Nombres desconocidos =====================
do
    Boot()
    local before = Chronicle.Utils.DeepCopy(ChronicleCharDB)
    local calls = Listen()
    local r = Service(Names("Elwynn Forest", "Goldshire")):Check()
    check("nombres que ningún dato conoce: 'unrecognized' en ambos, sin descubrir ni escribir nada ni emitir eventos",
        r.zone.status == "unrecognized" and r.subzone.status == "unrecognized" and Chronicle.Discovery:Count() == 0
            and deepEqual(ChronicleCharDB, before) and #calls == 0)
    check("el nombre se conserva en la salida para poder diagnosticar", r.zone.name == "Elwynn Forest" and r.subzone.name == "Goldshire")
    local r2 = Service(Names("Dun", "Kharan")):Check()
    check("sin coincidencias parciales: 'Dun' y 'Kharan' no se reconocen",
        r2.zone.status == "unrecognized" and r2.subzone.status == "unrecognized" and Chronicle.Discovery:Count() == 0)
end

-- ===================== Ambigüedad =====================
do
    local reg = Chronicle.Registry.New(Chronicle.Schema)
    for _, e in ipairs({
        { id = "continent:c", type = "continent" },
        { id = "zone:z1", type = "zone", parent = "continent:c" },
        { id = "city:c1", type = "city", parent = "continent:c" },
        { id = "zone:z2", type = "zone", parent = "continent:c" },
        { id = "subzone:s1", type = "subzone", parent = "zone:z1" },
        { id = "subzone:s2", type = "subzone", parent = "zone:z2" },
        { id = "subzone:s3", type = "subzone", parent = "zone:z2" },
    }) do assert(reg:Register(e)) end
    local loc = Chronicle.Localization.New(reg)
    loc:Add("esES", "zone:z1", { name = "Valle" })
    loc:Add("esES", "city:c1", { name = "valle" })
    loc:Add("esES", "zone:z2", { name = "Bosque" })
    loc:Add("esES", "subzone:s1", { name = "Puerto" })
    loc:Add("esES", "subzone:s2", { name = "Puerto" })
    loc:Add("esES", "subzone:s3", { name = "Claro" })
    local res = Chronicle.Resolver.New(reg, loc)
    res:Init()
    local stateData = { discovery = { entries = {} } }
    local state = { IsReady = function() return true end, IsReadOnly = function() return false end,
        Get = function(self, ...) local n = stateData for i = 1, select("#", ...) do n = type(n) == "table" and n[(select(i, ...))] or nil end return n end,
        Set = function(self, value, ...) local keys = { ... } local n = stateData
            for i = 1, #keys - 1 do n[keys[i]] = n[keys[i]] or {}; n = n[keys[i]] end
            n[keys[#keys]] = value return true end }
    local discovered = {}
    local disc = Chronicle.Discovery.New({ state = state, registry = reg, events = { Emit = function(_, name, id) discovered[#discovered + 1] = id end } })
    disc:Init()
    local svc = Service(Names("Valle", "Puerto"), { resolver = res, discovery = disc })
    local r = svc:Check()
    check("un nombre de zona que vale para una zona Y una ciudad es 'ambiguous' con sus candidatos ordenados, y no se descubre ninguno",
        r.zone.status == "ambiguous" and deepEqual(r.zone.candidates, { "city:c1", "zone:z1" }) and r.zone.id == nil)
    check("un nombre de subzona de dos subzonas es 'ambiguous' y no se descubre ninguna",
        r.subzone.status == "ambiguous" and deepEqual(r.subzone.candidates, { "subzone:s1", "subzone:s2" }) and r.subzone.id == nil)
    check("tras resultados ambiguos no se ha descubierto nada ni se ha escrito nada", disc:Count() == 0 and #discovered == 0
        and next(stateData.discovery.entries) == nil)
    local ok = Service(Names("Bosque", "Claro"), { resolver = res, discovery = disc }):Check()
    check("(control) los nombres inequívocos del mismo mundo sí se descubren",
        ok.zone.id == "zone:z2" and ok.subzone.id == "subzone:s3" and disc:Count() == 2)
end

-- ===================== APIs que no entregan nombres =====================
do
    Boot()
    local mpStates = {
        { "vacío ('unavailable'/'empty')", { "unavailable", "empty" } },
        { "API ausente ('unknown'/'api_missing')", { "unknown", "api_missing" } },
        { "error de API ('unknown'/'api_error')", { "unknown", "api_error" } },
        { "valor inválido ('unknown'/'invalid_value')", { "unknown", "invalid_value" } },
    }
    for _, case in ipairs(mpStates) do
        local r = Service(FakeMapPosition(case[2], case[2])):Check()
        check("MapPosition con nombres " .. case[1] .. ": 'unavailable' con su motivo en zona y subzona, y no se descubre nada",
            r.zone.status == "unavailable" and r.zone.reason == case[2][2] and r.subzone.status == "unavailable"
                and r.subzone.reason == case[2][2] and Chronicle.Discovery:Count() == 0)
    end
    local function RealMP(zone, subzone)
        return Chronicle.MapPosition.New({ GetRealZoneText = zone, GetSubZoneText = subzone })
    end
    local r1 = Service(RealMP(function() return "" end, function() return nil end)):Check()
    check("con MapPosition real y APIs que devuelven '' y nil: nada se descubre",
        r1.zone.status == "unavailable" and r1.subzone.status == "unavailable" and Chronicle.Discovery:Count() == 0)
    local r2 = Service(RealMP(function() error("roto") end, function() return 42 end)):Check()
    check("con APIs que lanzan error o devuelven algo que no es cadena: 'unavailable' (con motivo) y nada se descubre",
        r2.zone.status == "unavailable" and r2.zone.reason == "api_error" and r2.subzone.reason == "invalid_value"
            and Chronicle.Discovery:Count() == 0)
    local r3 = Service(Chronicle.MapPosition.New({})):Check()
    check("sin APIs del cliente (api_missing) no se descubre nada y no hay errores", r3.zone.reason == "api_missing"
        and r3.subzone.reason == "api_missing" and Chronicle.Discovery:Count() == 0)
    local r4 = Service(RealMP(function() return "Dun Morogh" end, function() return "" end)):Check()
    check("subzona vacía (fuera de una subzona) pero zona conocida: se descubre la zona y la subzona queda 'unavailable'",
        r4.zone.status == "discovered" and r4.subzone.status == "unavailable" and Chronicle.Discovery:Count() == 1)
end

-- ===================== Independencia entre zona y subzona =====================
do
    Boot()
    local r = Service(Names("Zona Desconocida", "Kharanos")):Check()
    check("una zona no reconocida no impide descubrir una subzona reconocida (cada nombre se trata por separado)",
        r.zone.status == "unrecognized" and r.subzone.status == "discovered" and r.subzone.id == "subzone:kharanos")
    Boot()
    local r2 = Service(Names("Dun Morogh", "Subzona Desconocida")):Check()
    check("ni al revés", r2.zone.status == "discovered" and r2.subzone.status == "unrecognized")
end

-- ===================== Cambios de zona y subzona =====================
do
    Boot()
    local calls = Listen()
    local mp = Names("Dun Morogh", "Coldridge Valley")
    local svc = Service(mp)
    local route = {
        { "Dun Morogh", "Coldridge Valley" }, { "Dun Morogh", "Kharanos" }, { "Loch Modan", "Thelsamar" },
        { "Dun Morogh", "Kharanos" }, { "Dun Morogh", "Coldridge Valley" }, { "Ciudad de Forjaz", "El Trono" },
        { "Loch Modan", "Thelsamar" }, { "Ciudad de Forjaz", "El Trono" },
    }
    for _, step in ipairs(route) do
        mp.zone = { "available", step[1] }
        mp.subzone = { "available", step[2] }
        svc:Check()
    end
    check("cambiando de zona y subzona varias veces (y volviendo a las mismas) cada ID se descubre y se emite una sola vez",
        Chronicle.Discovery:Count() == 7 and #calls == 7 and Chronicle.Discovery:Count("zone") == 2
            and Chronicle.Discovery:Count("city") == 1 and Chronicle.Discovery:Count("subzone") == 4)
    check("y el orden de los descubrimientos es el del recorrido (primeras apariciones)",
        deepEqual(calls, { "zone:dun_morogh", "subzone:coldridge_valley", "subzone:kharanos", "zone:loch_modan",
            "subzone:thelsamar", "city:ironforge", "subzone:the_great_forge" }))
    mp.zone = { "unavailable", "empty" }
    mp.subzone = { "unavailable", "empty" }
    svc:Check()
    check("una comprobación sin nombres (p. ej. en una pantalla de carga) no deshace ni duplica nada",
        Chronicle.Discovery:Count() == 7 and #calls == 7)
end

-- ===================== Los fallos de Discovery y del Resolver no son un éxito =====================
do
    Boot()
    local function StateStub(opts)
        local s = { sets = 0 }
        function s:IsReady() return true end
        function s:IsReadOnly() return opts.readOnly == true end
        function s:Get() return nil end
        function s:Set() self.sets = self.sets + 1 return false end
        return s
    end
    local calls = Listen()
    for _, case in ipairs({ { "State en solo lectura", { readOnly = true }, "read_only" }, { "State:Set que falla", {}, "persist_failed" } }) do
        local st = StateStub(case[2])
        local disc = Chronicle.Discovery.New({ state = st, registry = Chronicle.Registry, events = Chronicle.Events })
        disc:Init()
        local r = Service(Names("Dun Morogh", "Kharanos"), { discovery = disc }):Check()
        check(case[1] .. ": la zona y la subzona salen 'failed' con el motivo de Discovery, y no hay evento",
            r.zone.status == "failed" and r.zone.reason == case[3] and r.zone.id == "zone:dun_morogh"
                and r.subzone.status == "failed" and r.subzone.reason == case[3] and #calls == 0)
    end
    local staleResolver = Chronicle.Resolver.New(Chronicle.Registry, Chronicle.Localization)
    staleResolver:Init()
    local svc = Service(Names("Dun Morogh", "Kharanos"), { resolver = staleResolver })
    staleResolver:AddAlias("esES", "zone:dun_morogh", "Alias nuevo") -- invalida el índice: Resolve devuelve not_ready
    local r = svc:Check()
    check("si el índice del Resolver no está listo: 'resolver_not_ready' en ambos y no se descubre nada",
        r.zone.status == "resolver_not_ready" and r.subzone.status == "resolver_not_ready" and Chronicle.Discovery:Count() == 0)
    local flip = { ready = true, Discover = function() error("no debería llamarse") end }
    function flip:IsReady() return self.ready end
    local svc2 = Service(Names("Dun Morogh", "Kharanos"), { discovery = flip })
    flip.ready = false
    check("si Discovery deja de estar listo, Check devuelve 'not_ready' sin intentar descubrir", svc2:Check().status == "not_ready")
    local thrower = { IsReady = function() return true end, Discover = function() error("discovery roto") end }
    local r5 = Service(Names("Dun Morogh", "Kharanos"), { discovery = thrower }):Check()
    check("si Discover lanzara error, se captura: 'failed' con 'discovery_error'",
        r5.zone.status == "failed" and r5.zone.reason == "discovery_error" and r5.subzone.reason == "discovery_error")
end

-- ===================== Cableado con los eventos del cliente (instancia por defecto) =====================
do
    local savedZone, savedSub = GetRealZoneText, GetSubZoneText
    GetRealZoneText = function() return "Dun Morogh" end
    GetSubZoneText = function() return "Kharanos" end
    Boot()
    local checks = 0
    local original = Chronicle.ZoneDiscovery.Check
    Chronicle.ZoneDiscovery.Check = function(self) checks = checks + 1 return original(self) end
    check("antes de cualquier evento del cliente no se ha descubierto nada", Chronicle.Discovery:Count() == 0)
    FireEvent("ZONE_CHANGED")
    check("un evento del cliente (ZONE_CHANGED) dispara la comprobación y descubre zona y subzona reales con las APIs del cliente",
        checks == 1 and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") and Chronicle.Discovery:IsDiscovered("subzone:kharanos")
            and ChronicleCharDB.discovery.entries["subzone:kharanos"] ~= nil)
    for _, eventName in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do
        local before = checks
        FireEvent(eventName)
        check("el evento " .. eventName .. " también dispara la comprobación", checks == before + 1)
    end
    local before = checks
    FireEvent("PLAYER_TARGET_CHANGED"); FireEvent("QUEST_DETAIL"); FireEvent("UNIT_AURA")
    check("otros eventos del cliente no la disparan", checks == before)
    check("repetir los eventos no duplica nada: siguen siendo 2 descubrimientos", Chronicle.Discovery:Count() == 2)
    GetRealZoneText = function() return "Ciudad de Forjaz" end
    GetSubZoneText = function() return "El Trono" end
    FireEvent("ZONE_CHANGED_NEW_AREA")
    check("al cambiar de zona se descubre lo nuevo (city:ironforge y su subzona) y lo anterior no se repite",
        Chronicle.Discovery:IsDiscovered("city:ironforge") and Chronicle.Discovery:IsDiscovered("subzone:the_great_forge")
            and Chronicle.Discovery:Count() == 4)
    ReportedErrors = {}
    Chronicle.ZoneDiscovery.Check = function() error("check roto") end
    local okFire = pcall(FireEvent, "ZONE_CHANGED")
    check("un error dentro de la comprobación no se propaga al cliente y se comunica", okFire == true and contains(ReportedErrors, "check roto"))
    Chronicle.ZoneDiscovery.Check = original
    GetRealZoneText = function() error("el cliente falla") end
    GetSubZoneText = nil
    local okFire2 = pcall(FireEvent, "ZONE_CHANGED")
    check("con APIs del cliente que fallan o no existen el evento no rompe nada ni descubre nada nuevo", okFire2 == true
        and Chronicle.Discovery:Count() == 4)
    GetRealZoneText, GetSubZoneText = savedZone, savedSub
end

-- ===================== Resolver y datos intactos =====================
check("no se han añadido alias, entidades ni textos: 22 alias, 53 entidades, 53 textos esES",
    Chronicle.Resolver:CountAliases() == 22 and Chronicle.Registry:Count() == 53 and #Chronicle.Localization:GetIds("esES") == 53)

-- ===================== Alcance y fronteras =====================
local function codeOf(name)
    for _, file in ipairs(ADDON_FILES) do
        if file.name == name then
            local lines = {}
            for line in file.source:gmatch("[^\n]+") do
                if not line:match("^%s*%-%-") then lines[#lines + 1] = line end
            end
            return lines
        end
    end
end
check("ZoneDiscovery no escribe en State ni en ChronicleCharDB, ni toca el Registry ni Localization",
    (function()
        for _, line in ipairs(codeOf("Services/ZoneDiscovery.lua")) do
            for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", "Chronicle.Registry", "Chronicle.Localization" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("ZoneDiscovery no usa coordenadas ni mapas: nunca pide la posición (ni mapID, ni Proximity)",
    (function()
        for _, line in ipairs(codeOf("Services/ZoneDiscovery.lua")) do
            for _, word in ipairs({ "GetPosition", "mapID", "Chronicle.Proximity", "C_Map", "GetPlayerMapPosition" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("ZoneDiscovery no usa temporizadores, sonidos ni interfaz; el único frame es el de eventos y es un 'Frame' sin Show",
    (function()
        local frames = 0
        for _, line in ipairs(codeOf("Services/ZoneDiscovery.lua")) do
            for _, word in ipairs({ "C_Timer", "OnUpdate", "PlaySound", "UIParent", "StaticPopup", "CreateTexture", "CreateFontString",
                "DEFAULT_CHAT_FRAME", ":Show(", "SetPoint", "SetSize" }) do
                if line:find(word, 1, true) then return false, word end
            end
            if line:find("createFrame, \"Frame\"", 1, true) or line:find("CreateFrame(...)", 1, true) then frames = frames + 1 end
        end
        return frames == 2 -- la llamada con "Frame" y el envoltorio del CreateFrame del cliente
    end)())
check("ZoneDiscovery solo pide el descubrimiento a Discovery (Discover) y los nombres a MapPosition",
    (function()
        local discover, names = false, false
        for _, line in ipairs(codeOf("Services/ZoneDiscovery.lua")) do
            if line:find("Discovery().Discover", 1, true) then discover = true end
            if line:find("GetZoneName", 1, true) and line:find("mp:", 1, true) then names = true end
        end
        return discover and names
    end)())
check("la API pública de ZoneDiscovery es mínima: Check, Init, IsReady (y New)",
    (function()
        local keys = {}
        for key in pairs(Chronicle.ZoneDiscovery) do keys[#keys + 1] = key end
        table.sort(keys)
        return table.concat(keys, ",") == "Check,Init,IsReady,New"
    end)())
check("Resolver y datos migrados siguen funcionando igual tras todo lo anterior (Forjaz -> city:ironforge)",
    Chronicle.Resolver:Resolve("Forjaz") == "city:ironforge")

-- ===================== Dependencias en el arranque =====================
announced = Boot(function() Chronicle.Resolver:AddAlias("esES", "city:no_existe", "Fantasma") end)
check("si el Resolver falla, ZoneDiscovery NO se intenta (depende de 'Resolver'); Proximity y Discovery no se ven afectados",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Resolver ~= nil
        and (Chronicle.Init.skipped.ZoneDiscovery or ""):find("'Resolver'", 1, true) ~= nil
        and Chronicle.Init.skipped.Proximity == nil and Chronicle.Init.skipped.Discovery == nil
        and Chronicle.ZoneDiscovery:IsReady() == false and Chronicle.Proximity:IsReady() and Chronicle.Discovery:IsReady())
check("y sin ZoneDiscovery iniciado los eventos de zona del cliente no descubren nada",
    (function()
        local saved = GetRealZoneText
        GetRealZoneText = function() return "Dun Morogh" end
        FireEvent("ZONE_CHANGED")
        GetRealZoneText = saved
        return Chronicle.Discovery:Count() == 0
    end)())
announced = Boot(function() Chronicle.ZoneDiscovery.Init = function() error("zonas roto") end end)
check("un fallo de ZoneDiscovery.Init se diagnostica e impide anunciar el arranque",
    Chronicle.Init.ready == false and announced == 0 and (Chronicle.Init.failed.ZoneDiscovery or ""):find("zonas roto", 1, true) ~= nil)
announced = Boot(function() Chronicle.ZoneDiscovery = nil end)
check("ZoneDiscovery ausente: se diagnostica como no cargado y no se anuncia el arranque",
    Chronicle.Init.ready == false and announced == 0 and (Chronicle.Init.failed.ZoneDiscovery or ""):find("no está cargado", 1, true) ~= nil)
announced = Boot(function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
check("si Discovery falla, ZoneDiscovery tampoco se intenta ('Discovery') y no se escucha ningún evento de zona",
    (Chronicle.Init.skipped.ZoneDiscovery or ""):find("'Discovery'", 1, true) ~= nil and Chronicle.ZoneDiscovery:IsReady() == false)
announced = Boot()
check("arranque normal restablecido: todo listo, nada omitido y el arranque se anuncia una vez",
    Chronicle.Init.ready == true and announced == 1 and next(Chronicle.Init.skipped) == nil and next(Chronicle.Init.failed) == nil)
