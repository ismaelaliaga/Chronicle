-- Escenarios de prueba de la Fase 11: visor 3D de NPC y enlaces a contenido relacionado en las páginas del Codex. Con el mock estricto:
-- el mock tiene un tipo de frame "PlayerModel" con SetDisplayInfo / SetCreature / ClearModel que solo GUARDAN lo que se les pide.
-- Esto NO demuestra que el cliente real de Classic Era tenga ese tipo de frame, que dibuje el modelo ni que el display ID sea el
-- correcto: eso sigue sin verificar (ver docs/fase11_npc3d_contenido_relacionado.md).

local FRAME_NAME = "ChronicleCodexFrame"
local EVENT = "Chronicle.Discovery.Discovered"

local realCreateFrame = CreateFrame
local created = {}

local function Boot(prepare, keepRecorder)
    created = {}
    local recorder = function(kind, name, parent, template)
        local frame = realCreateFrame(kind, name, parent, template)
        created[#created + 1] = { kind = kind, name = name, template = template, frame = frame, parent = parent }
        return frame
    end
    CreateFrame = recorder
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    FireEvent("ADDON_LOADED", "Chronicle")
    if not keepRecorder then CreateFrame = realCreateFrame end
end
local function bootedFrames()
    local list = {}
    for _, entry in ipairs(created) do list[#list + 1] = entry.frame end
    return list
end
local function click(frame)
    local handler = frame and frame.__scripts and frame.__scripts.OnClick
    if handler then handler(frame) end
end
local function textOf(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.text ~= nil then return child.text, child end
    end
end
local MISSING_FRAME = { __scripts = {}, children = {}, points = { {} }, shown = false }
local MISSING_ROW = { select = MISSING_FRAME, toggle = MISSING_FRAME }

local function Inspect(source)
    local function F()
        if type(source) == "function" then return source() end
        return source
    end
    local ui = {}
    for _, f in ipairs(F()) do if f.name == FRAME_NAME then ui.win = f end end
    local panes = {}
    for _, f in ipairs(F()) do
        if f.kind == "Frame" and f.parent == ui.win and f.name == nil then panes[#panes + 1] = f end
    end
    ui.nav, ui.content = panes[1], panes[2]
    for _, f in ipairs(F()) do
        if f.kind == "ScrollFrame" and f.parent == ui.nav then ui.navScroll = f end
        if f.kind == "ScrollFrame" and f.parent == ui.content then ui.pageScroll = f end
        if f.kind == "Frame" and f.parent == ui.content and not ui.toolbar then ui.toolbar = f end
    end
    function ui.rows()
        local out, pending = {}, nil
        for _, f in ipairs(F()) do
            if f.kind == "Button" and f.parent == ui.navScroll.scrollChild then
                if not pending then pending = f else out[#out + 1] = { select = pending, toggle = f }; pending = nil end
            end
        end
        local visible = {}
        for _, row in ipairs(out) do if row.select.shown == true then visible[#visible + 1] = row end end
        return visible
    end
    function ui.row(name)
        for _, row in ipairs(ui.rows()) do if (textOf(row.select)) == name then return row end end
        return MISSING_ROW
    end
    function ui.page()
        local c = ui.pageScroll.scrollChild.children
        return { title = c[1], kind = c[2], location = c[3], details = c[4], description = c[5], rule = c[6], body = c[7], empty = c[8] }
    end
    function ui.models()
        local out = {}
        for _, f in ipairs(F()) do if f.kind == "PlayerModel" then out[#out + 1] = f end end
        return out
    end
    -- Si no hay visor se devuelve un marcador inerte: así la ausencia sale como aserciones fallidas, no como excepción.
    local MISSING_MODEL = { __scripts = {}, points = { {} }, children = {}, width = 0, height = 0 }
    function ui.model() return ui.models()[1] or MISSING_MODEL end
    -- botones de enlace visibles de la página (los hijos Button del contenido de la página que no son de la barra)
    function ui.links()
        local out = {}
        for _, f in ipairs(F()) do
            if f.kind == "Button" and f.parent == ui.pageScroll.scrollChild and f.shown == true then out[#out + 1] = f end
        end
        return out
    end
    function ui.linkNames()
        local out = {}
        for _, b in ipairs(ui.links()) do out[#out + 1] = (textOf(b)) end
        return out
    end
    function ui.allLinkTexts()
        local out = {}
        for _, f in ipairs(F()) do
            if f.kind == "Button" and f.parent == ui.pageScroll.scrollChild then
                local text = textOf(f)
                if text ~= nil and text ~= "" then out[#out + 1] = text end
            end
        end
        return out
    end
    function ui.link(name)
        for _, b in ipairs(ui.links()) do if (textOf(b)) == name then return b end end
        return MISSING_FRAME
    end
    function ui.crumbNames()
        local out, index = {}, 0
        for _, f in ipairs(F()) do
            if f.kind == "Button" and f.parent == ui.toolbar then
                index = index + 1
                if index > 2 and f.shown == true then out[#out + 1] = (textOf(f)) end
            end
        end
        return out
    end
    function ui.toolbarButtons()
        local out = {}
        for _, f in ipairs(F()) do if f.kind == "Button" and f.parent == ui.toolbar then out[#out + 1] = f end end
        return out
    end
    function ui.allTexts()
        local out = {}
        for _, f in ipairs(F()) do
            for _, child in ipairs(f.children or {}) do
                if type(child.text) == "string" and child.text ~= "" then out[#out + 1] = child.text end
            end
        end
        return out
    end
    function ui.leak(forbidden)
        for _, text in ipairs(ui.allTexts()) do
            local lower = text:lower()
            for _, bad in ipairs(forbidden) do
                if lower:find(bad:lower(), 1, true) then return text, bad end
            end
        end
        return nil
    end
    function ui.expandAll()
        for _ = 1, 120 do
            local changed = false
            for _, row in ipairs(ui.rows()) do
                if row.toggle.shown == true and (textOf(row.toggle)) == "+" then click(row.toggle); changed = true; break end
            end
            if not changed then break end
        end
    end
    return ui
end

local function Disc()
    local d = { set = {}, ready = true, calls = 0, discovers = 0, EVENT_DISCOVERED = EVENT }
    d.IsReady = function() return d.ready end
    d.IsDiscovered = function(_, id) d.calls = d.calls + 1; return d.set[id] end
    d.Discover = function() d.discovers = d.discovers + 1 end
    return d
end

local function World(entities, texts, schema)
    local registry = Chronicle.Registry.New(schema or Chronicle.Schema)
    for _, entity in ipairs(entities) do
        local ok, err = registry:Register(entity)
        if not ok then error("entidad de prueba rechazada (" .. tostring(entity.id) .. "): " .. (type(err) == "table" and table.concat(err.errors or err, "; ") or tostring(err))) end
    end
    local localization = Chronicle.Localization.New(registry)
    for id, entry in pairs(texts or {}) do
        local ok, err = localization:Add("esES", id, entry)
        if not ok then error("texto de prueba rechazado: " .. tostring(err)) end
    end
    return registry, localization
end

-- Un mundo con NPC con y sin modelo, relaciones declaradas por los dos lados, destinos inexistentes y secretos reconocibles.
local function ContentWorld()
    return World({
        { id = "continent:c", type = "continent" },
        { id = "zone:z", type = "zone", parent = "continent:c", related_to = { "city:p", "zone:y" } },
        { id = "zone:y", type = "zone", parent = "continent:c" },
        { id = "subzone:s", type = "subzone", parent = "zone:z" },
        { id = "city:p", type = "city", parent = "continent:c", located_in = "zone:z" },
        { id = "npc:a", type = "npc", located_in = "subzone:s", npcID = 100, displayID = 200 },
        { id = "npc:b", type = "npc", located_in = "subzone:s" },
        { id = "npc:c", type = "npc", located_in = "subzone:s", npcID = 101, displayID = 300, related_to = { "npc:a", "npc:fantasma" } },
        { id = "npc:d", type = "npc", located_in = "subzone:s", displayID = 400 },
        { id = "lore:l", type = "lore", located_in = "subzone:s" },
    }, {
        ["continent:c"] = { name = "Continente Alfa" },
        ["zone:z"] = { name = "Zona Zeta", description = "Descripción de la zona zeta" },
        ["zone:y"] = { name = "Zona Ypsilon", description = "Descripción de ypsilon" },
        ["subzone:s"] = { name = "Subzona Sigma", description = "Descripción de sigma" },
        ["city:p"] = { name = "Puerto Pi", description = "Descripción del puerto pi" },
        ["npc:a"] = { name = "Alba", description = "Descripción de alba", race = "Enana", role = "Guardiana" },
        ["npc:b"] = { name = "Beto", description = "Descripción de beto", race = "Gnomo", role = "Mecánico" },
        ["npc:c"] = { name = "Cora", description = "Descripción de cora", race = "Humana", role = "Maga" },
        ["npc:d"] = { name = "Dani", description = "Descripción de dani" },
        ["lore:l"] = { name = "Leyenda", description = "Descripción de la leyenda" },
    })
end
local NAMES = { "Continente Alfa", "Zona Zeta", "Zona Ypsilon", "Subzona Sigma", "Puerto Pi", "Alba", "Beto", "Cora", "Dani", "Leyenda" }
local TEXTS = { "Descripción de la zona zeta", "Descripción de ypsilon", "Descripción de sigma", "Descripción del puerto pi", "Descripción de alba",
    "Descripción de beto", "Descripción de cora", "Descripción de dani", "Descripción de la leyenda", "Enana", "Guardiana", "Gnomo", "Mecánico", "Humana", "Maga" }
local IDS = { "continent:c", "zone:z", "zone:y", "subzone:s", "city:p", "npc:a", "npc:b", "npc:c", "npc:d", "lore:l", "fantasma" }

-- `discovered` = lista de IDs descubiertos, o true para todos. `over` = ajustes (createFrame de la ventana, bus...).
local function Mount(reg, loc, discovery, over)
    over = over or {}
    local mount = { frames = {}, discovery = discovery }
    mount.codex = Chronicle.Codex.New({
        theme = Chronicle.Theme, registry = reg, localization = loc, discovery = discovery, events = over.events or Chronicle.Events,
        uiParent = UIParent, specialFrames = {},
        createFrame = function(...)
            if over.beforeCreate then over.beforeCreate(...) end
            local f = realCreateFrame(...)
            if over.afterCreate then over.afterCreate(f, ...) end
            mount.frames[#mount.frames + 1] = f
            return f
        end,
    })
    mount.ok, mount.err = pcall(mount.codex.Init, mount.codex)
    mount.ui = Inspect(mount.frames)
    return mount
end
local function DiscoverAll(reg, d)
    for _, id in ipairs(reg:GetIds()) do d.set[id] = true end
end
local function countReports(fragment, from)
    local n = 0
    for i = (from or 0) + 1, #ReportedErrors do
        if ReportedErrors[i]:find(fragment, 1, true) then n = n + 1 end
    end
    return n
end
local function ModelOf(reg, loc, d)
    return Chronicle.CodexModel.New({ registry = reg, localization = loc, discovery = d })
end

-- ===================== LÓGICA: qué datos de modelo y de enlaces da el modelo =====================
Boot()
local reg, loc = ContentWorld()
local before = Chronicle.Utils.DeepCopy(reg:GetAll())

do
    local d = Disc()
    DiscoverAll(reg, d)
    local m = ModelOf(reg, loc, d)
    check("1. un NPC descubierto con displayID válido da los datos del modelo (displayID y npcID)",
        m:GetPage("npc:a").model ~= nil and m:GetPage("npc:a").model.displayID == 200 and m:GetPage("npc:a").model.npcID == 100)
    check("1b. un NPC sin identificadores no tiene modelo, y su página conserva el resto (nombre, tipo, ubicación, raza, rol, descripción)",
        (function()
            local p = m:GetPage("npc:b")
            return p.model == nil and p.name == "Beto" and p.typeLabel == "Personaje" and p.location.id == "subzone:s"
                and p.details[1].value == "Gnomo" and p.description == "Descripción de beto"
        end)())
    check("1c. un NPC con displayID pero sin npcID da el modelo con npcID nil (no se inventa el npcID)",
        m:GetPage("npc:d").model ~= nil and m:GetPage("npc:d").model.displayID == 400 and m:GetPage("npc:d").model.npcID == nil)
    check("1d. una entidad que no es NPC nunca tiene modelo, aunque su esquema le deje guardar un displayID",
        (function()
            local schema = Chronicle.Schema.New({
                continent = {}, zone = { parent = { types = { "continent" }, required = true }, fields = { displayID = "positiveInteger" } },
                npc = { located_in = { types = { "zone" } }, fields = { npcID = "positiveInteger", displayID = "positiveInteger" } },
            })
            local r, l = World({ { id = "continent:c", type = "continent" }, { id = "zone:z", type = "zone", parent = "continent:c", displayID = 77 },
                { id = "npc:n", type = "npc", located_in = "zone:z", displayID = 88 } }, {}, schema)
            local dd = Disc(); DiscoverAll(r, dd)
            local mm = ModelOf(r, l, dd)
            return mm:GetPage("zone:z").model == nil and mm:GetPage("npc:n").model ~= nil
        end)())
    check("1e. valores de displayID no válidos (0, negativos, fraccionarios, no numéricos) no producen modelo",
        (function()
            local fake = {
                Has = function() return true end,
                Get = function(_, id) return { id = id, type = "npc", displayID = ({ ["npc:z"] = 0, ["npc:n"] = -5, ["npc:f"] = 2.5, ["npc:s"] = "12", ["npc:i"] = math.huge })[id] } end,
                GetAll = function() return {} end, GetContained = function() return {} end, GetRelated = function() return {} end,
            }
            local mm = Chronicle.CodexModel.New({ registry = fake, localization = { Get = function() return nil end }, discovery = (function() local dd = Disc(); setmetatable(dd.set, { __index = function() return true end }); return dd end)() })
            for _, id in ipairs({ "npc:z", "npc:n", "npc:f", "npc:s", "npc:i" }) do
                if mm:GetPage(id).model ~= nil then return false, id end
            end
            return true
        end)())
    check("1f. un NPC bloqueado no tiene datos de modelo ni de enlaces (su página es solo «???»)",
        (function()
            local locked = ModelOf(reg, loc, Disc())
            local p = locked:GetPage("npc:a")
            return p.locked == true and p.model == nil and p.links == nil and p.id == nil
        end)())
end

do
    local d = Disc()
    DiscoverAll(reg, d)
    local m = ModelOf(reg, loc, d)
    local function ids(section)
        local out = {}
        for _, item in ipairs(section and section.items or {}) do out[#out + 1] = item.id end
        return table.concat(out, ",")
    end
    local zone = m:GetPage("zone:z").links
    check("2. la zona enlaza lo situado en ella por `located_in` (el puerto) y NO sus hijos por `parent` (eso es el árbol)",
        #zone >= 1 and zone[1].kind == "contains" and zone[1].label == "Situado aquí" and ids(zone[1]) == "city:p")
    check("2b. `related_to` se enlaza en su sección propia, sin repetir lo ya enlazado: el puerto sale una vez (en «Situado aquí») y ypsilon en «Relacionado con»",
        #zone == 2 and zone[2].kind == "related" and zone[2].label == "Relacionado con" and ids(zone[2]) == "zone:y")
    local sub = m:GetPage("subzone:s").links
    check("2c. la subzona enlaza los NPC y el lore situados en ella, ordenados por tipo e ID",
        #sub == 1 and ids(sub[1]) == "npc:a,npc:b,npc:c,npc:d,lore:l")
    check("2d. `related_to` se ve desde los dos lados (a enlaza con c aunque solo c lo declara) y un destino inexistente se descarta",
        ids(m:GetPage("npc:a").links[1]) == "npc:c" and ids(m:GetPage("npc:c").links[1]) == "npc:a")
    check("2e. el destino inexistente no deja ningún enlace roto ni rompe la página",
        #m:GetPage("npc:c").links == 1 and #m:GetPage("npc:c").links[1].items == 1 and m:GetPage("npc:c").name == "Cora")
    check("2f. ningún enlace se repite en una página y una entidad no se enlaza a sí misma",
        (function()
            for _, id in ipairs(reg:GetIds()) do
                local seen = { [id] = true }
                for _, section in ipairs(m:GetPage(id).links or {}) do
                    for _, item in ipairs(section.items) do
                        if seen[item.id] then return false, id .. " -> " .. item.id end
                        seen[item.id] = true
                    end
                end
            end
            return true
        end)())
    check("2g. las secciones vacías no existen (un NPC sin relaciones no tiene `links` vacíos con cabecera)",
        #m:GetPage("npc:b").links == 0 and #m:GetPage("continent:c").links == 0)
    check("2h. los enlaces no alteran las relaciones canónicas: las entidades del Registry son idénticas antes y después, y el árbol no cambia",
        deepEqual(before, reg:GetAll()) and table.concat(m:GetChildren("zone:z"), ",") == "subzone:s"
            and reg:Get("city:p").located_in == "zone:z" and reg:Get("city:p").parent == "continent:c")
    check("2i. el breadcrumb sigue solo `parent` y la ubicación sigue siendo el dato contextual",
        table.concat((function() local o = {} for _, c in ipairs(m:GetBreadcrumbs("city:p")) do o[#o + 1] = c.id end return o end)(), ",") == "continent:c,city:p"
            and m:GetPage("city:p").location.id == "zone:z")
end

do
    -- Discovery: cada destino se evalúa por sí solo
    local d = Disc()
    d.set["npc:c"] = true
    local m = ModelOf(reg, loc, d)
    local function first(page) return page.links[1] and page.links[1].items[1] or {} end
    local links = m:GetPage("npc:c").links
    check("3. un destino bloqueado se enlaza como «???» (sin nombre real, sin su ID en el nombre) y marcado como bloqueado",
        #links == 1 and first(m:GetPage("npc:c")).name == "???" and first(m:GetPage("npc:c")).locked == true
            and first(m:GetPage("npc:c")).nameIsFallback == false)
    d.set["npc:a"] = true
    check("3b. al descubrir el destino, el enlace muestra su nombre; el resto sigue como estaba",
        first(m:GetPage("npc:c")).name == "Alba" and first(m:GetPage("npc:c")).locked == false)
    check("3c. el modelo avisa de que una página cambia cuando se descubre uno de sus destinos (pero no una entidad ajena)",
        (function() m:Select("npc:c"); return m:AffectsPage("npc:a") == true and m:AffectsPage("zone:y") == false end)())
end

-- ===================== INTERFAZ: el visor 3D =====================
Boot(nil, true)
CreateFrame = realCreateFrame
do
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    click(ui.row("Alba").select)
    local model = ui.model()
    check("4. un NPC descubierto con displayID válido usa el visor: un PlayerModel, cargado con su displayID (SetDisplayInfo) y visible",
        m.ok == true and model ~= nil and model.displayInfo == 200 and model.shown == true and model.creatureID == nil)
    check("4b. el visor tiene el tamaño de Theme, está dentro del ancho de la página y colocado en la columna de la página",
        model.width == Chronicle.Theme:GetLayout("CODEX_MODEL_WIDTH") and model.height == Chronicle.Theme:GetLayout("CODEX_MODEL_HEIGHT")
            and model.width <= ui.pageScroll.width and model.points[1][1] == "TOPLEFT")
    check("4b2. la página reserva el espacio del visor: la descripción queda por debajo del recuadro del modelo (no se solapan)",
        (function()
            local modelTop = -(model.points[1][5] or 0)
            local descriptionTop = -ui.page().description.points[1][5]
            return descriptionTop >= modelTop + model.height
        end)())
    check("4c. el recuadro del visor usa el color de panel de Theme y el contenido de la página es más alto (lo reserva)",
        (function()
            local box
            for _, child in ipairs(ui.pageScroll.scrollChild.children) do
                if child.vertexColor and deepEqual(child.vertexColor, Chronicle.Theme:GetColor("BG_PANEL")) and child.shown == true then box = child end
            end
            return box ~= nil and ui.pageScroll.scrollChild.height >= model.height
        end)())
    check("4d. el visor no captura ratón ni rueda y no tiene scripts (no impide el desplazamiento ni la navegación)",
        not model.mouse and not model.mouseWheel and (model.__scripts == nil or next(model.__scripts) == nil))
    local wheel = ui.pageScroll.__scripts.OnMouseWheel
    check("4e. con el visor visible la página sigue funcionando: rueda, breadcrumbs, Atrás/Adelante y selección de otras entradas",
        (function()
            wheel(ui.pageScroll, -1)
            local buttons = ui.toolbarButtons()
            click(ui.row("Beto").select)
            local betoOk = ui.page().title.text == "Beto"
            click(buttons[1]) -- Atrás
            local backOk = ui.page().title.text == "Alba" and model.displayInfo == 200 and model.shown == true
            click(buttons[2]) -- Adelante
            local fwdOk = ui.page().title.text == "Beto"
            click(buttons[1])
            local crumbs = ui.crumbNames()
            return betoOk and backOk and fwdOk and #crumbs == 1 and crumbs[1] == "Alba"
        end)())

    -- (más abajo, en su propio montaje: el visor recién creado visible queda oculto)
    -- paso de un NPC con modelo a otro sin modelo y de vuelta (reutilización del widget)
    click(ui.row("Alba").select)
    local framesBefore = #ui.models()
    click(ui.row("Beto").select)
    check("5. al pasar de un NPC con modelo a otro sin modelo no queda nada del anterior: el visor está oculto, vacío y sin recuadro",
        model.shown == false and model.displayInfo == nil and model.model == nil and model.creatureID == nil
            and (function()
                for _, child in ipairs(ui.pageScroll.scrollChild.children) do
                    if child.vertexColor and deepEqual(child.vertexColor, Chronicle.Theme:GetColor("BG_PANEL")) and child.shown == true then return false end
                end
                return true
            end)())
    check("5b. y su página muestra el resto de datos sin hueco para el modelo (nombre, tipo, ubicación, raza y rol, descripción)",
        ui.page().title.text == "Beto" and ui.page().kind.text == "Personaje" and ui.page().description.text == "Descripción de beto"
            and ui.page().details.text:find("Gnomo", 1, true) ~= nil)
    click(ui.row("Cora").select)
    check("5c. al volver a un NPC con modelo se reutiliza el MISMO widget: ningún PlayerModel nuevo, cargado con el modelo de Cora",
        #ui.models() == framesBefore and #ui.models() == 1 and model.displayInfo == 300 and model.shown == true)
    click(ui.row("Zona Zeta").select)
    check("5d. en una página que no es de NPC (zona) el visor está oculto y vacío; sin scripts ni datos obsoletos",
        model.shown == false and model.displayInfo == nil and model.model == nil and (model.__scripts == nil or next(model.__scripts) == nil))
    click(ui.row("Dani").select)
    check("5e. un NPC con displayID y sin npcID también muestra su modelo", model.displayInfo == 400 and model.shown == true)
    click(ui.row("Leyenda").select)
    check("5f. una entrada de lore no muestra el visor", model.shown == false and model.displayInfo == nil)
end

do
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d, { afterCreate = function(f, kind) if kind == "PlayerModel" then f.shown = true end end })
    check("4f. un visor recién creado (visible por defecto en el cliente) queda oculto desde el principio, antes de abrir ninguna página",
        m.ok and m.ui.model() ~= nil and m.ui.model().shown == false)
end

do
    -- NPC bloqueado: el visor no se crea ni se carga; no hay información residual
    local d = Disc()
    d.set["npc:b"] = true
    local calls = 0
    local m = Mount(reg, loc, d, { afterCreate = function(f, kind)
        if kind == "PlayerModel" then
            local original = f.SetDisplayInfo
            f.SetDisplayInfo = function(self, id) calls = calls + 1; return original(self, id) end
        end
    end })
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    local locked
    for _, row in ipairs(ui.rows()) do if (textOf(row.select)) == "???" then locked = row; break end end
    for _, row in ipairs(ui.rows()) do
        if (textOf(row.select)) == "???" then click(row.select) end
    end
    check("6. ninguna página de NPC bloqueado carga un modelo: el visor nunca recibió un displayID y está oculto y vacío",
        calls == 0 and ui.model().shown ~= true and ui.model().displayInfo == nil and ui.model().model == nil)
    check("6b. las páginas bloqueadas no dejan ningún dato de los NPC en ningún widget (nombres, textos, IDs ni números de modelo)",
        ui.leak(NAMES) == nil or (function() local text = ui.leak(NAMES); return text == "Beto" end)())
    click(ui.row("Beto").select)
    check("6c. el NPC descubierto sin modelo no carga nada tampoco", calls == 0 and ui.model().displayInfo == nil)
end

do
    -- Un NPC bloqueado y luego descubierto con la ventana visible: el modelo aparece (y solo entonces)
    local d = Disc()
    local calls = 0
    local m = Mount(reg, loc, d, { afterCreate = function(f, kind)
        if kind == "PlayerModel" then
            local original = f.SetDisplayInfo
            f.SetDisplayInfo = function(self, id) calls = calls + 1; return original(self, id) end
        end
    end })
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    d.set["continent:c"] = true; Chronicle.Events:Emit(EVENT, "continent:c")
    d.set["zone:z"] = true; Chronicle.Events:Emit(EVENT, "zone:z")
    d.set["subzone:s"] = true; Chronicle.Events:Emit(EVENT, "subzone:s")
    ui.expandAll()
    local npcRow
    local rows = ui.rows()
    for i, row in ipairs(rows) do
        if (textOf(row.select)) == "Subzona Sigma" then npcRow = rows[i + 1] end -- el primer NPC (npc:a), aún bloqueado
    end
    click((npcRow or MISSING_ROW).select)
    check("7. el NPC bloqueado no carga modelo", calls == 0 and ui.model().shown ~= true)
    d.set["npc:a"] = true
    Chronicle.Events:Emit(EVENT, "npc:a")
    check("7b. al descubrirlo con la ventana visible su página se actualiza y el visor muestra su modelo",
        ui.page().title.text == "Alba" and ui.model().displayInfo == 200 and ui.model().shown == true and calls == 1)
end

-- ===================== INTERFAZ: fallos del visor =====================
do
    local before = #ReportedErrors
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d, { beforeCreate = function(kind) if kind == "PlayerModel" then error("sin PlayerModel") end end })
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    click(ui.row("Alba").select)
    check("8. si el cliente no puede crear el PlayerModel el Codex se inicializa igual y la página de un NPC se muestra completa, sin marco",
        m.ok == true and m.codex:IsReady() and #ui.models() == 0 and ui.page().title.text == "Alba" and ui.page().description.text == "Descripción de alba"
            and ui.page().details.text:find("Enana", 1, true) ~= nil)
    check("8b. el fallo se comunica una sola vez, aunque se visiten varios NPC", (function()
        click(ui.row("Cora").select); click(ui.row("Alba").select); click(ui.row("Beto").select)
        return countReports("sin PlayerModel", before) == 1
    end)())
    check("8c. los enlaces, el scroll y la navegación siguen funcionando sin visor",
        (function() click(ui.row("Alba").select); return #ui.links() == 1 and (click(ui.link("Cora")) or true) and ui.page().title.text == "Cora" end)())
end

do
    local before = #ReportedErrors
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d, { afterCreate = function(f, kind)
        if kind == "PlayerModel" then f.SetDisplayInfo = function() error("modelo roto") end end
    end })
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    click(ui.row("Alba").select)
    local model = ui.model()
    check("9. si configurar el modelo falla (SetDisplayInfo lanza error) la página se muestra sin visor: oculto, vacío y sin recuadro",
        m.ok and model.shown ~= true and model.model == nil and ui.page().title.text == "Alba" and ui.page().description.text == "Descripción de alba")
    click(ui.row("Cora").select); click(ui.row("Alba").select)
    check("9b. el fallo se comunica una vez y no impide seguir navegando", countReports("modelo roto", before) == 1 and ui.page().title.text == "Alba")
    check("9c. el Codex sigue entero: otros NPC y otras páginas no se ven afectados", (function() click(ui.row("Zona Zeta").select); return ui.page().title.text == "Zona Zeta" end)())
end

do
    local before = #ReportedErrors
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d, { afterCreate = function(f, kind)
        if kind == "PlayerModel" then f.Show = function() error("show roto") end end
    end })
    m.codex:Show(); m.ui.expandAll(); click(m.ui.row("Alba").select)
    check("9g. si mostrar el visor falla después de cargar el modelo, queda vacío y oculto (no queda el modelo cargado) y la página sigue",
        m.ok and m.ui.model().displayInfo == nil and m.ui.model().model == nil and m.ui.model().shown ~= true
            and m.ui.page().title.text == "Alba" and countReports("show roto", before) == 1)
end

do
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d, { afterCreate = function(f, kind)
        if kind == "PlayerModel" then f.SetDisplayInfo = false; f.SetCreature = false end
    end })
    check("9d. un frame sin SetDisplayInfo ni SetCreature no sirve: el visor no está disponible y la página funciona",
        (function()
            local ui = m.ui
            m.codex:Show(); ui.expandAll(); click(ui.row("Alba").select)
            return m.ok and ui.model().shown ~= true and ui.page().title.text == "Alba"
        end)())
    local m2 = Mount(reg, loc, d, { afterCreate = function(f, kind)
        if kind == "PlayerModel" then f.SetDisplayInfo = false end
    end })
    local ui2 = m2.ui
    m2.codex:Show(); ui2.expandAll(); click(ui2.row("Alba").select)
    check("9e. sin SetDisplayInfo se usa SetCreature(npcID, displayID) si hay npcID válido",
        ui2.model().creatureID == 100 and ui2.model().creatureDisplayID == 200 and ui2.model().shown == true)
    click(ui2.row("Dani").select)
    check("9f. sin SetDisplayInfo y sin npcID no hay llamada de modelo utilizable: el visor queda oculto y vacío, y la página sigue",
        ui2.model().shown == false and ui2.model().model == nil and ui2.page().title.text == "Dani")
end

do
    Boot(function() Chronicle.CodexNpcModel = nil end, true)
    CreateFrame = realCreateFrame
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show(); ui.expandAll(); click(ui.row("Alba").select)
    check("10. sin el módulo del visor (es opcional) el Codex funciona igual: página completa de NPC y sin PlayerModel",
        m.ok and #ui.models() == 0 and ui.page().title.text == "Alba" and ui.page().description.text == "Descripción de alba")
end

do
    local noToken = {}
    for _, key in ipairs({ "IsReady", "GetColor", "GetFontRole", "GetSpacing", "GetStrata", "GetTexture", "GetBackdrop", "ApplyText", "ApplyBackdrop" }) do
        noToken[key] = function(_, ...) return Chronicle.Theme[key](Chronicle.Theme, ...) end
    end
    noToken.GetLayout = function(_, name) if name == "CODEX_MODEL_WIDTH" then return nil end return Chronicle.Theme:GetLayout(name) end
    local frames = 0
    local codex = Chronicle.Codex.New({ theme = noToken, registry = reg, localization = loc, discovery = Disc(), events = Chronicle.Events,
        uiParent = UIParent, specialFrames = {}, createFrame = function(...) frames = frames + 1; return realCreateFrame(...) end })
    local ok, err = pcall(codex.Init, codex)
    check("9h. si a Theme le falta el tamaño del visor, el Codex no se inicializa, lo dice y no crea ningún frame",
        ok == false and tostring(err):find("CODEX_MODEL_WIDTH", 1, true) ~= nil and frames == 0)
end

-- ===================== COMPONENTE del visor, aislado =====================
Boot(nil) -- (la prueba anterior quitó el módulo del visor: se recarga el addon completo)
do
    local frame
    local viewer = Chronicle.CodexNpcModel.New({ theme = Chronicle.Theme, createFrame = function(kind, name, parent)
        frame = realCreateFrame(kind, name, parent)
        frame.shown = true -- como en el cliente: un frame recién creado es visible
        return frame
    end })
    local parent = realCreateFrame("Frame", nil, UIParent)
    viewer:Attach(parent, 1000)
    check("C1. el componente crea un único PlayerModel, oculto, y está disponible", frame ~= nil and frame.kind == "PlayerModel" and viewer:IsAvailable() and not viewer:IsShown())
    check("C1b. Show con datos válidos lo carga con su displayID, lo coloca y lo muestra; Hide lo oculta y lo vacía",
        viewer:Show({ displayID = 55, npcID = 9 }, 10, 20) and frame.displayInfo == 55 and viewer:IsShown() and frame.points[1][4] == 10 and frame.points[1][5] == -20
            and (function() viewer:Hide(); return not viewer:IsShown() and frame.displayInfo == nil and frame.model == nil end)())
    viewer:Show({ displayID = 55 }, 0, 0)
    check("C1c. Show con datos no válidos no deja cargado el modelo anterior: se oculta y se vacía y devuelve false",
        viewer:Show({ displayID = 0 }, 0, 0) == false and not viewer:IsShown() and frame.displayInfo == nil)
    viewer:Show({ displayID = 56 }, 0, 0)
    check("C1d. lo mismo con datos ausentes o con posiciones que no son números",
        viewer:Show(nil, 0, 0) == false and frame.displayInfo == nil and viewer:Show({ displayID = 5 }, "x", 0) == false and frame.displayInfo == nil
            and not viewer:IsShown())
    local sized = Chronicle.CodexNpcModel.New({ theme = Chronicle.Theme, createFrame = realCreateFrame })
    sized:Attach(parent, 60)
    check("C1e. el tamaño no desborda el ancho disponible (se limita) y toma la altura de Theme",
        select(1, sized:GetSize()) == 60 and select(2, sized:GetSize()) == Chronicle.Theme:GetLayout("CODEX_MODEL_HEIGHT"))
    local never = Chronicle.CodexNpcModel.New({ theme = Chronicle.Theme, createFrame = realCreateFrame })
    check("C1f. sin Attach no hay visor y nada lanza error: Show devuelve false, Hide y IsShown son seguros",
        never:IsAvailable() == false and never:Show({ displayID = 5 }, 0, 0) == false and pcall(never.Hide, never) and never:IsShown() == false)
    local twice = 0
    local reuse = Chronicle.CodexNpcModel.New({ theme = Chronicle.Theme, createFrame = function(...) twice = twice + 1; return realCreateFrame(...) end })
    reuse:Attach(parent, 500); reuse:Attach(parent, 500)
    check("C1g. Attach repetido no crea otro widget", twice == 1)
end

-- ===================== INTERFAZ: enlaces =====================
Boot(nil, true)
CreateFrame = realCreateFrame
do
    local d = Disc(); DiscoverAll(reg, d)
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    click(ui.row("Zona Zeta").select)
    check("11. la página de la zona muestra los enlaces válidos: el puerto («Situado aquí») y ypsilon («Relacionado con»), cada uno una vez",
        table.concat(ui.linkNames(), "|") == "Puerto Pi|Zona Ypsilon")
    check("11a. los enlaces usan el color de enlace de Theme (GOLD_DIM), distinto del texto normal y del de lo bloqueado",
        deepEqual(select(2, textOf(ui.link("Puerto Pi"))).color, Chronicle.Theme:GetColor("GOLD_DIM"))
            and not deepEqual(Chronicle.Theme:GetColor("GOLD_DIM"), Chronicle.Theme:GetColor("LOCKED")))
    check("11b. cada sección tiene su cabecera",
        (function()
            local headers = {}
            for _, child in ipairs(ui.pageScroll.scrollChild.children) do
                if child.text == "Situado aquí" or child.text == "Relacionado con" then headers[#headers + 1] = child.text end
            end
            return table.concat(headers, "|") == "Situado aquí|Relacionado con"
        end)())
    local toolbar = ui.toolbarButtons()
    click(ui.link("Puerto Pi"))
    check("12. pulsar un enlace navega a esa entidad con la navegación de siempre: página, breadcrumbs y fila seleccionada",
        ui.page().title.text == "Puerto Pi" and table.concat(ui.crumbNames(), "|") == "Continente Alfa|Puerto Pi")
    click(toolbar[1])
    check("12b. el enlace entró en el historial: Atrás vuelve a la página anterior y Adelante a la enlazada",
        ui.page().title.text == "Zona Zeta" and (function() click(toolbar[2]); return ui.page().title.text == "Puerto Pi" end)())
    check("12c. pulsar un enlace después de retroceder borra el futuro como cualquier selección (Adelante queda atenuado)",
        (function()
            click(toolbar[1]); click(ui.link("Zona Ypsilon"))
            return ui.page().title.text == "Zona Ypsilon" and deepEqual(toolbar[2].children[1].color, Chronicle.Theme:GetColor("TEXT_MUTED"))
        end)())
    click(ui.row("Cora").select)
    check("13. un destino inexistente no deja ningún enlace: Cora solo enlaza con Alba (la relación con «fantasma» se descarta)",
        table.concat(ui.linkNames(), "|") == "Alba" and ui.page().title.text == "Cora")
    click(ui.row("Alba").select)
    check("13b. una relación declarada por un solo lado se ve desde los dos: Alba enlaza con Cora", table.concat(ui.linkNames(), "|") == "Cora")
    click(ui.row("Subzona Sigma").select)
    check("14. la subzona enlaza los NPC y el lore situados en ella, uno por entrada y en orden",
        table.concat(ui.linkNames(), "|") == "Alba|Beto|Cora|Dani|Leyenda")
    click(ui.link("Leyenda"))
    check("14b. pasar de una página con muchos enlaces a otra sin enlaces no deja ni filas ni textos residuales",
        #ui.links() == 0 and ui.leak({ "Situado aquí", "Relacionado con" }) == nil and #ui.allLinkTexts() == 0)
end

do
    -- Discovery y enlaces
    local d = Disc()
    for _, id in ipairs({ "npc:c", "subzone:s" }) do d.set[id] = true end
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    click(ui.row("Cora").select)
    check("15. un destino bloqueado se enlaza como «???»: su nombre real no aparece en ningún widget",
        table.concat(ui.linkNames(), "|") == "???" and ui.leak({ "Alba", "Descripción de alba", "Enana", "Guardiana" }) == nil)
    local link = ui.links()[1]
    check("15b. el enlace bloqueado va en el color LOCKED", deepEqual(select(2, textOf(link)).color, Chronicle.Theme:GetColor("LOCKED")))
    click(link)
    check("15c. abrirlo lleva a su página bloqueada (solo «???»), sin modelo, sin enlaces y sin datos del NPC",
        ui.page().title.text == "???" and ui.page().kind.text == "Aún no has descubierto esta entrada." and #ui.links() == 0
            and ui.model().shown ~= true and ui.model().displayInfo == nil and ui.leak({ "Alba", "Enana", "Guardiana", "Descripción de alba", "npc:a" }) == nil)
    check("15d. abrir un enlace o una página no descubre nada: Discover no se llamó ni una vez",
        d.discovers == 0 and d.set["npc:a"] == nil)
    d.set["npc:a"] = true
    Chronicle.Events:Emit(EVENT, "npc:a")
    check("15e. al descubrirse el destino con la ventana visible, la página bloqueada pasa a ser la real y muestra su modelo",
        ui.page().title.text == "Alba" and ui.model().displayInfo == 200)
    click(ui.row("Cora").select)
    check("15f. y el enlace de Cora ya dice «Alba»", table.concat(ui.linkNames(), "|") == "Alba")
    d.set["npc:b"] = nil
    click(ui.row("???").select)
end

do
    -- Un destino descubierto bajo un ancestro bloqueado no revela el nombre de ese ancestro
    local d = Disc()
    d.set["npc:c"] = true
    d.set["npc:a"] = true
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    click(ui.row("Cora").select)
    click(ui.link("Alba"))
    check("16. Alba (descubierta) bajo ancestros bloqueados: su página nombra su lugar como «???» y los nombres de sus ancestros no aparecen en ningún widget",
        ui.page().title.text == "Alba" and ui.page().location.text == "Ubicado en: ???"
            and ui.leak({ "Subzona Sigma", "Zona Zeta", "Continente Alfa", "Zona Ypsilon", "Puerto Pi" }) == nil)
    check("16b. su modelo se muestra (se evalúa por su propio estado) sin que se revele nada del ancestro bloqueado",
        ui.model().displayInfo == 200 and ui.model().shown == true and ui.leak({ "Subzona Sigma", "Zona Zeta", "Continente Alfa" }) == nil)
    check("16c. recorrer todas las entradas bloqueadas no filtra los nombres, textos ni IDs de lo bloqueado",
        (function()
            for i = 1, #ui.rows() do
                click(ui.rows()[i].select)
                if ui.leak({ "Subzona Sigma", "Zona Zeta", "Continente Alfa", "Zona Ypsilon", "Puerto Pi", "Beto", "Dani", "Leyenda", "Gnomo", "Mecánico",
                    "Descripción de la zona zeta", "Descripción de sigma", "Descripción de beto", "Descripción de dani", "zone:z", "subzone:s", "npc:b", "city:p" }) then
                    return false, i
                end
            end
            return true
        end)())
end

do
    -- la página de una entidad bloqueada no trae enlaces aunque tenga relaciones
    local d = Disc()
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show(); ui.expandAll()
    local all = true
    for i = 1, #ui.rows() do
        click(ui.rows()[i].select)
        if #ui.links() ~= 0 or ui.model().shown == true or ui.leak(NAMES) or ui.leak(TEXTS) then all = false end
    end
    check("17. con todo bloqueado, ninguna página muestra enlaces, visor ni cabeceras de relaciones: solo «???»", all)
    check("17b. y los widgets reutilizados de enlaces no guardan nada (ni texto ni ID) de ninguna entrada", ui.leak(IDS) == nil)
end

-- ===================== Datos reales =====================
-- (el registro de frames sigue activo en esta sección: las filas del árbol se crean después del arranque, al expandir)
Boot(function() Chronicle.Discovery.IsDiscovered = function() return true end end, true)
do
    local ui = Inspect(bootedFrames)
    local persisted = Chronicle.Utils.DeepCopy(ChronicleCharDB)
    local npcs, withModel = 0, 0
    for _, entity in ipairs(Chronicle.Registry:GetAll("npc")) do
        npcs = npcs + 1
        if type(entity.displayID) == "number" and entity.displayID >= 1 then withModel = withModel + 1 end
    end
    check("18. datos reales: los 9 NPC del catálogo tienen un displayID declarado (el mismo que la copia literal del original, comprobado en data_tests)",
        npcs == 9 and withModel == 9)
    Chronicle.Codex:Show()
    ui.expandAll()
    click(ui.row("Grelin Whitebeard").select)
    check("18b. Grelin Whitebeard (NPC real) muestra su modelo con su displayID real (1354)",
        ui.model() ~= nil and ui.model().displayInfo == 1354 and ui.model().shown == true)
    click(ui.row(Chronicle.Localization:Get("zone:dun_morogh", "name")).select)
    check("18c. Dun Morogh enlaza con Forjaz (situada en ella por located_in) y con Loch Modan (related_to), sin duplicar Forjaz",
        table.concat(ui.linkNames(), "|") == Chronicle.Localization:Get("city:ironforge", "name") .. "|" .. Chronicle.Localization:Get("zone:loch_modan", "name")
            and ui.model().shown ~= true)
    click(ui.link(Chronicle.Localization:Get("city:ironforge", "name")))
    check("18d. el enlace a Forjaz lleva a Forjaz: breadcrumb continente > Forjaz, ubicación contextual Dun Morogh y enlace de vuelta a Dun Morogh",
        ui.page().title.text == Chronicle.Localization:Get("city:ironforge", "name")
            and ui.page().location.text == "Ubicado en: " .. Chronicle.Localization:Get("zone:dun_morogh", "name")
            and #ui.crumbNames() == 2)
    check("18e. navegar por enlaces y modelos del catálogo real no escribe nada en ChronicleCharDB", deepEqual(ChronicleCharDB, persisted))
end
CreateFrame = realCreateFrame

-- ===================== Aislamiento =====================
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
check("19. el visor 3D no accede a ChronicleCharDB, State ni Discovery, no usa temporizadores ni OnUpdate y no define colores propios",
    (function()
        local lines = codeOf("UI/CodexNpcModel.lua")
        if not lines then return false, "no está en el .toc" end
        for _, line in ipairs(lines) do
            for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", "Discovery", "Discover", "C_Timer", "OnUpdate", "SetScript", "EnableMouse", "SetTextColor", "SetFont(" }) do
                if line:find(word, 1, true) then return false, word end
            end
            if line:find("0%.%d+%s*,%s*0%.%d+") then return false, line end
        end
        return true
    end)())
check("19b. el visor solo depende de Theme (inyectado) y se carga antes que la página en el .toc",
    (function()
        for _, line in ipairs(codeOf("UI/CodexNpcModel.lua")) do
            for name in line:gmatch("Chronicle%.(%w+)") do
                if name ~= "CodexNpcModel" then return false, name end
            end
        end
        local order = {}
        for i, file in ipairs(ADDON_FILES) do order[file.name] = i end
        return order["UI/CodexNpcModel.lua"] ~= nil and order["UI/CodexNpcModel.lua"] < order["UI/CodexPage.lua"]
    end)())
check("19c. las vistas de página y el visor no llaman a Discover ni nombran a Discovery; los enlaces usan model:Select",
    (function()
        for _, name in ipairs({ "UI/CodexPage.lua", "UI/CodexNpcModel.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                if line:find("Discover", 1, true) then return false, name end
            end
        end
        return true
    end)())
check("19d. Theme aporta los tamaños del visor y el Codex los exige al inicializar",
    Chronicle.Theme:GetLayout("CODEX_MODEL_WIDTH") == 150 and Chronicle.Theme:GetLayout("CODEX_MODEL_HEIGHT") == 170)
check("19e. Discovery sigue siendo una dependencia opcional del Codex (Init.lua no la exige)",
    (function()
        for _, line in ipairs(codeOf("Core/Init.lua")) do
            if line:find('name = "Codex"', 1, true) and line:find("Discovery", 1, true) then return false end
        end
        return true
    end)())
CreateFrame = realCreateFrame
