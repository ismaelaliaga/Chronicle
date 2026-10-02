-- Escenarios de prueba de la migración de datos (Fase 3): Dun Morogh, Loch Modan y Forjaz.
--
-- La referencia es LegacyReference (tests/fixtures/legacy_reference.lua): una copia literal
-- de los datos del addon ORIGINAL, obtenida ejecutando sus ficheros. Los textos migrados se
-- comparan con == contra esos valores, sin normalizar espacios, mayúsculas ni acentos.
-- Los IDs esperados se escriben a mano aquí, de forma independiente del generador de datos.
-- (Fase 4: los textos se leen ahora de Chronicle.Localization, idioma esES, y no de LegacyText.)

local Ref = LegacyReference

-- Arranca el addon completo (datos reales incluidos) y devuelve cuántas veces se anunció
-- "Chronicle.Initialized". `prepare` puede sabotear/ampliar los datos antes de ADDON_LOADED.
local function Boot(prepare)
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    FireEvent("ADDON_LOADED", "Chronicle")
    return announced
end

-- ---------------------------------------------------------------------------
-- IDs esperados (escritos a mano)
-- ---------------------------------------------------------------------------
local PLACE_IDS = {
    ["Dun Morogh"] = "zone:dun_morogh",
    ["Loch Modan"] = "zone:loch_modan",
    ["Ironforge"] = "city:ironforge",
}

local SUBZONE_IDS = {
    -- Dun Morogh (21)
    ["Coldridge Valley"] = "subzone:coldridge_valley",
    ["Coldridge Pass"] = "subzone:coldridge_pass",
    ["Kharanos"] = "subzone:kharanos",
    ["Thunderbrew Distillery"] = "subzone:thunderbrew_distillery",
    ["Steelgrill's Depot"] = "subzone:steelgrills_depot",
    ["Brewnall Village"] = "subzone:brewnall_village",
    ["Amberstill Ranch"] = "subzone:amberstill_ranch",
    ["Frostmane Hold"] = "subzone:frostmane_hold",
    ["Iceflow Lake"] = "subzone:iceflow_lake",
    ["Gol'Bolar Quarry"] = "subzone:golbolar_quarry",
    ["Shimmer Ridge"] = "subzone:shimmer_ridge",
    ["Helm's Bed Lake"] = "subzone:helms_bed_lake",
    ["North Gate Outpost"] = "subzone:north_gate_outpost",
    ["North Gate Pass"] = "subzone:north_gate_pass",
    ["South Gate Outpost"] = "subzone:south_gate_outpost",
    ["South Gate Pass"] = "subzone:south_gate_pass",
    ["Gates of Ironforge"] = "subzone:gates_of_ironforge",
    ["The Grizzled Den"] = "subzone:the_grizzled_den",
    ["The Tundrid Hills"] = "subzone:the_tundrid_hills",
    ["Gnomeregan"] = "subzone:gnomeregan",
    ["Ironforge Airfield"] = "subzone:ironforge_airfield",
    -- Loch Modan (12)
    ["Thelsamar"] = "subzone:thelsamar",
    ["The Loch"] = "subzone:the_loch",
    ["Stonewrought Dam"] = "subzone:stonewrought_dam",
    ["Valley of Kings"] = "subzone:valley_of_kings",
    ["Grizzlepaw Ridge"] = "subzone:grizzlepaw_ridge",
    ["Stonesplinter Valley"] = "subzone:stonesplinter_valley",
    ["The Farstrider Lodge"] = "subzone:the_farstrider_lodge",
    ["Ironband's Excavation Site"] = "subzone:ironbands_excavation_site",
    ["Silver Stream Mine"] = "subzone:silver_stream_mine",
    ["Mo'grosh Stronghold"] = "subzone:mogrosh_stronghold",
    ["Algaz Station"] = "subzone:algaz_station",
    ["Dun Algaz"] = "subzone:dun_algaz",
    -- Forjaz (7)
    ["The Commons"] = "subzone:the_commons",
    ["The Great Forge"] = "subzone:the_great_forge",
    ["The Mystic Ward"] = "subzone:the_mystic_ward",
    ["The Military Ward"] = "subzone:the_military_ward",
    ["The Forlorn Cavern"] = "subzone:the_forlorn_cavern",
    ["Hall of Explorers"] = "subzone:hall_of_explorers",
    ["Tinker Town"] = "subzone:tinker_town",
}

local NPC_IDS = {
    ["Grelin Whitebeard"] = "npc:grelin_whitebeard",
    ["Sten Stoutarm"] = "npc:sten_stoutarm",
    ["Senir Whitebeard"] = "npc:senir_whitebeard",
    ["Jarven Thunderbrew"] = "npc:jarven_thunderbrew",
    ["Innkeeper Belm"] = "npc:innkeeper_belm",
    ["Captain Rugelfuss"] = "npc:captain_rugelfuss",
    ["Chief Engineer Hinderweir VII"] = "npc:chief_engineer_hinderweir_vii",
    ["King Magni Bronzebeard"] = "npc:king_magni_bronzebeard",
    ["High Tinker Mekkatorque"] = "npc:high_tinker_mekkatorque",
}

local CONTINENT_ID = "continent:eastern_kingdoms"

-- Las tres áreas tal y como las organiza la fuente.
local AREAS = {
    { name = "Dun Morogh", data = Ref.zones["Dun Morogh"], subzones = 21, npcs = 5 },
    { name = "Loch Modan", data = Ref.zones["Loch Modan"], subzones = 12, npcs = 2 },
    { name = "Ironforge", data = Ref.cities["Ironforge"], subzones = 7, npcs = 2 },
}

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ===================== Sanidad de la referencia =====================
check("la referencia del addon original tiene lo esperado: 40 subzonas y 9 NPC en las tres áreas",
    (function()
        local sub, npcs = 0, 0
        for _, area in ipairs(AREAS) do
            sub = sub + count(area.data.subzones)
            for _, s in pairs(area.data.subzones) do npcs = npcs + #(s.npcs or {}) end
        end
        return sub == 40 and npcs == 9
    end)())

-- ===================== Registro del conjunto =====================
local announced = Boot()
local Registry = Chronicle.Registry

check("el addon arranca con los datos migrados: Init.ready, sin fallos y se anuncia el arranque",
    Chronicle.Init.ready == true and next(Chronicle.Init.failed) == nil and announced == 1)
check("no se ha rechazado ninguna entidad al registrar", #Registry:GetRejected() == 0)
check("hay 53 entidades: 1 continente, 2 zonas, 1 ciudad, 40 subzonas, 9 NPC, 0 lore",
    Registry:Count() == 53 and Registry:Count("continent") == 1 and Registry:Count("zone") == 2
        and Registry:Count("city") == 1 and Registry:Count("subzone") == 40
        and Registry:Count("npc") == 9 and Registry:Count("lore") == 0)

-- ===================== IDs: formato, ejemplos pedidos, sin duplicados =====================
check("se conservan los IDs de ejemplo del encargo",
    Registry:Has("continent:eastern_kingdoms") and Registry:Has("zone:dun_morogh")
        and Registry:Has("zone:loch_modan") and Registry:Has("city:ironforge")
        and Registry:Has("subzone:coldridge_valley") and Registry:Has("npc:grelin_whitebeard"))

local expectedIds = { [CONTINENT_ID] = true }
for _, id in pairs(PLACE_IDS) do expectedIds[id] = true end
for _, id in pairs(SUBZONE_IDS) do expectedIds[id] = true end
for _, id in pairs(NPC_IDS) do expectedIds[id] = true end
check("el conjunto de IDs registrados es exactamente el esperado (ni más ni menos)",
    (function()
        local registered = {}
        for _, id in ipairs(Registry:GetIds()) do registered[id] = true end
        for id in pairs(expectedIds) do if not registered[id] then return false end end
        for id in pairs(registered) do if not expectedIds[id] then return false end end
        return true
    end)())
check("todos los IDs cumplen el formato tipo:slug y su tipo coincide con el prefijo",
    (function()
        for _, id in ipairs(Registry:GetIds()) do
            if not Chronicle.Schema:IsValidId(id) then return false end
            if Registry:Get(id).type ~= id:match("^(%a+):") then return false end
        end
        return true
    end)())
check("ningún ID incorpora el slug de su padre ni de su ubicación (los IDs no dependen de la jerarquía)",
    (function()
        for _, e in ipairs(Registry:GetAll()) do
            local slug = e.id:match(":(.+)$")
            for _, field in ipairs({ "parent", "located_in" }) do
                if e[field] then
                    local parentSlug = e[field]:match(":(.+)$")
                    if slug:sub(1, #parentSlug + 1) == parentSlug .. "_" then return false, e.id end
                end
            end
        end
        return true
    end)())

-- Sin duplicados: cada llamada a Register del código de datos corresponde a una entidad
-- distinta (si hubiera un ID repetido, el Registry lo rechazaría y habría menos entidades).
local registerCalls = 0
for _, file in ipairs(ADDON_FILES) do
    if file.name:find("^Data/Entities/") then
        for line in file.source:gmatch("[^\n]+") do
            if line:match("^Registry:Register%(") then registerCalls = registerCalls + 1 end
        end
    end
end
check("no hay IDs duplicados: tantas llamadas a Register en los ficheros de datos como entidades",
    registerCalls == 53 and registerCalls == Registry:Count() and #Registry:GetRejected() == 0,
    "llamadas=" .. registerCalls)
check("cada ID aparece una sola vez en el listado",
    (function()
        local seen = {}
        for _, id in ipairs(Registry:GetIds()) do
            if seen[id] then return false end
            seen[id] = true
        end
        return true
    end)())

-- ===================== Referencias y validación global =====================
local report = Registry:Validate()
check("el conjunto completo supera Registry:Validate() sin errores ni advertencias",
    report.ok == true and #report.errors == 0 and #report.warnings == 0, table.concat(report.errors, " | "))
check("todas las referencias parent, located_in y related_to apuntan a entidades existentes",
    (function()
        local refs = 0
        for _, e in ipairs(Registry:GetAll()) do
            for _, field in ipairs({ "parent", "located_in" }) do
                if e[field] then
                    refs = refs + 1
                    if not Registry:Has(e[field]) then return false end
                end
            end
            for _, target in ipairs(e.related_to or {}) do
                refs = refs + 1
                if not Registry:Has(target) then return false end
            end
        end
        return refs > 0
    end)())
check("ninguna entidad declara contains (es una consulta derivada)",
    (function()
        for _, e in ipairs(Registry:GetAll()) do if e.contains ~= nil then return false end end
        return true
    end)())

-- ===================== Relaciones migradas =====================
check("las zonas y la ciudad cuelgan del continente (la fuente los lista en Reinos del Este)",
    (function()
        local places = Ref.continents["Reinos del Este"].places
        local listed = {}
        for _, name in ipairs(places) do listed[name] = true end
        for name, id in pairs(PLACE_IDS) do
            if not listed[name] then return false end -- la fuente debe confirmarlo
            if Registry:Get(id).parent ~= CONTINENT_ID then return false end
        end
        return true
    end)())
check("el continente no tiene parent ni located_in", Registry:Get(CONTINENT_ID).parent == nil
    and Registry:Get(CONTINENT_ID).located_in == nil)
check("Forjaz está en Dun Morogh (located_in) según nestedCities de la fuente, y su parent es el continente",
    Ref.zones["Dun Morogh"].nestedCities[1] == "Ironforge"
        and Registry:Get("city:ironforge").located_in == "zone:dun_morogh"
        and Registry:Get("city:ironforge").parent == CONTINENT_ID)
check("las zonas de Dun Morogh y Loch Modan no tienen located_in", Registry:Get("zone:dun_morogh").located_in == nil
    and Registry:Get("zone:loch_modan").located_in == nil)

check("cada subzona cuelga (parent) de la zona o ciudad donde la fuente la lista",
    (function()
        for _, area in ipairs(AREAS) do
            for subName in pairs(area.data.subzones) do
                local e = Registry:Get(SUBZONE_IDS[subName])
                if not e or e.parent ~= PLACE_IDS[area.name] or e.located_in ~= nil then return false end
            end
        end
        return true
    end)())
check("North Gate Pass y South Gate Pass cuelgan de Dun Morogh y no de Loch Modan, como dice la fuente",
    Registry:Get("subzone:north_gate_pass").parent == "zone:dun_morogh"
        and Registry:Get("subzone:south_gate_pass").parent == "zone:dun_morogh")
check("Gates of Ironforge es una subzona de Dun Morogh, no de la ciudad",
    Registry:Get("subzone:gates_of_ironforge").parent == "zone:dun_morogh")

check("cada NPC está located_in en la subzona de la que cuelga en la fuente, y no tiene parent",
    (function()
        for _, area in ipairs(AREAS) do
            for subName, sub in pairs(area.data.subzones) do
                for _, npc in ipairs(sub.npcs or {}) do
                    local e = Registry:Get(NPC_IDS[npc.name])
                    if not e or e.located_in ~= SUBZONE_IDS[subName] or e.parent ~= nil then return false end
                end
            end
        end
        return true
    end)())

check("related_to: cada relatedPlaces de la fuente se ve desde los dos lados (GetRelated), sin duplicarla",
    (function()
        local pairsSeen = 0
        for _, area in ipairs(AREAS) do
            for _, otherName in ipairs(area.data.relatedPlaces or {}) do
                local a, b = PLACE_IDS[area.name], PLACE_IDS[otherName]
                local fromA, fromB = Registry:GetRelated(a), Registry:GetRelated(b)
                local function has(list, id) for _, v in ipairs(list) do if v == id then return true end end end
                if not (has(fromA, b) and has(fromB, a)) then return false end
                pairsSeen = pairsSeen + 1
            end
        end
        return pairsSeen == 4
    end)())
check("related_to de los lugares: solo Dun Morogh lo declara (una vez por pareja)",
    deepEqual(Registry:Get("zone:dun_morogh").related_to, { "city:ironforge", "zone:loch_modan" })
        and Registry:Get("zone:loch_modan").related_to == nil and Registry:Get("city:ironforge").related_to == nil)
check("la única relación entre personajes es la de familia que declara el texto de Senir (Senir -> Grelin)",
    deepEqual(Registry:Get("npc:senir_whitebeard").related_to, { "npc:grelin_whitebeard" })
        and Registry:Get("npc:grelin_whitebeard").related_to == nil
        and table.concat(Registry:GetRelated("npc:grelin_whitebeard"), ",") == "npc:senir_whitebeard"
        and Ref.zones["Dun Morogh"].subzones["Kharanos"].npcs[1].text:find("es familia de Grelin Whitebeard", 1, true) ~= nil)
check("ningún otro NPC ni subzona declara related_to",
    (function()
        for _, e in ipairs(Registry:GetAll()) do
            if e.related_to and e.id ~= "zone:dun_morogh" and e.id ~= "npc:senir_whitebeard" then return false end
        end
        return true
    end)())

-- ===================== Datos de cada área =====================
for _, area in ipairs(AREAS) do
    local placeId = PLACE_IDS[area.name]
    local contained = Registry:GetContained(placeId)
    local subs, npcs = 0, 0
    for subName, sub in pairs(area.data.subzones) do
        subs = subs + 1
        npcs = npcs + #(sub.npcs or {})
    end
    check(area.name .. ": están sus " .. area.subzones .. " subzonas y sus " .. area.npcs .. " NPC",
        subs == area.subzones and npcs == area.npcs
            and (function()
                local nSub = 0
                for _, id in ipairs(contained) do if id:find("^subzone:") then nSub = nSub + 1 end end
                return nSub == area.subzones
            end)())
end
check("Contained de Dun Morogh: sus 21 subzonas y la ciudad de Forjaz (located_in)",
    #Registry:GetContained("zone:dun_morogh") == 22 and (function()
        for _, id in ipairs(Registry:GetContained("zone:dun_morogh")) do if id == "city:ironforge" then return true end end
    end)())
check("Contained de Forjaz: sus 7 subzonas", #Registry:GetContained("city:ironforge") == 7)
check("Contained de Loch Modan: sus 12 subzonas", #Registry:GetContained("zone:loch_modan") == 12)
check("Contained del continente: las dos zonas y la ciudad", table.concat(Registry:GetContained(CONTINENT_ID), ",")
    == "city:ironforge,zone:dun_morogh,zone:loch_modan")
check("Contained de Coldridge Valley: Grelin y Sten", table.concat(Registry:GetContained("subzone:coldridge_valley"), ",")
    == "npc:grelin_whitebeard,npc:sten_stoutarm")

-- ===================== Campos específicos de NPC =====================
check("cada NPC conserva exactamente su npcID y su displayID originales, como números distintos",
    (function()
        local n = 0
        for _, area in ipairs(AREAS) do
            for _, sub in pairs(area.data.subzones) do
                for _, npc in ipairs(sub.npcs or {}) do
                    local e = Registry:Get(NPC_IDS[npc.name])
                    if e.npcID ~= npc.npcID or e.displayID ~= npc.displayID then return false end
                    if type(e.npcID) ~= "number" or type(e.displayID) ~= "number" or e.npcID == e.displayID then return false end
                    n = n + 1
                end
            end
        end
        return n == 9
    end)())
check("valores concretos de npcID/displayID (anclados a mano a lo que dice la fuente)",
    Registry:Get("npc:grelin_whitebeard").npcID == 786 and Registry:Get("npc:grelin_whitebeard").displayID == 1354
        and Registry:Get("npc:king_magni_bronzebeard").npcID == 2784
        and Registry:Get("npc:king_magni_bronzebeard").displayID == 3597
        and Registry:Get("npc:high_tinker_mekkatorque").npcID == 7937
        and Registry:Get("npc:high_tinker_mekkatorque").displayID == 7006)

-- ===================== Separación canónico / presentación =====================
local CANONICAL_KEYS = { id = true, type = true, parent = true, located_in = true, related_to = true,
    npcID = true, displayID = true }
check("las entidades solo llevan campos canónicos: ni textos, ni nombres, ni coordenadas, ni claves de presentación",
    (function()
        for _, e in ipairs(Registry:GetAll()) do
            for key in pairs(e) do if not CANONICAL_KEYS[key] then return false, key end end
            if e.type ~= "npc" and (e.npcID ~= nil or e.displayID ~= nil) then return false end
        end
        return true
    end)())
check("las coordenadas de los NPC (x, y, radius) NO se han migrado (el esquema no las admite)",
    (function()
        for _, e in ipairs(Registry:GetAll(("npc"))) do
            if e.x ~= nil or e.y ~= nil or e.radius ~= nil then return false end
        end
        return true
    end)())
check("no se usan nameKey, descriptionKey ni textKey: la clave de presentación por defecto es el ID",
    (function()
        for _, e in ipairs(Registry:GetAll()) do
            if e.nameKey or e.descriptionKey or e.textKey then return false end
        end
        return true
    end)())

-- ===================== Textos preservados literalmente =====================
-- Desde la Fase 4 los textos viven en Chronicle.Localization (idioma esES). Se reconstruye aquí
-- una tabla id -> campos con GetExact (sin fallback) para comparar con la referencia original
-- exactamente igual que antes.
local Loc = Chronicle.Localization
local Text = {}
for _, id in ipairs(Loc:GetIds("esES")) do
    Text[id] = {}
    for _, field in ipairs({ "name", "description", "hint", "race", "role" }) do
        Text[id][field] = Loc:GetExact(id, field, "esES")
    end
end
check("los textos migrados están registrados en Localization (esES) y el contenedor provisional LegacyText ya no existe",
    Loc:HasLanguage("esES") and Chronicle.LegacyText == nil)

local function sameText(id, field, expected)
    local entry = Text[id]
    if expected == nil then return entry ~= nil and entry[field] == nil end
    return entry ~= nil and entry[field] == expected
end

check("hay texto para cada entidad registrada y ninguno huérfano",
    (function()
        for _, id in ipairs(Registry:GetIds()) do if Text[id] == nil then return false end end
        for id in pairs(Text) do if not Registry:Has(id) then return false end end
        return count(Text) == 53
    end)())

check("continente: nombre y descripción idénticos a la fuente",
    sameText(CONTINENT_ID, "name", "Reinos del Este")
        and sameText(CONTINENT_ID, "description", Ref.continents["Reinos del Este"].text)
        and sameText(CONTINENT_ID, "hint", nil))

for _, area in ipairs(AREAS) do
    local placeId = PLACE_IDS[area.name]
    check(area.name .. ": nombre y descripción del lugar idénticos a la fuente (sin pista, como en la fuente)",
        sameText(placeId, "name", area.name) and sameText(placeId, "description", area.data.text)
            and sameText(placeId, "hint", nil) and area.data.hint == nil)

    check(area.name .. ": nombre, descripción y pista de cada subzona idénticos a la fuente",
        (function()
            for subName, sub in pairs(area.data.subzones) do
                local id = SUBZONE_IDS[subName]
                if not (sameText(id, "name", subName) and sameText(id, "description", sub.text)
                    and sameText(id, "hint", sub.hint)) then
                    return false, subName
                end
            end
            return true
        end)())

    check(area.name .. ": nombre, descripción, pista, raza y rol de cada NPC idénticos a la fuente",
        (function()
            for _, sub in pairs(area.data.subzones) do
                for _, npc in ipairs(sub.npcs or {}) do
                    local id = NPC_IDS[npc.name]
                    if not (sameText(id, "name", npc.name) and sameText(id, "description", npc.text)
                        and sameText(id, "hint", npc.hint) and sameText(id, "race", npc.race)
                        and sameText(id, "role", npc.role)) then
                        return false, npc.name
                    end
                end
            end
            return true
        end)())
end

check("las subzonas y los NPC de la fuente sin pista/raza/rol tampoco los tienen aquí (nada inventado)",
    (function()
        for _, e in ipairs(Registry:GetAll()) do
            local entry = Text[e.id]
            if e.type ~= "npc" and (entry.race ~= nil or entry.role ~= nil) then return false end
            for field in pairs(entry) do
                if field ~= "name" and field ~= "description" and field ~= "hint" and field ~= "race" and field ~= "role" then
                    return false
                end
            end
        end
        return true
    end)())

-- Anclas escritas a mano (copiadas de los ficheros originales): protegen frente a un fallo
-- común de la referencia y de la migración.
check("ancla literal: descripción de Grelin Whitebeard",
    Text["npc:grelin_whitebeard"].description == "Grelin Whitebeard es uno de los pocos gnomos que sobrevivió a la "
        .. "catástrofe de Gnomeregan y decidió quedarse cerca de la entrada, "
        .. "cuidando de los refugiados y de los jóvenes gnomos que llegan a "
        .. "Coldridge Valley. Habla con reverencia y tristeza de la ciudad "
        .. "perdida, y suele ser el primer contacto de un gnomo novato con la "
        .. "historia real de su pueblo.")
check("ancla literal: descripción de Dun Morogh",
    Text["zone:dun_morogh"].description == "Dun Morogh es la tierra ancestral del clan Bronzebeard, un reino de "
        .. "montañas nevadas y túneles excavados bajo el hielo. Aquí se alza Forjaz "
        .. "(Ironforge), la gran ciudad-fortaleza de los enanos, y en sus valles se "
        .. "refugiaron también los gnomos tras la caída de Gnomeregan. Es, para "
        .. "muchos, el primer paisaje que ven quienes empiezan su viaje como enano o "
        .. "gnomo.")
check("ancla literal: pista de Gol'Bolar Quarry (con apóstrofo) y descripción de Ironband's Excavation Site",
    Text["subzone:golbolar_quarry"].hint == "Una cantera al sureste de la zona, tomada por troggs."
        and Text["subzone:ironbands_excavation_site"].description == "En su yacimiento de excavación, el Prospector Ironband "
            .. "recluta aventureros algo más curtidos para investigar las "
            .. "ruinas de Uldaman, una de las expediciones arqueológicas "
            .. "más ambiciosas de todo el pueblo enano.")
check("ancla literal: el rol de Mekkatorque conserva su paréntesis y el texto de Forjaz su 'Forjaz'",
    Text["npc:high_tinker_mekkatorque"].role == "Alto Manitas (líder del gobierno gnomo en el exilio)"
        and Text["city:ironforge"].description:find("Forjaz es la gran ciudad-fortaleza de los enanos", 1, true) == 1)
check("los textos migrados no se han normalizado: conservan tildes, ñ y puntuación originales",
    Text["subzone:coldridge_valley"].description:find("Gnomeregan. Es un lugar pequeño pero cargado de historia", 1, true) ~= nil
        and Text["subzone:coldridge_valley"].description:sub(-1) == "."
        and not Text["zone:loch_modan"].description:find("  ", 1, true))

-- ===================== Lo que NO se migra =====================
check("fuera de alcance: no hay entidades de Kalimdor, de otras capitales ni de lore",
    not Registry:Has("continent:kalimdor") and not Registry:Has("city:stormwind") and not Registry:Has("city:undercity")
        and not Registry:Has("city:orgrimmar") and Text["continent:kalimdor"] == nil
        and #Registry:GetIds("lore") == 0)
check("no se han creado NPC candidatos de los TODO de la fuente (sin npcID ni datos verificados)",
    not Registry:Has("npc:rejold_barleybrew") and not Registry:Has("npc:beldin_steelgrill")
        and not Registry:Has("npc:prospector_ironband"))

-- ===================== Independencia del orden de carga =====================
-- Los ficheros de datos no dependen de cargarse en un orden concreto: el Registry acepta las
-- entidades y es Registry:Validate() quien comprueba las referencias. Se cargan al revés.
LoadAddon({ "^Data/Entities/", "^Localization/esES/" })
local byName = {}
for _, file in ipairs(ADDON_FILES) do byName[file.name] = file end
for _, name in ipairs({ "Data/Entities/Npcs.lua", "Data/Entities/Subzones.lua", "Data/Entities/Geography.lua" }) do
    assert(load(byName[name].source, "@" .. name))()
end
local reversed = Chronicle.Registry:Validate()
check("cargando los ficheros de entidades en orden inverso (NPC, subzonas, geografía) el conjunto sigue siendo válido",
    Chronicle.Registry:Count() == 53 and reversed.ok == true and #reversed.errors == 0 and #Chronicle.Registry:GetRejected() == 0)

LoadAddon({ "^Data/Entities/", "^Localization/esES/" })
assert(load(byName["Data/Entities/Npcs.lua"].source, "@Npcs"))()
local partial = Chronicle.Registry:Validate()
check("con solo los NPC cargados, Validate detecta las referencias a subzonas que aún no existen",
    partial.ok == false and contains(partial.errors, "located_in: 'subzone:coldridge_valley' no está registrada")
        and Chronicle.Registry:Count() == 9 and #Chronicle.Registry:GetRejected() == 0)

-- ===================== Una referencia rota o un duplicado impiden anunciar el arranque =====================
announced = Boot(function()
    Chronicle.Registry:Register({ id = "npc:fantasma", type = "npc", located_in = "subzone:no_existe" })
end)
check("una referencia located_in rota impide anunciar el arranque y queda diagnosticada",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Registry ~= nil
        and Chronicle.Init.failed.Registry:find("subzone:no_existe", 1, true) ~= nil
        and Chronicle.Init.failed.Registry:find("no está registrada", 1, true) ~= nil
        and Chronicle.Registry:IsValidated() == false and contains(ReportedErrors, "Registry"))

announced = Boot(function()
    Chronicle.Registry:Register({ id = "zone:isla_fantasma", type = "zone", parent = "continent:no_existe" })
end)
check("un parent roto impide anunciar el arranque", Chronicle.Init.ready == false and announced == 0
    and Chronicle.Init.failed.Registry:find("continent:no_existe", 1, true) ~= nil)

announced = Boot(function()
    Chronicle.Registry:Register({ id = "subzone:kharanos", type = "subzone", parent = "zone:dun_morogh",
        related_to = { "lore:no_existe" } })
end)
check("un ID duplicado (aunque traiga datos distintos) impide anunciar el arranque y NO sobrescribe el dato migrado",
    Chronicle.Init.ready == false and announced == 0
        and Chronicle.Init.failed.Registry:find("ID duplicado", 1, true) ~= nil
        and Chronicle.Registry:Get("subzone:kharanos").related_to == nil)

announced = Boot(function()
    Chronicle.Registry:Register({ id = "zone:dun_morogh", type = "zone", parent = "continent:eastern_kingdoms" })
end)
check("un duplicado idéntico a uno migrado también impide anunciar el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Registry:find("ID duplicado", 1, true) ~= nil)

announced = Boot(function()
    Chronicle.Registry:Register({ id = "zone:isla_fantasma", type = "zone" }) -- sin el parent obligatorio
end)
check("una entidad estructuralmente inválida añadida a los datos impide anunciar el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Registry:find("parent: es obligatorio", 1, true) ~= nil)

announced = Boot(function()
    Chronicle.Registry:Register({ id = "continent:eastern_kingdoms_dup", type = "continent", related_to = { "zone:dun_morogh" } })
end)
check("control: una entidad extra válida, con referencias que existen, NO impide el arranque (los fallos anteriores se deben al dato roto)",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Registry:Count() == 54)

-- ===================== Los datos no tocan el estado persistente =====================
check("los ficheros de datos no referencian ChronicleCharDB ni Chronicle.State en su código",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name:find("^Data/Entities/") or file.name:find("^Localization/esES/") then
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") and (line:find("ChronicleCharDB", 1, true)
                        or line:find("Chronicle.State", 1, true)) then
                        return false
                    end
                end
            end
        end
        return true
    end)())
check("las entidades se registran solo a través de Chronicle.Registry (ninguna escritura directa en tablas internas)",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name:find("^Data/Entities/") then
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") and line:find("%S") and not line:match("^Registry:Register%(")
                        and not line:match("^local Registry = Chronicle%.Registry$")
                        and not line:match("^Chronicle = Chronicle or {}$")
                        and not line:match("^[%s}]") and not line:match("^%s*$") then
                        return false, line
                    end
                end
            end
        end
        return true
    end)())
