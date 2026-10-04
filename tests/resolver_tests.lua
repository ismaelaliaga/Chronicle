-- Escenarios de prueba del Resolver (Fase 4): nombres y alias reales con los datos migrados, y
-- el contrato (normalización, ambigüedad, ausencia de coincidencias parciales) con instancias
-- propias. Los alias esperados se escriben a mano aquí (no se leen del fichero de datos).

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

-- Antes de la inicialización el índice no existe
LoadAddon()
check("antes de Init el Resolver no está listo y Resolve lo dice (not_ready), sin resolver con datos a medias",
    Chronicle.Resolver:IsReady() == false and select(2, Chronicle.Resolver:Resolve("Ironforge")) == "not_ready"
        and Chronicle.Resolver:Resolve("Ironforge") == nil)

local announced = Boot()
local Resolver, Registry, Loc = Chronicle.Resolver, Chronicle.Registry, Chronicle.Localization

check("el Resolver se inicializa con el arranque, que se anuncia con todos los módulos requeridos listos",
    Resolver:IsReady() == true and Chronicle.Init.ready == true and announced == 1 and next(Chronicle.Init.failed) == nil)
local report = Resolver:Validate()
check("Resolver:Validate() del conjunto real: sin errores ni advertencias (no hay ningún nombre ambiguo)",
    report.ok == true and #report.errors == 0 and #report.warnings == 0, table.concat(report.errors, " | "))

-- ===================== Forjaz e Ironforge =====================
check("'Ironforge' (el nombre de la entidad) resuelve a city:ironforge", Resolver:Resolve("Ironforge") == "city:ironforge")
check("'Forjaz' (alias respaldado por la fuente) resuelve a city:ironforge", Resolver:Resolve("Forjaz") == "city:ironforge")
check("'Ciudad de Forjaz' (alias que la fuente marca como confirmado) resuelve a city:ironforge",
    Resolver:Resolve("Ciudad de Forjaz") == "city:ironforge")
check("el ID canónico sigue siendo city:ironforge y no depende de ninguno de sus nombres",
    Registry:Has("city:ironforge") and not Registry:Has("city:forjaz") and not Registry:Has("zone:ciudad_de_forjaz"))

-- ===================== Nombres visibles =====================
check("los nombres visibles de las entidades migradas resuelven a su ID",
    Resolver:Resolve("Dun Morogh") == "zone:dun_morogh" and Resolver:Resolve("Loch Modan") == "zone:loch_modan"
        and Resolver:Resolve("Reinos del Este") == "continent:eastern_kingdoms"
        and Resolver:Resolve("Coldridge Valley") == "subzone:coldridge_valley"
        and Resolver:Resolve("Gol'Bolar Quarry") == "subzone:golbolar_quarry"
        and Resolver:Resolve("Grelin Whitebeard") == "npc:grelin_whitebeard"
        and Resolver:Resolve("High Tinker Mekkatorque") == "npc:high_tinker_mekkatorque")
check("las 53 entidades migradas se resuelven por su nombre y cada una devuelve su propio ID",
    (function()
        local n = 0
        for _, id in ipairs(Loc:GetIds("esES")) do
            local resolved, reason = Resolver:Resolve(Loc:Get(id, "name"))
            if resolved ~= id then return false, id .. " -> " .. tostring(resolved) .. " " .. tostring(reason) end
            n = n + 1
        end
        return n == 53
    end)())

-- ===================== Alias (escritos a mano, de la fuente original) =====================
local ALIASES = {
    ["Ciudad de Forjaz"] = "city:ironforge", ["Forjaz"] = "city:ironforge",
    ["Desfiladero de Crestanevada"] = "subzone:coldridge_pass",
    ["Destilería Cebatruenos"] = "subzone:thunderbrew_distillery",
    ["Almacén de Brasacerada"] = "subzone:steelgrills_depot",
    ["Granja de Semperámbar"] = "subzone:amberstill_ranch",
    ["Refugio Peloescarcha"] = "subzone:frostmane_hold",
    ["Lago Glacial"] = "subzone:iceflow_lake",
    ["Cantera de Gol'Bolar"] = "subzone:golbolar_quarry",
    ["Lago de Helm"] = "subzone:helms_bed_lake",
    ["Avanzada de la Puerta Norte"] = "subzone:north_gate_outpost",
    ["Paso de la Puerta Norte"] = "subzone:north_gate_pass",
    ["Puertas de Forjaz"] = "subzone:gates_of_ironforge",
    ["Cubil Pardo"] = "subzone:the_grizzled_den",
    ["Colinas Tundra"] = "subzone:the_tundrid_hills",
    ["Base aérea de Forjaz"] = "subzone:ironforge_airfield",
    ["La Plaza"] = "subzone:the_commons",
    ["La Gran Forja"] = "subzone:the_great_forge",
    ["Gran Fundición"] = "subzone:the_great_forge",
    ["El Trono"] = "subzone:the_great_forge",
    ["La Sala Militar"] = "subzone:the_military_ward",
    ["Ciudad Manitas"] = "subzone:tinker_town",
}
local aliasCount = 0
for _ in pairs(ALIASES) do aliasCount = aliasCount + 1 end
check("la fuente tenía 22 alias (2 de zona + 20 de subzona); aquí se esperan 22 entradas y hay 23 registradas (22 de la fuente + 1 observado en el cliente real)",
    aliasCount == 22 and Resolver:CountAliases() == 23)
check("alias observado en el cliente real (WoW Classic Era esES): 'Destilería Thunderbrew' resuelve a la subzona y como subzona",
    Resolver:Resolve("Destilería Thunderbrew") == "subzone:thunderbrew_distillery"
        and Resolver:Resolve("Destilería Thunderbrew", { type = "subzone" }) == "subzone:thunderbrew_distillery"
        and select(2, Resolver:Resolve("Destilería Thunderbrew", { type = "zone" })) == "not_found")
check("cada uno de los 22 alias de la fuente resuelve a la entidad correcta",
    (function()
        for alias, id in pairs(ALIASES) do
            local resolved = Resolver:Resolve(alias)
            if resolved ~= id then return false, alias .. " -> " .. tostring(resolved) end
        end
        return true
    end)())
check("tres nombres distintos de la fuente apuntan a la misma subzona (La Gran Forja, Gran Fundición, El Trono)",
    Resolver:Resolve("La Gran Forja") == Resolver:Resolve("Gran Fundición")
        and Resolver:Resolve("El Trono") == "subzone:the_great_forge" and Resolver:Resolve("The Great Forge") == "subzone:the_great_forge")
check("los nombres de Cataclysm que la fuente descarta NO están ('Frente de Peloescarcha', 'Nueva Ciudad Manitas')",
    select(2, Resolver:Resolve("Frente de Peloescarcha")) == "not_found" and select(2, Resolver:Resolve("Nueva Ciudad Manitas")) == "not_found")
check("ningún alias crea entidades: el Registry sigue con las 53 de la Fase 3",
    Registry:Count() == 53 and #Registry:GetRejected() == 0)
check("los alias no son texto visible: Localization sigue devolviendo el nombre original",
    Loc:Get("city:ironforge", "name") == "Ironforge" and Loc:Get("subzone:the_great_forge", "name") == "The Great Forge"
        and Loc:Get("city:ironforge", "description"):find("Forjaz", 1, true) ~= nil)

-- ===================== Normalización =====================
check("mayúsculas y minúsculas: 'forjaz', 'FORJAZ', 'ironforge' e 'IRONFORGE' resuelven igual",
    Resolver:Resolve("forjaz") == "city:ironforge" and Resolver:Resolve("FORJAZ") == "city:ironforge"
        and Resolver:Resolve("ironforge") == "city:ironforge" and Resolver:Resolve("IRONFORGE") == "city:ironforge"
        and Resolver:Resolve("dUn mOrOgH") == "zone:dun_morogh")
check("mayúsculas acentuadas del español: 'DESTILERÍA CEBATRUENOS' y 'ALMACÉN DE BRASACERADA' resuelven",
    Resolver:Resolve("DESTILERÍA CEBATRUENOS") == "subzone:thunderbrew_distillery"
        and Resolver:Resolve("ALMACÉN DE BRASACERADA") == "subzone:steelgrills_depot"
        and Resolver:Resolve("granja de semperámbar") == "subzone:amberstill_ranch"
        and Resolver:Resolve("BASE AÉREA DE FORJAZ") == "subzone:ironforge_airfield")
check("espacios: se recortan los extremos y se reducen los internos repetidos (incluidos tabuladores y saltos de línea)",
    Resolver:Resolve("  Forjaz  ") == "city:ironforge" and Resolver:Resolve("Ciudad   de   Forjaz") == "city:ironforge"
        and Resolver:Resolve("\tCiudad de\nForjaz\r\n") == "city:ironforge"
        and Resolver:Resolve("Dun  Morogh") == "zone:dun_morogh")
check("NO se quitan los acentos: 'Destileria Cebatruenos' (sin tilde) no es 'Destilería Cebatruenos'",
    select(2, Resolver:Resolve("Destileria Cebatruenos")) == "not_found" and select(2, Resolver:Resolve("Almacen de Brasacerada")) == "not_found")
check("NO se unifican apóstrofos: el recto resuelve y el tipográfico no",
    Resolver:Resolve("Cantera de Gol'Bolar") == "subzone:golbolar_quarry"
        and select(2, Resolver:Resolve("Cantera de Gol\226\128\153Bolar")) == "not_found")
check("la normalización no altera lo que se muestra (Localization conserva mayúsculas, tildes y espacios)",
    Loc:Get("subzone:thunderbrew_distillery", "name") == "Thunderbrew Distillery"
        and Loc:Get("npc:chief_engineer_hinderweir_vii", "name") == "Chief Engineer Hinderweir VII")

-- ===================== Sin coincidencia =====================
local function reason(text, opts) local id, why, c = Resolver:Resolve(text, opts) return id, why, c end
check("un nombre desconocido devuelve nil y 'not_found'",
    (function() local id, why = reason("Stormwind") return id == nil and why == "not_found" end)()
        and select(2, reason("Ventormenta")) == "not_found" and select(2, reason("Kalimdor")) == "not_found")
check("una entrada vacía, solo espacios o que no es cadena devuelve nil y 'empty'",
    (function()
        for _, input in ipairs({ "", "   ", "\t\n" }) do
            local id, why = reason(input)
            if id ~= nil or why ~= "empty" then return false end
        end
        local id, why = Resolver:Resolve(nil)
        local id2, why2 = Resolver:Resolve(42)
        local id3, why3 = Resolver:Resolve({})
        return id == nil and why == "empty" and id2 == nil and why2 == "empty" and id3 == nil and why3 == "empty"
    end)())
check("un resultado negativo no devuelve candidatos", select(3, reason("Stormwind")) == nil)

-- ===================== Sin coincidencias parciales =====================
check("no hay coincidencias parciales: prefijos, sufijos y subcadenas no se resuelven",
    (function()
        for _, input in ipairs({ "Forja", "Forj", "Iron", "Dun", "Morogh", "Gates", "Thunderbrew", "Distillery", "Valley",
            "Coldridge", "Great Forge", "Gran", "Trono", "Ciudad", "Manitas", "Tinker", "Grelin", "Whitebeard", "Lake", "Gol'Bolar",
            "Forjazz", "Ironforgee", "Forjaz Ciudad", "de Forjaz" }) do
            local id, why = reason(input)
            if id ~= nil or why ~= "not_found" then return false, input .. " -> " .. tostring(id) end
        end
        return true
    end)())
check("un nombre que contiene a otro resuelve solo a la entidad exacta ('Ironforge' no es 'Ironforge Airfield' ni 'Gates of Ironforge')",
    Resolver:Resolve("Ironforge") == "city:ironforge" and Resolver:Resolve("Ironforge Airfield") == "subzone:ironforge_airfield"
        and Resolver:Resolve("Gates of Ironforge") == "subzone:gates_of_ironforge")
check("un ID canónico NO es un nombre ni un alias: no se acepta ni se confunde con uno",
    (function()
        for _, id in ipairs(Registry:GetIds()) do
            local resolved, why = Resolver:Resolve(id)
            if resolved ~= nil or why ~= "not_found" then return false, id end
        end
        return true
    end)())

-- ===================== Filtro por tipo =====================
check("opts.type restringe a candidatos de ese tipo",
    Resolver:Resolve("Ironforge", { type = "city" }) == "city:ironforge" and Resolver:Resolve("Forjaz", { type = "city" }) == "city:ironforge"
        and Resolver:Resolve("El Trono", { type = "subzone" }) == "subzone:the_great_forge"
        and Resolver:Resolve("Grelin Whitebeard", { type = "npc" }) == "npc:grelin_whitebeard")
check("un nombre que existe pero no es de ese tipo devuelve 'not_found'",
    select(2, Resolver:Resolve("Ironforge", { type = "zone" })) == "not_found"
        and select(2, Resolver:Resolve("Forjaz", { type = "subzone" })) == "not_found"
        and select(2, Resolver:Resolve("Grelin Whitebeard", { type = "lore" })) == "not_found")
check("un tipo que el Registry no conoce lanza error (errata); opts sin type o no tabla se ignoran",
    not pcall(Resolver.Resolve, Resolver, "Forjaz", { type = "faction" }) and not pcall(Resolver.Resolve, Resolver, "Forjaz", { type = 5 })
        and Resolver:Resolve("Forjaz", {}) == "city:ironforge" and Resolver:Resolve("Forjaz", "city") == "city:ironforge"
        and Resolver:Resolve("Forjaz", nil) == "city:ironforge")

-- ===================== Aislamiento: consultar no crea ni modifica nada =====================
local beforeEntities = Registry:GetAll()
local beforeIds = Registry:GetIds()
local beforeLocText = {}
for _, id in ipairs(Loc:GetIds("esES")) do beforeLocText[id] = Loc:Get(id, "name") .. "|" .. tostring(Loc:Get(id, "description")) end
local beforeAliases = Resolver:CountAliases()
for _, input in ipairs({ "Forjaz", "Ironforge", "Stormwind", "", "Forja", "El Trono", "zone:dun_morogh", "DUN MOROGH" }) do
    Resolver:Resolve(input); Resolver:Resolve(input, { type = "zone" })
end
Resolver:Validate()
local afterLocText = {}
for _, id in ipairs(Loc:GetIds("esES")) do afterLocText[id] = Loc:Get(id, "name") .. "|" .. tostring(Loc:Get(id, "description")) end
check("resolver no crea ni modifica entidades: el Registry queda exactamente igual",
    deepEqual(beforeEntities, Registry:GetAll()) and deepEqual(beforeIds, Registry:GetIds()) and Registry:Count() == 53
        and #Registry:GetRejected() == 0)
check("resolver no modifica Localization ni los alias", deepEqual(beforeLocText, afterLocText) and Resolver:CountAliases() == beforeAliases)
check("ningún dato de presentación ni alias se escribe en ChronicleCharDB",
    deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} } }))
check("los resultados son deterministas: reconstruir el índice no cambia ninguna resolución",
    (function()
        local before = {}
        for alias in pairs(ALIASES) do before[alias] = Resolver:Resolve(alias) end
        Resolver:Rebuild(); Resolver:Rebuild()
        for alias, id in pairs(before) do if Resolver:Resolve(alias) ~= id then return false end end
        return Resolver:Resolve("Forjaz") == "city:ironforge"
    end)())

-- ===================== Contrato con instancias propias =====================
local function NewWorld()
    local reg = Chronicle.Registry.New(Chronicle.Schema)
    for _, e in ipairs({
        { id = "continent:alpha", type = "continent" },
        { id = "continent:beta", type = "continent" },
        { id = "zone:z1", type = "zone", parent = "continent:alpha" },
        { id = "subzone:s1", type = "subzone", parent = "zone:z1" },
        { id = "npc:n1", type = "npc", located_in = "subzone:s1" },
    }) do
        assert(reg:Register(e))
    end
    local loc = Chronicle.Localization.New(reg)
    return reg, loc, Chronicle.Resolver.New(reg, loc)
end
check("Resolver.New exige un Registry y un Localization",
    not pcall(Chronicle.Resolver.New, nil, nil) and not pcall(Chronicle.Resolver.New, {}, {}))

-- Ambigüedad: dos entidades de distinto tipo con el mismo nombre
local reg, loc, res = NewWorld()
loc:Add("esES", "zone:z1", { name = "Valle" })
loc:Add("esES", "subzone:s1", { name = "VALLE" })
loc:Add("esES", "continent:alpha", { name = "Alfa" })
res:Init()
local id, why, candidates = res:Resolve("valle")
check("un nombre compartido por dos entidades es ambiguo: nil, 'ambiguous' y los candidatos ordenados (no se elige uno)",
    id == nil and why == "ambiguous" and deepEqual(candidates, { "subzone:s1", "zone:z1" }))
check("la ambigüedad se resuelve con opts.type cuando solo un candidato es del tipo pedido",
    res:Resolve("Valle", { type = "zone" }) == "zone:z1" and res:Resolve("Valle", { type = "subzone" }) == "subzone:s1"
        and select(2, res:Resolve("Valle", { type = "npc" })) == "not_found")
check("Validate avisa de la ambigüedad como advertencia (con los candidatos) sin convertirla en error",
    res:Validate().ok == true and #res:Validate().warnings == 1
        and contains(res:Validate().warnings, "'valle' es ambiguo") and contains(res:Validate().warnings, "subzone:s1, zone:z1"))
check("las entidades no ambiguas del mismo conjunto siguen resolviendo", res:Resolve("Alfa") == "continent:alpha")
check("el resultado de una consulta ambigua es una copia: modificarlo no afecta a la siguiente",
    (function()
        local _, _, c = res:Resolve("valle")
        c[1] = "roto"; table.insert(c, "otro")
        return deepEqual(select(3, res:Resolve("valle")), { "subzone:s1", "zone:z1" })
    end)())

-- Ambigüedad: un alias que coincide con el nombre de otra entidad
local reg2, loc2, res2 = NewWorld()
loc2:Add("esES", "continent:alpha", { name = "Alfa" })
loc2:Add("esES", "continent:beta", { name = "Beta" })
res2:AddAlias("esES", "continent:beta", "ALFA")
res2:Init()
local id2, why2, c2 = res2:Resolve("alfa")
check("un alias que coincide con el nombre de otra entidad la hace ambigua en vez de elegir una",
    id2 == nil and why2 == "ambiguous" and deepEqual(c2, { "continent:alpha", "continent:beta" })
        and res2:Resolve("Beta") == "continent:beta")
-- Dos alias iguales de dos entidades
local reg3, loc3, res3 = NewWorld()
res3:AddAlias("esES", "continent:alpha", "Reino")
res3:AddAlias("esES", "continent:beta", "reino")
loc3:Add("esES", "continent:alpha", { name = "Alfa" })
res3:Init()
check("el mismo alias para dos entidades distintas es ambiguo",
    select(2, res3:Resolve("REINO")) == "ambiguous" and deepEqual(select(3, res3:Resolve("Reino")), { "continent:alpha", "continent:beta" }))

-- Mismo nombre en dos idiomas para la MISMA entidad: no es ambigüedad
local reg4, loc4, res4 = NewWorld()
loc4:Add("esES", "continent:alpha", { name = "Alpha" })
loc4:Add("enUS", "continent:alpha", { name = "Alpha" })
loc4:Add("deDE", "continent:alpha", { name = "Alpha-DE" })
res4:AddAlias("esES", "continent:alpha", "alpha")
res4:Init()
check("el mismo nombre en varios idiomas (o como alias) de una misma entidad no es ambiguo; el índice recorre todos los idiomas",
    res4:Resolve("Alpha") == "continent:alpha" and res4:Resolve("alpha-de") == "continent:alpha" and #res4:Validate().warnings == 0)

-- Independencia del orden de inserción
local function Build(order)
    local r, l, rs = NewWorld()
    for _, step in ipairs(order) do
        if step[1] == "text" then l:Add(unpack(step, 2, 4)) else rs:AddAlias(unpack(step, 2, 4)) end
    end
    rs:Init()
    return rs
end
local steps = {
    { "text", "esES", "zone:z1", { name = "Valle" } }, { "text", "esES", "subzone:s1", { name = "Valle" } },
    { "alias", "esES", "continent:alpha", "Valle" }, { "alias", "esES", "npc:n1", "Persona" },
    { "text", "enUS", "npc:n1", { name = "Person" } },
}
local reversed = {}
for i = #steps, 1, -1 do reversed[#reversed + 1] = steps[i] end
local r1, r2 = Build(steps), Build(reversed)
check("los resultados (y el orden de los candidatos) no dependen del orden en que se cargaron textos y alias",
    deepEqual({ r1:Resolve("valle") }, { r2:Resolve("valle") }) and deepEqual(select(3, r1:Resolve("valle")),
        { "continent:alpha", "subzone:s1", "zone:z1" })
        and r1:Resolve("persona") == r2:Resolve("persona") and r1:Resolve("Person") == r2:Resolve("Person")
        and deepEqual(r1:Validate(), r2:Validate()))

-- AddAlias: rechazos
local reg5, loc5, res5 = NewWorld()
loc5:Add("esES", "continent:alpha", { name = "Alfa" })
check("AddAlias acepta un alias válido y rechaza un duplicado (aunque cambie mayúsculas o espacios)",
    res5:AddAlias("esES", "continent:alpha", "Primero") == true
        and res5:AddAlias("esES", "continent:alpha", "  PRIMERO ") == false and res5:CountAliases() == 1)
local badCases = {
    { "idioma que no es cadena", { nil, "continent:alpha", "x" } },
    { "idioma vacío", { "", "continent:alpha", "x" } },
    { "ID que no es cadena", { "esES", nil, "x" } },
    { "ID vacío", { "esES", "", "x" } },
    { "alias que no es cadena", { "esES", "continent:alpha", 5 } },
    { "alias vacío", { "esES", "continent:alpha", "" } },
    { "alias de solo espacios", { "esES", "continent:alpha", " \t " } },
}
for _, case in ipairs(badCases) do
    local ok, err = res5:AddAlias(unpack(case[2], 1, 3))
    check("AddAlias rechaza: " .. case[1], ok == false and type(err) == "string" and err ~= "", tostring(err))
end
check("los alias rechazados no se añaden y quedan anotados", res5:CountAliases() == 1 and #res5:GetRejected() == #badCases + 1)
check("Init falla si hay alias rechazados, no construye el índice y Resolve devuelve not_ready",
    not pcall(res5.Init, res5) and res5:IsReady() == false and select(2, res5:Resolve("Alfa")) == "not_ready")

-- Alias a una entidad inexistente / en un idioma sin textos
local reg6, loc6, res6 = NewWorld()
loc6:Add("esES", "continent:alpha", { name = "Alfa" })
res6:AddAlias("esES", "continent:fantasma", "Fantasma")
check("un alias de un ID que no está en el Registry es un error y no se indexa",
    res6:Validate().ok == false and contains(res6:Validate().errors, "continent:fantasma")
        and not pcall(res6.Init, res6) and select(2, res6:Resolve("Fantasma")) == "not_ready")
local reg7, loc7, res7 = NewWorld()
loc7:Add("esES", "continent:alpha", { name = "Alfa" })
res7:AddAlias("deDE", "continent:alpha", "Alpha-DE")
check("un alias en un idioma sin textos en Localization es un error",
    res7:Validate().ok == false and contains(res7:Validate().errors, "idioma sin textos"))
local okMsg, msg = pcall(res6.Init, res6)
check("el mensaje de error de Init nombra el problema", okMsg == false and tostring(msg):find("Resolver: validación fallida", 1, true) ~= nil)

-- Tras cambiar los alias el índice se invalida hasta reconstruirlo
local reg8, loc8, res8 = NewWorld()
loc8:Add("esES", "continent:alpha", { name = "Alfa" })
res8:Init()
check("tras Init resuelve", res8:Resolve("Alfa") == "continent:alpha" and res8:IsReady())
res8:AddAlias("esES", "continent:alpha", "Alfita")
check("añadir un alias después de Init invalida el índice (not_ready) en vez de resolver con datos desfasados",
    select(2, res8:Resolve("Alfa")) == "not_ready" and res8:IsReady() == false)
res8:Init()
check("tras volver a inicializar resuelve también el alias nuevo", res8:Resolve("Alfita") == "continent:alpha" and res8:Resolve("Alfa") == "continent:alpha")
loc8:Add("esES", "continent:beta", { name = "Beta" })
check("los textos añadidos a Localization después de Init no se ven hasta Rebuild/Init",
    select(2, res8:Resolve("Beta")) == "not_found" and (function() res8:Rebuild() return res8:Resolve("Beta") == "continent:beta" end)())

-- Un nombre de una entidad que no está en el Registry (texto huérfano) no se indexa
local reg9, loc9, res9 = NewWorld()
loc9:Add("esES", "continent:alpha", { name = "Alfa" })
loc9:Add("esES", "continent:orfano", { name = "Huérfano" })
res9:Rebuild()
check("un texto de un ID que no existe nunca se resuelve (el Registry es la fuente de verdad)",
    res9:Resolve("Alfa") == "continent:alpha" and select(2, res9:Resolve("Huérfano")) == "not_found")

-- ===================== Estado de preparación: invariantes (regresión) =====================
-- Contrato: IsReady() es true si y solo si Resolve() no responde "not_ready". `coherent` lo
-- comprueba; se aplica tras cada paso de los escenarios siguientes.
local function coherent(r)
    local _, why = r:Resolve("Alfa")
    return r:IsReady() == (why ~= "not_ready")
end

local regR, locR, resR = NewWorld()
locR:Add("esES", "continent:alpha", { name = "Alfa" })
locR:Add("esES", "continent:beta", { name = "Beta" })
check("estado inicial: sin Init el Resolver no está listo y Resolve responde not_ready (coherente)",
    resR:IsReady() == false and select(2, resR:Resolve("Alfa")) == "not_ready" and coherent(resR))

-- 1. Construir el índice
resR:Init()
check("1. tras construir el índice IsReady() es true y Resolve funciona (coherente)",
    resR:IsReady() == true and resR:Resolve("Alfa") == "continent:alpha" and coherent(resR))
check("1b. Init es repetible: volver a llamarlo con datos válidos deja el módulo listo",
    pcall(resR.Init, resR) and resR:IsReady() == true and resR:Resolve("Beta") == "continent:beta")

-- 2. Un alias válido modifica los datos e invalida el índice hasta reconstruir
check("2. un alias válido se acepta, invalida el índice: IsReady() false y Resolve not_ready para todo, incluso lo anterior",
    resR:AddAlias("esES", "continent:alpha", "Primero") == true and resR:CountAliases() == 1
        and resR:IsReady() == false
        and select(2, resR:Resolve("Alfa")) == "not_ready" and select(2, resR:Resolve("Primero")) == "not_ready"
        and resR:Resolve("Alfa") == nil and coherent(resR))

-- 3. Reconstruir correctamente
local rebuilt, rebuiltMsg = resR:Rebuild()
check("3. Rebuild satisfactorio devuelve true, deja IsReady() en true y el alias nuevo resuelve a su ID (coherente)",
    rebuilt == true and rebuiltMsg == nil and resR:IsReady() == true and resR:Resolve("Primero") == "continent:alpha"
        and resR:Resolve("Alfa") == "continent:alpha" and resR:Resolve("Beta") == "continent:beta" and coherent(resR))

-- 4. Un alias duplicado se rechaza sin tocar nada
local aliasesBefore, rejectedBefore = resR:CountAliases(), #resR:GetRejected()
local dupOk = resR:AddAlias("esES", "continent:alpha", "  PRIMERO ")
check("4. un alias duplicado se rechaza: el índice previo sigue válido, IsReady() true, resuelve igual y los alias no cambian",
    dupOk == false and resR:IsReady() == true and resR:Resolve("Primero") == "continent:alpha"
        and resR:Resolve("Alfa") == "continent:alpha" and resR:CountAliases() == aliasesBefore
        and #resR:GetRejected() == rejectedBefore + 1 and coherent(resR))

-- 5. Alias vacío o con datos inválidos: tampoco invalidan un índice válido
local allRejected, stillReady = true, true
for _, case in ipairs(badCases) do
    if resR:AddAlias(unpack(case[2], 1, 3)) ~= false then allRejected = false end
    if not (resR:IsReady() and resR:Resolve("Primero") == "continent:alpha" and coherent(resR)) then stillReady = false end
end
check("5. alias vacío, solo espacios o con datos inválidos (7 casos): todos se rechazan y tras cada uno el índice sigue válido",
    allRejected and stillReady and resR:CountAliases() == aliasesBefore and #resR:GetRejected() == rejectedBefore + 1 + #badCases)
check("5b. un rechazo no revoca IsReady() (describe el último Init/Rebuild), pero queda registrado y Validate ya falla",
    resR:IsReady() == true and resR:Validate().ok == false and #resR:Validate().errors == #resR:GetRejected())

-- 6. Reconstruir con datos que incumplen la validación: nunca queda listo
local failedOk, failedMsg = resR:Rebuild()
check("6a. Rebuild con rechazos registrados falla en modo seguro: false, mensaje descriptivo, índice descartado y NO listo",
    failedOk == false and type(failedMsg) == "string" and failedMsg:find("Resolver: validación fallida", 1, true) ~= nil
        and resR:IsReady() == false and select(2, resR:Resolve("Alfa")) == "not_ready" and coherent(resR))
check("6b. repetir Rebuild no lo deja listo: no hay forma de eludir la validación",
    resR:Rebuild() == false and resR:Rebuild() == false and resR:IsReady() == false
        and select(2, resR:Resolve("Primero")) == "not_ready" and coherent(resR))
check("6c. Init lanza el error de la validación y el módulo sigue NO listo",
    (function() local ok, err = pcall(resR.Init, resR); return ok == false and tostring(err):find("Resolver: validación fallida", 1, true) ~= nil end)()
        and resR:IsReady() == false and coherent(resR))

-- El caso del defecto original: Init falla y después alguien llama a Rebuild
local regT, locT, resT = NewWorld()
locT:Add("esES", "continent:alpha", { name = "Alfa" })
resT:AddAlias("esES", "continent:alpha", "")
check("7. tras un Init() fallido, Rebuild() NO puede dejar el Resolver resolviendo con datos inválidos",
    not pcall(resT.Init, resT) and resT:IsReady() == false and select(2, resT:Resolve("Alfa")) == "not_ready"
        and resT:Rebuild() == false and resT:IsReady() == false and select(2, resT:Resolve("Alfa")) == "not_ready"
        and coherent(resT))

-- Un alias a una entidad inexistente se acepta (el formato es válido), invalida, y la reconstrucción falla
local regS, locS, resS = NewWorld()
locS:Add("esES", "continent:alpha", { name = "Alfa" })
resS:Init()
check("8a. un alias de formato válido pero de un ID inexistente se acepta (el orden de carga no importa) e invalida el índice",
    resS:AddAlias("esES", "continent:fantasma", "Fantasma") == true and resS:IsReady() == false and coherent(resS))
local okS, msgS = resS:Rebuild()
check("8b. Rebuild con un alias a una entidad inexistente: false, el mensaje nombra el ID, y no queda listo",
    okS == false and msgS:find("continent:fantasma", 1, true) ~= nil and resS:IsReady() == false
        and select(2, resS:Resolve("Alfa")) == "not_ready" and coherent(resS))
check("8c. y repetir Rebuild o fallar Init no cambia nada", resS:Rebuild() == false and not pcall(resS.Init, resS)
    and resS:IsReady() == false and coherent(resS))

-- Con los datos reales: reconstruir con datos válidos es coherente y no cambia ninguna resolución
local rb1 = Chronicle.Resolver:Rebuild()
check("con los datos reales: Rebuild devuelve true, IsReady() es true y las resoluciones siguen siendo las mismas",
    rb1 == true and Chronicle.Resolver:IsReady() == true and Chronicle.Resolver:Resolve("Forjaz") == "city:ironforge"
        and Chronicle.Resolver:Resolve("El Trono") == "subzone:the_great_forge"
        and Chronicle.Resolver:Resolve("Ironforge") == "city:ironforge" and Chronicle.Resolver:CountAliases() == 23)
check("ambigüedad y normalización no cambian tras reconstruir (instancia con nombre compartido)",
    (function()
        local _, l, r = NewWorld()
        l:Add("esES", "zone:z1", { name = "Valle" }); l:Add("esES", "subzone:s1", { name = "VALLE" })
        r:Init()
        local a1 = { r:Resolve(" valle ") }
        r:Rebuild()
        local a2 = { r:Resolve(" valle ") }
        return a1[2] == "ambiguous" and deepEqual(a1, a2) and r:Resolve("Valle", { type = "zone" }) == "zone:z1"
    end)())

-- ===================== Integración con el arranque =====================
announced = Boot(function() Chronicle.Resolver:AddAlias("esES", "city:no_existe", "Ciudad fantasma") end)
check("un alias que apunta a una entidad inexistente impide anunciar el arranque y queda diagnosticado",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Resolver ~= nil
        and Chronicle.Init.failed.Resolver:find("city:no_existe", 1, true) ~= nil and Chronicle.Resolver:IsReady() == false
        and select(2, Chronicle.Resolver:Resolve("Forjaz")) == "not_ready" and contains(ReportedErrors, "Resolver"))
announced = Boot(function() Chronicle.Resolver:AddAlias("esES", "city:ironforge", "Forjaz") end)
check("un alias duplicado de los datos migrados impide anunciar el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Resolver:find("alias duplicado", 1, true) ~= nil)
announced = Boot(function() Chronicle.Resolver = nil end)
check("Resolver ausente: se diagnostica como no cargado y no se anuncia el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Resolver:find("no está cargado", 1, true) ~= nil)
announced = Boot(function() Chronicle.Resolver.Init = function() error("resolver roto") end end)
check("un Resolver:Init que lanza error deja Init.ready en false",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Resolver:find("resolver roto", 1, true) ~= nil)
check("los fallos del Resolver no impiden que los módulos independientes se inicialicen",
    Chronicle.State:IsReady() == true and Chronicle.Registry:IsValidated() == true and SlashCmdList["CHRONICLE"] ~= nil)
announced = Boot(function() Chronicle.Registry:Register({ id = "continent:eastern_kingdoms_x", type = "continent", related_to = { "zone:no_existe" } }) end)
check("los fallos del Registry siguen impidiendo anunciar el arranque con Localization y Resolver presentes",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Registry ~= nil)
announced = Boot()
check("arranque normal restablecido: todo listo y se anuncia exactamente una vez",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Resolver:Resolve("Forjaz") == "city:ironforge")

-- El fichero de alias tiene los 22 de la fuente + 1 observado en el cliente real
check("el fichero de alias contiene exactamente 23 llamadas a AddAlias (22 de la fuente + 1 del cliente real), todas en esES",
    (function()
        local n = 0
        for _, file in ipairs(ADDON_FILES) do
            if file.name == "Localization/esES/Aliases.lua" then
                for line in file.source:gmatch("[^\n]+") do
                    if line:match("^Resolver:AddAlias%(") then
                        n = n + 1
                        if not line:match('^Resolver:AddAlias%("esES", ') then return false end
                    end
                end
            end
        end
        return n == 23
    end)())
