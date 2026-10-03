-- Escenarios de prueba de la navegación y las páginas del Codex (Fase 9). Dos niveles, que no hay que confundir:
--   · LÓGICA (CodexModel): el árbol, las páginas, los breadcrumbs y el historial, sobre el catálogo real y sobre catálogos
--     sintéticos (mundos pequeños con casos que el catálogo actual no tiene: textKey, sin textos, tipos futuros...).
--   · INTERFAZ con el mock estricto: se pulsan los botones reales (OnClick) y se miran los textos y estados de los widgets.
-- Esto NO demuestra que la ventana se vea, se desplace o se pueda pulsar bien en el cliente real de Classic Era.

local realCreateFrame = CreateFrame
local created = {}

local function Boot(prepare)
    created = {}
    CreateFrame = function(kind, name, parent, template)
        local frame = realCreateFrame(kind, name, parent, template)
        created[#created + 1] = { kind = kind, name = name, template = template, frame = frame, parent = parent }
        return frame
    end
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    FireEvent("ADDON_LOADED", "Chronicle")
    CreateFrame = realCreateFrame
end

local function ids(list)
    local out = {}
    for i, item in ipairs(list) do out[i] = type(item) == "table" and item.id or item end
    return out
end
local function joined(list) return table.concat(ids(list), ",") end
local function setOf(list)
    local set = {}
    for _, id in ipairs(list) do set[id] = true end
    return set
end
local function contains(list, id) return setOf(ids(list))[id] == true end

-- Un mundo sintético: Registry y Localization propios.
local function World(entities, texts)
    local registry = Chronicle.Registry.New(Chronicle.Schema)
    for _, entity in ipairs(entities) do
        local ok, err = registry:Register(entity)
        if not ok then
            error("entidad de prueba rechazada (" .. tostring(entity.id) .. "): "
                .. (type(err) == "table" and table.concat(err.errors or err, "; ") or tostring(err)))
        end
    end
    local localization = Chronicle.Localization.New(registry)
    for id, entry in pairs(texts or {}) do
        local ok, err = localization:Add("esES", id, entry)
        if not ok then error("texto de prueba rechazado: " .. tostring(err)) end
    end
    return registry, localization
end
local function ModelOf(registry, localization, onChange)
    return Chronicle.CodexModel.New({ registry = registry, localization = localization, onChange = onChange })
end

-- ===================== LÓGICA sobre el catálogo real =====================
Boot()
local registry, localization = Chronicle.Registry, Chronicle.Localization
local model = ModelOf(registry, localization)

local allEntities = registry:GetAll()
-- Abre todo el árbol (independiente de la interfaz) y devuelve las filas.
local function ExpandAll(m)
    for _ = 1, 10 do
        local changed = false
        for _, row in ipairs(m:GetRows()) do
            if row.hasChildren and not row.expanded then m:SetExpanded(row.id, true); changed = true end
        end
        if not changed then break end
    end
    return m:GetRows()
end

local rows0 = model:GetRows()
check("1. el árbol empieza con las raíces reales de Registry (entidades sin ancla) y contraído",
    #rows0 == 1 and rows0[1].id == "continent:eastern_kingdoms" and rows0[1].depth == 0 and rows0[1].hasChildren == true
        and rows0[1].expanded == false)
local expandedRows = ExpandAll(model)
check("1b. con todo expandido aparecen TODAS las entidades registradas, cada una una sola vez (nada se oculta ni se duplica)",
    #expandedRows == registry:Count() and (function()
        local seen = {}
        for _, row in ipairs(expandedRows) do
            if seen[row.id] then return false end
            seen[row.id] = true
        end
        for _, entity in ipairs(allEntities) do if not seen[entity.id] then return false, entity.id end end
        return true
    end)())
check("2. las relaciones `parent` del Registry se representan: los hijos de cada nodo son exactamente las entidades cuyo parent es ese nodo",
    (function()
        for _, entity in ipairs(allEntities) do
            local expected = {}
            for _, other in ipairs(allEntities) do
                if other.parent == entity.id or (other.parent == nil and other.located_in == entity.id) then expected[#expected + 1] = other.id end
            end
            table.sort(expected)
            local got = model:GetChildren(entity.id)
            table.sort(got)
            if table.concat(got, ",") ~= table.concat(expected, ",") then return false, entity.id end
        end
        return true
    end)())
check("2b. la profundidad de las filas sigue la cadena parent: continente 0, zona/ciudad 1, subzona 2, NPC 3 (bajo su subzona)",
    (function()
        local depthOf = {}
        for _, row in ipairs(expandedRows) do depthOf[row.id] = row.depth end
        return depthOf["continent:eastern_kingdoms"] == 0 and depthOf["zone:dun_morogh"] == 1 and depthOf["city:ironforge"] == 1
            and depthOf["subzone:coldridge_valley"] == 2 and depthOf["npc:grelin_whitebeard"] == 3
    end)())
check("3. `located_in` NO se convierte en `parent`: Forjaz (en Dun Morogh, pero ciudad del continente) NO cuelga de Dun Morogh en el árbol",
    not contains(model:GetChildren("zone:dun_morogh"), "city:ironforge") and contains(model:GetChildren("continent:eastern_kingdoms"), "city:ironforge")
        and registry:Get("city:ironforge").located_in == "zone:dun_morogh")
check("3b. los NPC (sin parent) cuelgan de su `located_in`, y ningún NPC aparece como hijo geográfico de otra cosa",
    contains(model:GetChildren("subzone:coldridge_valley"), "npc:grelin_whitebeard")
        and (function()
            for _, entity in ipairs(allEntities) do
                if entity.type == "npc" and #model:GetChildren(entity.id) ~= 0 then return false end
            end
            return true
        end)())
check("3c. la relación related_to (Dun Morogh <-> Loch Modan) tampoco crea jerarquía: no son padre e hijo",
    not contains(model:GetChildren("zone:dun_morogh"), "zone:loch_modan") and not contains(model:GetChildren("zone:loch_modan"), "zone:dun_morogh"))
check("3d. el breadcrumb de Forjaz sigue SOLO `parent` (continente > Forjaz), nunca pasa por Dun Morogh (located_in)",
    joined(model:GetBreadcrumbs("city:ironforge")) == "continent:eastern_kingdoms,city:ironforge")
check("3e. la ubicación de Forjaz se da como dato contextual aparte (page.location = Dun Morogh), no como ruta",
    model:GetPage("city:ironforge").location.id == "zone:dun_morogh")

-- Nombres desde Localization
check("4. los nombres visibles salen de Localization para todas las entidades",
    (function()
        for _, row in ipairs(expandedRows) do
            local expected = localization:Get(row.id, "name")
            if expected and (row.name ~= expected or row.nameIsFallback) then return false, row.id end
        end
        return true
    end)())
check("4b. el modelo consulta de verdad a Localization: con otro Localization los nombres cambian",
    (function()
        local stub = { Get = function(_, id, field) return field == "name" and ("N<" .. id .. ">") or nil end }
        local m = ModelOf(registry, stub)
        return m:GetName("zone:dun_morogh") == "N<zone:dun_morogh>" and m:GetPage("zone:dun_morogh").name == "N<zone:dun_morogh>"
    end)())

-- Entidades sin textos
do
    local reg, loc = World({
        { id = "continent:alpha", type = "continent" },
        { id = "zone:beta", type = "zone", parent = "continent:alpha" },
        { id = "npc:gamma", type = "npc", located_in = "zone:beta" },
    }, { ["continent:alpha"] = { name = "Alfa" } })
    local m = ModelOf(reg, loc)
    ExpandAll(m)
    local list = m:GetRows()
    check("5. las entidades sin textos siguen en el árbol y se pueden seleccionar; su nombre es el fallback documentado (el propio ID, atenuado)",
        #list == 3 and list[1].name == "Alfa" and list[1].nameIsFallback == false and list[2].name == "zone:beta" and list[2].nameIsFallback == true
            and list[3].name == "npc:gamma" and m:Select("npc:gamma") == true and m:GetCurrent() == "npc:gamma")
    local page = m:GetPage("npc:gamma")
    check("5b. su página existe con solo lo disponible: nombre (fallback), tipo y ubicación; sin descripción, cuerpo ni detalles inventados",
        page.name == "npc:gamma" and page.nameIsFallback == true and page.typeLabel == "Personaje" and page.description == nil
            and page.body == nil and #page.details == 0 and page.location.id == "zone:beta" and page.location.nameIsFallback == true)
    local blank = World({ { id = "continent:vacio", type = "continent" } }, { ["continent:vacio"] = { name = "" } })
    check("5c. un nombre vacío cuenta como ausente: se usa el fallback en vez de mostrar una fila vacía",
        select(1, ModelOf(blank, (select(2, World({ { id = "continent:vacio", type = "continent" } }, { ["continent:vacio"] = { name = "" } })))):GetName("continent:vacio")) == "continent:vacio")
end

-- Selección, expansión, orden
do
    local m = ModelOf(registry, localization)
    check("6. seleccionar un nodo fija la página actual; esa página es la del nodo",
        m:Select("zone:dun_morogh") == true and m:GetCurrent() == "zone:dun_morogh" and m:GetPage(m:GetCurrent()).type == "zone")
    check("6b. seleccionar expande sus ancestros para que su fila sea visible, y solo la fila elegida está marcada como seleccionada",
        (function()
            m:Select("subzone:kharanos")
            local selected, count = nil, 0
            for _, row in ipairs(m:GetRows()) do if row.selected then selected = row.id; count = count + 1 end end
            return selected == "subzone:kharanos" and count == 1 and m:IsExpanded("zone:dun_morogh") and m:IsExpanded("continent:eastern_kingdoms")
        end)())
    local before = m:GetCurrent()
    local sizeBefore = #m:GetRows()
    m:Toggle("zone:dun_morogh") -- contraer
    check("7. contraer un nodo no cambia la página seleccionada ni el historial; solo cambian las filas visibles",
        m:GetCurrent() == before and #m:GetHistory().ids == 2 and #m:GetRows() < sizeBefore and not m:IsExpanded("zone:dun_morogh"))
    m:Toggle("zone:dun_morogh") -- expandir
    check("7b. expandir tampoco cambia la página; Toggle devuelve el nuevo estado",
        m:GetCurrent() == before and m:IsExpanded("zone:dun_morogh") and select(2, m:Toggle("zone:dun_morogh")) == false and m:GetCurrent() == before)
    check("7c. una entidad sin hijos no se expande (devuelve no_children) pero se puede seleccionar",
        select(2, m:Toggle("npc:grelin_whitebeard")) == "no_children" and m:Select("npc:grelin_whitebeard") == true)

    local a, b = ExpandAll(ModelOf(registry, localization)), ExpandAll(ModelOf(registry, localization))
    check("8. el orden es determinista entre construcciones", joined(a) == joined(b))
    local order = ids(model:GetChildren("continent:eastern_kingdoms"))
    check("8b. orden por tipo (zonas antes que ciudades) y luego por ID", table.concat(order, ",") == "zone:dun_morogh,zone:loch_modan,city:ironforge")
    local list1 = {
        { id = "continent:c", type = "continent" }, { id = "city:z_city", type = "city", parent = "continent:c" },
        { id = "zone:b_zone", type = "zone", parent = "continent:c" }, { id = "zone:a_zone", type = "zone", parent = "continent:c" },
        { id = "subzone:b_sub", type = "subzone", parent = "zone:a_zone" }, { id = "subzone:a_sub", type = "subzone", parent = "zone:a_zone" },
        { id = "lore:l1", type = "lore", located_in = "zone:a_zone" }, { id = "npc:n1", type = "npc", located_in = "zone:a_zone" },
    }
    local list2 = {}
    for i = #list1, 1, -1 do list2[#list2 + 1] = list1[i] end
    local reg1, loc1 = World(list1)
    local reg2, loc2 = World(list2)
    check("8c. el orden no depende del orden de registro ni de los nombres: por tipo (zonas, ciudad; subzonas, personaje, lore) y por ID dentro de cada tipo",
        joined(ModelOf(reg1, loc1):GetChildren("continent:c")) == "zone:a_zone,zone:b_zone,city:z_city"
            and joined(ModelOf(reg1, loc1):GetChildren("zone:a_zone")) == "subzone:a_sub,subzone:b_sub,npc:n1,lore:l1"
            and joined(ModelOf(reg2, loc2):GetChildren("zone:a_zone")) == joined(ModelOf(reg1, loc1):GetChildren("zone:a_zone"))
            and joined(ModelOf(reg2, loc2):GetChildren("continent:c")) == joined(ModelOf(reg1, loc1):GetChildren("continent:c")))
end

-- Breadcrumbs
do
    local m = ModelOf(registry, localization)
    check("9. los breadcrumbs de una subzona son la jerarquía real: continente > zona > subzona",
        joined(m:GetBreadcrumbs("subzone:coldridge_valley")) == "continent:eastern_kingdoms,zone:dun_morogh,subzone:coldridge_valley")
    check("9b. cada elemento lleva el nombre de Localization", m:GetBreadcrumbs("zone:dun_morogh")[2].name == localization:Get("zone:dun_morogh", "name"))
    check("9c. un NPC no tiene ruta jerárquica inventada: su breadcrumb es solo él mismo (su ubicación es dato aparte)",
        joined(m:GetBreadcrumbs("npc:grelin_whitebeard")) == "npc:grelin_whitebeard" and m:GetPage("npc:grelin_whitebeard").location.id == "subzone:coldridge_valley")
    check("9d. un continente es su propia ruta; un ID inexistente no tiene ruta", joined(m:GetBreadcrumbs("continent:eastern_kingdoms")) == "continent:eastern_kingdoms"
        and #m:GetBreadcrumbs("zone:no_existe") == 0)
end

-- Historial
do
    local m = ModelOf(registry, localization)
    m:Select("zone:dun_morogh"); m:Select("zone:loch_modan"); m:Select("city:ironforge")
    check("10. el historial registra las páginas en orden y se puede retroceder y avanzar",
        joined(m:GetHistory().ids) == "zone:dun_morogh,zone:loch_modan,city:ironforge" and m:CanBack() and not m:CanForward()
            and m:Back() == true and m:GetCurrent() == "zone:loch_modan" and m:Back() == true and m:GetCurrent() == "zone:dun_morogh"
            and not m:CanBack() and m:CanForward() and m:Forward() == true and m:GetCurrent() == "zone:loch_modan")
    check("10b. retroceder y avanzar no modifican la lista, solo la posición", joined(m:GetHistory().ids) == "zone:dun_morogh,zone:loch_modan,city:ironforge"
        and m:GetHistory().index == 2)
    check("10c. fuera de los extremos Back/Forward devuelven false, 'no_history' y no cambian nada",
        (function()
            local n = ModelOf(registry, localization)
            local r1, r2 = n:Back()
            local f1, f2 = n:Forward()
            return r1 == false and r2 == "no_history" and f1 == false and f2 == "no_history" and n:GetCurrent() == nil
        end)())
    m:Select("subzone:kharanos") -- estando en loch_modan, con ironforge «por delante»
    check("11. seleccionar una página nueva tras retroceder DESCARTA lo que había por delante y añade la nueva a continuación",
        joined(m:GetHistory().ids) == "zone:dun_morogh,zone:loch_modan,subzone:kharanos" and not m:CanForward() and m:GetHistory().index == 3
            and m:Back() == true and m:GetCurrent() == "zone:loch_modan")
    check("11b. seleccionar la página actual no duplica la entrada ni notifica un cambio",
        (function()
            local changes = 0
            local n = ModelOf(registry, localization, function() changes = changes + 1 end)
            n:Select("zone:dun_morogh"); local c1 = changes
            n:Select("zone:dun_morogh"); n:Select("zone:dun_morogh")
            return #n:GetHistory().ids == 1 and changes == c1
        end)())
    check("11c. volver atrás y seleccionar lo mismo que ya hay delante cuenta como página nueva (se reescribe el futuro)",
        (function()
            local n = ModelOf(registry, localization)
            n:Select("zone:dun_morogh"); n:Select("zone:loch_modan"); n:Back()
            n:Select("zone:loch_modan")
            return joined(n:GetHistory().ids) == "zone:dun_morogh,zone:loch_modan" and n:GetHistory().index == 2 and not n:CanForward()
        end)())
    check("11d. el historial está acotado (100) y descarta lo más antiguo sin romperse",
        (function()
            local entities = { { id = "continent:big", type = "continent" } }
            for i = 1, 120 do entities[#entities + 1] = { id = "zone:z" .. i, type = "zone", parent = "continent:big" } end
            local reg, loc = World(entities)
            local n = ModelOf(reg, loc)
            for i = 1, 120 do n:Select("zone:z" .. i) end
            local history = n:GetHistory()
            return #history.ids == 100 and history.ids[1] == "zone:z21" and history.ids[100] == "zone:z120" and history.index == 100
        end)())
    check("11e. el historial es de la sesión: un modelo nuevo empieza vacío y no hay nada en ChronicleCharDB",
        ModelOf(registry, localization):GetCurrent() == nil and #ModelOf(registry, localization):GetHistory().ids == 0)
end

-- Páginas: descripción y cuerpo
do
    local reg, loc = World({
        { id = "continent:world", type = "continent" },
        { id = "zone:valley", type = "zone", parent = "continent:world" },
        { id = "lore:valley_history", type = "lore", located_in = "zone:valley", textKey = "lore:valley_history_text" },
        { id = "lore:valley_history_text", type = "lore", located_in = "zone:valley" },
        { id = "lore:sin_cuerpo", type = "lore", located_in = "zone:valley" },
        { id = "lore:huerfano", type = "lore", located_in = "zone:valley", textKey = "lore:no_registrada" },
        { id = "npc:guide", type = "npc", located_in = "zone:valley" },
    }, {
        ["lore:valley_history"] = { name = "Historia del valle", description = "Resumen corto." },
        ["lore:valley_history_text"] = { description = "Este es el artículo largo del valle." },
        ["lore:sin_cuerpo"] = { name = "Sin cuerpo", description = "Solo descripción." },
        ["lore:huerfano"] = { name = "Huérfano", description = "Descripción presente." },
        ["npc:guide"] = { name = "Guía", description = "Un guía.", race = "Enano", role = "Guía de la zona", hint = "Pista de descubrimiento" },
    })
    local m = ModelOf(reg, loc)
    local page = m:GetPage("lore:valley_history")
    check("12. la página distingue la descripción corta y el cuerpo del artículo (textKey): son textos diferentes y cada uno en su campo",
        page.description == "Resumen corto." and page.body == "Este es el artículo largo del valle." and page.bodyUnresolved == false
            and page.type == "lore" and page.typeLabel == "Lore")
    local plain = m:GetPage("lore:sin_cuerpo")
    check("12b. sin textKey no hay cuerpo: la descripción NO se usa como cuerpo", plain.description == "Solo descripción." and plain.body == nil and plain.bodyUnresolved == false)
    local orphan = m:GetPage("lore:huerfano")
    check("12c. con textKey que Localization no resuelve: no hay cuerpo, se marca bodyUnresolved y la descripción no lo sustituye",
        orphan.description == "Descripción presente." and orphan.body == nil and orphan.bodyUnresolved == true)
    local npc = m:GetPage("npc:guide")
    check("12d. un NPC muestra raza y rol; la pista de descubrimiento (hint) no se muestra todavía",
        #npc.details == 2 and npc.details[1].label == "Raza" and npc.details[1].value == "Enano" and npc.details[2].label == "Rol"
            and npc.details[2].value == "Guía de la zona" and (function()
                for _, d in ipairs(npc.details) do if d.value == "Pista de descubrimiento" then return false end end
                return true
            end)())
    check("12e. la página no contiene campos de otras entidades (no todas tienen los mismos campos): una zona no trae raza, rol ni cuerpo",
        #m:GetPage("zone:valley").details == 0 and m:GetPage("zone:valley").body == nil and m:GetPage("zone:valley").description == nil)
    local reg2, loc2 = World({ { id = "continent:k", type = "continent", nameKey = "continent:k_texts", descriptionKey = "continent:k_texts" },
        { id = "continent:k_texts", type = "continent" } },
        { ["continent:k_texts"] = { name = "Nombre por clave", description = "Descripción por clave" }, ["continent:k"] = { name = "Nombre propio" } })
    check("13. nameKey/descriptionKey de la entidad se respetan antes que su propio ID",
        ModelOf(reg2, loc2):GetName("continent:k") == "Nombre por clave" and ModelOf(reg2, loc2):GetPage("continent:k").description == "Descripción por clave")
    local reg3, loc3 = World({ { id = "continent:k", type = "continent", nameKey = "continent:no_registrada" } }, { ["continent:k"] = { name = "Nombre propio" } })
    check("13b. si la clave de presentación no resuelve, se usa el ID de la entidad antes del fallback", ModelOf(reg3, loc3):GetName("continent:k") == "Nombre propio")
    local huge = string.rep("Texto largo de lore. ", 2000)
    local regH, locH = World({ { id = "continent:h", type = "continent", textKey = nil } }, { ["continent:h"] = { name = "Largo", description = huge } })
    check("13c. los textos largos no se descartan ni se truncan por la lógica de presentación",
        ModelOf(regH, locH):GetPage("continent:h").description == huge and #huge == 42000)
end

-- IDs inexistentes y tipos futuros
do
    local m = ModelOf(registry, localization)
    local results = {}
    for i, call in ipairs({
        function() return m:Select("zone:no_existe") end, function() return m:Select(nil) end, function() return m:Select(42) end,
        function() return m:Select("") end, function() return m:Toggle("zone:no_existe") end, function() return m:Toggle(nil) end,
        function() return m:GetPage("x") end, function() return m:GetPage(nil) end, function() return m:GetName("x") end,
        function() return m:GetChildren("x") end, function() return m:GetBreadcrumbs(nil) end, function() return m:SetExpanded("x", true) end,
    }) do
        local ok, r1, r2 = pcall(call)
        results[i] = { ok = ok, r1 = r1, r2 = r2 }
    end
    check("14. IDs inexistentes o inválidos se manejan sin errores: Select/Toggle devuelven false y el motivo, las consultas devuelven nil o vacío",
        results[1].ok and results[1].r1 == false and results[1].r2 == "unknown_id" and results[2].r2 == "invalid_id" and results[3].r2 == "invalid_id"
            and results[4].r2 == "invalid_id" and results[5].r1 == false and results[5].r2 == "unknown_id" and results[6].r2 == "unknown_id"
            and results[7].r1 == nil and results[8].r1 == nil and results[9].r1 == nil and #results[10].r1 == 0 and #results[11].r1 == 0
            and results[12].r2 == "unknown_id" and (function() for _, r in ipairs(results) do if not r.ok then return false end end return true end)())
    check("14b. un intento fallido no deja huellas: ni página, ni historial, ni cambios", m:GetCurrent() == nil and #m:GetHistory().ids == 0)
    local gone = {}
    local proxy = setmetatable({}, { __index = function(_, key)
        if key == "Has" then return function(_, id) return not gone[id] and registry:Has(id) end end
        return function(_, ...) return registry[key](registry, ...) end
    end })
    local n = ModelOf(proxy, localization)
    n:Select("zone:dun_morogh"); n:Select("zone:loch_modan"); n:Select("city:ironforge")
    gone["zone:loch_modan"] = true
    check("14c. el historial salta las entradas cuyo ID ya no existe (Atrás desde Forjaz va a Dun Morogh; Adelante no vuelve a una entidad inexistente)",
        n:Back() == true and n:GetCurrent() == "zone:dun_morogh" and n:Forward() == true and n:GetCurrent() == "city:ironforge")
    local regO = World({ { id = "zone:huerfana", type = "zone", parent = "continent:no_existe" } })
    local locO = Chronicle.Localization.New(regO)
    check("14d. una entidad cuyo ancla no está registrada aparece como raíz en vez de desaparecer en silencio",
        #ModelOf(regO, locO):GetRows() == 1 and ModelOf(regO, locO):GetRows()[1].id == "zone:huerfana")
    local regF, locF = World({ { id = "continent:c", type = "continent" } })
    local futureSchema = Chronicle.Schema.New({ continent = {}, zone = { parent = { types = { "continent" }, required = true } }, region = { parent = { types = { "continent" } } } })
    local regT = Chronicle.Registry.New(futureSchema)
    regT:Register({ id = "continent:c", type = "continent" })
    regT:Register({ id = "region:r", type = "region", parent = "continent:c" })
    local mT = ModelOf(regT, Chronicle.Localization.New(regT))
    mT:Toggle("continent:c")
    check("14e. un tipo futuro (no conocido por la interfaz) aparece igualmente, con su tipo como etiqueta y al final de su nivel",
        #mT:GetRows() == 2 and mT:GetRows()[2].id == "region:r" and mT:GetPage("region:r").typeLabel == "region")
    check("14f. una función onChange que falla no rompe al modelo",
        (function()
            local n2 = ModelOf(registry, localization, function() error("listener roto") end)
            return pcall(n2.Select, n2, "zone:dun_morogh") and n2:GetCurrent() == "zone:dun_morogh"
        end)())
end

-- ===================== INTERFAZ con el mock =====================
Boot()
-- Las filas del árbol se crean DESPUÉS del arranque (al expandir): el registro de frames sigue activo durante esta sección.
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    created[#created + 1] = { kind = kind, name = name, template = template, frame = frame, parent = parent }
    return frame
end
local win = _G["ChronicleCodexFrame"]
if not win then
    check("U0. el Codex crea su ventana al arrancar (sin ella no se puede comprobar la interfaz)", false)
    CreateFrame = realCreateFrame
    do return end
end
local codex = Chronicle.Codex
local navPane, contentPane
do
    local list = {}
    for _, entry in ipairs(created) do
        if entry.parent == win and entry.kind == "Frame" then list[#list + 1] = entry.frame end
    end
    navPane, contentPane = list[1], list[2]
end
local function scrollOf(pane)
    for _, entry in ipairs(created) do
        if entry.kind == "ScrollFrame" and entry.parent == pane then return entry.frame end
    end
end
local navScroll, pageScroll = scrollOf(navPane), scrollOf(contentPane)
local navChild, pageChild = navScroll.scrollChild, pageScroll.scrollChild
local toolbar
for _, entry in ipairs(created) do
    if entry.parent == contentPane and entry.kind == "Frame" then toolbar = entry.frame; break end
end
local function textOf(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.text ~= nil then return child.text, child end
    end
end
-- Pares (seleccionar, alternar) de las filas del árbol, en orden de creación; solo las visibles.
local function navRows()
    local rows, pending = {}, nil
    for _, entry in ipairs(created) do
        if entry.kind == "Button" and entry.parent == navChild then
            if not pending then
                pending = entry.frame
            else
                rows[#rows + 1] = { select = pending, toggle = entry.frame }
                pending = nil
            end
        end
    end
    local visible = {}
    for _, row in ipairs(rows) do
        if row.select.shown == true then visible[#visible + 1] = row end
    end
    return visible
end
local function rowNamed(name)
    for _, row in ipairs(navRows()) do
        if textOf(row.select) == name then return row end
    end
    return MISSING_ROW
end
local function names()
    local out = {}
    for _, row in ipairs(navRows()) do out[#out + 1] = textOf(row.select) end
    return out
end
local function nameOf(id) local name = localization:Get(id, "name"); return name end
local function toolbarButtons()
    local list = {}
    for _, entry in ipairs(created) do
        if entry.kind == "Button" and entry.parent == toolbar then list[#list + 1] = entry.frame end
    end
    return list
end
local function crumbs()
    local out = {}
    local list = toolbarButtons()
    for i = 3, #list do
        if list[i].shown == true then out[#out + 1] = list[i] end
    end
    return out
end
local function crumbNames()
    local out = {}
    for _, button in ipairs(crumbs()) do out[#out + 1] = textOf(button) end
    return out
end
local function page()
    local c = pageChild.children
    return { title = c[1], kind = c[2], location = c[3], details = c[4], description = c[5], rule = c[6], body = c[7], empty = c[8] }
end
local function click(frame)
    local handler = frame and frame.__scripts and frame.__scripts.OnClick
    if handler then handler(frame) end
end
-- Si una fila no existe, se devuelve una fila inerte para que el fallo salga como aserción y no como excepción.
local MISSING_FRAME = { __scripts = {}, children = {}, points = { {} }, shown = false }
local MISSING_ROW = { select = MISSING_FRAME, toggle = MISSING_FRAME }
local backButton, forwardButton = toolbarButtons()[1], toolbarButtons()[2]

check("U1. el Codex arranca con el árbol real: una fila (el continente) con su nombre de Localization, y la página vacía con una indicación discreta",
    #navRows() == 1 and names()[1] == nameOf("continent:eastern_kingdoms") and page().empty.shown == true and page().title.shown ~= true)
check("U1b. el árbol y la página usan los widgets esperados: zona con desplazamiento + rueda del ratón en las dos zonas",
    navScroll ~= nil and pageScroll ~= nil and navScroll.mouseWheel == true and pageScroll.mouseWheel == true
        and navScroll.__scripts.OnMouseWheel ~= nil and pageScroll.__scripts.OnMouseWheel ~= nil)
check("U1c. la ventana sigue oculta tras construir las vistas y Show() la muestra sin recrear nada",
    win:IsShown() == false and (function() local n = #created; codex:Show(); local ok = #created == n; codex:Hide(); return ok end)())

check("U1d. al empezar, sin historial, los botones Atrás y Adelante están atenuados",
    deepEqual(backButton.children[1].color, Chronicle.Theme:GetColor("TEXT_MUTED")) and deepEqual(forwardButton.children[1].color, Chronicle.Theme:GetColor("TEXT_MUTED")))

local continentRow = rowNamed(nameOf("continent:eastern_kingdoms"))
click(continentRow.toggle)
check("U2. expandir el continente (botón +/-) muestra sus hijos en el orden del modelo y NO cambia la página (sigue vacía)",
    #navRows() == 4 and names()[2] == nameOf("zone:dun_morogh") and names()[3] == nameOf("zone:loch_modan") and names()[4] == nameOf("city:ironforge")
        and page().empty.shown == true and select(1, textOf(continentRow.toggle)) == "-")
check("U2b. los hijos están sangrados un nivel respecto a su padre",
    navRows()[2].select.children[2].points[1][4] > navRows()[1].select.children[2].points[1][4])

click(rowNamed(nameOf("zone:dun_morogh")).select)
local p = page()
check("U3. seleccionar una zona muestra su página: nombre, tipo y descripción de Localization en el área derecha",
    p.title.shown == true and p.title.text == nameOf("zone:dun_morogh") and p.kind.text == "Zona"
        and p.description.text == localization:Get("zone:dun_morogh", "description") and p.empty.shown ~= true)
check("U3b. no se muestra cuerpo (la zona no tiene textKey) ni la línea separadora, y la descripción no se repite como cuerpo",
    p.body.shown ~= true and p.rule.shown ~= true and p.body.text == "")
check("U3c. la fila seleccionada se distingue: fondo de selección visible solo en ella y texto en el color de oro de Theme",
    (function()
        local selectedRows = 0
        for _, row in ipairs(navRows()) do
            local isSel = textOf(row.select) == nameOf("zone:dun_morogh")
            local _, label = textOf(row.select)
            local highlight = row.select.children[1]
            if (highlight.shown == true) ~= isSel then return false end
            if isSel then
                selectedRows = selectedRows + 1
                if not deepEqual(label.color, Chronicle.Theme:GetColor("GOLD")) then return false end
                if not deepEqual(highlight.vertexColor, Chronicle.Theme:GetColor("SELECTION")) then return false end
            end
        end
        return selectedRows == 1
    end)())
check("U3d. los breadcrumbs muestran la ruta real y el último tramo (la página actual) no es un enlace",
    table.concat(crumbNames(), "|") == nameOf("continent:eastern_kingdoms") .. "|" .. nameOf("zone:dun_morogh")
        and crumbs()[1].__scripts.OnClick ~= nil)

-- Contraer un nodo oculta sus filas
do
    local before = #navRows()
    click(rowNamed(nameOf("continent:eastern_kingdoms")).toggle) -- contraer
    local collapsedCount, collapsedPage = #navRows(), page().title.text == nameOf("zone:dun_morogh")
    click(rowNamed(nameOf("continent:eastern_kingdoms")).toggle) -- expandir de nuevo
    check("U2c. contraer el continente deja solo su fila (las filas sobrantes se ocultan, no se destruyen) y expandirlo las recupera",
        before == 4 and collapsedCount == 1 and collapsedPage == true and #navRows() == 4 and names()[2] == nameOf("zone:dun_morogh"))
end

-- Expandir Dun Morogh no cambia la página
local tallBefore = pageScroll.verticalScroll
click(rowNamed(nameOf("zone:dun_morogh")).toggle)
check("U4. expandir un nodo con la página seleccionada no cambia la página mostrada ni su desplazamiento",
    page().title.text == nameOf("zone:dun_morogh") and pageScroll.verticalScroll == tallBefore and #navRows() > 4)

-- Seleccionar una subzona y un NPC, y navegar por los breadcrumbs
click(rowNamed(nameOf("subzone:coldridge_valley")).toggle)
click(rowNamed(nameOf("subzone:coldridge_valley")).select)
check("U5. seleccionar una subzona: breadcrumbs continente > zona > subzona, con el tipo «Subzona»",
    table.concat(crumbNames(), "|") == table.concat({ nameOf("continent:eastern_kingdoms"), nameOf("zone:dun_morogh"), nameOf("subzone:coldridge_valley") }, "|")
        and page().kind.text == "Subzona")
click(rowNamed(nameOf("npc:grelin_whitebeard")).select)
local np = page()
check("U6. seleccionar un NPC muestra su página con ubicación contextual (la subzona), raza y rol; el breadcrumb es solo él (sin ruta inventada)",
    np.title.text == nameOf("npc:grelin_whitebeard") and np.kind.text == "Personaje"
        and np.location.text == "Ubicado en: " .. nameOf("subzone:coldridge_valley") and np.details.text:find(localization:Get("npc:grelin_whitebeard", "race"), 1, true) ~= nil
        and #crumbNames() == 1 and crumbs()[1].__scripts.OnClick ~= nil)
check("U6b. el último tramo del breadcrumb es la página actual: pulsarlo no cambia nada",
    (function()
        click(crumbs()[1])
        return page().title.text == nameOf("npc:grelin_whitebeard")
    end)())
click(rowNamed(nameOf("subzone:coldridge_valley")).select)
click(crumbs()[2]) -- breadcrumb de la zona
check("U7. pulsar un breadcrumb navega a esa entidad",
    page().title.text == nameOf("zone:dun_morogh") and table.concat(crumbNames(), "|") == nameOf("continent:eastern_kingdoms") .. "|" .. nameOf("zone:dun_morogh"))

-- Historial en la interfaz
click(backButton)
check("U8. el botón Atrás vuelve a la página anterior (la subzona) y Adelante regresa a la zona",
    page().title.text == nameOf("subzone:coldridge_valley") and (function() click(forwardButton); return page().title.text == nameOf("zone:dun_morogh") end)())
check("U8b. los botones de historial se atenúan cuando no hay a dónde ir (Adelante sin futuro)",
    deepEqual(forwardButton.children[1].color, Chronicle.Theme:GetColor("TEXT_MUTED")) and deepEqual(backButton.children[1].color, Chronicle.Theme:GetColor("GOLD")))
click(backButton); click(backButton)
click(rowNamed(nameOf("zone:loch_modan")).select)
check("U9. tras retroceder, seleccionar otra página borra el futuro: Adelante queda deshabilitado y no reaparece lo anterior",
    page().title.text == nameOf("zone:loch_modan") and deepEqual(forwardButton.children[1].color, Chronicle.Theme:GetColor("TEXT_MUTED"))
        and (function() click(forwardButton); return page().title.text == nameOf("zone:loch_modan") end)())

-- Desplazamiento y textos largos
do
    local hugeText = string.rep("Un texto muy largo de lore para comprobar el desplazamiento. ", 400)
    local reg, loc = World({ { id = "continent:big", type = "continent" } }, { ["continent:big"] = { name = "Gran lore", description = hugeText } })
    local ctx = { frames = {} }
    local big = Chronicle.Codex.New({
        theme = Chronicle.Theme, registry = reg, localization = loc, uiParent = UIParent, specialFrames = {},
        createFrame = function(...) local f = realCreateFrame(...); ctx.frames[#ctx.frames + 1] = f; return f end,
    })
    big:Init()
    local scrolls, buttons = {}, {}
    for _, f in ipairs(ctx.frames) do
        if f.kind == "ScrollFrame" then scrolls[#scrolls + 1] = f end
        if f.kind == "Button" then buttons[#buttons + 1] = f end
    end
    local bigNav, bigPage = scrolls[1], scrolls[2]
    local rowButton
    for _, f in ipairs(buttons) do
        if f.parent == bigNav.scrollChild then rowButton = f; break end
    end
    click(rowButton)
    local descText = bigPage.scrollChild.children[5]
    check("U10. un texto largo se muestra ENTERO (no se trunca) y la zona de la página es más alta que lo visible, para poder desplazarla",
        descText.text == hugeText and #hugeText > 20000 and bigPage.scrollChild.height > bigPage.height and bigPage.scrollChild.height >= descText:GetStringHeight())
    local range = bigPage.scrollChild.height - bigPage.height
    local wheel = bigPage.__scripts.OnMouseWheel
    wheel(bigPage, -1)
    local after1 = bigPage.verticalScroll
    for _ = 1, 2000 do wheel(bigPage, -1) end
    local atEnd = bigPage.verticalScroll
    for _ = 1, 2000 do wheel(bigPage, 1) end
    check("U10b. la rueda desplaza la página, no pasa de los límites (0 y el final del contenido) y vuelve arriba",
        after1 == Chronicle.Theme:GetLayout("CODEX_SCROLL_STEP") and atEnd == range and bigPage.verticalScroll == 0)
    wheel(bigPage, -1); wheel(bigPage, -1)
    click(rowButton) -- misma página
    check("U10c. repintar sin cambiar de página no pierde el punto de lectura (el desplazamiento se conserva)", bigPage.verticalScroll == 2 * Chronicle.Theme:GetLayout("CODEX_SCROLL_STEP"))
end
check("U11. el árbol largo también se desplaza: con todo expandido hay más filas que alto visible y la lista tiene rango de desplazamiento",
    (function()
        for _, row in ipairs(navRows()) do if row.toggle.shown == true and textOf(row.toggle) == "+" then click(row.toggle) end end
        for _ = 1, 4 do
            for _, row in ipairs(navRows()) do if row.toggle.shown == true and textOf(row.toggle) == "+" then click(row.toggle) end end
        end
        local rowHeight = Chronicle.Theme:GetLayout("CODEX_ROW_HEIGHT")
        return #navRows() > navScroll.height / rowHeight and navChild.height == #navRows() * rowHeight and navChild.height > navScroll.height
    end)())
check("U11b. seleccionar una fila lejana desplaza la lista para que sea visible",
    (function()
        local target = navRows()[#navRows()]
        local targetName = textOf(target.select)
        click(target.select)
        local index
        for i, row in ipairs(navRows()) do if textOf(row.select) == targetName then index = i end end
        local rowHeight = Chronicle.Theme:GetLayout("CODEX_ROW_HEIGHT")
        local offset = navScroll.verticalScroll
        return index ~= nil and offset <= (index - 1) * rowHeight and (index * rowHeight) <= offset + navScroll.height
    end)())

-- ===================== Integración, Theme y aislamiento =====================
check("A1. la API pública del Codex sigue siendo la de la Fase 8 y no expone frames ni el modelo",
    (function()
        local expected = { Init = true, IsReady = true, IsVisible = true, Show = true, Hide = true, Toggle = true, New = true }
        for key in pairs(Chronicle.Codex) do if not expected[key] then return false, key end end
        return true
    end)())
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
check("A2. ningún fichero de la navegación define colores, fuentes ni rutas de textura propios: todo sale de Theme",
    (function()
        for _, name in ipairs({ "UI/CodexModel.lua", "UI/CodexScroll.lua", "UI/CodexNavigation.lua", "UI/CodexPage.lua" }) do
            local lines = codeOf(name)
            if not lines then return false, name .. " no está en el .toc" end
            for _, line in ipairs(lines) do
                for _, word in ipairs({ "SetFont(", "SetBackdrop(", "SetBackdropColor", "SetColorTexture", "Fonts\\", "Interface\\", "Interface/" }) do
                    if line:find(word, 1, true) then return false, name .. ": " .. word end
                end
                if line:find("0%.%d+%s*,%s*0%.%d+") then return false, name .. ": " .. line end
            end
        end
        return true
    end)())
check("A3. ningún fichero de la navegación accede a ChronicleCharDB, State, Discovery, Proximity ni ZoneDiscovery, ni usa temporizadores o eventos del cliente",
    (function()
        for _, name in ipairs({ "UI/CodexModel.lua", "UI/CodexScroll.lua", "UI/CodexNavigation.lua", "UI/CodexPage.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", "Chronicle.Discovery", "Chronicle.Proximity", "Chronicle.ZoneDiscovery",
                    "Chronicle.MapPosition", "C_Timer", "OnUpdate", "RegisterEvent", "Chronicle.Events", "SLASH_", "Minimap" }) do
                    if line:find(word, 1, true) then return false, name .. ": " .. word end
                end
            end
        end
        return true
    end)())
check("A4. el modelo solo depende de lo que se le inyecta (Registry y Localization): no referencia otros módulos de Chronicle",
    (function()
        for _, line in ipairs(codeOf("UI/CodexModel.lua")) do
            for name in line:gmatch("Chronicle%.(%w+)") do
                if name ~= "CodexModel" then return false, name end
            end
        end
        return true
    end)())
check("A5. usar la navegación no escribe nada en ChronicleCharDB: queda exactamente el estado inicial del Core",
    deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} } }))
check("A6. la navegación no usa Discovery: no hay estados de descubierto/no descubierto ni marcadores ??? en ninguna fila ni página",
    (function()
        for _, row in ipairs(navRows()) do
            if (textOf(row.select) or ""):find("?", 1, true) then return false end
        end
        return Chronicle.Discovery:Count() == 0
    end)())

-- Tokens de Theme que usa la navegación
check("A7. Theme aporta los tokens de la navegación sin alterar los anteriores",
    Chronicle.Theme:GetLayout("CODEX_ROW_HEIGHT") == 22 and Chronicle.Theme:GetLayout("CODEX_SCROLL_STEP") == 44 and Chronicle.Theme:GetColor("SELECTION") ~= nil
        and Chronicle.Theme:GetLayout("POPUP_WIDTH") == 420 and Chronicle.Theme:GetLayout("CODEX_WIDTH") == 840)

-- ===================== Fallos =====================
CreateFrame = realCreateFrame
do
    Boot(function() Chronicle.CodexModel = nil end)
    check("F1. si falta un módulo interno el Codex falla al inicializar SIN crear la ventana y sin impedir el arranque ni los servicios",
        Chronicle.Init.failed.Codex ~= nil and Chronicle.Init.failed.Codex:find("CodexModel", 1, true) ~= nil and _G["ChronicleCodexFrame"] == nil
            and Chronicle.Init.ready == true and Chronicle.Discovery:IsReady() and Chronicle.Popup:IsReady())
    Boot(function() Chronicle.Registry.Init = function() error("registro roto") end end)
    check("F2. si Registry (requerido) falla, el Codex se omite sin intentarlo; los demás módulos dependientes de Registry también",
        Chronicle.Init.failed.Registry ~= nil and Chronicle.Init.skipped.Codex ~= nil and Chronicle.Init.failed.Codex == nil and _G["ChronicleCodexFrame"] == nil)
    Boot(function() Chronicle.Localization.Init = function() error("textos rotos") end end)
    check("F3. si Localization (requerido) falla, el Codex se omite sin intentarlo", Chronicle.Init.failed.Localization ~= nil
        and Chronicle.Init.skipped.Codex ~= nil and _G["ChronicleCodexFrame"] == nil)
    Boot()
    local failing = Chronicle.Codex.New({ theme = Chronicle.Theme, registry = false, localization = Chronicle.Localization,
        createFrame = realCreateFrame, uiParent = UIParent, specialFrames = {} })
    local ok, err = pcall(failing.Init, failing)
    check("F4. sin Registry el Codex falla con un error descriptivo y no crea nada", ok == false and tostring(err):find("Registry", 1, true) ~= nil)
    local calls = 0
    local broken = Chronicle.Codex.New({ theme = Chronicle.Theme, registry = Chronicle.Registry, localization = Chronicle.Localization,
        uiParent = UIParent, specialFrames = {},
        createFrame = function(kind, ...)
            calls = calls + 1
            if kind == "ScrollFrame" then error("sin ScrollFrame") end
            return realCreateFrame(kind, ...)
        end })
    local okB, errB = pcall(broken.Init, broken)
    local callsAfterFirst = calls
    local okB2, errB2 = pcall(broken.Init, broken)
    check("F5. si falla un widget de la navegación (ScrollFrame), Init falla con ese motivo, no queda listo y es definitivo (sin más frames)",
        okB == false and tostring(errB):find("sin ScrollFrame", 1, true) ~= nil and broken:IsReady() == false and errB == errB2
            and calls == callsAfterFirst and select(2, broken:Show()) == "not_ready")
    local reg, loc = World({ { id = "continent:c", type = "continent" } }, { ["continent:c"] = { name = "C" } })
    local fragile = Chronicle.Codex.New({ theme = Chronicle.Theme, registry = reg, localization = loc, uiParent = UIParent, specialFrames = {},
        createFrame = function(...) return realCreateFrame(...) end })
    fragile:Init()
    local before = #ReportedErrors
    local okShow = pcall(fragile.Show, fragile)
    check("F6. el Codex ya construido sigue funcionando y no lanza errores", okShow and fragile:IsVisible() == true and #ReportedErrors == before)
end


-- ===================== Montaje sintético: lore, desbordamiento y fallos en uso =====================
CreateFrame = realCreateFrame
local function Mount(reg, loc, createFrameOver, theme)
    local mount = { frames = {} }
    mount.codex = Chronicle.Codex.New({
        theme = theme or Chronicle.Theme, registry = reg, localization = loc, uiParent = UIParent, specialFrames = {},
        createFrame = function(...)
            if createFrameOver then createFrameOver(...) end
            local f = realCreateFrame(...)
            mount.frames[#mount.frames + 1] = f
            return f
        end,
    })
    mount.codex:Init()
    local scrolls = {}
    for _, f in ipairs(mount.frames) do if f.kind == "ScrollFrame" then scrolls[#scrolls + 1] = f end end
    mount.navScroll, mount.pageScroll = scrolls[1], scrolls[2]
    for _, f in ipairs(mount.frames) do
        if f.kind == "Frame" and f.parent == mount.pageScroll.parent then mount.toolbar = f; break end
    end
    function mount.rows()
        local out, pending = {}, nil
        for _, f in ipairs(mount.frames) do
            if f.kind == "Button" and f.parent == mount.navScroll.scrollChild then
                if not pending then pending = f else out[#out + 1] = { select = pending, toggle = f }; pending = nil end
            end
        end
        local visible = {}
        for _, row in ipairs(out) do if row.select.shown == true then visible[#visible + 1] = row end end
        return visible
    end
    function mount.row(name)
        for _, row in ipairs(mount.rows()) do if (textOf(row.select)) == name then return row end end
        return MISSING_ROW
    end
    function mount.page()
        local c = mount.pageScroll.scrollChild.children
        return { title = c[1], kind = c[2], location = c[3], details = c[4], description = c[5], rule = c[6], body = c[7], empty = c[8] }
    end
    function mount.crumbs()
        local out = {}
        local index = 0
        for _, f in ipairs(mount.frames) do
            if f.kind == "Button" and f.parent == mount.toolbar then
                index = index + 1
                if index > 2 and f.shown == true then out[#out + 1] = f end
            end
        end
        return out
    end
    function mount.ellipsisShown()
        for _, child in ipairs(mount.toolbar.children or {}) do
            if child.text == "..." and child.shown == true then return true end
        end
        return false
    end
    return mount
end

do
    local reg, loc = World({
        { id = "continent:world", type = "continent" },
        { id = "zone:valley", type = "zone", parent = "continent:world" },
        { id = "lore:history", type = "lore", located_in = "zone:valley", textKey = "lore:history_text" },
        { id = "lore:history_text", type = "lore", located_in = "zone:valley" },
    }, {
        ["continent:world"] = { name = "Mundo" }, ["zone:valley"] = { name = "Valle" },
        ["lore:history"] = { name = "Historia", description = "Resumen corto de la historia." },
        ["lore:history_text"] = { description = "Artículo largo de la historia del valle." },
    })
    local m = Mount(reg, loc)
    click(m.row("Mundo").toggle)
    click(m.row("Valle").toggle)
    click(m.row("Historia").select)
    local pg = m.page()
    check("U12. una entidad de lore con textKey muestra en la página la descripción, una línea de separación y el cuerpo, en elementos distintos",
        pg.title.text == "Historia" and pg.kind.text == "Lore" and pg.description.text == "Resumen corto de la historia."
            and pg.rule.shown == true and pg.body.text == "Artículo largo de la historia del valle." and pg.body.shown == true
            and pg.description ~= pg.body and pg.location.text == "Ubicado en: Valle")
    check("U12b. el cuerpo queda por debajo de la separación y esta por debajo de la descripción (orden de lectura)",
        pg.rule.points[1][5] > pg.body.points[1][5] and pg.description.points[1][5] > pg.rule.points[1][5])
    click(m.row("Valle").select)
    local pv = m.page()
    check("U12c. al pasar a una página sin descripción ni cuerpo, esos elementos se ocultan (no quedan restos de la página anterior)",
        pv.description.shown ~= true and pv.body.shown ~= true and pv.rule.shown ~= true and pv.description.text == "" and pv.body.text == ""
            and pv.title.text == "Valle")
end

do
    local long = string.rep("N", 50)
    local reg, loc = World({
        { id = "continent:a", type = "continent" },
        { id = "zone:b", type = "zone", parent = "continent:a" },
        { id = "subzone:c", type = "subzone", parent = "zone:b" },
    }, { ["continent:a"] = { name = long .. "1" }, ["zone:b"] = { name = long .. "2" }, ["subzone:c"] = { name = long .. "3" } })
    local m = Mount(reg, loc)
    click(m.row(long .. "1").toggle); click(m.row(long .. "2").toggle); click(m.row(long .. "3").select)
    local shown = m.crumbs()
    check("U13. si los breadcrumbs no caben se quitan tramos por el principio y se antepone «...»; el último tramo (la página actual) siempre se conserva",
        #shown >= 1 and #shown < 3 and (textOf(shown[#shown])) == long .. "3" and m.ellipsisShown())
    local reg2, loc2 = World({ { id = "continent:a", type = "continent" }, { id = "zone:b", type = "zone", parent = "continent:a" } },
        { ["continent:a"] = { name = "A" }, ["zone:b"] = { name = "B" } })
    local m2 = Mount(reg2, loc2)
    click(m2.row("A").toggle); click(m2.row("B").select)
    check("U13b. si caben, se muestran todos los tramos y no aparece «...»", #m2.crumbs() == 2 and not m2.ellipsisShown())
end

do
    local reg, loc = World({ { id = "continent:a", type = "continent" }, { id = "zone:b", type = "zone", parent = "continent:a" } },
        { ["continent:a"] = { name = "A" }, ["zone:b"] = { name = "B" } })
    local failRows = false
    local m = Mount(reg, loc, function(kind) if failRows and kind == "Button" then error("sin botones") end end)
    local before = #ReportedErrors
    failRows = true
    local ok = pcall(click, m.row("A").toggle)
    local reported = false
    for i = before + 1, #ReportedErrors do
        if ReportedErrors[i]:find("Chronicle.Codex: error al actualizar", 1, true) and ReportedErrors[i]:find("sin botones", 1, true) then reported = true end
    end
    check("F7. si la interfaz falla al repintar en uso, el clic no lanza error y el fallo se comunica por geterrorhandler",
        ok and reported and m.codex:IsReady() == true)
    failRows = false
    check("F7b. y el Codex se recupera: la siguiente actualización correcta repinta con normalidad",
        (function() click(m.row("A").toggle); click(m.row("A").toggle); return #m.rows() == 2 end)())
end


-- ===================== Desplazamiento, medidas de Theme y nombres de reserva (montajes sintéticos) =====================
local function AlteredTheme(overrides)
    local t = {}
    for _, key in ipairs({ "IsReady", "GetColor", "GetFontRole", "GetSpacing", "GetStrata", "GetTexture", "GetBackdrop", "ApplyText", "ApplyBackdrop" }) do
        t[key] = function(_, ...) return Chronicle.Theme[key](Chronicle.Theme, ...) end
    end
    t.GetLayout = function(_, name)
        if overrides[name] ~= nil then return overrides[name] end
        return Chronicle.Theme:GetLayout(name)
    end
    return t
end

local function WideWorld(count)
    local entities = { { id = "continent:c", type = "continent" } }
    local texts = { ["continent:c"] = { name = "Continente" } }
    for i = 1, count do
        local id = string.format("zone:z%02d", i)
        entities[#entities + 1] = { id = id, type = "zone", parent = "continent:c" }
        texts[id] = { name = string.format("Zona %02d", i), description = string.rep("Descripción de la zona. ", 120) }
    end
    entities[#entities + 1] = { id = "subzone:s01", type = "subzone", parent = "zone:z01" }
    texts["subzone:s01"] = { name = "Subzona 01" }
    local reg, loc = World(entities, texts)
    return reg, loc
end

do
    local reg, loc = WideWorld(40)
    local m = Mount(reg, loc)
    local nav = m.navScroll
    click(m.row("Continente").toggle)
    click(m.row("Zona 40").select)
    local rowHeight = Chronicle.Theme:GetLayout("CODEX_ROW_HEIGHT")
    local revealed = nav.verticalScroll
    check("U11c. seleccionar una fila lejana desplaza el árbol hasta dejarla visible",
        revealed > 0 and (41 * rowHeight) <= revealed + nav.height + rowHeight)
    for _ = 1, 200 do nav.__scripts.OnMouseWheel(nav, 1) end
    click(m.row("Zona 01").toggle) -- expandir otra rama: no debe mover la lista
    check("U11d. expandir o contraer una rama NO mueve la lista (solo la selección la desplaza)", nav.verticalScroll == 0 and #m.rows() == 42)

    -- indicador de posición
    local track, thumb = nav.parent.children[2], nav.parent.children[3]
    local thumbBefore = thumb.points[#thumb.points][5]
    nav.__scripts.OnMouseWheel(nav, -1)
    local thumbAfter = thumb.points[#thumb.points][5]
    check("U16. con contenido más alto que lo visible el indicador de posición se muestra y baja al desplazar la lista",
        track.shown == true and thumb.shown == true and thumbAfter < thumbBefore)
    local shortReg, shortLoc = WideWorld(2)
    local shortMount = Mount(shortReg, shortLoc)
    local shortTrack, shortThumb = shortMount.navScroll.parent.children[2], shortMount.navScroll.parent.children[3]
    check("U16b. si todo cabe, el indicador de posición está oculto", shortTrack.shown == false and shortThumb.shown == false)

    -- cada página nueva empieza arriba
    click(m.row("Zona 02").select)
    local pageScroll = m.pageScroll
    local wheel = pageScroll.__scripts.OnMouseWheel
    wheel(pageScroll, -1); wheel(pageScroll, -1)
    local scrolled = pageScroll.verticalScroll
    click(m.row("Zona 01").toggle) -- cambia el árbol, no la página
    check("U17b. expandir un nodo del árbol no repinta la página ni pierde el punto de lectura",
        scrolled > 0 and pageScroll.verticalScroll == scrolled and m.page().title.text == "Zona 02")
    click(m.row("Zona 03").select)
    check("U17. cada página nueva empieza arriba: tras leer una página desplazada, abrir otra vuelve al principio",
        scrolled > 0 and pageScroll.verticalScroll == 0 and m.page().title.text == "Zona 03")
end

do
    local reg, loc = WideWorld(30)
    local themed = AlteredTheme({ CODEX_ROW_HEIGHT = 30, CODEX_SCROLL_STEP = 99 })
    local m = Mount(reg, loc, nil, themed)
    click(m.row("Continente").toggle)
    local second = m.rows()[2]
    local nav = m.navScroll
    nav.__scripts.OnMouseWheel(nav, -1)
    check("U15. las medidas de filas y de desplazamiento salen de Theme: con otro tema las filas miden 30 y la rueda avanza 99",
        second.select.points[1][5] == -30 and second.select.height == 30 and nav.scrollChild.height == #m.rows() * 30 and nav.verticalScroll == 99)
end

do
    local reg, loc = World({ { id = "continent:a", type = "continent" }, { id = "zone:sin_nombre", type = "zone", parent = "continent:a" } },
        { ["continent:a"] = { name = "Con nombre" } })
    local m = Mount(reg, loc)
    click(m.row("Con nombre").toggle)
    local row = m.row("zone:sin_nombre")
    local _, label = textOf(row.select)
    local _, namedLabel = textOf(m.row("Con nombre").select)
    check("U14. una entidad sin nombre localizado se muestra con su ID como nombre de reserva, atenuado (color de texto secundario)",
        row ~= nil and deepEqual(label.color, Chronicle.Theme:GetColor("TEXT_MUTED")) and deepEqual(namedLabel.color, Chronicle.Theme:GetColor("TEXT_IVORY")))
    click(row.select)
    local pg = m.page()
    check("U14b. y su página se abre con ese nombre de reserva (también atenuado), sin descripción ni cuerpo",
        pg.title.text == "zone:sin_nombre" and deepEqual(pg.title.color, Chronicle.Theme:GetColor("TEXT_MUTED")) and pg.description.shown ~= true
            and pg.body.shown ~= true)
    local leafToggleHidden = (function()
        for _, r in ipairs(m.rows()) do
            if (textOf(r.select)) == "zone:sin_nombre" then return r.toggle.shown ~= true end
        end
    end)()
    check("U14c. una fila sin hijos no tiene botón +/- visible", leafToggleHidden == true)
    click(m.row("Con nombre").toggle) -- contraer: la fila de la hoja queda libre y se reutiliza
    click(m.row("Con nombre").toggle)
    check("U14d. al reutilizar filas, una hoja nunca hereda el botón +/- de una fila anterior que tenía hijos",
        (function()
            for _, r in ipairs(m.rows()) do
                if (textOf(r.select)) == "zone:sin_nombre" and r.toggle.shown == true then return false end
            end
            return true
        end)())
end

do
    local reg, loc = World({
        { id = "continent:a", type = "continent" }, { id = "continent:b", type = "continent" }, { id = "continent:c", type = "continent" },
        { id = "zone:z1", type = "zone", parent = "continent:a" }, { id = "zone:z2", type = "zone", parent = "continent:b" },
    }, { ["continent:a"] = { name = "A" }, ["continent:b"] = { name = "B" }, ["continent:c"] = { name = "C" },
        ["zone:z1"] = { name = "Z1" }, ["zone:z2"] = { name = "Z2" } })
    local m = Mount(reg, loc)
    click(m.row("A").toggle) -- A, Z1, B, C
    click(m.row("A").toggle) -- A, B, C
    click(m.row("B").toggle) -- A, B, Z2, C: Z2 ocupa la fila que tenía el botón +/- de B
    local z2 = m.row("Z2")
    check("U14e. una hoja que ocupa una fila reutilizada que antes tenía el botón +/- no lo conserva",
        z2 ~= MISSING_ROW and z2.toggle.shown ~= true and (textOf(z2.toggle)) == "" and #m.rows() == 4)
end
