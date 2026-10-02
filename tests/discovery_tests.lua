-- Escenarios de prueba de Discovery (Fase 5): el servicio que registra qué entidades ha
-- descubierto el personaje. Se prueba con los datos reales (53 entidades) a través del arranque,
-- y con instancias propias (Discovery.New) y un State simulado para los casos límite.
-- Estas pruebas leen ChronicleCharDB directamente solo para comprobar lo que se ha guardado: el
-- código del addon no lo hace (eso lo verifica la última sección).

local EVENT = "Chronicle.Discovery.Discovered"

-- Arranca el addon completo con los datos reales. `db` es el contenido guardado de
-- ChronicleCharDB (nil = primera vez); `prepare` puede sabotear antes de ADDON_LOADED.
local function Boot(db, prepare)
    LoadAddon()
    ChronicleCharDB = db
    if prepare then prepare() end
    local announced = 0
    if Chronicle.Events then
        Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    end
    FireEvent("ADDON_LOADED", "Chronicle")
    return announced
end

-- Escucha el evento de descubrimiento; devuelve la lista de llamadas (cada una, la lista de args).
local function Listen()
    local calls = {}
    Chronicle.Events:Register(EVENT, function(...) calls[#calls + 1] = { n = select("#", ...), ... } end)
    return calls
end

-- State simulado: permite probar "no listo", "solo lectura" y fallos de Set sin tocar el real.
local function FakeState(opts)
    opts = opts or {}
    local data = opts.data or { discovery = { entries = {} } }
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
        if opts.lyingSet then return true end -- dice que guarda pero no guarda
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

-- Registry pequeño de ejemplo, para las instancias propias.
local function SmallRegistry()
    local reg = Chronicle.Registry.New(Chronicle.Schema)
    for _, e in ipairs({
        { id = "continent:alpha", type = "continent" },
        { id = "zone:z1", type = "zone", parent = "continent:alpha" },
        { id = "zone:z2", type = "zone", parent = "continent:alpha" },
        { id = "subzone:s1", type = "subzone", parent = "zone:z1" },
        { id = "npc:n1", type = "npc", located_in = "subzone:s1" },
    }) do
        assert(reg:Register(e))
    end
    return reg
end

-- Eventos simulados que cuentan las emisiones.
local function FakeEvents()
    local fake = { emitted = {} }
    function fake:Emit(name, ...) self.emitted[#self.emitted + 1] = { name = name, n = select("#", ...), ... } end
    return fake
end

-- ===================== Arranque y estado inicial =====================
local announced = Boot(nil)
local Discovery = Chronicle.Discovery

check("Discovery arranca con el addon: módulo listo, sin fallos ni omitidos, y el arranque se anuncia una vez",
    Discovery:IsReady() == true and Chronicle.Init.ready == true and announced == 1
        and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)
check("el nombre del evento público está expuesto y es el documentado",
    Discovery.EVENT_DISCOVERED == EVENT)
check("1. el servicio arranca con el estado vacío: 0 descubrimientos, lista vacía y nada guardado",
    Discovery:Count() == 0 and #Discovery:GetIds() == 0
        and deepEqual(ChronicleCharDB.discovery, { entries = {} }))
check("1b. progreso inicial: 0 descubiertas de 53, y por tipo (0 de 2 zonas, 0 de 40 subzonas, 0 de 0 lore)",
    select(1, Discovery:GetProgress()) == 0 and select(2, Discovery:GetProgress()) == 53
        and select(2, Discovery:GetProgress("zone")) == 2 and select(2, Discovery:GetProgress("subzone")) == 40
        and select(1, Discovery:GetProgress("lore")) == 0 and select(2, Discovery:GetProgress("lore")) == 0)
check("2. un ID existente inicialmente no está descubierto",
    Discovery:IsDiscovered("zone:dun_morogh") == false and Discovery:IsDiscovered("npc:grelin_whitebeard") == false)

-- ===================== Guardar a través de State:Set =====================
-- Un State espía que delega en el real: permite ver exactamente qué se escribe y cuántas veces.
local realState = Chronicle.State
local spy = { sets = {} }
function spy:IsReady() return realState:IsReady() end
function spy:IsReadOnly() return realState:IsReadOnly() end
function spy:Get(...) return realState:Get(...) end
function spy:Set(value, ...)
    self.sets[#self.sets + 1] = { value = value, path = { ... } }
    return realState:Set(value, ...)
end
local viaSpy = Chronicle.Discovery.New({ state = spy, registry = function() return Chronicle.Registry end,
    events = function() return Chronicle.Events end })
viaSpy:Init()
local calls = Listen()

local ok, info, emitted = viaSpy:Discover("zone:dun_morogh")
check("3. marcar una entidad válida: devuelve true, 'new' y que se emitió el evento",
    ok == true and info == "new" and emitted == true)
check("3b. se guarda a través de State:Set, una sola vez, en discovery.entries[id] y con una tabla",
    #spy.sets == 1 and type(spy.sets[1].value) == "table" and next(spy.sets[1].value) == nil
        and deepEqual(spy.sets[1].path, { "discovery", "entries", "zone:dun_morogh" }))
check("4. tras el guardado la entidad está descubierta (por el servicio de prueba y por el de por defecto)",
    viaSpy:IsDiscovered("zone:dun_morogh") == true and Discovery:IsDiscovered("zone:dun_morogh") == true)
check("4b. el formato persistente es discovery.entries[id] = {} y no se ha cambiado nada más del estado",
    deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = { ["zone:dun_morogh"] = {} } } }))
check("5. se emite exactamente un evento, con un solo argumento: el ID canónico",
    #calls == 1 and calls[1].n == 1 and calls[1][1] == "zone:dun_morogh")

-- ===================== Repetición: idempotencia =====================
local ok2, info2, emitted2 = viaSpy:Discover("zone:dun_morogh")
check("6. repetir el descubrimiento: true, 'already' y no se emite nada (el tercer valor es nil)",
    ok2 == true and info2 == "already" and emitted2 == nil)
check("6b. repetir no vuelve a escribir (State:Set no se llamó otra vez) ni duplica el registro ni repite el evento",
    #spy.sets == 1 and #calls == 1 and Discovery:Count() == 1
        and deepEqual(ChronicleCharDB.discovery.entries, { ["zone:dun_morogh"] = {} }))
for i = 1, 5 do viaSpy:Discover("zone:dun_morogh") end
check("6c. repetirlo muchas veces sigue sin escribir ni emitir", #spy.sets == 1 and #calls == 1)

-- ===================== Consultar no cambia nada =====================
local before = Chronicle.Utils.DeepCopy(ChronicleCharDB)
local setsBefore, callsBefore = #spy.sets, #calls
for _, id in ipairs({ "zone:dun_morogh", "zone:loch_modan", "npc:grelin_whitebeard", "zone:no_existe", "Dun Morogh", "" }) do
    viaSpy:IsDiscovered(id); Discovery:IsDiscovered(id)
end
Discovery:GetIds(); Discovery:GetIds("zone"); Discovery:Count(); Discovery:Count("npc"); Discovery:GetProgress(); Discovery:GetProgress("subzone")
check("7. consultar un ID, listar y contar no descubre nada, no escribe en el estado y no emite eventos",
    #spy.sets == setsBefore and #calls == callsBefore and deepEqual(ChronicleCharDB, before)
        and Discovery:IsDiscovered("zone:loch_modan") == false and Discovery:Count() == 1)

-- ===================== IDs desconocidos y argumentos inválidos =====================
local function untouched()
    return #spy.sets == setsBefore and #calls == callsBefore and deepEqual(ChronicleCharDB, before)
end
local okU, infoU = viaSpy:Discover("zone:no_existe")
check("8. un ID inexistente (con formato válido) se rechaza: false, 'unknown_entity', sin cambiar el estado ni emitir",
    okU == false and infoU == "unknown_entity" and untouched())
check("8b. nunca se crean entidades: sigue habiendo 53 y el ID rechazado no existe",
    Chronicle.Registry:Count() == 53 and not Chronicle.Registry:Has("zone:no_existe"))
check("8c. un nombre visible o un alias NO es un ID: 'Dun Morogh', 'Forjaz' y 'zone:Dun_Morogh' se rechazan",
    select(2, viaSpy:Discover("Dun Morogh")) == "unknown_entity" and select(2, viaSpy:Discover("Forjaz")) == "unknown_entity"
        and select(2, viaSpy:Discover("zone:Dun_Morogh")) == "unknown_entity" and viaSpy:Discover("Forjaz") == false and untouched())
check("9. argumentos de tipo incorrecto en Discover: false, 'invalid_id', sin error de Lua y sin cambios",
    (function()
        for _, bad in ipairs({ 5, true, false, {}, print }) do
            local okCall, a, b = pcall(viaSpy.Discover, viaSpy, bad)
            if not okCall or a ~= false or b ~= "invalid_id" then return false end
        end
        local a, b = viaSpy:Discover(nil)
        local c, d = viaSpy:Discover("")
        return a == false and b == "invalid_id" and c == false and d == "invalid_id"
    end)() and untouched())
check("9b. IsDiscovered con argumentos inválidos o desconocidos devuelve false, sin error",
    (function()
        for _, bad in ipairs({ 5, true, {}, "", "zone:no_existe", "no es un id" }) do
            local okCall, r = pcall(viaSpy.IsDiscovered, viaSpy, bad)
            if not okCall or r ~= false then return false end
        end
        return viaSpy:IsDiscovered(nil) == false
    end)())

-- ===================== Listas y recuentos deterministas =====================
local order = { "npc:grelin_whitebeard", "subzone:kharanos", "zone:loch_modan", "city:ironforge", "subzone:coldridge_valley", "npc:sten_stoutarm" }
for _, id in ipairs(order) do assert(Discovery:Discover(id)) end
local list = Discovery:GetIds()
check("10. GetIds devuelve los IDs ordenados, sea cual sea el orden en que se descubrieron",
    table.concat(list, ",") == table.concat({ "city:ironforge", "npc:grelin_whitebeard", "npc:sten_stoutarm",
        "subzone:coldridge_valley", "subzone:kharanos", "zone:dun_morogh", "zone:loch_modan" }, ","))
check("10b. Count coincide con la lista y las consultas repetidas dan lo mismo",
    Discovery:Count() == 7 and #list == 7 and deepEqual(list, Discovery:GetIds()) and Discovery:Count() == Discovery:Count())
list[1] = "roto"; table.insert(list, "otro")
check("10c. la lista devuelta es una copia: modificarla no altera el servicio ni el estado",
    Discovery:Count() == 7 and Discovery:GetIds()[1] == "city:ironforge" and ChronicleCharDB.discovery.entries["roto"] == nil)
check("10d. se emitió un evento por cada descubrimiento nuevo y ninguno más, en el orden en que ocurrieron",
    #calls == 7 and calls[2][1] == "npc:grelin_whitebeard" and calls[7][1] == "npc:sten_stoutarm")

-- ===================== Filtro por tipo y progreso =====================
check("11. el filtro por tipo cuenta y lista solo entidades de ese tipo",
    table.concat(Discovery:GetIds("zone"), ",") == "zone:dun_morogh,zone:loch_modan"
        and table.concat(Discovery:GetIds("subzone"), ",") == "subzone:coldridge_valley,subzone:kharanos"
        and table.concat(Discovery:GetIds("npc"), ",") == "npc:grelin_whitebeard,npc:sten_stoutarm"
        and table.concat(Discovery:GetIds("city"), ",") == "city:ironforge"
        and Discovery:Count("zone") == 2 and Discovery:Count("subzone") == 2 and Discovery:Count("npc") == 2
        and Discovery:Count("city") == 1 and Discovery:Count("continent") == 0 and Discovery:Count("lore") == 0)
check("11b. la suma por tipo coincide con el total", (function()
    local sum = 0
    for _, typeName in ipairs(Chronicle.Schema:GetTypes()) do sum = sum + Discovery:Count(typeName) end
    return sum == Discovery:Count()
end)())
check("11c. GetProgress(tipo) devuelve descubiertas y el total del Registry de ese tipo",
    select(1, Discovery:GetProgress("zone")) == 2 and select(2, Discovery:GetProgress("zone")) == 2
        and select(1, Discovery:GetProgress("subzone")) == 2 and select(2, Discovery:GetProgress("subzone")) == 40
        and select(1, Discovery:GetProgress("npc")) == 2 and select(2, Discovery:GetProgress("npc")) == 9
        and select(1, Discovery:GetProgress()) == 7 and select(2, Discovery:GetProgress()) == 53)
check("11d. un tipo desconocido, o que no es cadena, lanza error (errata), igual que el Registry",
    not pcall(Discovery.GetIds, Discovery, "faction") and not pcall(Discovery.Count, Discovery, "faction")
        and not pcall(Discovery.GetProgress, Discovery, "faction") and not pcall(Discovery.GetIds, Discovery, 5)
        and not pcall(Discovery.Count, Discovery, {}) and pcall(Discovery.Count, Discovery, nil))

-- ===================== Estado incompleto o antiguo =====================
Boot({ schemaVersion = 1 })
check("12. un guardado sin 'discovery' equivale a progreso vacío y no produce errores",
    Chronicle.Init.ready == true and Chronicle.Discovery:IsReady() and Chronicle.Discovery:Count() == 0
        and #Chronicle.Discovery:GetIds() == 0 and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") == false)
Boot({ schemaVersion = 1, discovery = {} })
check("12b. un 'discovery' sin 'entries' tampoco da errores y se puede descubrir encima",
    Chronicle.Discovery:Count() == 0 and Chronicle.Discovery:Discover("zone:dun_morogh") == true
        and Chronicle.Discovery:Count() == 1)
Boot({ schemaVersion = 1, discovery = { entries = {} } })
check("12c. 'entries' vacío es el estado inicial normal", Chronicle.Discovery:Count() == 0 and Chronicle.Init.ready == true)
Boot({ discoveredZones = { DunMorogh = true }, enabled = false })
check("12d. un guardado de versiones anteriores (sin schemaVersion) arranca sin errores, sin progreso, y no pierde sus claves",
    Chronicle.Init.ready == true and Chronicle.Discovery:Count() == 0 and ChronicleCharDB.discoveredZones.DunMorogh == true
        and ChronicleCharDB.enabled == false)
Boot({ schemaVersion = 1, discovery = { entries = {
    ["zone:dun_morogh"] = true, ["zone:loch_modan"] = "sí", ["city:ironforge"] = {}, ["zone:ya_no_existe"] = {},
    [5] = {}, ["npc:sten_stoutarm"] = false } } })
local junkBefore = Chronicle.Utils.DeepCopy(ChronicleCharDB)
check("12e. valores que no son tabla y IDs que ya no existen en el Registry se IGNORAN (no cuentan, no dan error)",
    Chronicle.Discovery:Count() == 1 and Chronicle.Discovery:GetIds()[1] == "city:ironforge"
        and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") == false and Chronicle.Discovery:IsDiscovered("zone:ya_no_existe") == false
        and Chronicle.Discovery:Count("zone") == 0 and deepEqual(ChronicleCharDB, junkBefore))
local calls12 = Listen()
check("12f. descubrir una entidad cuyo valor guardado era basura la guarda bien y emite el evento; lo ajeno no se toca",
    Chronicle.Discovery:Discover("zone:dun_morogh") == true and Chronicle.Discovery:IsDiscovered("zone:dun_morogh")
        and #calls12 == 1 and type(ChronicleCharDB.discovery.entries["zone:ya_no_existe"]) == "table"
        and ChronicleCharDB.discovery.entries["zone:loch_modan"] == "sí" and Chronicle.Discovery:Count() == 2)

-- ===================== State no listo =====================
local regNR = SmallRegistry()
local evNR = FakeEvents()
local stateNR = FakeState({ ready = false })
local notReady = Chronicle.Discovery.New({ state = stateNR, registry = regNR, events = evNR })
check("13. si State no está listo, Init lanza un error descriptivo y el servicio no queda listo",
    (function()
        local okInit, err = pcall(notReady.Init, notReady)
        return okInit == false and tostring(err):find("State no está listo", 1, true) ~= nil and notReady:IsReady() == false
    end)())
local okNR, infoNR, emitNR = notReady:Discover("zone:z1")
check("13b. sin inicializar / con State no listo: Discover devuelve false, 'not_ready', no escribe y no emite",
    okNR == false and infoNR == "not_ready" and emitNR == nil and #stateNR.sets == 0 and #evNR.emitted == 0)
check("13c. las consultas devuelven vacío en vez de fallar", notReady:IsDiscovered("zone:z1") == false
    and notReady:Count() == 0 and #notReady:GetIds() == 0 and select(1, notReady:GetProgress()) == 0 and select(2, notReady:GetProgress()) == 5)
-- un argumento inválido o una entidad desconocida se rechazan igualmente, aunque no esté listo
check("13d. un ID inválido o desconocido se rechaza con su motivo aunque el servicio no esté listo",
    select(2, notReady:Discover(nil)) == "invalid_id" and select(2, notReady:Discover("zone:no_existe")) == "unknown_entity")
LoadAddon() -- addon cargado pero SIN ADDON_LOADED: nada inicializado
ChronicleCharDB = nil
check("13e. con el addon cargado pero sin inicializar (antes de ADDON_LOADED): not_ready, y no se crea ni escribe ChronicleCharDB",
    Chronicle.Discovery:IsReady() == false and select(2, Chronicle.Discovery:Discover("zone:dun_morogh")) == "not_ready"
        and ChronicleCharDB == nil and Chronicle.Discovery:Count() == 0)
local flip = FakeState({ ready = true }); local ready = true
function flip:IsReady() return ready end
local flipping = Chronicle.Discovery.New({ state = flip, registry = regNR, events = evNR })
flipping:Init(); ready = false
check("13f. si State deja de estar listo después de inicializar, Discover devuelve not_ready y no escribe",
    select(2, flipping:Discover("zone:z1")) == "not_ready" and #flip.sets == 0)
check("Discovery.New exige una tabla de dependencias", not pcall(Chronicle.Discovery.New, nil) and not pcall(Chronicle.Discovery.New, "x"))
check("sin Registry disponible Discover devuelve not_ready y las consultas, vacío",
    (function()
        local d = Chronicle.Discovery.New({ state = FakeState(), registry = nil, events = FakeEvents() })
        return select(2, d:Discover("zone:z1")) == "not_ready" and d:Count() == 0 and d:IsDiscovered("zone:z1") == false
            and #d:GetIds() == 0 and not pcall(d.GetIds, d, 5)
    end)())
check("Init falla si no hay Registry",
    not pcall(Chronicle.Discovery.New({ state = FakeState(), registry = nil, events = FakeEvents() }).Init,
        Chronicle.Discovery.New({ state = FakeState(), registry = nil, events = FakeEvents() })))

-- ===================== State en solo lectura =====================
local roDb = { schemaVersion = 99, discovery = { entries = { ["zone:dun_morogh"] = {} } } }
Boot(roDb)
local roCalls = Listen()
local roBefore = Chronicle.Utils.DeepCopy(ChronicleCharDB)
check("14. con State en solo lectura el servicio se inicializa (se puede consultar) y lee el progreso guardado",
    Chronicle.State:IsReadOnly() == true and Chronicle.Discovery:IsReady() == true
        and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") == true and Chronicle.Discovery:Count() == 1)
local okRO, infoRO, emitRO = Chronicle.Discovery:Discover("zone:loch_modan")
check("14b. en solo lectura Discover devuelve false, 'read_only', no escribe y no emite el evento",
    okRO == false and infoRO == "read_only" and emitRO == nil and #roCalls == 0 and deepEqual(ChronicleCharDB, roBefore)
        and Chronicle.Discovery:IsDiscovered("zone:loch_modan") == false)
check("14c. en solo lectura tampoco se afirma éxito para algo ya guardado: 'read_only' (nada se persiste)",
    select(2, Chronicle.Discovery:Discover("zone:dun_morogh")) == "read_only" and #roCalls == 0)
check("14d. un guardado de versión futura SIN 'discovery' (solo lectura) se consulta como vacío, sin errores",
    (function()
        Boot({ schemaVersion = 99 })
        return Chronicle.State:IsReadOnly() and Chronicle.Discovery:Count() == 0 and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") == false
            and Chronicle.Discovery:GetIds()[1] == nil and ChronicleCharDB.discovery == nil
    end)())

-- Fallos de persistencia
local stateFail = FakeState({ failSet = true })
local evFail = FakeEvents()
local failing = Chronicle.Discovery.New({ state = stateFail, registry = SmallRegistry(), events = evFail })
failing:Init()
local okF, infoF = failing:Discover("zone:z1")
check("14e. si State:Set devuelve false: false, 'persist_failed', no se afirma éxito, no queda descubierta y no se emite",
    okF == false and infoF == "persist_failed" and failing:IsDiscovered("zone:z1") == false and #evFail.emitted == 0
        and failing:Count() == 0)
local stateLie = FakeState({ lyingSet = true })
local evLie = FakeEvents()
local lying = Chronicle.Discovery.New({ state = stateLie, registry = SmallRegistry(), events = evLie })
lying:Init()
check("14f. si State:Set dice true pero no guarda, tampoco se afirma éxito ni se emite (se comprueba lo guardado)",
    select(2, lying:Discover("zone:z1")) == "persist_failed" and #evLie.emitted == 0 and lying:IsDiscovered("zone:z1") == false)
local stateRO = FakeState({ readOnly = true })
local evRO = FakeEvents()
local roFake = Chronicle.Discovery.New({ state = stateRO, registry = SmallRegistry(), events = evRO })
roFake:Init()
check("14g. State simulado en solo lectura: read_only, sin llamar a Set ni emitir",
    select(2, roFake:Discover("zone:z1")) == "read_only" and #stateRO.sets == 0 and #evRO.emitted == 0)

-- ===================== Persistencia entre sesiones y reconstrucción del servicio =====================
Boot(nil)
for _, id in ipairs({ "zone:dun_morogh", "subzone:kharanos", "npc:sten_stoutarm" }) do assert(Chronicle.Discovery:Discover(id)) end
local saved = ChronicleCharDB
Boot(saved) -- /reload: el cliente restaura la SavedVariable antes de cargar los ficheros
local reloadCalls = Listen()
check("15. el progreso sobrevive a una recarga: mismos IDs, mismo recuento y orden",
    Chronicle.Discovery:Count() == 3 and table.concat(Chronicle.Discovery:GetIds(), ",") == "npc:sten_stoutarm,subzone:kharanos,zone:dun_morogh"
        and Chronicle.Discovery:IsDiscovered("subzone:kharanos") == true and Chronicle.Discovery:IsDiscovered("zone:loch_modan") == false)
check("15b. tras recargar, redescubrir lo guardado es 'already': no se duplica ni se emite el evento",
    select(2, Chronicle.Discovery:Discover("subzone:kharanos")) == "already" and #reloadCalls == 0 and Chronicle.Discovery:Count() == 3)
check("15c. un descubrimiento nuevo tras recargar sí se guarda y emite",
    select(2, Chronicle.Discovery:Discover("zone:loch_modan")) == "new" and #reloadCalls == 1 and Chronicle.Discovery:Count() == 4)
local rebuiltService = Chronicle.Discovery.New({ state = function() return Chronicle.State end,
    registry = function() return Chronicle.Registry end, events = function() return Chronicle.Events end })
rebuiltService:Init()
check("15d. un servicio reconstruido sobre el mismo estado ve el mismo progreso y es coherente con el original",
    rebuiltService:Count() == 4 and deepEqual(rebuiltService:GetIds(), Chronicle.Discovery:GetIds())
        and select(2, rebuiltService:Discover("zone:loch_modan")) == "already")
check("15e. el estado persistente no guarda nada más que discovery.entries[id] = {} (y schemaVersion sigue en 1)",
    deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {
        ["zone:dun_morogh"] = {}, ["subzone:kharanos"] = {}, ["npc:sten_stoutarm"] = {}, ["zone:loch_modan"] = {} } } }))

-- ===================== Datos reales: descubrir todo =====================
Boot(nil)
local allCalls = Listen()
local allIds = Chronicle.Registry:GetIds()
for i = #allIds, 1, -1 do assert(Chronicle.Discovery:Discover(allIds[i])) end -- en orden inverso a propósito
check("descubrir las 53 entidades reales (en orden inverso): 53 eventos, uno por cada, y el recuento total",
    #allCalls == 53 and Chronicle.Discovery:Count() == 53 and deepEqual(Chronicle.Discovery:GetIds(), allIds))
check("por tipo: 1 continente, 2 zonas, 1 ciudad, 40 subzonas, 9 NPC y 0 lore; el progreso por tipo llega al 100%",
    Chronicle.Discovery:Count("continent") == 1 and Chronicle.Discovery:Count("zone") == 2 and Chronicle.Discovery:Count("city") == 1
        and Chronicle.Discovery:Count("subzone") == 40 and Chronicle.Discovery:Count("npc") == 9 and Chronicle.Discovery:Count("lore") == 0
        and select(1, Chronicle.Discovery:GetProgress()) == 53 and select(2, Chronicle.Discovery:GetProgress()) == 53)
check("el Registry no cambia por descubrir (sigue siendo el catálogo): 53 entidades y valida", Chronicle.Registry:Count() == 53
    and Chronicle.Registry:Validate().ok == true)

-- ===================== Events ausente o con fallos =====================
Boot(nil)
local realEvents = Chronicle.Events
Chronicle.Events = nil
ReportedErrors = {}
local okE, infoE, emitE = Chronicle.Discovery:Discover("zone:dun_morogh")
check("16. sin bus de eventos el descubrimiento ya guardado se mantiene, devuelve true, 'new' y emitido = false (no finge)",
    okE == true and infoE == "new" and emitE == false and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") == true
        and type(ChronicleCharDB.discovery.entries["zone:dun_morogh"]) == "table")
check("16b. la ausencia del bus se comunica por el mecanismo de errores", contains(ReportedErrors, "bus de eventos")
    and contains(ReportedErrors, "zone:dun_morogh") and contains(ReportedErrors, "no se ha emitido"))
Chronicle.Events = realEvents
check("16c. al volver el bus, lo ya descubierto sigue siendo 'already' (no se emite retroactivamente)",
    select(2, Chronicle.Discovery:Discover("zone:dun_morogh")) == "already")
local savedEmit = Chronicle.Events.Emit
Chronicle.Events.Emit = function() error("emit roto") end
ReportedErrors = {}
local okEm, infoEm, emitEm = Chronicle.Discovery:Discover("zone:loch_modan")
check("16d. si Emit lanza un error: se guarda, true, 'new', emitido = false, y el fallo se comunica sin propagarse",
    okEm == true and infoEm == "new" and emitEm == false and Chronicle.Discovery:IsDiscovered("zone:loch_modan")
        and contains(ReportedErrors, "falló la emisión") and contains(ReportedErrors, "emit roto"))
Chronicle.Events.Emit = savedEmit
Chronicle.Events.Emit = nil
ReportedErrors = {}
check("16e. si Emit no existe se trata como bus no disponible: guarda, emitido = false y lo comunica",
    select(3, Chronicle.Discovery:Discover("city:ironforge")) == false and Chronicle.Discovery:IsDiscovered("city:ironforge")
        and contains(ReportedErrors, "bus de eventos"))
Chronicle.Events.Emit = savedEmit
local goodListener = {}
Chronicle.Events:Register(EVENT, function() error("listener roto") end)
Chronicle.Events:Register(EVENT, function(id) goodListener[#goodListener + 1] = id end)
ReportedErrors = {}
local okL, infoL, emitL = Chronicle.Discovery:Discover("zone:loch_modan")
check("16f. (control) el error de un listener lo aísla Events: no afecta al resultado; los listeners posteriores sí se ejecutan",
    okL == true and infoL == "already")
local okL2, infoL2, emitL2 = Chronicle.Discovery:Discover("subzone:kharanos")
check("16g. un listener roto no impide el guardado ni que el siguiente listener reciba el ID, y Discover sigue devolviendo emitido = true",
    okL2 == true and infoL2 == "new" and emitL2 == true and goodListener[1] == "subzone:kharanos"
        and contains(ReportedErrors, "listener roto"))
check("16h. con el addon arrancado sin bus de eventos, Discovery se inicializa igualmente (la política del bus es de Core/Init)",
    (function()
        Boot(nil, function() Chronicle.Events = nil end)
        return Chronicle.Init.ready == false and Chronicle.Init.failed.Events ~= nil and Chronicle.Discovery:IsReady() == true
            and next(Chronicle.Init.skipped) == nil
    end)())

-- ===================== Diagnóstico durante el arranque =====================
announced = Boot(nil, function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
check("17. un fallo de Discovery.Init se diagnostica: Init.failed.Discovery, Init.ready false, sin anunciar el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Discovery ~= nil
        and Chronicle.Init.failed.Discovery:find("discovery roto", 1, true) ~= nil and contains(ReportedErrors, "Discovery")
        and Chronicle.Discovery:IsReady() == false)
announced = Boot(nil, function() Chronicle.Discovery = nil end)
check("17b. Discovery ausente: se diagnostica como no cargado y no se anuncia el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Discovery:find("no está cargado", 1, true) ~= nil)
announced = Boot(nil, function() Chronicle.State.Init = function() error("estado roto") end end)
check("17c. si State falla, Discovery NO se intenta: queda en Init.skipped (no en failed), Init.ready es false y no se anuncia",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.State ~= nil and Chronicle.Init.failed.Discovery == nil
        and Chronicle.Init.skipped.Discovery ~= nil and Chronicle.Init.skipped.Discovery:find("'State'", 1, true) ~= nil
        and Chronicle.Discovery:IsReady() == false)
check("17d. con State fallido Discover devuelve not_ready y no escribe nada", select(2, Chronicle.Discovery:Discover("zone:dun_morogh")) == "not_ready")
announced = Boot(nil, function() Chronicle.Registry:Register({ id = "zone:sin_padre", type = "zone" }) end)
check("17e. si el Registry falla su validación, Discovery NO se intenta: omitido por depender de 'Registry'",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Registry ~= nil and Chronicle.Init.failed.Discovery == nil
        and Chronicle.Init.skipped.Discovery:find("'Registry'", 1, true) ~= nil and Chronicle.Discovery:IsReady() == false)
announced = Boot(nil, function() Chronicle.Resolver:AddAlias("esES", "city:no_existe", "Fantasma") end)
check("17f. un módulo independiente que falla (Resolver) no impide inicializar Discovery ni se marca como omitido",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Resolver ~= nil
        and Chronicle.Discovery:IsReady() == true and next(Chronicle.Init.skipped) == nil)
announced = Boot(nil)
check("17g. con todo correcto: Init.ready, nada omitido ni fallido y el arranque se anuncia una vez",
    Chronicle.Init.ready == true and announced == 1 and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)
check("17h. Discovery sigue la política de módulos de Core/Init: no se intenta antes que sus dependencias (State y Registry)",
    (function()
        local pos = {}
        for i, file in ipairs(ADDON_FILES) do pos[file.name] = i end
        return pos["Core/State.lua"] < pos["Services/Discovery.lua"] and pos["Data/Registry.lua"] < pos["Services/Discovery.lua"]
            and pos["Services/Discovery.lua"] < pos["Core/Init.lua"] and pos["Core/Init.lua"] == #ADDON_FILES
    end)())
-- Init ya anuncia el arranque una sola vez aunque se llame de nuevo
Chronicle.Init:Run()
check("Init:Run repetido no vuelve a inicializar Discovery ni a anunciar el arranque", Chronicle.Init.ready == true and announced == 1)

-- ===================== Contrato de la API y alcance =====================
local keys = {}
for key in pairs(Chronicle.Discovery) do keys[#keys + 1] = key end
table.sort(keys)
check("la API pública es pequeña y no expone tablas internas mutables",
    table.concat(keys, ",") == "Count,Discover,EVENT_DISCOVERED,GetIds,GetProgress,Init,IsDiscovered,IsReady,New"
        and type(Chronicle.Discovery.EVENT_DISCOVERED) == "string", table.concat(keys, ","))
check("Services/Discovery.lua no referencia ChronicleCharDB en su código (solo usa State:Get/State:Set)",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name == "Services/Discovery.lua" then
                local usesGet, usesSet = false, false
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") then
                        if line:find("ChronicleCharDB", 1, true) then return false end
                        if line:find("state:Get(", 1, true) then usesGet = true end
                        if line:find("state:Set(", 1, true) then usesSet = true end
                    end
                end
                return usesGet and usesSet
            end
        end
        return false
    end)())
check("Discovery no usa APIs del juego de detección (zonas, GUID, mapas, eventos del cliente, ventanas): solo es un servicio",
    (function()
        local forbidden = { "GetRealZoneText", "GetSubZoneText", "UnitGUID", "C_Map", "RegisterEvent", "CreateFrame",
            "PLAYER_TARGET_CHANGED", "ZONE_CHANGED", "GetPlayerMapPosition", "OnUpdate", "PlaySound" }
        for _, file in ipairs(ADDON_FILES) do
            if file.name == "Services/Discovery.lua" then
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") then
                        for _, word in ipairs(forbidden) do
                            if line:find(word, 1, true) then return false, word end
                        end
                    end
                end
            end
        end
        return true
    end)())
check("Discovery no depende de Localization ni del Resolver (trabaja solo con IDs canónicos)",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name == "Services/Discovery.lua" then
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") and (line:find("Chronicle.Localization", 1, true) or line:find("Chronicle.Resolver", 1, true)) then
                        return false
                    end
                end
            end
        end
        return true
    end)())
check("Discovery no añade entidades ni textos: tras todo lo anterior el Registry y Localization siguen intactos",
    Chronicle.Registry:Count() == 53 and #Chronicle.Localization:GetIds("esES") == 53 and Chronicle.Resolver:Resolve("Forjaz") == "city:ironforge")
