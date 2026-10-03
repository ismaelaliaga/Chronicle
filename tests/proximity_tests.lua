-- Escenarios de prueba de Proximity (Fase 6). El motor se prueba con una posición simulada, una lista de
-- objetivos inyectada y un Discovery real sobre un State simulado. NO hay objetivos espaciales reales:
-- los datos del addon original no están verificados ni migrados. Lo que se prueba es el motor, no que un
-- NPC concreto se descubra en el juego.

-- ---------- Ayudas ----------
local EVENT = "Chronicle.Discovery.Discovered"

local function FakeState(opts)
    opts = opts or {}
    local data = { discovery = { entries = {} } }
    local fake = { sets = {}, data = data }
    function fake:IsReady() return opts.ready ~= false end
    function fake:IsReadOnly() return opts.readOnly == true end
    function fake:Get(...)
        local node = data
        for i = 1, select("#", ...) do
            if type(node) ~= "table" then return nil end
            node = node[(select(i, ...))]
        end
        return node
    end
    function fake:Set(value, ...)
        self.sets[#self.sets + 1] = { value = value, path = { ... } }
        if opts.failSet then return false end
        if opts.lyingSet then return true end
        local n = select("#", ...)
        local node = data
        for i = 1, n - 1 do
            local key = select(i, ...)
            if type(node[key]) ~= "table" then node[key] = {} end
            node = node[key]
        end
        node[(select(n, ...))] = value
        return true
    end
    return fake
end

LoadAddon()
local function Registry()
    local reg = Chronicle.Registry.New(Chronicle.Schema)
    for _, e in ipairs({
        { id = "continent:alpha", type = "continent" },
        { id = "zone:z1", type = "zone", parent = "continent:alpha" },
        { id = "subzone:s1", type = "subzone", parent = "zone:z1" },
        { id = "npc:n1", type = "npc", located_in = "subzone:s1" },
        { id = "npc:n2", type = "npc", located_in = "subzone:s1" },
        { id = "npc:n3", type = "npc", located_in = "subzone:s1" },
    }) do assert(reg:Register(e)) end
    return reg
end

-- Mundo: Discovery real (con State simulado y eventos simulados), posición simulada y proveedor simulado.
local function World(opts)
    opts = opts or {}
    local w = { state = FakeState(opts.state), events = { emitted = {} }, positionCalls = 0, providerCalls = 0, discoverCalls = {} }
    function w.events:Emit(name, ...) self.emitted[#self.emitted + 1] = { name = name, ... } end
    w.discovery = Chronicle.Discovery.New({ state = w.state, registry = Registry(), events = w.events })
    if opts.initDiscovery ~= false then w.discovery:Init() end
    -- Discovery espía: cuenta las llamadas a Discover y delega.
    w.spy = {}
    function w.spy:IsReady() return w.discovery:IsReady() end
    function w.spy:IsDiscovered(id) return w.discovery:IsDiscovered(id) end
    function w.spy:Discover(id)
        w.discoverCalls[#w.discoverCalls + 1] = id
        if opts.discoverThrows then error("discovery roto") end
        return w.discovery:Discover(id)
    end
    w.positionStatus, w.positionValue = "available", { mapID = 1, x = 0.5, y = 0.5 }
    w.mapPosition = { GetPosition = function()
        w.positionCalls = w.positionCalls + 1
        return w.positionStatus, w.positionValue
    end }
    w.targets = opts.targets or {}
    w.proximity = Chronicle.Proximity.New({
        mapPosition = w.mapPosition,
        discovery = opts.rawDiscovery and w.discovery or w.spy,
        targets = function()
            w.providerCalls = w.providerCalls + 1
            if opts.providerError then error("proveedor roto") end
            return w.targets
        end,
    })
    if opts.initProximity ~= false then w.proximity:Init() end
    return w
end

local function Target(over)
    local t = { id = "npc:n1", mapID = 1, x = 0.5, y = 0.5, radius = 0.1, verified = true }
    for k, v in pairs(over or {}) do
        if v == "NIL" then t[k] = nil else t[k] = v end
    end
    return t
end

-- Evaluate envuelto: si el código bajo prueba lanzara una excepción, se convierte en un resultado "THROWS" para que
-- salte una aserción clara en vez de interrumpir todo el arnés.
local function Eval(proximity)
    local ok, result = pcall(proximity.Evaluate, proximity)
    if ok then return result end
    return { status = "THROWS", reason = tostring(result), discovered = {}, rejected = {}, targets = 0, invalid = 0,
        alreadyDiscovered = 0, otherMap = 0, outside = 0, inside = 0 }
end

-- ===================== Dependencias ausentes o no listas =====================
check("Proximity.New exige una tabla de dependencias", not pcall(Chronicle.Proximity.New, nil) and not pcall(Chronicle.Proximity.New, "x"))
check("Init falla si falta MapPosition",
    (function()
        local p = Chronicle.Proximity.New({ discovery = World().spy })
        local ok, err = pcall(p.Init, p)
        return ok == false and tostring(err):find("MapPosition no está disponible", 1, true) ~= nil and p:IsReady() == false
    end)())
check("Init falla si falta Discovery o no está listo, y el servicio no queda listo",
    (function()
        local mp = { GetPosition = function() return "available", { mapID = 1, x = 0.5, y = 0.5 } end }
        local p1 = Chronicle.Proximity.New({ mapPosition = mp })
        local p2 = Chronicle.Proximity.New({ mapPosition = mp, discovery = World({ initDiscovery = false, initProximity = false }).spy })
        local ok1, e1 = pcall(p1.Init, p1)
        local ok2, e2 = pcall(p2.Init, p2)
        return ok1 == false and ok2 == false and tostring(e1):find("Discovery no está listo", 1, true) ~= nil
            and tostring(e2):find("Discovery no está listo", 1, true) ~= nil and not p1:IsReady() and not p2:IsReady()
    end)())
do
    local w = World({ initProximity = false, targets = { Target() } })
    local r = Eval(w.proximity)
    check("antes de Init, Evaluate devuelve 'not_ready' y no consulta nada (ni posición, ni proveedor, ni Discovery)",
        r.status == "not_ready" and w.positionCalls == 0 and w.providerCalls == 0 and #w.discoverCalls == 0)
end
do
    local w = World({ targets = { Target() } })
    -- Discovery que deja de estar listo después de inicializar Proximity
    local ready = true
    local fakeDisc = { IsReady = function() return ready end, IsDiscovered = function() return false end,
        Discover = function() error("no debería llamarse") end }
    local p = Chronicle.Proximity.New({ mapPosition = w.mapPosition, discovery = fakeDisc, targets = function() return { Target() } end })
    p:Init(); ready = false
    check("si Discovery deja de estar listo después de Init, Evaluate devuelve 'not_ready' sin intentar descubrir",
        Eval(p).status == "not_ready")
    local q = Chronicle.Proximity.New({ mapPosition = nil, discovery = fakeDisc })
    check("sin MapPosition Evaluate devuelve 'not_ready'", Eval(q).status == "not_ready")
end

-- ===================== Proveedor de objetivos =====================
do
    local w = World({ targets = {} })
    local r = Eval(w.proximity)
    check("una lista vacía de objetivos: 'no_targets' y no se consulta la posición",
        r.status == "no_targets" and w.positionCalls == 0 and #w.discoverCalls == 0 and r.targets == 0)
    local noProvider = Chronicle.Proximity.New({ mapPosition = w.mapPosition, discovery = w.spy })
    noProvider:Init()
    check("sin proveedor (como la instancia por defecto) 'no_targets' y nada se descubre",
        Eval(noProvider).status == "no_targets" and #w.discoverCalls == 0)
    check("SetTargetProvider valida su argumento: una función se acepta, nil la quita, otra cosa se rechaza",
        noProvider:SetTargetProvider(function() return { Target() } end) == true and Eval(noProvider).status == "evaluated"
            and noProvider:SetTargetProvider("x") == false and noProvider:SetTargetProvider({}) == false
            and noProvider:SetTargetProvider(nil) == true and Eval(noProvider).status == "no_targets")
    local wErr = World({ providerError = true })
    local rErr = Eval(wErr.proximity)
    check("un proveedor que lanza error: 'provider_error' con el motivo, sin propagar ni descubrir nada",
        rErr.status == "provider_error" and rErr.reason:find("proveedor roto", 1, true) ~= nil and #wErr.discoverCalls == 0
            and wErr.positionCalls == 0)
    local wBad = World()
    wBad.proximity:SetTargetProvider(function() return "no soy una lista" end)
    check("un proveedor que no devuelve una tabla: 'provider_error'", Eval(wBad.proximity).status == "provider_error")
    wBad.proximity:SetTargetProvider(function() return nil end)
    check("un proveedor que devuelve nil: 'provider_error'", Eval(wBad.proximity).status == "provider_error")
end

-- ===================== Posición no disponible o desconocida =====================
for _, case in ipairs({
    { "unavailable", "no_map", "position_unavailable" }, { "unavailable", "incomplete", "position_unavailable" },
    { "unknown", "api_missing", "position_unknown" }, { "unknown", "invalid_coordinates", "position_unknown" },
    { "basura", "x", "position_unknown" },
}) do
    local w = World({ targets = { Target({ x = 0.5, y = 0.5 }) } })
    w.positionStatus, w.positionValue = case[1], case[2]
    local r = Eval(w.proximity)
    check("posición '" .. case[1] .. "/" .. case[2] .. "' -> '" .. case[3] .. "' con el motivo; no se descubre nada",
        r.status == case[3] and r.reason == case[2] and #w.discoverCalls == 0 and #r.discovered == 0 and w.state.sets[1] == nil)
end
do
    local w = World({ targets = { Target() } })
    w.positionStatus, w.positionValue = "available", nil
    local r1 = Eval(w.proximity)
    w.positionValue = "no es una tabla"
    local r2 = Eval(w.proximity)
    check("estado 'available' pero con un valor que no es una posición: 'position_unknown', no se descubre nada",
        r1.status == "position_unknown" and r2.status == "position_unknown" and #w.discoverCalls == 0)
end

-- ===================== Distancia y radio =====================
-- Valores exactos en binario: objetivo (0.125, 0.0625), jugador a (0.375, 0.5) de distancia: 0.625.
local EPS = 2 ^ -20
local function atDistance(radius, opts)
    local w = World(opts or {})
    w.targets = { Target({ x = 0.125, y = 0.0625, radius = radius }) }
    w.positionValue = { mapID = 1, x = 0.5, y = 0.5625 }
    return w, Eval(w.proximity)
end
do
    local w, r = atDistance(0.625)
    check("distancia EXACTAMENTE igual al radio: dentro, descubre",
        r.status == "evaluated" and r.inside == 1 and r.outside == 0 and r.discovered[1] == "npc:n1" and w.discovery:IsDiscovered("npc:n1"))
    local w2, r2 = atDistance(0.625 - EPS)
    check("distancia apenas mayor que el radio: fuera, no descubre ni llama a Discover",
        r2.inside == 0 and r2.outside == 1 and #r2.discovered == 0 and #w2.discoverCalls == 0 and not w2.discovery:IsDiscovered("npc:n1"))
    local w3, r3 = atDistance(0.625 + EPS)
    check("distancia apenas menor que el radio: dentro, descubre", r3.inside == 1 and r3.discovered[1] == "npc:n1")
    local w4, r4 = atDistance(0.0625)
    check("claramente fuera: no descubre", r4.outside == 1 and #r4.discovered == 0)
    local w5 = World({ targets = { Target({ x = 0.5, y = 0.5, radius = 0.001 }) } })
    check("misma posición que el objetivo (distancia 0): dentro", Eval(w5.proximity).inside == 1)
    local w6 = World({ targets = { Target({ x = 0.5, y = 0.5, radius = 0.1 }) } })
    w6.positionValue = { mapID = 1, x = 0.5 - 0.1, y = 0.5 }
    check("en un eje, a exactamente el radio: dentro (en ambos sentidos)", Eval(w6.proximity).inside == 1
        and (function() w6.positionValue = { mapID = 1, x = 0.5, y = 0.5 + 0.1 }; return true end)())
    local w7 = World({ targets = { Target({ x = 0.5, y = 0.5, radius = 0.1 }) } })
    w7.positionValue = { mapID = 1, x = 0.5 + 0.08, y = 0.5 + 0.08 }
    check("la distancia es euclídea (no por ejes): (0.08, 0.08) está a 0.113, fuera de un radio de 0.1",
        Eval(w7.proximity).outside == 1)
    local w8 = World({ targets = { Target({ x = 0.5, y = 0.5, radius = 1 }) } })
    w8.positionValue = { mapID = 1, x = 0.99, y = 0.99 }
    check("un radio de 1 (el máximo admitido) es válido", Eval(w8.proximity).invalid == 0)
end

-- ===================== Radios inválidos =====================
for _, case in ipairs({
    { "cero", 0 }, { "negativo", -0.1 }, { "nil", "NIL" }, { "cadena numérica", "0.1" }, { "NaN", 0 / 0 },
    { "infinito", 1 / 0 }, { "infinito negativo", -1 / 0 }, { "mayor que 1", 1.0001 }, { "booleano", true }, { "tabla", {} },
}) do
    local w = World({ targets = { Target({ radius = case[2] }) } })
    local r = Eval(w.proximity)
    check("radio " .. case[1] .. ": se rechaza ('invalid_radius') aunque el jugador esté encima, y no se descubre",
        r.invalid == 1 and (r.rejected[1] or {}).reason == "invalid_radius" and (r.rejected[1] or {}).id == "npc:n1"
            and #w.discoverCalls == 0 and #r.discovered == 0 and w.state.sets[1] == nil)
end

-- ===================== Objetivos mal configurados =====================
for _, case in ipairs({
    { "no es una tabla (nil entre otros)", false, "invalid_target" }, { "es un número", 5, "invalid_target" },
    { "es una cadena", "npc:n1", "invalid_target" },
}) do
    local w = World()
    w.targets = { case[2], Target({ id = "npc:n2" }) }
    local r = Eval(w.proximity)
    check("objetivo que " .. case[1] .. ": se rechaza y NO impide evaluar el siguiente",
        (r.rejected[1] or {}).reason == case[3] and r.discovered[1] == "npc:n2" and r.invalid == 1)
end
for _, case in ipairs({
    { "sin id", { id = "NIL" }, "invalid_id" }, { "con id vacío", { id = "" }, "invalid_id" },
    { "con id numérico", { id = 5 }, "invalid_id" },
    { "sin 'verified'", { verified = "NIL" }, "unverified" }, { "con verified = false", { verified = false }, "unverified" },
    { "con verified = 'true' (cadena)", { verified = "true" }, "unverified" }, { "con verified = 1", { verified = 1 }, "unverified" },
    { "sin mapID", { mapID = "NIL" }, "invalid_map" }, { "con mapID 0", { mapID = 0 }, "invalid_map" },
    { "con mapID negativo", { mapID = -1 }, "invalid_map" }, { "con mapID decimal", { mapID = 1.5 }, "invalid_map" },
    { "con mapID cadena", { mapID = "1" }, "invalid_map" }, { "con mapID NaN", { mapID = 0 / 0 }, "invalid_map" },
    { "con x fuera de rango", { x = 1.5 }, "invalid_coordinates" }, { "con y negativa", { y = -0.2 }, "invalid_coordinates" },
    { "con x nil", { x = "NIL" }, "invalid_coordinates" }, { "con y cadena", { y = "0.5" }, "invalid_coordinates" },
    { "con x NaN", { x = 0 / 0 }, "invalid_coordinates" },
}) do
    local w = World({ targets = { Target(case[2]) } })
    local r = Eval(w.proximity)
    check("objetivo " .. case[1] .. ": 'rejected' con '" .. case[3] .. "', sin descubrir ni llamar a Discover",
        r.rejected[1] and (r.rejected[1] or {}).reason == case[3] and #w.discoverCalls == 0 and #r.discovered == 0 and r.invalid == 1)
end
do
    local w = World({ targets = { Target({ id = "npc:desconocido" }) } })
    local r = Eval(w.proximity)
    check("objetivo con un ID desconocido (dentro del radio): lo rechaza Discovery ('unknown_entity'), no se presenta como descubierto y no se guarda nada",
        r.inside == 1 and (r.rejected[1] or {}).id == "npc:desconocido" and (r.rejected[1] or {}).reason == "unknown_entity"
            and #r.discovered == 0 and w.state.sets[1] == nil and #w.events.emitted == 0 and w.discovery:Count() == 0)
    local wFar = World({ targets = { Target({ id = "npc:desconocido", x = 0.9, y = 0.9 }) } })
    local rFar = Eval(wFar.proximity)
    check("... y uno desconocido pero lejano ni se intenta descubrir (no se llama a Discover)",
        rFar.outside == 1 and #wFar.discoverCalls == 0 and #rFar.rejected == 0)
end

-- ===================== Posiciones y objetivos en (0, 0) =====================
-- (0, 0) no es un valor especial (ver MapPosition): un objetivo válido en (0, 0) se acepta y un jugador en (0, 0) se evalúa.
local function ZeroWorld(targetOver, playerX, playerY, playerMap, opts)
    local w = World(opts or {})
    w.targets = { Target(targetOver) }
    w.positionValue = { mapID = playerMap or 1, x = playerX, y = playerY }
    return w, Eval(w.proximity)
end
do
    local w, r = ZeroWorld({ x = 0, y = 0, radius = 0.1 }, 0.5, 0.5)
    check("4. un objetivo válido situado en (0, 0) se acepta (no se rechaza por sus coordenadas) y se evalúa",
        r.status == "evaluated" and r.invalid == 0 and #r.rejected == 0 and r.targets == 1 and r.outside == 1)
    local w2, r2 = ZeroWorld({ x = 0, y = 0, radius = 0.1 }, 0.05, 0.05)
    check("4b. y si el jugador está dentro de su radio, lo descubre (distancia 0,0707 < 0,1)",
        r2.invalid == 0 and r2.inside == 1 and r2.discovered[1] == "npc:n1" and w2.discovery:IsDiscovered("npc:n1"))
    local w3, r3 = ZeroWorld({ id = "npc:n1", x = 0.3, y = 0.4, radius = 0.6 }, 0, 0)
    check("5. el jugador en (0, 0) se evalúa correctamente: a distancia 0,5 de un objetivo con radio 0,6 -> dentro y lo descubre",
        r3.status == "evaluated" and r3.inside == 1 and r3.discovered[1] == "npc:n1")
    local w4, r4 = ZeroWorld({ x = 0.3, y = 0.4, radius = 0.4 }, 0, 0)
    check("5b. el jugador en (0, 0) a más distancia que el radio: fuera, sin descubrir ni llamar a Discover",
        r4.status == "evaluated" and r4.outside == 1 and r4.inside == 0 and #r4.discovered == 0 and #w4.discoverCalls == 0)
    local w5, r5 = ZeroWorld({ x = 0, y = 0, radius = 0.1 }, 0, 0)
    check("6. jugador y objetivo en (0, 0), mismo mapID y radio válido: se descubre a través de Discovery:Discover",
        r5.discovered[1] == "npc:n1" and #w5.discoverCalls == 1 and w5.discoverCalls[1] == "npc:n1" and w5.discovery:IsDiscovered("npc:n1"))
    check("6b. se guarda por State:Set una vez (ruta de Discovery) y se emite un único evento",
        #w5.state.sets == 1 and deepEqual(w5.state.sets[1].path, { "discovery", "entries", "npc:n1" })
            and #w5.events.emitted == 1 and w5.events.emitted[1][1] == "npc:n1")
    local w6, r6 = ZeroWorld({ mapID = 2, x = 0, y = 0, radius = 1 }, 0, 0, 1)
    check("7. jugador y objetivo en (0, 0) pero con DISTINTO mapID: no se comparan como el mismo mapa (otherMap), ni siquiera con radio 1",
        r6.otherMap == 1 and r6.inside == 0 and r6.outside == 0 and #w6.discoverCalls == 0 and #r6.discovered == 0)
    local w7, r7 = ZeroWorld({ mapID = 7, x = 0, y = 0, radius = 0.5 }, 0, 0, 7)
    check("7b. con el mismo mapID (7) sí se comparan", r7.inside == 1 and r7.otherMap == 0 and r7.discovered[1] == "npc:n1")
    -- Exactamente en el radio, medido desde (0, 0): objetivo a (0,375; 0,5) -> distancia exacta 0,625
    local wE, rE = ZeroWorld({ x = 0.375, y = 0.5, radius = 0.625 }, 0, 0)
    check("8. exactamente en el radio sigue contando como dentro (también con el jugador en (0, 0))", rE.inside == 1 and rE.discovered[1] == "npc:n1")
    local wF, rF = ZeroWorld({ x = 0.375, y = 0.5, radius = 0.625 - 2 ^ -20 }, 0, 0)
    check("8b. apenas por fuera del radio sigue siendo fuera", rF.outside == 1 and rF.inside == 0 and #rF.discovered == 0)
    local wG, rG = ZeroWorld({ x = 0, y = 0, radius = 0.001 }, 0, 0)
    check("8c. distancia 0 con un radio diminuto es dentro", rG.inside == 1 and rG.discovered[1] == "npc:n1")
end
-- Un objetivo en (0, 0) sigue sujeto a TODAS las demás reglas
for _, case in ipairs({
    { "no verificado (sin verified)", { verified = "NIL" }, "unverified" }, { "con verified = false", { verified = false }, "unverified" },
    { "con radio 0", { radius = 0 }, "invalid_radius" }, { "con radio negativo", { radius = -0.1 }, "invalid_radius" },
    { "con radio nil", { radius = "NIL" }, "invalid_radius" }, { "con radio NaN", { radius = 0 / 0 }, "invalid_radius" },
    { "con radio mayor que 1", { radius = 2 }, "invalid_radius" },
    { "sin mapID", { mapID = "NIL" }, "invalid_map" }, { "con mapID 0", { mapID = 0 }, "invalid_map" },
    { "sin id", { id = "NIL" }, "invalid_id" },
    { "con la otra coordenada fuera de rango", { y = 1.5 }, "invalid_coordinates" },
    { "con la otra coordenada negativa", { x = -0.1 }, "invalid_coordinates" },
    { "con una coordenada nil", { y = "NIL" }, "invalid_coordinates" },
    { "con una coordenada NaN", { x = 0 / 0 }, "invalid_coordinates" },
}) do
    local over = { x = 0, y = 0, radius = 0.1 }
    for k, v in pairs(case[2]) do over[k] = v end
    local w, r = ZeroWorld(over, 0, 0)
    check("9. un objetivo en (0, 0) " .. case[1] .. ": se rechaza ('" .. case[3] .. "') aunque el jugador esté encima, y no se descubre",
        (r.rejected[1] or {}).reason == case[3] and r.invalid == 1 and #w.discoverCalls == 0 and #r.discovered == 0 and w.state.sets[1] == nil)
end
do
    local w = World({ targets = { Target({ x = 0, y = 0, radius = 0.1 }) } })
    w.positionValue = { mapID = 1, x = 0, y = 0 }
    local r1 = Eval(w.proximity)
    local r2 = Eval(w.proximity)
    local r3 = Eval(w.proximity)
    check("10. en (0, 0) el descubrimiento es idempotente: la 2.ª y 3.ª evaluación dan 'alreadyDiscovered', sin Discover, sin escribir y sin evento",
        r1.discovered[1] == "npc:n1" and #r2.discovered == 0 and r2.alreadyDiscovered == 1 and #r3.discovered == 0
            and #w.discoverCalls == 1 and #w.state.sets == 1 and #w.events.emitted == 1 and r2.inside == 0)
    local stale = { IsReady = function() return true end, IsDiscovered = function() return false end,
        Discover = function() return true, "already" end }
    local mp = { GetPosition = function() return "available", { mapID = 1, x = 0, y = 0 } end }
    local p = Chronicle.Proximity.New({ mapPosition = mp, discovery = stale,
        targets = function() return { Target({ x = 0, y = 0, radius = 0.1 }) } end })
    p:Init()
    local rs = Eval(p)
    check("10b. un 'already' de Discovery (en (0, 0)) no se cuenta como descubrimiento nuevo",
        #rs.discovered == 0 and rs.alreadyDiscovered == 1 and rs.inside == 1 and #rs.rejected == 0)
    local wf = World({ state = { failSet = true }, targets = { Target({ x = 0, y = 0, radius = 0.1 }) } })
    wf.positionValue = { mapID = 1, x = 0, y = 0 }
    local rf = Eval(wf.proximity)
    check("10c. si Discovery no puede guardar, en (0, 0) tampoco se presenta como descubierto: rechazo 'persist_failed'",
        (rf.rejected[1] or {}).reason == "persist_failed" and #rf.discovered == 0 and #wf.events.emitted == 0)
end

-- De extremo a extremo con el MapPosition REAL y una API simulada
do
    local function Real(apiOver)
        local api = { C_Map = {
            GetBestMapForUnit = function() return 5 end,
            GetPlayerMapPosition = function() return { GetXY = function() return 0, 0 end } end,
        } }
        for k, v in pairs(apiOver or {}) do api[k] = v end
        return Chronicle.MapPosition.New(api)
    end
    local function Run(mp, targetOver)
        local w = World({ targets = { Target(targetOver) } })
        local p = Chronicle.Proximity.New({ mapPosition = mp, discovery = w.spy, targets = function() return w.targets end })
        p:Init()
        return w, Eval(p)
    end
    local w, r = Run(Real(), { mapID = 5, x = 0, y = 0, radius = 0.01 })
    check("11. de extremo a extremo: un MapPosition real cuya API devuelve (0, 0) en el mapa 5 da una posición válida y Proximity descubre el objetivo en (0, 0)",
        r.status == "evaluated" and r.discovered[1] == "npc:n1" and w.discovery:IsDiscovered("npc:n1"))
    local wB, rB = Run(Real(), { mapID = 6, x = 0, y = 0, radius = 1 })
    check("11b. ... pero un objetivo de otro mapa (6) en (0, 0) no se compara", rB.otherMap == 1 and #rB.discovered == 0)
    local nilPos = Chronicle.MapPosition.New({ C_Map = { GetBestMapForUnit = function() return 5 end,
        GetPlayerMapPosition = function() return { GetXY = function() return nil, nil end } end } })
    local wN, rN = Run(nilPos, { mapID = 5, x = 0, y = 0, radius = 1 })
    check("11c. si la API NO da coordenadas (nil) no se inventa un (0, 0): 'position_unavailable' y nada se descubre, aunque el objetivo esté en (0, 0) con radio 1",
        rN.status == "position_unavailable" and rN.reason == "incomplete" and #rN.discovered == 0 and #wN.discoverCalls == 0)
    local wM, rM = Run(Chronicle.MapPosition.New({}), { mapID = 5, x = 0, y = 0, radius = 1 })
    check("11d. sin API de mapas no se inventa una posición: 'position_unknown' ('api_missing') y nada se descubre",
        rM.status == "position_unknown" and rM.reason == "api_missing" and #rM.discovered == 0 and #wM.discoverCalls == 0)
    local errMp = Chronicle.MapPosition.New({ C_Map = { GetBestMapForUnit = function() error("roto") end,
        GetPlayerMapPosition = function() return nil end } })
    local wE, rE = Run(errMp, { mapID = 5, x = 0, y = 0, radius = 1 })
    check("11e. una API que lanza error no genera posición: 'position_unknown' ('api_error') y nada se descubre",
        rE.status == "position_unknown" and rE.reason == "api_error" and #rE.discovered == 0 and #wE.discoverCalls == 0)
    local outMp = Chronicle.MapPosition.New({ C_Map = { GetBestMapForUnit = function() return 5 end,
        GetPlayerMapPosition = function() return { GetXY = function() return 1.5, 0 end } end } })
    local wO, rO = Run(outMp, { mapID = 5, x = 0, y = 0, radius = 1 })
    check("11f. coordenadas fuera de rango no generan posición: 'position_unknown' ('invalid_coordinates')",
        rO.status == "position_unknown" and rO.reason == "invalid_coordinates" and #rO.discovered == 0)
end

-- ===================== Mapas incompatibles =====================
do
    local w = World({ targets = { Target({ mapID = 2, x = 0.5, y = 0.5, radius = 0.5 }) } })
    w.positionValue = { mapID = 1, x = 0.5, y = 0.5 }
    local r = Eval(w.proximity)
    check("un objetivo de otro mapa NO se compara aunque las coordenadas coincidan: no se descubre y se cuenta en 'otherMap'",
        r.otherMap == 1 and r.inside == 0 and r.outside == 0 and #w.discoverCalls == 0 and #r.discovered == 0)
    local w2 = World({ targets = { Target({ id = "npc:n1", mapID = 1 }), Target({ id = "npc:n2", mapID = 2 }) } })
    local r2 = Eval(w2.proximity)
    check("con dos objetivos en las mismas coordenadas de mapas distintos, solo se activa el del mapa del jugador",
        r2.discovered[1] == "npc:n1" and #r2.discovered == 1 and r2.otherMap == 1)
    w2.positionValue = { mapID = 2, x = 0.5, y = 0.5 }
    local r3 = Eval(w2.proximity)
    check("al cambiar el jugador de mapa, se activa el del otro mapa (sin conversión entre mapas)",
        r3.discovered[1] == "npc:n2" and r3.otherMap == 0 and r3.alreadyDiscovered == 1)
end

-- ===================== Descubrimiento nuevo y su persistencia =====================
do
    local w = World({ targets = { Target() } })
    local r = Eval(w.proximity)
    check("un descubrimiento nuevo se guarda: 'discovered', State:Set llamado una vez con la ruta de Discovery y el ID queda descubierto",
        r.status == "evaluated" and r.discovered[1] == "npc:n1" and #r.rejected == 0 and #w.state.sets == 1
            and deepEqual(w.state.sets[1].path, { "discovery", "entries", "npc:n1" }) and w.discovery:IsDiscovered("npc:n1"))
    check("se emite exactamente un evento de Discovery, con el ID",
        #w.events.emitted == 1 and w.events.emitted[1].name == EVENT and w.events.emitted[1][1] == "npc:n1")
    check("Proximity solo habló con Discovery: una llamada a IsDiscovered/Discover por objetivo, nunca con State",
        #w.discoverCalls == 1 and w.discoverCalls[1] == "npc:n1")
end

-- ===================== Idempotencia =====================
do
    local w = World({ targets = { Target() } })
    Eval(w.proximity)
    local r2 = Eval(w.proximity)
    local r3 = Eval(w.proximity)
    check("un objetivo ya descubierto no vuelve a descubrirse: 'alreadyDiscovered', sin Discover, sin escribir y sin evento",
        #r2.discovered == 0 and r2.alreadyDiscovered == 1 and #r3.discovered == 0 and #w.discoverCalls == 1
            and #w.state.sets == 1 and #w.events.emitted == 1 and w.discovery:Count() == 1)
    check("tampoco se calcula la distancia de lo ya descubierto (no cuenta como dentro ni fuera)", r2.inside == 0 and r2.outside == 0)
    local w2 = World({ targets = { Target() } })
    w2.discovery:Discover("npc:n1") -- descubierto por otra vía antes de evaluar
    local r4 = Eval(w2.proximity)
    check("algo descubierto por otra vía (p. ej. por zona) tampoco se vuelve a descubrir",
        r4.alreadyDiscovered == 1 and #w2.discoverCalls == 0 and #w2.events.emitted == 1)
end

-- ===================== Fallos de Discovery: nunca se presentan como éxito =====================
do
    local w = World({ state = { failSet = true }, targets = { Target() } })
    local r = Eval(w.proximity)
    check("fallo de persistencia (State:Set devuelve false): 'rejected persist_failed', no se cuenta como descubierto y no hay evento",
        (r.rejected[1] or {}).id == "npc:n1" and (r.rejected[1] or {}).reason == "persist_failed" and #r.discovered == 0
            and #w.events.emitted == 0 and not w.discovery:IsDiscovered("npc:n1"))
    local w2 = World({ state = { lyingSet = true }, targets = { Target() } })
    local r2 = Eval(w2.proximity)
    check("un State:Set que dice guardar sin guardar tampoco cuenta como descubrimiento",
        (r2.rejected[1] or {}).reason == "persist_failed" and #r2.discovered == 0 and #w2.events.emitted == 0)
    local w3 = World({ state = { readOnly = true }, targets = { Target() } })
    local r3 = Eval(w3.proximity)
    check("State en solo lectura: 'rejected read_only', sin descubrir, sin escribir y sin evento",
        (r3.rejected[1] or {}).reason == "read_only" and #r3.discovered == 0 and w3.state.sets[1] == nil and #w3.events.emitted == 0)
    check("los fallos se repiten en cada evaluación (no se da nada por descubierto) y no rompen nada",
        (Eval(w3.proximity).rejected[1] or {}).reason == "read_only" and w3.discovery:Count() == 0)
    local w4 = World({ discoverThrows = true, targets = { Target(), Target({ id = "npc:n2", x = 0.5, y = 0.5 }) } })
    local r4 = Eval(w4.proximity)
    check("si Discover lanzara un error se captura: 'discovery_error', sin propagar y se sigue con el resto",
        (r4.rejected[1] or {}).reason == "discovery_error" and (r4.rejected[2] or {}).reason == "discovery_error" and #r4.discovered == 0)
    local stateFlip = FakeState()
    local ready = true
    function stateFlip:IsReady() return ready end
    local evFlip = { Emit = function() end }
    local discFlip = Chronicle.Discovery.New({ state = stateFlip, registry = Registry(), events = evFlip })
    discFlip:Init()
    local mp = { GetPosition = function() return "available", { mapID = 1, x = 0.5, y = 0.5 } end }
    local pFlip = Chronicle.Proximity.New({ mapPosition = mp, discovery = discFlip, targets = function() return { Target() } end })
    pFlip:Init(); ready = false
    local rFlip = Eval(pFlip)
    check("si State deja de estar listo, Discovery no descubre ('not_ready') y Proximity tampoco lo da por descubierto",
        rFlip.status == "evaluated" and (rFlip.rejected[1] or {}).reason == "not_ready" and #rFlip.discovered == 0 and #stateFlip.sets == 0)
end

-- Un objetivo que Discovery ya tenía descubierto aunque IsDiscovered dijera lo contrario (carrera): no es un
-- descubrimiento nuevo y no debe contarse como tal.
do
    local mp = { GetPosition = function() return "available", { mapID = 1, x = 0.5, y = 0.5 } end }
    local stale = { IsReady = function() return true end, IsDiscovered = function() return false end,
        Discover = function() return true, "already" end }
    local p = Chronicle.Proximity.New({ mapPosition = mp, discovery = stale, targets = function() return { Target() } end })
    p:Init()
    local r = Eval(p)
    check("si Discover responde 'already', no se cuenta como descubrimiento nuevo (sino como ya descubierto)",
        #r.discovered == 0 and r.alreadyDiscovered == 1 and #r.rejected == 0 and r.inside == 1)
    local odd = { IsReady = function() return true end, IsDiscovered = function() return false end,
        Discover = function() return true, "algo raro" end }
    local q = Chronicle.Proximity.New({ mapPosition = mp, discovery = odd, targets = function() return { Target() } end })
    q:Init()
    local rq = Eval(q)
    check("una respuesta de Discover que no es ni 'new' ni 'already' ni un fallo conocido no se presenta como descubrimiento",
        #rq.discovered == 0 and (rq.rejected[1] or {}).id == "npc:n1")
end

-- ===================== Varios objetivos =====================
do
    local w = World({ targets = {
        Target({ id = "npc:n3", x = 0.5, y = 0.5 }), Target({ id = "npc:n1", x = 0.55, y = 0.5 }),
        Target({ id = "npc:n2", x = 0.9, y = 0.9 }), Target({ id = "npc:malo", radius = 0 }), Target({ id = "npc:n2", mapID = 9 }),
    } })
    local r = Eval(w.proximity)
    check("varios objetivos a la vez: se descubren los cercanos (en orden de ID), se cuentan los lejanos, otros mapas e inválidos",
        deepEqual(r.discovered, { "npc:n1", "npc:n3" }) and r.targets == 5 and r.inside == 2 and r.outside == 1
            and r.otherMap == 1 and r.invalid == 1 and #r.rejected == 1)
    check("cada evaluación devuelve una tabla nueva (el resultado anterior no se altera)",
        (function()
            local again = Eval(w.proximity)
            r.discovered[1] = "roto"
            return again ~= r and again.discovered[1] == nil
        end)())
    local list = { Target({ id = "npc:n1", x = 0.5, y = 0.5 }) }
    local before = Chronicle.Utils.DeepCopy(list)
    local w2 = World({ targets = list })
    Eval(w2.proximity)
    check("Proximity no modifica la lista de objetivos que le da el proveedor", deepEqual(list, before))
    check("cada Evaluate consulta la posición una vez y al proveedor una vez (no escanea nada más)",
        (function() local wp = World({ targets = { Target(), Target({ id = "npc:n2" }), Target({ id = "npc:n3" }) } })
            Eval(wp.proximity)
            return wp.positionCalls == 1 and wp.providerCalls == 1 end)())
end

-- ===================== Estado de los datos espaciales y producción =====================
local announced = 0
LoadAddon()
ChronicleCharDB = nil
Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
FireEvent("ADDON_LOADED", "Chronicle")
check("arranque completo: Proximity listo, sin fallos ni omitidos, y el arranque se anuncia una vez",
    Chronicle.Proximity:IsReady() == true and Chronicle.Init.ready == true and announced == 1
        and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)
check("la instancia por defecto no tiene objetivos verificados: Evaluate devuelve 'no_targets' y NO descubre ningún NPC",
    Eval(Chronicle.Proximity).status == "no_targets" and Chronicle.Discovery:Count("npc") == 0 and Chronicle.Discovery:Count() == 0)
check("los datos migrados no tienen coordenadas, radios ni mapID (nada espacial entró en el Registry ni en los textos)",
    (function()
        for _, e in ipairs(Chronicle.Registry:GetAll()) do
            for _, field in ipairs({ "x", "y", "radius", "mapID", "coords", "position" }) do
                if e[field] ~= nil then return false end
            end
        end
        return true
    end)())
check("el Schema no admite campos espaciales: x, y y radius en un NPC son advertencia de campo desconocido",
    contains(Chronicle.Schema:Validate({ id = "npc:x", type = "npc", x = 0.4, y = 0.6, radius = 0.03 }).warnings, "campo desconocido"))
check("la API pública de Proximity es mínima: Evaluate, Init, IsReady, SetTargetProvider (y New)",
    (function()
        local keys = {}
        for key in pairs(Chronicle.Proximity) do keys[#keys + 1] = key end
        table.sort(keys)
        return table.concat(keys, ",") == "Evaluate,Init,IsReady,New,SetTargetProvider"
    end)())

-- ===================== Dependencias en el arranque =====================
local function Boot(prepare)
    LoadAddon(); ChronicleCharDB = nil
    if prepare then prepare() end
    local n = 0
    if Chronicle.Events then Chronicle.Events:Register("Chronicle.Initialized", function() n = n + 1 end) end
    FireEvent("ADDON_LOADED", "Chronicle")
    return n
end
announced = Boot(function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
check("si Discovery falla, Proximity NO se intenta: queda en Init.skipped por depender de 'Discovery' y no se anuncia el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Discovery ~= nil and Chronicle.Init.failed.Proximity == nil
        and Chronicle.Init.skipped.Proximity ~= nil and (Chronicle.Init.skipped.Proximity or ""):find("'Discovery'", 1, true) ~= nil
        and Chronicle.Proximity:IsReady() == false and Eval(Chronicle.Proximity).status == "not_ready")
announced = Boot(function() Chronicle.MapPosition = nil end)
check("si MapPosition no está cargado se diagnostica, y Proximity y ZoneDiscovery no se intentan",
    Chronicle.Init.ready == false and announced == 0 and (Chronicle.Init.failed.MapPosition or ""):find("no está cargado", 1, true) ~= nil
        and (Chronicle.Init.skipped.Proximity or ""):find("'MapPosition'", 1, true) ~= nil and Chronicle.Init.skipped.ZoneDiscovery ~= nil)
announced = Boot(function() Chronicle.State.Init = function() error("estado roto") end end)
check("si State falla, Discovery, Proximity y ZoneDiscovery quedan omitidos (en cadena) y solo State figura como fallo",
    Chronicle.Init.ready == false and next(Chronicle.Init.failed) == "State" and next(Chronicle.Init.failed, "State") == nil
        and Chronicle.Init.skipped.Discovery ~= nil and Chronicle.Init.skipped.Proximity ~= nil and Chronicle.Init.skipped.ZoneDiscovery ~= nil)
announced = Boot(function() Chronicle.Proximity.Init = function() error("proximity roto") end end)
check("un fallo de Proximity.Init se diagnostica, impide anunciar el arranque y no afecta a Discovery ni a ZoneDiscovery",
    Chronicle.Init.ready == false and announced == 0 and (Chronicle.Init.failed.Proximity or ""):find("proximity roto", 1, true) ~= nil
        and Chronicle.Discovery:IsReady() and Chronicle.ZoneDiscovery:IsReady() and next(Chronicle.Init.skipped) == nil)
check("Proximity.Init, igual que Discovery, se inicializa después de sus dependencias (orden de carga y de módulos)",
    (function()
        local pos = {}
        for i, f in ipairs(ADDON_FILES) do pos[f.name] = i end
        return pos["Services/Discovery.lua"] < pos["Services/MapPosition.lua"] and pos["Services/MapPosition.lua"] < pos["Services/Proximity.lua"]
            and pos["Services/Proximity.lua"] < pos["Services/ZoneDiscovery.lua"] and pos["Services/ZoneDiscovery.lua"] < pos["Core/Init.lua"]
    end)())

-- ===================== Alcance =====================
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
check("Proximity no escribe en State ni en ChronicleCharDB, ni toca Localization, Resolver o Registry",
    (function()
        for _, line in ipairs(codeOf("Services/Proximity.lua")) do
            for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", "Chronicle.Localization", "Chronicle.Resolver", "Chronicle.Registry" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("Proximity no crea frames, temporizadores, sonidos ni interfaz, ni usa eventos del cliente, ni busca NPC en el mundo",
    (function()
        for _, line in ipairs(codeOf("Services/Proximity.lua")) do
            for _, word in ipairs({ "CreateFrame", "C_Timer", "OnUpdate", "PlaySound", "UIParent", "RegisterEvent", "SetScript",
                "StaticPopup", "CreateTexture", "CreateFontString", "DEFAULT_CHAT_FRAME", ":Show(", "UnitGUID", "UnitExists",
                "UnitPosition", "GetPlayerMapPosition", "C_Map" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("Proximity no usa npcID ni displayID para calcular nada",
    (function()
        for _, line in ipairs(codeOf("Services/Proximity.lua")) do
            if line:find("npcID", 1, true) or line:find("displayID", 1, true) then return false end
        end
        return true
    end)())
check("Proximity obtiene la posición solo a través de MapPosition (no repite la lógica de coordenadas)",
    (function()
        local usesGetPosition = false
        for _, line in ipairs(codeOf("Services/Proximity.lua")) do
            if line:find("mp:GetPosition", 1, true) then usesGetPosition = true end
        end
        return usesGetPosition
    end)())
