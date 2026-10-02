-- Escenarios de prueba del Registry (Fase 2) y de su integración con el arranque del Core.
-- Usan entidades de ejemplo con IDs ilustrativos: no son datos del addon (Fase 3).

-- Estas pruebas comprueban el Registry con entidades de ejemplo propias, así que cargan el
-- addon SIN los ficheros de datos reales (Fases 3 y 4: Data/Entities y Localization/esES): el Registry por defecto parte vacío. Las
-- pruebas con los datos reales y su arranque están en data_tests.lua.
local NO_DATA = { "^Data/Entities/", "^Localization/esES/" }

LoadAddon(NO_DATA)
local Schema = Chronicle.Schema

local function copy(t) return Chronicle.Utils.DeepCopy(t) end
local function with(base, changes)
    local e = copy(base)
    for k, v in pairs(changes) do e[k] = v end
    return e
end

local continent = { id = "continent:eastern_kingdoms", type = "continent" }
local zoneDM = { id = "zone:dun_morogh", type = "zone", parent = "continent:eastern_kingdoms" }
local zoneLM = { id = "zone:loch_modan", type = "zone", parent = "continent:eastern_kingdoms",
    related_to = { "zone:dun_morogh" } }
local city = { id = "city:ironforge", type = "city", parent = "continent:eastern_kingdoms", located_in = "zone:dun_morogh" }
local subColdridge = { id = "subzone:coldridge_valley", type = "subzone", parent = "zone:dun_morogh" }
local subKharanos = { id = "subzone:kharanos", type = "subzone", parent = "zone:dun_morogh" }
local subCommons = { id = "subzone:the_commons", type = "subzone", parent = "city:ironforge" }
local npcGrelin = { id = "npc:grelin_whitebeard", type = "npc", located_in = "subzone:coldridge_valley",
    npcID = 786, displayID = 1354, related_to = { "npc:senir_whitebeard" } }
local npcSenir = { id = "npc:senir_whitebeard", type = "npc", located_in = "subzone:kharanos" }
local loreFrostmane = { id = "lore:the_frostmane_trolls", type = "lore", located_in = "zone:dun_morogh",
    textKey = "lore.frostmane.body" }

-- Carga el conjunto completo en un Registry nuevo (en un orden deliberadamente "al revés":
-- hijos antes que padres, para comprobar que el orden de carga no importa).
local function FullRegistry()
    local reg = Chronicle.Registry.New(Schema)
    for _, e in ipairs({ npcGrelin, npcSenir, loreFrostmane, subCommons, subKharanos, subColdridge,
        city, zoneLM, zoneDM, continent }) do
        assert(reg:Register(e))
    end
    return reg
end

-- ===================== Registry vacío =====================
local empty = Chronicle.Registry.New(Schema)
check("un Registry vacío no tiene entidades", empty:Count() == 0 and empty:Count("zone") == 0)
check("un Registry vacío devuelve listas vacías", #empty:GetIds() == 0 and #empty:GetIds("npc") == 0
    and #empty:GetAll() == 0 and #empty:GetAll("zone") == 0)
check("un Registry vacío no tiene ningún ID ni devuelve entidades",
    empty:Has("zone:dun_morogh") == false and empty:Get("zone:dun_morogh") == nil)
check("un Registry vacío no tiene relaciones derivadas",
    #empty:GetContained("zone:dun_morogh") == 0 and #empty:GetRelated("zone:dun_morogh") == 0)
check("un Registry vacío supera la validación global",
    empty:Validate().ok == true and #empty:Validate().errors == 0 and #empty:GetRejected() == 0)
check("el Registry por defecto del addon arranca vacío", Chronicle.Registry:Count() == 0)
check("Registry.New exige un esquema", not pcall(Chronicle.Registry.New, nil) and not pcall(Chronicle.Registry.New, {}))

-- ===================== Registro y consulta por ID =====================
local reg = Chronicle.Registry.New(Schema)
local ok, report = reg:Register(zoneDM)
check("Register devuelve true y un informe sin errores para una entidad válida",
    ok == true and report.ok == true and #report.errors == 0)
check("Has indica si un ID está registrado", reg:Has("zone:dun_morogh") == true and reg:Has("zone:loch_modan") == false)
check("Has con valores que no son cadenas devuelve false", reg:Has(nil) == false and reg:Has(5) == false and reg:Has({}) == false)
check("Get devuelve la entidad registrada", deepEqual(reg:Get("zone:dun_morogh"), zoneDM))
check("Get de un ID no registrado (o que no es cadena) devuelve nil",
    reg:Get("zone:nope") == nil and reg:Get(nil) == nil and reg:Get(5) == nil)
check("Count refleja las entidades registradas", reg:Count() == 1 and reg:Count("zone") == 1 and reg:Count("npc") == 0)
check("Count y GetIds con un tipo desconocido lanzan error (errata del llamante)",
    not pcall(reg.Count, reg, "faction") and not pcall(reg.GetIds, reg, "faction") and not pcall(reg.GetAll, reg, "faction"))

-- ===================== Rechazo de entidades inválidas =====================
local reg2 = Chronicle.Registry.New(Schema)
local badOk, badReport = reg2:Register({ id = "zone:dun_morogh", type = "zone" })
check("Register rechaza una entidad estructuralmente inválida y explica por qué",
    badOk == false and badReport.ok == false and contains(badReport.errors, "parent: es obligatorio"))
check("lo rechazado no queda registrado", reg2:Count() == 0 and reg2:Has("zone:dun_morogh") == false)
check("lo rechazado queda anotado en GetRejected con su ID y sus errores",
    #reg2:GetRejected() == 1 and reg2:GetRejected()[1].id == "zone:dun_morogh"
        and contains(reg2:GetRejected()[1].errors, "parent"))
check("Register no lanza error con basura (nil, cadenas, tablas vacías)",
    pcall(reg2.Register, reg2, nil) and pcall(reg2.Register, reg2, "x") and pcall(reg2.Register, reg2, {}))
check("la basura se rechaza y se anota (sin ID cuando no lo tiene)",
    reg2:Count() == 0 and #reg2:GetRejected() == 4 and reg2:GetRejected()[2].id == nil)
local warnOk, warnReport = reg2:Register(with(zoneDM, { colour = "azul" }))
check("una entidad con solo advertencias se registra y devuelve las advertencias",
    warnOk == true and #warnReport.warnings == 1 and reg2:Has("zone:dun_morogh"))

-- ===================== IDs duplicados =====================
local regDup = Chronicle.Registry.New(Schema)
regDup:Register(with(zoneDM, { nameKey = "original" }))
local dupOk, dupReport = regDup:Register(with(zoneDM, { nameKey = "intruso" }))
check("un ID duplicado se rechaza con un error que lo dice", dupOk == false and contains(dupReport.errors, "ID duplicado"))
check("el duplicado NO sobrescribe la entidad original", regDup:Get("zone:dun_morogh").nameKey == "original"
    and regDup:Count() == 1)
check("el duplicado queda anotado en GetRejected", #regDup:GetRejected() == 1 and contains(regDup:GetRejected()[1].errors, "duplicado"))
check("también se rechaza un duplicado idéntico (nunca se sobrescribe en silencio)",
    regDup:Register(with(zoneDM, { nameKey = "original" })) == false)
check("un duplicado de ID con otro tipo declarado se rechaza igualmente",
    regDup:Register({ id = "zone:dun_morogh", type = "city" }) == false and regDup:Get("zone:dun_morogh").type == "zone")

-- ===================== Consultas por tipo y listados deterministas =====================
local full = FullRegistry()
check("GetIds() devuelve todos los IDs ordenados, aunque se registraran en otro orden",
    table.concat(full:GetIds(), ",") == table.concat({
        "city:ironforge", "continent:eastern_kingdoms", "lore:the_frostmane_trolls",
        "npc:grelin_whitebeard", "npc:senir_whitebeard", "subzone:coldridge_valley",
        "subzone:kharanos", "subzone:the_commons", "zone:dun_morogh", "zone:loch_modan" }, ","))
check("GetIds(tipo) devuelve solo los de ese tipo, ordenados",
    table.concat(full:GetIds("subzone"), ",") == "subzone:coldridge_valley,subzone:kharanos,subzone:the_commons"
        and table.concat(full:GetIds("zone"), ",") == "zone:dun_morogh,zone:loch_modan"
        and table.concat(full:GetIds("npc"), ",") == "npc:grelin_whitebeard,npc:senir_whitebeard")
check("hay entidades de los seis tipos en el conjunto de prueba",
    full:Count("continent") == 1 and full:Count("zone") == 2 and full:Count("city") == 1
        and full:Count("subzone") == 3 and full:Count("npc") == 2 and full:Count("lore") == 1 and full:Count() == 10)
check("GetIds es estable: dos llamadas dan el mismo resultado",
    deepEqual(full:GetIds(), full:GetIds()) and deepEqual(full:GetIds("zone"), full:GetIds("zone")))
local all = full:GetAll("zone")
check("GetAll(tipo) devuelve las entidades completas, ordenadas por ID",
    #all == 2 and all[1].id == "zone:dun_morogh" and all[2].id == "zone:loch_modan"
        and deepEqual(all[2], zoneLM))
check("GetAll() sin tipo devuelve todas las entidades", #full:GetAll() == 10)
check("GetIds de un tipo sin entidades devuelve una lista vacía",
    #Chronicle.Registry.New(Schema):GetIds("lore") == 0 and #regDup:GetIds("npc") == 0)
check("el índice por tipo se actualiza al registrar más entidades después de consultar",
    (function()
        local r = Chronicle.Registry.New(Schema)
        r:Register(zoneDM)
        local n1 = #r:GetIds("zone")
        r:Register(zoneLM)
        return n1 == 1 and #r:GetIds("zone") == 2 and #r:GetIds() == 2
    end)())

-- ===================== Aislamiento de las tablas internas =====================
local iso = Chronicle.Registry.New(Schema)
local original = copy(npcGrelin)
iso:Register(original)
original.displayID = 999
original.related_to[1] = "npc:cambiado"
check("Register guarda una copia: cambiar la tabla original después no altera el Registry",
    iso:Get("npc:grelin_whitebeard").displayID == 1354 and iso:Get("npc:grelin_whitebeard").related_to[1] == "npc:senir_whitebeard")
local got = iso:Get("npc:grelin_whitebeard")
got.displayID = 1
got.related_to[1] = "npc:roto"
got.extra = true
check("modificar lo devuelto por Get no altera el Registry",
    iso:Get("npc:grelin_whitebeard").displayID == 1354 and iso:Get("npc:grelin_whitebeard").extra == nil
        and iso:Get("npc:grelin_whitebeard").related_to[1] == "npc:senir_whitebeard")
local list = iso:GetIds()
list[1] = "roto"
table.insert(list, "otro")
check("modificar lo devuelto por GetIds no altera el Registry", #iso:GetIds() == 1 and iso:GetIds()[1] == "npc:grelin_whitebeard")
iso:GetAll()[1].displayID = 5
check("modificar lo devuelto por GetAll no altera el Registry", iso:Get("npc:grelin_whitebeard").displayID == 1354)
local rejectedBefore = #regDup:GetRejected()
local rejectedCopy = regDup:GetRejected()
rejectedCopy[1].errors[1] = "roto"
table.remove(rejectedCopy, 1)
check("modificar lo devuelto por GetRejected no altera el Registry", #regDup:GetRejected() == rejectedBefore
    and contains(regDup:GetRejected()[1].errors, "duplicado"))
local internalKeys = {}
for key in pairs(full) do internalKeys[#internalKeys + 1] = key end
table.sort(internalKeys)
check("el objeto Registry solo expone su API pública (ningún campo con datos internos)",
    table.concat(internalKeys, ",") == "Count,Get,GetAll,GetContained,GetIds,GetRejected,GetRelated,Has,Init,IsValidated,Register,Validate",
    table.concat(internalKeys, ","))
check("Registry:Register no modifica la entidad recibida", (function()
    local e = { id = "zone:dun_morogh", type = "zone", parent = "continent:eastern_kingdoms", colour = "x" }
    local before = copy(e)
    Chronicle.Registry.New(Schema):Register(e)
    return deepEqual(e, before)
end)())

-- ===================== Relaciones derivadas =====================
check("GetContained devuelve lo que cuelga por parent o está por located_in, ordenado",
    table.concat(full:GetContained("zone:dun_morogh"), ",")
        == "city:ironforge,lore:the_frostmane_trolls,subzone:coldridge_valley,subzone:kharanos")
check("GetContained de una ciudad devuelve sus subzonas",
    table.concat(full:GetContained("city:ironforge"), ",") == "subzone:the_commons")
check("GetContained de un continente devuelve sus zonas y ciudades",
    table.concat(full:GetContained("continent:eastern_kingdoms"), ",") == "city:ironforge,zone:dun_morogh,zone:loch_modan")
check("GetContained de una subzona devuelve sus NPC",
    table.concat(full:GetContained("subzone:coldridge_valley"), ",") == "npc:grelin_whitebeard")
check("GetContained de algo sin contenido (o desconocido) es una lista vacía",
    #full:GetContained("npc:grelin_whitebeard") == 0 and #full:GetContained("zone:nope") == 0 and #full:GetContained(nil) == 0)
check("la relación contains no se guarda en las entidades (se deriva)",
    full:Get("zone:dun_morogh").contains == nil)
check("GetRelated ve related_to en los dos sentidos sin duplicarlo",
    table.concat(full:GetRelated("zone:loch_modan"), ",") == "zone:dun_morogh"
        and table.concat(full:GetRelated("zone:dun_morogh"), ",") == "zone:loch_modan"
        and table.concat(full:GetRelated("npc:senir_whitebeard"), ",") == "npc:grelin_whitebeard"
        and table.concat(full:GetRelated("npc:grelin_whitebeard"), ",") == "npc:senir_whitebeard")
check("GetRelated de algo sin relaciones es una lista vacía", #full:GetRelated("city:ironforge") == 0 and #full:GetRelated(nil) == 0)

-- ===================== Validación global =====================
local good = full:Validate()
check("el conjunto completo y coherente supera la validación global (relaciones válidas entre entidades)",
    good.ok == true and #good.errors == 0)
check("el orden de carga no afecta a la validez: se registró al revés y valida",
    good.ok == true and full:Count() == 10)

-- referencias a entidades inexistentes (se registran bien individualmente)
local dangling = Chronicle.Registry.New(Schema)
check("registrar una entidad con referencias a IDs aún no registrados es válido (no se exige el orden)",
    dangling:Register(subColdridge) == true)
dangling:Register(with(npcGrelin, { related_to = { "npc:fantasma", "lore:otro" } }))
dangling:Register(npcSenir)
local dReport = dangling:Validate()
check("la validación global detecta un parent inexistente",
    dReport.ok == false and contains(dReport.errors, "entidad 'subzone:coldridge_valley': parent: 'zone:dun_morogh' no está registrada"))
check("la validación global detecta un located_in inexistente",
    contains(dReport.errors, "entidad 'npc:senir_whitebeard': located_in: 'subzone:kharanos' no está registrada"))
check("la validación global detecta related_to inexistentes indicando la posición",
    contains(dReport.errors, "related_to[1]: 'npc:fantasma' no está registrada")
        and contains(dReport.errors, "related_to[2]: 'lore:otro' no está registrada"))
check("la validación global informa de todos los problemas, no solo del primero", #dReport.errors == 4)
dangling:Register(zoneDM)
dangling:Register(continent)
local fixed = dangling:Validate()
check("al registrar lo que faltaba, los errores de referencia resueltos desaparecen",
    contains(fixed.errors, "parent: 'zone:dun_morogh' no está registrada") == false
        and contains(fixed.errors, "'continent:eastern_kingdoms' no está registrada") == false
        and #fixed.errors == 3)
check("la validación global es determinista (mismos mensajes, mismo orden)",
    deepEqual(dangling:Validate(), dangling:Validate()))
check("Validate no modifica el Registry",
    (function() local n = dangling:Count(); dangling:Validate(); return dangling:Count() == n end)())
local wReg = Chronicle.Registry.New(Schema)
wReg:Register(with(continent, { colour = "x" }))
check("Validate recoge como advertencias las anotadas al registrar", #wReg:Validate().warnings == 1 and wReg:Validate().ok)

-- ===================== Ciclos en la jerarquía =====================
-- Con los tipos por defecto un ciclo no se puede construir (el tipo del padre siempre es
-- de un nivel superior), así que se prueba con un esquema propio que admite región -> región.
local nested = Schema.New({
    region = { parent = { types = { "region" } } },
    root = {},
})
local function RegionRegistry(parents)
    local r = Chronicle.Registry.New(nested)
    for id, parent in pairs(parents) do
        assert(r:Register({ id = id, type = "region", parent = parent }))
    end
    return r
end

local cyc = RegionRegistry({ ["region:a"] = "region:b", ["region:b"] = "region:c", ["region:c"] = "region:a" }):Validate()
check("detecta un ciclo de tres nodos en parent y lo informa empezando por el menor ID",
    cyc.ok == false and #cyc.errors == 1
        and cyc.errors[1] == "ciclo en la jerarquía parent: region:a -> region:b -> region:c -> region:a", cyc.errors[1])
local cyc2 = RegionRegistry({ ["region:x"] = "region:y", ["region:y"] = "region:x" }):Validate()
check("detecta un ciclo de dos nodos",
    cyc2.ok == false and cyc2.errors[1] == "ciclo en la jerarquía parent: region:x -> region:y -> region:x")
local cyc3 = RegionRegistry({
    ["region:a"] = "region:b", ["region:b"] = "region:a",
    ["region:c"] = "region:d", ["region:d"] = "region:c",
    ["region:e"] = "region:a",
}):Validate()
check("informa cada ciclo una sola vez, aunque otros nodos cuelguen de él",
    #cyc3.errors == 2 and cyc3.errors[1]:find("region:a -> region:b -> region:a", 1, true)
        and cyc3.errors[2]:find("region:c -> region:d -> region:c", 1, true))
local noCycle = RegionRegistry({ ["region:a"] = "region:b", ["region:b"] = "region:c", ["region:c"] = "region:d",
    ["region:d"] = "region:e", ["region:f"] = "region:c" })
check("una cadena larga sin ciclo (con un padre no registrado al final) no da ciclo",
    #noCycle:Validate().errors == 1 and noCycle:Validate().errors[1]:find("no está registrada", 1, true) ~= nil)
check("una entidad no puede ser su propio padre (rechazada al registrar)",
    Chronicle.Registry.New(nested):Register({ id = "region:a", type = "region", parent = "region:a" }) == false)
check("con los tipos por defecto no es posible construir un ciclo de parent",
    Schema:Validate({ id = "zone:a", type = "zone", parent = "zone:b" }).ok == false
        and Schema:Validate({ id = "subzone:a", type = "subzone", parent = "subzone:b" }).ok == false
        and Schema:Validate({ id = "continent:a", type = "continent", parent = "continent:b" }).ok == false)

-- ===================== Integración con el arranque del Core =====================
local function Boot(prepare)
    LoadAddon(NO_DATA)
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    if Chronicle.Events then
        Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    end
    local okBoot, err = pcall(FireEvent, "ADDON_LOADED", "Chronicle")
    return announced, okBoot, err
end

local announced = Boot()
check("arranque con Registry vacío: Init.ready, sin fallos y se anuncia el arranque",
    Chronicle.Init.ready == true and next(Chronicle.Init.failed) == nil and announced == 1)
check("tras el arranque el Registry por defecto está validado", Chronicle.Registry:IsValidated() == true)
check("antes de Init el Registry no está validado", (function()
    LoadAddon(NO_DATA)
    return Chronicle.Registry:IsValidated() == false
end)())

announced = Boot(function()
    assert(Chronicle.Registry:Register(continent))
    assert(Chronicle.Registry:Register(zoneDM))
    assert(Chronicle.Registry:Register(subColdridge))
end)
check("arranque con datos válidos cargados antes de Init: listo y validado",
    Chronicle.Init.ready == true and Chronicle.Registry:IsValidated() == true and announced == 1
        and Chronicle.Registry:Count() == 3)

announced = Boot(function() Chronicle.Registry:Register({ id = "zone:sin_padre", type = "zone" }) end)
check("una entidad rechazada impide dar el Registry por listo: Init falla y no anuncia el arranque",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Registry ~= nil and announced == 0
        and Chronicle.Registry:IsValidated() == false)
check("el fallo del Registry nombra el problema y se comunica por el mecanismo de errores",
    Chronicle.Init.failed.Registry:find("zone:sin_padre", 1, true) ~= nil
        and Chronicle.Init.failed.Registry:find("parent: es obligatorio", 1, true) ~= nil
        and contains(ReportedErrors, "Registry"))
check("aunque el Registry falle, los módulos independientes se siguen inicializando",
    Chronicle.State:IsReady() == true and SlashCmdList["CHRONICLE"] ~= nil)

announced = Boot(function() Chronicle.Registry:Register(zoneDM) end)
check("una referencia a una entidad inexistente hace fallar la validación de Init",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Registry:find("no está registrada", 1, true) ~= nil
        and announced == 0)

announced = Boot(function()
    Chronicle.Registry:Register(continent)
    Chronicle.Registry:Register(continent)
end)
check("un ID duplicado cargado antes de Init hace fallar el Registry (no se acepta en silencio)",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Registry:find("ID duplicado", 1, true) ~= nil)

announced = Boot(function() Chronicle.Registry = nil end)
check("Registry ausente: se diagnostica como no cargado y no se anuncia el arranque",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Registry:find("no está cargado", 1, true) ~= nil
        and announced == 0)

announced = Boot(function() Chronicle.Registry.Init = function() error("registry roto") end end)
check("un Registry:Init que lanza error deja Init.ready en false",
    Chronicle.Init.ready == false and Chronicle.Init.failed.Registry:find("registry roto", 1, true) ~= nil)

announced = Boot()
Chronicle.Registry:Register(continent)
check("registrar algo después de Init invalida el estado 'validado' hasta la siguiente validación",
    Chronicle.Registry:IsValidated() == false)

-- el .toc carga Schema y Registry después del Core base y antes de Init
local order = {}
for i, file in ipairs(ADDON_FILES) do order[file.name] = i end
check("orden de carga: Utils < Schema < Registry < Init, y Init es el último",
    order["Core/Utils.lua"] < order["Data/Schema.lua"] and order["Data/Schema.lua"] < order["Data/Registry.lua"]
        and order["Data/Registry.lua"] < order["Core/Init.lua"] and order["Core/Init.lua"] == #ADDON_FILES)
check("Schema y Registry no consultan la SavedVariable ni el estado persistente", (function()
    for _, file in ipairs(ADDON_FILES) do
        if file.name:find("^Data/") then
            for line in file.source:gmatch("[^\n]+") do
                if not line:match("^%s*%-%-") and (line:find("ChronicleCharDB", 1, true) or line:find("Chronicle.State", 1, true)) then
                    return false
                end
            end
        end
    end
    return true
end)())
