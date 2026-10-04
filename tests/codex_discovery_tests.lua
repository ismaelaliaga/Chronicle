-- Escenarios de prueba de la integración Discovery <-> Codex (Fase 10). Dos niveles, que no hay que confundir:
--   · LÓGICA (CodexModel): qué entidades se consideran descubiertas y qué datos devuelve el modelo de las que no.
--   · INTERFAZ con el mock estricto: se pulsan los botones reales y se leen TODOS los textos de TODOS los widgets (también
--     los ocultos y los reutilizados) para detectar fugas del contenido bloqueado.
-- Esto NO demuestra que nada se filtre ni se vea bien en el cliente real de Classic Era.

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

-- Lee la interfaz de un Codex a partir de la lista de TODOS sus frames.
local function Inspect(source)
    local function F()
        if type(source) == "function" then return source() end
        return source
    end
    local ui = { frames = F() }
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
    function ui.labels()
        local out = {}
        for _, row in ipairs(ui.rows()) do out[#out + 1] = (textOf(row.select)) end
        return out
    end
    function ui.page()
        local c = ui.pageScroll.scrollChild.children
        return { title = c[1], kind = c[2], location = c[3], details = c[4], description = c[5], rule = c[6], body = c[7], empty = c[8] }
    end
    function ui.crumbs()
        local out, index = {}, 0
        for _, f in ipairs(F()) do
            if f.kind == "Button" and f.parent == ui.toolbar then
                index = index + 1
                if index > 2 and f.shown == true then out[#out + 1] = f end
            end
        end
        return out
    end
    function ui.crumbNames()
        local out = {}
        for _, b in ipairs(ui.crumbs()) do out[#out + 1] = (textOf(b)) end
        return out
    end
    -- TODOS los textos de TODOS los widgets, también los ocultos o reutilizados (lo que podría leer una herramienta de accesibilidad).
    function ui.allTexts()
        local out = {}
        for _, f in ipairs(F()) do
            for _, child in ipairs(f.children or {}) do
                if type(child.text) == "string" and child.text ~= "" then out[#out + 1] = child.text end
            end
            if type(f.name) == "string" then out[#out + 1] = f.name end
        end
        return out
    end
    -- Primer texto que contiene alguna de las cadenas prohibidas (comparación sin distinguir mayúsculas), o nil.
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
        for _ = 1, 8 do
            local changed = false
            for _, row in ipairs(ui.rows()) do
                if row.toggle.shown == true and (textOf(row.toggle)) == "+" then click(row.toggle); changed = true; break end
            end
            if not changed then break end
        end
    end
    return ui
end

-- Un Discovery de prueba: un conjunto de IDs descubiertos y los fallos que se quieran provocar.
local function Disc()
    local d = { set = {}, ready = true, calls = 0, EVENT_DISCOVERED = EVENT }
    d.IsReady = function()
        if d.readyError then error("IsReady roto") end
        return d.ready
    end
    d.IsDiscovered = function(_, id)
        d.calls = d.calls + 1
        if d.queryError then error("consulta rota") end
        return d.set[id]
    end
    return d
end

local function World(entities, texts)
    local registry = Chronicle.Registry.New(Chronicle.Schema)
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

-- Un mundo con SECRETOS reconocibles en cada campo, para buscarlos en toda la presentación.
local SECRETS = {
    "Mundo Secreto", "Valle Prohibido", "Cueva Oculta", "Sabio Arcano", "Tomo Prohibido", "Puerto Sombrío", "Nombre Alternativo",
    "Descripción secreta del valle", "Descripción de la cueva", "Descripción del sabio", "Resumen del tomo", "CUERPO SECRETO DEL TOMO",
    "Elfo de Sangre", "Archimago", "Pista secreta", "Descripción del puerto",
}
local SLUGS = {
    "continent:world", "zone:valley", "subzone:cave", "npc:sage", "lore:tome", "lore:tome_text", "city:port", "lore:valley_alias",
    "valley", "cave", "sage", "tome", "world", "port",
}
local function SecretWorld()
    return World({
        { id = "continent:world", type = "continent" },
        { id = "zone:valley", type = "zone", parent = "continent:world", nameKey = "lore:valley_alias" },
        { id = "subzone:cave", type = "subzone", parent = "zone:valley" },
        { id = "city:port", type = "city", parent = "continent:world", located_in = "zone:valley", related_to = { "zone:valley" } },
        { id = "npc:sage", type = "npc", located_in = "subzone:cave" },
        { id = "lore:tome", type = "lore", located_in = "zone:valley", textKey = "lore:tome_text" },
        { id = "lore:tome_text", type = "lore", located_in = "zone:valley" },
        { id = "lore:valley_alias", type = "lore", located_in = "continent:world" },
    }, {
        ["continent:world"] = { name = "Mundo Secreto" },
        ["zone:valley"] = { name = "Valle Prohibido", description = "Descripción secreta del valle" },
        ["lore:valley_alias"] = { name = "Nombre Alternativo" },
        ["subzone:cave"] = { name = "Cueva Oculta", description = "Descripción de la cueva" },
        ["city:port"] = { name = "Puerto Sombrío", description = "Descripción del puerto" },
        ["npc:sage"] = { name = "Sabio Arcano", description = "Descripción del sabio", race = "Elfo de Sangre", role = "Archimago", hint = "Pista secreta" },
        ["lore:tome"] = { name = "Tomo Prohibido", description = "Resumen del tomo" },
        ["lore:tome_text"] = { description = "CUERPO SECRETO DEL TOMO" },
    })
end

local function Mount(reg, loc, discovery, over)
    over = over or {}
    local mount = { frames = {} }
    local events = Chronicle.Events
    if over.events == false then events = nil elseif over.events then events = over.events end
    mount.codex = Chronicle.Codex.New({
        theme = Chronicle.Theme, registry = reg, localization = loc, discovery = discovery,
        events = events,
        uiParent = UIParent, specialFrames = {},
        createFrame = function(...)
            local f = realCreateFrame(...)
            mount.frames[#mount.frames + 1] = f
            return f
        end,
    })
    mount.codex:Init()
    mount.ui = Inspect(mount.frames)
    return mount
end
local function ModelOf(reg, loc, discovery)
    return Chronicle.CodexModel.New({ registry = reg, localization = loc, discovery = discovery })
end
local function ids(list)
    local out = {}
    for i, item in ipairs(list) do out[i] = type(item) == "table" and item.id or item end
    return out
end

-- ===================== LÓGICA: qué se considera descubierto =====================
Boot()
local reg, loc = SecretWorld()
check("0. el Codex arranca y queda listo con la integración (condición de las pruebas de interfaz de este fichero)", Chronicle.Codex:IsReady() == true)
if not Chronicle.Codex:IsReady() then
    CreateFrame = realCreateFrame
    do return end
end

do
    local d = Disc()
    local m = ModelOf(reg, loc, d)
    check("1. sin nada descubierto, todo está bloqueado: el nombre es «???» y no se da ni el nombre real ni el ID como reserva",
        (function()
            for _, id in ipairs(reg:GetIds()) do
                local name, fallback, locked = m:GetName(id)
                if name ~= "???" or fallback ~= false or locked ~= true then return false, id end
            end
            return true
        end)())
    d.set["npc:sage"] = true
    check("1b. una entidad descubierta muestra su nombre localizado; el resto sigue bloqueado (no es recursivo)",
        m:GetName("npc:sage") == "Sabio Arcano" and m:GetName("subzone:cave") == "???" and m:GetName("zone:valley") == "???"
            and m:GetName("continent:world") == "???")
    local page = m:GetPage("npc:sage")
    check("1c. la página de una descubierta conserva el comportamiento de la Fase 9: nombre, tipo, ubicación, raza, rol y descripción",
        page.name == "Sabio Arcano" and page.typeLabel == "Personaje" and page.description == "Descripción del sabio"
            and page.details[1].value == "Elfo de Sangre" and page.details[2].value == "Archimago" and page.location.id == "subzone:cave")
    check("1d. su ubicación contextual es «???» mientras el lugar siga bloqueado (no revela el nombre de la cueva)",
        page.location.name == "???" and page.location.locked == true)
    d.set["lore:tome"] = true; d.set["lore:tome_text"] = true
    check("1e. el cuerpo del artículo se muestra al estar descubierta la entrada (misma regla de la Fase 9: textKey)",
        m:GetPage("lore:tome").body == "CUERPO SECRETO DEL TOMO" and m:GetPage("lore:tome").description == "Resumen del tomo")
    d.set["lore:tome_text"] = nil
    check("1f. el cuerpo es parte de la propia entrada: se muestra si la entrada está descubierta aunque la entidad de textKey (un simple contenedor de texto) no lo esté",
        m:GetPage("lore:tome").body == "CUERPO SECRETO DEL TOMO")
    check("1g. y la entidad de textKey, si se abre por sí sola sin estar descubierta, sigue siendo «???» y no filtra el texto",
        m:GetPage("lore:tome_text").locked == true and m:GetPage("lore:tome_text").description == nil)
    d.set["lore:tome_text"] = true
end

do
    local d = Disc()
    local m = ModelOf(reg, loc, d)
    local locked = m:GetPage("npc:sage")
    local keys = {}
    for k in pairs(locked) do keys[#keys + 1] = k end
    table.sort(keys)
    check("2. la página bloqueada solo contiene lo mínimo: ni ID, ni tipo, ni ubicación, ni descripción, cuerpo, raza ni rol",
        table.concat(keys, ",") == "bodyUnresolved,details,locked,name,nameIsFallback" and locked.name == "???" and locked.locked == true
            and #locked.details == 0 and locked.id == nil and locked.type == nil and locked.typeLabel == nil and locked.location == nil
            and locked.description == nil and locked.body == nil)
    check("2b. el modelo no deja pasar el nombre real en ningún dato de la página bloqueada",
        (function()
            local function scan(value)
                if type(value) == "string" then
                    for _, bad in ipairs(SECRETS) do if value:find(bad, 1, true) then return false end end
                    for _, bad in ipairs(SLUGS) do if value:find(bad, 1, true) then return false end end
                elseif type(value) == "table" then
                    for k, v in pairs(value) do if not scan(k) or not scan(v) then return false end end
                end
                return true
            end
            for _, id in ipairs(reg:GetIds()) do if not scan(m:GetPage(id)) then return false, id end end
            return true
        end)())
    m:Select("zone:valley"); m:Select("subzone:cave"); m:Select("npc:sage")
    check("2c. los breadcrumbs del modelo usan «???» para lo bloqueado (la cueva y el sabio) y no traen nombres reales",
        (function()
            for _, crumb in ipairs(m:GetBreadcrumbs("subzone:cave")) do
                if crumb.name ~= "???" or crumb.locked ~= true then return false end
            end
            return #m:GetBreadcrumbs("subzone:cave") == 3
        end)())
    d.set["subzone:cave"] = true
    local crumbs = m:GetBreadcrumbs("subzone:cave")
    check("2d. con la cueva descubierta, sus ancestros bloqueados siguen siendo «???» en el breadcrumb y ella muestra su nombre",
        crumbs[1].name == "???" and crumbs[2].name == "???" and crumbs[3].name == "Cueva Oculta" and crumbs[3].locked == false)
end

-- ===================== LÓGICA: servicio ausente, no listo o roto =====================
do
    local cases = {
        { "sin servicio (nil)", nil },
        { "una tabla vacía", {} },
        { "sin IsReady", { IsDiscovered = function() return true end } },
        { "sin IsDiscovered", { IsReady = function() return true end } },
        { "IsReady devuelve false", (function() local d = Disc(); d.set["npc:sage"] = true; d.ready = false; return d end)() },
        { "IsReady devuelve algo que no es true", (function() local d = Disc(); d.set["npc:sage"] = true; d.ready = "sí"; return d end)() },
        { "IsDiscovered devuelve algo que no es true", { IsReady = function() return true end, IsDiscovered = function() return "true" end }, true },
        { "IsDiscovered devuelve 1", { IsReady = function() return true end, IsDiscovered = function() return 1 end }, true },
        { "una función que devuelve nil", function() return nil end },
    }
    local allLocked = true
    local failing = ""
    for _, case in ipairs(cases) do
        local m = ModelOf(reg, loc, case[2])
        local ok, name = pcall(m.GetName, m, "npc:sage")
        local okPage, page = pcall(m.GetPage, m, "npc:sage")
        local okRows, rows = pcall(m.GetRows, m)
        local rowsLocked = okRows and #rows > 0
        if okRows then for _, row in ipairs(rows) do if row.name ~= "???" or row.locked ~= true then rowsLocked = false end end end
        local okReady, discoveryReady = pcall(m.IsDiscoveryReady, m)
        if not (ok and name == "???" and okPage and page.locked == true and rowsLocked and okReady and discoveryReady == (case[3] == true)) then
            allLocked = false
            failing = failing .. case[1] .. "; "
        end
    end
    check("3. sin servicio, no listo o con respuestas que no son un true exacto, todo queda bloqueado sin lanzar errores " .. failing, allLocked)
    check("3b. y sin modelo de descubrimiento (la dependencia no se inyecta) el modelo también es seguro: todo bloqueado",
        (function()
            local m = Chronicle.CodexModel.New({ registry = reg, localization = loc })
            return m:GetName("npc:sage") == "???" and m:GetPage("zone:valley").locked == true
        end)())
end

do
    local before = #ReportedErrors
    local d = Disc()
    d.queryError = true
    local m = ModelOf(reg, loc, d)
    local ok1, name = pcall(m.GetName, m, "npc:sage")
    for _ = 1, 5 do m:GetRows(); m:GetPage("zone:valley") end
    local reported = 0
    for i = before + 1, #ReportedErrors do
        if ReportedErrors[i]:find("consulta rota", 1, true) then reported = reported + 1 end
    end
    check("4. si IsDiscovered lanza un error, la entidad NO se da por descubierta y el error se comunica una sola vez (no en cada repintado)",
        ok1 and name == "???" and reported == 1 and m:IsDiscovered("npc:sage") == false)
    local d2 = Disc()
    d2.readyError = true
    local m2 = ModelOf(reg, loc, d2)
    local before2 = #ReportedErrors
    check("4b. si IsReady lanza un error ocurre lo mismo: bloqueada, comunicado, sin excepción",
        pcall(m2.GetRows, m2) and m2:GetName("npc:sage") == "???" and #ReportedErrors == before2 + 1 and ReportedErrors[#ReportedErrors]:find("IsReady roto", 1, true) ~= nil)
    local m3 = ModelOf(reg, loc, function() error("sin servicio") end)
    check("4c. si la función que obtiene Discovery lanza un error, también queda todo bloqueado y sin excepción",
        pcall(m3.GetRows, m3) and m3:GetName("npc:sage") == "???" and m3:IsDiscovered("npc:sage") == false)
end

-- ===================== LÓGICA: el árbol y las relaciones no cambian =====================
do
    local locked, open = Disc(), Disc()
    for _, id in ipairs(reg:GetIds()) do open.set[id] = true end
    local mLocked, mOpen = ModelOf(reg, loc, locked), ModelOf(reg, loc, open)
    local function Open(m)
        for _ = 1, 8 do
            local changed = false
            for _, row in ipairs(m:GetRows()) do
                if row.hasChildren and not row.expanded then m:SetExpanded(row.id, true); changed = true end
            end
            if not changed then break end
        end
        return m:GetRows()
    end
    local rowsLocked, rowsOpen = Open(mLocked), Open(mOpen)
    check("5. las entradas bloqueadas siguen en el árbol: mismas filas, mismo orden y misma profundidad que con todo descubierto",
        #rowsLocked == reg:Count() and #rowsLocked == #rowsOpen and (function()
            for i, row in ipairs(rowsLocked) do
                if row.id ~= rowsOpen[i].id or row.depth ~= rowsOpen[i].depth or row.hasChildren ~= rowsOpen[i].hasChildren then return false end
            end
            return true
        end)())
    check("5b. el orden es determinista y no depende de qué esté descubierto (se calcula con el tipo y el ID, nunca con el nombre mostrado)",
        (function()
            local again = Open(ModelOf(reg, loc, Disc()))
            for i, row in ipairs(rowsLocked) do if again[i].id ~= row.id then return false end end
            return true
        end)())
    check("6. `parent` sigue siendo la jerarquía: los hijos de cada nodo son los mismos estén o no descubiertos",
        (function()
            for _, id in ipairs(reg:GetIds()) do
                if table.concat(mLocked:GetChildren(id), ",") ~= table.concat(mOpen:GetChildren(id), ",") then return false, id end
            end
            return true
        end)())
    check("6b. `located_in` no crea jerarquía: el puerto (ciudad situada en el valle) no cuelga del valle, aunque ambos estén bloqueados",
        (function()
            for _, c in ipairs(mLocked:GetChildren("zone:valley")) do if c == "city:port" then return false end end
            for _, c in ipairs(mLocked:GetChildren("continent:world")) do if c == "city:port" then return true end end
            return false
        end)())
    check("6c. `related_to` tampoco: el puerto está relacionado con el valle y no son padre e hijo",
        (function()
            for _, c in ipairs(mLocked:GetChildren("zone:valley")) do if c == "city:port" then return false end end
            return reg:GetRelated("zone:valley")[1] == "city:port"
        end)())
    check("6d. el NPC sigue colgando de su `located_in` y los breadcrumbs siguen solo `parent`: el sabio solo tiene su propio tramo",
        table.concat(mLocked:GetChildren("subzone:cave"), ",") == "npc:sage" and #mLocked:GetBreadcrumbs("npc:sage") == 1)
    mLocked:Select("npc:sage")
    local selected = 0
    for _, row in ipairs(mLocked:GetRows()) do if row.selected then selected = selected + 1 end end
    local before = mLocked:GetCurrent()
    mLocked:Toggle("zone:valley"); mLocked:Toggle("zone:valley")
    check("7. seleccionar una entrada bloqueada la marca como seleccionada y expandir o contraer no cambia la página",
        selected == 1 and mLocked:GetCurrent() == before and before == "npc:sage")
    check("7b. seleccionar, expandir y mostrar no descubren nada: el servicio no recibe ninguna escritura y el modelo no tiene Discover",
        mLocked.Discover == nil and next(locked.set) == nil)
end

-- ===================== INTERFAZ: ninguna fuga =====================
do
    local d = Disc()
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show()
    ui.expandAll()
    check("8. con todo bloqueado, el árbol completo se muestra como «???» y ningún texto de la interfaz contiene un nombre, descripción o ID reales",
        #ui.rows() == reg:Count() and (function()
            for _, label in ipairs(ui.labels()) do if label ~= "???" then return false end end
            return true
        end)() and ui.leak(SECRETS) == nil and ui.leak(SLUGS) == nil)
    -- recorrido exhaustivo: se selecciona CADA entrada y tras cada paso se buscan fugas en TODOS los widgets
    local leaks = {}
    local steps = 0
    for i = 1, #ui.rows() do
        local row = ui.rows()[i]
        click(row.select)
        steps = steps + 1
        local text, bad = ui.leak(SECRETS)
        local text2, bad2 = ui.leak(SLUGS)
        if text or text2 then leaks[#leaks + 1] = tostring(text or text2) .. " <- " .. tostring(bad or bad2) end
    end
    check("8b. recorrido exhaustivo: tras seleccionar cada entrada bloqueada, ninguno de los widgets (visibles, ocultos o reutilizados) contiene datos reales "
        .. table.concat(leaks, "; "), steps == reg:Count() and #leaks == 0)
    check("8c. la página de una entrada bloqueada es «???», el motivo y nada más; los demás elementos están vacíos y ocultos",
        (function()
            click(ui.row("???").select)
            local p = ui.page()
            return p.title.text == "???" and p.kind.text == "Aún no has descubierto esta entrada."
                and p.location.text == "" and p.details.text == "" and p.description.text == "" and p.body.text == ""
                and p.location.shown ~= true and p.description.shown ~= true and p.body.shown ~= true and p.rule.shown ~= true
        end)())
    check("8d. el título bloqueado va en el color LOCKED de Theme (no el oro de lo descubierto ni el de la selección)",
        deepEqual(ui.page().title.color, Chronicle.Theme:GetColor("LOCKED")) and not deepEqual(Chronicle.Theme:GetColor("LOCKED"), Chronicle.Theme:GetColor("GOLD"))
            and not deepEqual(Chronicle.Theme:GetColor("LOCKED"), Chronicle.Theme:GetColor("TEXT_MUTED")))
    check("8e. la fila bloqueada seleccionada conserva el fondo de selección pero su texto es LOCKED, no oro: bloqueada y seleccionada no se confunden",
        (function()
            local row = ui.rows()[1]
            click(row.select)
            local _, label = textOf(row.select)
            return row.select.children[1].shown == true and deepEqual(label.color, Chronicle.Theme:GetColor("LOCKED"))
        end)())
    check("8f. los breadcrumbs de una entrada bloqueada solo traen «???»",
        (function()
            for _, row in ipairs(ui.rows()) do
                if (textOf(row.select)) == "???" then
                    click(row.select)
                    for _, name in ipairs(ui.crumbNames()) do if name ~= "???" then return false end end
                end
            end
            return true
        end)())
    check("8g. la navegación Atrás/Adelante sobre entradas bloqueadas tampoco filtra nada",
        (function()
            local toolbarButtons = {}
            for _, f in ipairs(ui.frames) do if f.kind == "Button" and f.parent == ui.toolbar then toolbarButtons[#toolbarButtons + 1] = f end end
            for _ = 1, 5 do click(toolbarButtons[1]) end
            for _ = 1, 5 do click(toolbarButtons[2]) end
            return ui.leak(SECRETS) == nil and ui.leak(SLUGS) == nil
        end)())
end

-- ===================== INTERFAZ: descendientes bajo un ancestro bloqueado =====================
do
    local d = Disc()
    d.set["subzone:cave"] = true
    d.set["npc:sage"] = true
    local m = Mount(reg, loc, d)
    local ui = m.ui
    m.codex:Show()
    ui.expandAll()
    local labels = ui.labels()
    check("9. política de descendientes: cada entrada se evalúa por sí sola; una descendiente descubierta bajo ancestros bloqueados muestra su nombre y los ancestros siguen en «???»",
        (function()
            local named, locked = 0, 0
            for _, label in ipairs(labels) do
                if label == "Cueva Oculta" or label == "Sabio Arcano" then named = named + 1 elseif label == "???" then locked = locked + 1 end
            end
            return named == 2 and locked == #labels - 2
        end)())
    click(ui.row("Cueva Oculta").select)
    check("9b. su breadcrumb nombra solo lo descubierto: «???» / «???» / «Cueva Oculta»; nunca el continente ni el valle",
        table.concat(ui.crumbNames(), "|") == "???|???|Cueva Oculta" and ui.leak({ "Mundo Secreto", "Valle Prohibido", "Nombre Alternativo", "valley", "zone:valley" }) == nil)
    check("9b2. los tramos bloqueados del breadcrumb van en el color LOCKED y el tramo descubierto (la página actual) en oro",
        (function()
            local first = select(2, textOf(ui.crumbs()[1]))
            local last = select(2, textOf(ui.crumbs()[3]))
            return deepEqual(first.color, Chronicle.Theme:GetColor("LOCKED")) and deepEqual(last.color, Chronicle.Theme:GetColor("GOLD"))
        end)())
    click(ui.row("Sabio Arcano").select)
    local p = ui.page()
    check("9c. el sabio descubierto muestra todos sus datos, pero su ubicación contextual es «Ubicado en: Cueva Oculta» (descubierta); nada de lo bloqueado se cuela",
        p.title.text == "Sabio Arcano" and p.location.text == "Ubicado en: Cueva Oculta" and p.details.text:find("Elfo de Sangre", 1, true) ~= nil
            and p.description.text == "Descripción del sabio"
            and ui.leak({ "Mundo Secreto", "Valle Prohibido", "Nombre Alternativo", "Tomo Prohibido", "Puerto Sombrío", "CUERPO SECRETO", "Resumen del tomo", "valley" }) == nil)
    d.set["subzone:cave"] = nil
    m.codex:Hide(); m.codex:Show()
    click(ui.rows()[1].select) -- otra página, y de vuelta al sabio
    click(ui.row("Sabio Arcano").select)
    check("9d. si el lugar vuelve a estar bloqueado, la ubicación del sabio pasa a «???» (el nombre de la cueva no sobrevive en la página)",
        ui.page().location.text == "Ubicado en: ???" and ui.leak({ "Cueva Oculta" }) == nil)
end

-- ===================== INTERFAZ: actualización en vivo con el Discovery real =====================
local eventRegistrations = 0
Boot(function()
    Chronicle.DiscoveryNotice.Init = function() end -- (el aviso de descubrimiento registra su propio oyente: aquí se cuentan solo los del Codex)
    local events = Chronicle.Events
    local original = events.Register
    events.Register = function(self, name, callback)
        if name == EVENT then eventRegistrations = eventRegistrations + 1 end
        return original(self, name, callback)
    end
end, true)
do
    local ui = Inspect(bootedFrames)
    local codex = Chronicle.Codex
    local persisted = Chronicle.Utils.DeepCopy(ChronicleCharDB)
    check("10. con Discovery real y sin descubrimientos, el Codex arranca con todo bloqueado: una sola raíz «???»",
        codex:IsReady() and #ui.rows() == 1 and ui.labels()[1] == "???" and Chronicle.Discovery:Count() == 0)
    check("10b. el Codex se suscribe UNA vez al evento de Discovery al inicializarse", eventRegistrations == 1)
    for _ = 1, 10 do codex:Show(); codex:Hide(); codex:Toggle(); codex:Toggle(); codex:Hide() end
    codex:Init(); codex:Init()
    check("10c. abrir y cerrar muchas veces (y repetir Init) no duplica el manejador: sigue habiendo un único registro", eventRegistrations == 1)

    codex:Show()
    click(ui.row("???").toggle)
    local zoneRow
    for _, row in ipairs(ui.rows()) do if row.select ~= ui.rows()[1].select then zoneRow = row; break end end
    click((zoneRow or MISSING_ROW).select) -- una entrada bloqueada (la primera zona)
    check("11. antes de descubrir, la zona seleccionada es una página bloqueada",
        ui.page().title.text == "???" and ui.page().kind.text == "Aún no has descubierto esta entrada.")
    local ok, status = Chronicle.Discovery:Discover("zone:dun_morogh")
    check("11b. al descubrir la zona con la ventana visible, la fila y la página se actualizan al momento con su nombre y su descripción reales",
        ok == true and status == "new" and ui.page().title.text == Chronicle.Localization:Get("zone:dun_morogh", "name")
            and ui.page().description.text == Chronicle.Localization:Get("zone:dun_morogh", "description") and ui.page().kind.text == "Zona"
            and (function()
                for _, label in ipairs(ui.labels()) do if label == Chronicle.Localization:Get("zone:dun_morogh", "name") then return true end end
            end)())
    check("11c. el resto no se descubre por reflejo: la raíz y las demás zonas siguen bloqueadas (nada es recursivo)",
        ui.labels()[1] == "???" and Chronicle.Discovery:Count() == 1 and Chronicle.Discovery:IsDiscovered("continent:eastern_kingdoms") == false)
    check("11d. el breadcrumb se actualiza: el continente (bloqueado) en «???» y la zona con su nombre",
        table.concat(ui.crumbNames(), "|") == "???|" .. Chronicle.Localization:Get("zone:dun_morogh", "name"))

    -- descubrimiento con la ventana oculta
    codex:Hide()
    local labelBefore = ui.labels()[1]
    Chronicle.Discovery:Discover("continent:eastern_kingdoms")
    check("12. con la ventana oculta no se repinta nada: la fila conserva el texto anterior mientras sigue cerrada",
        ui.labels()[1] == labelBefore and labelBefore == "???" and codex:IsVisible() == false)
    codex:Show()
    check("12b. la siguiente apertura muestra el estado actual: el continente ya tiene su nombre",
        ui.labels()[1] == Chronicle.Localization:Get("continent:eastern_kingdoms", "name"))
    Chronicle.Discovery:Discover("continent:eastern_kingdoms") -- repetido: Discovery no emite
    check("12c. descubrir algo ya descubierto no cambia nada ni rompe la interfaz", ui.labels()[1] == Chronicle.Localization:Get("continent:eastern_kingdoms", "name"))

    -- ver una entrada no descubre
    local discoverCalls = 0
    local realDiscover = Chronicle.Discovery.Discover
    Chronicle.Discovery.Discover = function(self, ...) discoverCalls = discoverCalls + 1; return realDiscover(self, ...) end
    local countBefore = Chronicle.Discovery:Count()
    ui.expandAll()
    for i = 1, #ui.rows() do click(ui.rows()[i].select) end
    codex:Hide(); codex:Show(); codex:Toggle(); codex:Toggle()
    check("13. seleccionar, expandir y mostrar entradas (descubiertas o no) no genera ningún descubrimiento",
        discoverCalls == 0 and Chronicle.Discovery:Count() == countBefore)
    Chronicle.Discovery.Discover = realDiscover
    local expected = Chronicle.Utils.DeepCopy(persisted)
    expected.discovery.entries["zone:dun_morogh"] = {}
    expected.discovery.entries["continent:eastern_kingdoms"] = {}
    check("13b. lo único guardado en ChronicleCharDB son los dos descubrimientos explícitos: el renderizado no escribe nada",
        deepEqual(ChronicleCharDB, expected))
    check("13c. las entidades canónicas del Registry no cambian por el renderizado (las mismas copias que al arrancar)",
        (function()
            local a, b = Chronicle.Registry:GetAll(), Chronicle.Registry:GetAll()
            return #a == Chronicle.Registry:Count() and deepEqual(a, b) and Chronicle.Registry:Get("zone:dun_morogh").parent == "continent:eastern_kingdoms"
        end)())
end

-- descubrir con otro tipo de aviso malo no rompe nada
do
    local ui = Inspect(bootedFrames)
    local before = #ReportedErrors
    local ok1 = pcall(Chronicle.Events.Emit, Chronicle.Events, EVENT, "id:que_no_existe")
    local ok2 = pcall(Chronicle.Events.Emit, Chronicle.Events, EVENT)
    local ok3 = pcall(Chronicle.Events.Emit, Chronicle.Events, EVENT, 42)
    check("14. un aviso de Discovery con un ID inexistente, ausente o que no es una cadena se ignora sin errores",
        ok1 and ok2 and ok3 and #ReportedErrors == before and Chronicle.Codex:IsReady())
    check("14b. el Codex sigue mostrando lo que debía tras esos avisos", #ui.rows() >= 1)
end
do
    local reg2, loc2 = SecretWorld()
    local d = Disc()
    local m = Mount(reg2, loc2, d)
    m.codex:Show()
    local calls = d.calls
    Chronicle.Events:Emit(EVENT)
    Chronicle.Events:Emit(EVENT, 42)
    Chronicle.Events:Emit(EVENT, {})
    check("14c. un aviso sin ID válido no provoca ningún repintado (no se consulta el estado de ninguna entrada)", d.calls == calls)
end

-- ===================== Inicialización y fallos =====================
do
    local regs = 0
    Boot(function()
        Chronicle.Discovery.Init = function() error("discovery roto") end
        local events = Chronicle.Events
        local original = events.Register
        events.Register = function(self, name, callback)
            if name == EVENT then regs = regs + 1 end
            return original(self, name, callback)
        end
    end, true)
    local ui = Inspect(bootedFrames)
    check("15. si Discovery falla al arrancar, el Codex (opcional) se inicializa igual, con todo bloqueado y sin suscribirse a avisos que no llegarán",
        Chronicle.Init.failed.Discovery ~= nil and Chronicle.Codex:IsReady() == true and Chronicle.Init.failed.Codex == nil
            and Chronicle.Init.skipped.Codex == nil and regs == 0 and #ui.rows() == 1 and ui.labels()[1] == "???")
    check("15b. con Discovery caído abrir el Codex no lanza errores y no marca nada como descubierto",
        pcall(Chronicle.Codex.Show, Chronicle.Codex) and Chronicle.Discovery:IsDiscovered("zone:dun_morogh") == false
            and Chronicle.Discovery:Count() == 0)
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()
    local noEvents = Mount(reg2, loc2, (function() local d = Disc(); return d end)(), { events = false })
    noEvents.codex:Show()
    check("15c. sin bus de eventos el Codex funciona igual (sin actualización en vivo): todo bloqueado y utilizable",
        noEvents.codex:IsVisible() and #noEvents.ui.rows() == 1 and noEvents.ui.labels()[1] == "???")
    local d = Disc()
    local m2 = Mount(reg2, loc2, d, { events = false })
    m2.codex:Show()
    d.set["continent:world"] = true
    m2.codex:Hide(); m2.codex:Show()
    check("15d. sin aviso de Discovery, cada apertura repinta por completo: el estado mostrado es siempre el actual",
        m2.ui.labels()[1] == "Mundo Secreto")
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local failing = Chronicle.Codex.New({ theme = Chronicle.Theme, registry = Chronicle.Registry, localization = Chronicle.Localization,
        discovery = Chronicle.Discovery, events = { Register = function() error("bus roto") end },
        uiParent = UIParent, specialFrames = {}, createFrame = realCreateFrame })
    local before = #ReportedErrors
    local okInit = pcall(failing.Init, failing)
    check("15e. si el registro del aviso falla, el Codex se inicializa igual y el fallo se comunica",
        okInit and failing:IsReady() and #ReportedErrors == before + 1 and ReportedErrors[#ReportedErrors]:find("bus roto", 1, true) ~= nil)
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local calls = 0
    local reg2, loc2 = SecretWorld()
    local d = Disc()
    local m = Mount(reg2, loc2, d)
    local before = d.calls
    Chronicle.Events:Emit(EVENT, "zone:valley") -- oculta: no se consulta nada para pintar
    check("16. con la ventana oculta un aviso de Discovery no hace ningún trabajo de pintado (no se consulta el estado de ninguna fila)",
        d.calls == before and m.codex:IsVisible() == false)
    m.codex:Show()
    check("16b. al mostrarla sí se consulta y se repinta", d.calls > before)
    local afterShow = d.calls
    Chronicle.Events:Emit(EVENT, "zone:valley")
    check("16c. con la ventana visible un aviso repinta lo afectado", d.calls > afterShow)
end


-- ===================== Casos finos: ubicación, punto de lectura y restos en widgets ocultos =====================
do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()
    local d = Disc()
    d.set["npc:sage"] = true
    local m = Mount(reg2, loc2, d)
    m.codex:Show()
    m.ui.expandAll()
    click(m.ui.row("Sabio Arcano").select)
    check("18. la ubicación de una entrada descubierta con el lugar bloqueado es «???» y va en el color LOCKED",
        m.ui.page().location.text == "Ubicado en: ???" and deepEqual(m.ui.page().location.color, Chronicle.Theme:GetColor("LOCKED")))
    d.set["subzone:cave"] = true
    Chronicle.Events:Emit(EVENT, "subzone:cave")
    check("18b. al descubrir el lugar de la página actual, la ubicación se actualiza sin cambiar de página (aviso de Discovery)",
        m.ui.page().location.text == "Ubicado en: Cueva Oculta" and m.ui.page().title.text == "Sabio Arcano"
            and deepEqual(m.ui.page().location.color, Chronicle.Theme:GetColor("TEXT_MUTED")))
end

do
    local longText = string.rep("Texto largo de la entrada. ", 300)
    local reg2, loc2 = World({
        { id = "continent:a", type = "continent" }, { id = "zone:b", type = "zone", parent = "continent:a" },
        { id = "zone:c", type = "zone", parent = "continent:a" },
    }, { ["continent:a"] = { name = "A" }, ["zone:b"] = { name = "B", description = longText }, ["zone:c"] = { name = "C" } })
    local d = Disc()
    d.set["continent:a"] = true; d.set["zone:b"] = true
    local m = Mount(reg2, loc2, d)
    m.codex:Show()
    m.ui.expandAll()
    click(m.ui.row("B").select)
    local scroll = m.ui.pageScroll
    scroll.__scripts.OnMouseWheel(scroll, -1); scroll.__scripts.OnMouseWheel(scroll, -1)
    local offset = scroll.verticalScroll
    d.set["zone:c"] = true
    Chronicle.Events:Emit(EVENT, "zone:c")
    check("19. descubrir una entrada ajena a la página abierta actualiza el árbol pero no mueve el punto de lectura de la página",
        offset > 0 and scroll.verticalScroll == offset and m.ui.page().title.text == "B" and (function()
            for _, label in ipairs(m.ui.labels()) do if label == "C" then return true end end
        end)())
    d.set["continent:a"] = true
    Chronicle.Events:Emit(EVENT, "zone:b")
    check("19b. descubrir la propia página abierta la rehace (vuelve arriba)", scroll.verticalScroll == 0 and m.ui.page().title.text == "B")
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()
    local d = Disc()
    for _, id in ipairs(reg2:GetIds()) do d.set[id] = true end
    local m = Mount(reg2, loc2, d)
    m.codex:Show()
    m.ui.expandAll()
    check("20. con todo descubierto se ven todos los nombres reales (el filtro depende solo de Discovery)",
        m.ui.leak({ "Cueva Oculta" }) ~= nil and m.ui.leak({ "Sabio Arcano" }) ~= nil)
    for id in pairs(d.set) do d.set[id] = nil end
    click(m.ui.rows()[1].toggle) -- contrae a la vez que todo pasa a estar bloqueado: las filas que se ocultan no deben conservar su texto
    check("20b. las filas que se ocultan al contraer no conservan el nombre que tenían (ningún widget oculto guarda datos de lo bloqueado)",
        m.ui.leak(SECRETS) == nil and m.ui.leak(SLUGS) == nil)
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()
    local d = Disc()
    for _, id in ipairs(reg2:GetIds()) do d.set[id] = true end
    local m = Mount(reg2, loc2, d)
    m.codex:Show()
    m.ui.expandAll()
    click(m.ui.row("Cueva Oculta").select)
    check("21. con todo descubierto el breadcrumb de la cueva nombra continente, valle y cueva",
        table.concat(m.ui.crumbNames(), "|") == "Mundo Secreto|Nombre Alternativo|Cueva Oculta")
    for id in pairs(d.set) do d.set[id] = nil end
    click(m.ui.rows()[1].select) -- una página con un solo tramo: los otros dos se ocultan
    check("21b. los tramos de breadcrumb que dejan de usarse no conservan sus nombres anteriores",
        m.ui.leak(SECRETS) == nil and m.ui.leak(SLUGS) == nil and #m.ui.crumbs() == 1)
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local noLocked = {}
    for _, key in ipairs({ "IsReady", "GetFontRole", "GetSpacing", "GetStrata", "GetTexture", "GetBackdrop", "GetLayout", "ApplyText", "ApplyBackdrop" }) do
        noLocked[key] = function(_, ...) return Chronicle.Theme[key](Chronicle.Theme, ...) end
    end
    noLocked.GetColor = function(_, name) if name == "LOCKED" then return nil end return Chronicle.Theme:GetColor(name) end
    local frames = 0
    local codex = Chronicle.Codex.New({ theme = noLocked, registry = Chronicle.Registry, localization = Chronicle.Localization,
        discovery = Chronicle.Discovery, events = Chronicle.Events, uiParent = UIParent, specialFrames = {},
        createFrame = function(...) frames = frames + 1; return realCreateFrame(...) end })
    local ok, err = pcall(codex.Init, codex)
    check("22. si a Theme le falta el color LOCKED, el Codex no se inicializa, lo dice y no crea ningún frame",
        ok == false and tostring(err):find("LOCKED", 1, true) ~= nil and frames == 0 and codex:IsReady() == false)
end


-- ===================== Corrección: la suscripción a Discovery no puede romper la inicialización =====================
-- Regresión: Subscribe() preguntaba Discovery:IsReady() (y obtenía la dependencia) sin protección, DESPUÉS de construir la ventana
-- y marcar el Codex como listo; un error ahí salía de Init() con el Codex ya construido. Discovery es opcional.
local function SpyBus(register)
    local bus = { handlers = {}, calls = 0 }
    function bus:Register(name, callback)
        bus.calls = bus.calls + 1
        if register then return register(name, callback) end
        bus.handlers[#bus.handlers + 1] = callback
        return true
    end
    function bus:Emit(name, ...)
        for _, callback in ipairs(bus.handlers) do callback(...) end
    end
    return bus
end
local function countReports(fragment, from)
    local n = 0
    for i = (from or 0) + 1, #ReportedErrors do
        if ReportedErrors[i]:find(fragment, 1, true) then n = n + 1 end
    end
    return n
end
local function allLocked(ui)
    local labels = ui.labels()
    if #labels == 0 then return false end
    for _, label in ipairs(labels) do if label ~= "???" then return false end end
    return true
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()

    -- 1. obtener Discovery lanza un error
    local bus = SpyBus()
    local before = #ReportedErrors
    local frames = {}
    local codex = Chronicle.Codex.New({
        theme = Chronicle.Theme, registry = reg2, localization = loc2,
        discovery = function() error("sin servicio de descubrimiento") end, events = bus,
        uiParent = UIParent, specialFrames = {},
        createFrame = function(...) local f = realCreateFrame(...); frames[#frames + 1] = f; return f end,
    })
    local okInit, errInit = pcall(codex.Init, codex)
    local ui = Inspect(frames)
    check("R1. si obtener Discovery lanza un error, Init no lanza: el Codex queda inicializado, oculto y con una única ventana",
        okInit == true and codex:IsReady() == true and codex:IsVisible() == false and ui.win ~= nil and ui.win:IsShown() == false)
    check("R1b. sin Discovery utilizable no se registra ningún manejador (ni se intenta): el bus no recibe ninguna llamada",
        bus.calls == 0 and #bus.handlers == 0)
    check("R1c. todas las entradas quedan bloqueadas: filas «???», página bloqueada y sin datos reales en ningún widget",
        allLocked(ui) and ui.leak(SECRETS) == nil and ui.leak(SLUGS) == nil)
    local opened = pcall(function()
        for _ = 1, 10 do codex:Show(); codex:Hide() end
        codex:Show()
        ui.expandAll()
        for i = 1, #ui.rows() do click(ui.rows()[i].select) end
        codex:Toggle(); codex:Toggle()
    end)
    check("R1d. abrir, cerrar, expandir y seleccionar no lanzan errores, la ventana se abre y cierra de verdad y sigue todo bloqueado",
        opened and codex:IsVisible() == true and (function() codex:Hide(); return codex:IsVisible() == false end)()
            and ui.leak(SECRETS) == nil and ui.leak(SLUGS) == nil)
    check("R1e. el error se comunica UNA sola vez, aunque la ventana se abra y se repinte muchas veces",
        countReports("sin servicio de descubrimiento", before) == 1)
end

check("R2x. el bloque de IsReady roto se ejecuta entero sin excepciones (Init no deja escapar el error de Discovery)", pcall(function()
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()

    -- 2. IsReady lanza un error
    local d = Disc()
    d.set["continent:world"] = true
    d.readyError = true
    local bus = SpyBus()
    local before = #ReportedErrors
    local m = Mount(reg2, loc2, d, { events = bus })
    check("R2. si Discovery:IsReady lanza un error, el Codex queda inicializado y NO consulta ninguna entrada como descubierta",
        m.codex:IsReady() == true and d.calls == 0)
    check("R2b. no queda ningún manejador registrado por error (el bus no recibió llamadas)", bus.calls == 0 and #bus.handlers == 0)
    m.codex:Show()
    check("R2c. todas las entradas siguen bloqueadas aunque el estado de una esté marcado como descubierto en el servicio",
        allLocked(m.ui) and d.calls == 0 and m.ui.leak(SECRETS) == nil)
    for _ = 1, 10 do m.codex:Hide(); m.codex:Show() end
    click(m.ui.rows()[1].select); click(m.ui.rows()[1].toggle)
    check("R2d. el error se comunica una sola vez, no en cada apertura, selección o repintado",
        countReports("IsReady roto", before) == 1)

    -- 4. sin suscripción, cada apertura refresca el estado consultable
    d.readyError = false
    d.set["continent:world"] = true
    m.codex:Hide(); m.codex:Show()
    check("R2e. sin suscripción activa, al abrir se repinta con el estado consultable: el servicio ya responde y el continente muestra su nombre",
        m.ui.labels()[1] == "Mundo Secreto" and d.calls > 0)
    d.set["continent:world"] = nil
    d.set["zone:valley"] = true
    local callsBefore = d.calls
    bus:Emit(EVENT, "zone:valley")
    check("R2f. y como no hay manejador, un aviso del bus no hace nada con la ventana visible (nadie lo recibe)",
        d.calls == callsBefore and m.ui.labels()[1] == "Mundo Secreto")
end))

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()

    -- 6. comportamiento normal con Discovery disponible
    local d = Disc()
    local bus = SpyBus()
    local before = #ReportedErrors
    local m = Mount(reg2, loc2, d, { events = bus })
    check("R3. con Discovery disponible, listo y correcto el Codex se suscribe exactamente una vez",
        m.codex:IsReady() and bus.calls == 1 and #bus.handlers == 1)
    for _ = 1, 10 do m.codex:Show(); m.codex:Hide() end
    m.codex:Init(); m.codex:Init()
    check("R3b. abrir, cerrar y repetir Init no registran nada más", bus.calls == 1 and #bus.handlers == 1)
    m.codex:Show()
    d.set["continent:world"] = true
    bus:Emit(EVENT, "continent:world")
    check("R3c. con la ventana visible, el aviso de Discovery repinta: el continente muestra su nombre", m.ui.labels()[1] == "Mundo Secreto")
    m.codex:Hide()
    d.set["zone:valley"] = true
    local callsBefore = d.calls
    bus:Emit(EVENT, "zone:valley")
    check("R3d. con la ventana oculta el aviso no pinta nada y se aplica al abrir", d.calls == callsBefore)
    m.codex:Show()
    m.ui.expandAll()
    check("R3e. al abrir se ve el estado actual (el valle descubierto)", (function()
        for _, label in ipairs(m.ui.labels()) do if label == "Nombre Alternativo" then return true end end
    end)())
    check("R3f. sin ningún error comunicado", #ReportedErrors == before)
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()

    -- Events:Register devuelve false (esa función ya estaba registrada): no cuenta como suscripción activa
    local d = Disc()
    local rejecting = SpyBus(function() return false end)
    local before = #ReportedErrors
    local m = Mount(reg2, loc2, d, { events = rejecting })
    m.codex:Show()
    d.set["continent:world"] = true
    m.codex:Hide(); m.codex:Show()
    check("R4. si Events:Register no añade el manejador (devuelve false) el Codex no lo da por suscrito: cada apertura repinta con el estado actual",
        m.codex:IsReady() and rejecting.calls == 1 and m.ui.labels()[1] == "Mundo Secreto" and #ReportedErrors == before)

    -- un fallo de suscripción no hace al Codex dependiente de Discovery ni rompe nada
    local failingBus = SpyBus(function() error("bus roto") end)
    local d2 = Disc()
    local before2 = #ReportedErrors
    local m2 = Mount(reg2, loc2, d2, { events = failingBus })
    m2.codex:Show()
    d2.set["continent:world"] = true
    m2.codex:Hide(); m2.codex:Show()
    check("R4b. si Register lanza un error el Codex se inicializa, comunica el fallo una vez y se actualiza al abrir",
        m2.codex:IsReady() and countReports("bus roto", before2) == 1 and m2.ui.labels()[1] == "Mundo Secreto")
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()
    local d = Disc()
    local before = #ReportedErrors
    local frames = {}
    local codex = Chronicle.Codex.New({
        theme = Chronicle.Theme, registry = reg2, localization = loc2, discovery = d,
        events = function() error("sin bus de eventos") end, uiParent = UIParent, specialFrames = {},
        createFrame = function(...) local f = realCreateFrame(...); frames[#frames + 1] = f; return f end,
    })
    local okInit = pcall(codex.Init, codex)
    local ui = Inspect(frames)
    codex:Show()
    d.set["continent:world"] = true
    codex:Hide(); codex:Show()
    check("R6. si obtener el bus de eventos lanza un error, el Codex se inicializa igual, no se suscribe y se actualiza al abrir",
        okInit and codex:IsReady() and ui.labels()[1] == "Mundo Secreto" and d.calls > 0)
end

do
    Boot(nil, true)
    CreateFrame = realCreateFrame
    local reg2, loc2 = SecretWorld()
    -- Un Discovery inestable: obtenerlo falla en las llamadas alternas. Se prueban las dos paridades, así que alguna vez falla justo
    -- la obtención que hace Subscribe después de que el modelo ya lo obtuvo bien.
    for offset = 0, 1 do
        local d = Disc()
        local n = 0
        local bus = SpyBus()
        local before = #ReportedErrors
        local codex = Chronicle.Codex.New({
            theme = Chronicle.Theme, registry = reg2, localization = loc2,
            discovery = function() n = n + 1; if (n + offset) % 2 == 0 then error("servicio inestable") end return d end,
            events = bus, uiParent = UIParent, specialFrames = {}, createFrame = realCreateFrame,
        })
        local okInit, err = pcall(codex.Init, codex)
        check("R7. un Discovery que falla de forma intermitente nunca hace que Init lance un error (paridad " .. offset .. ")",
            okInit == true and codex:IsReady() == true and #bus.handlers <= 1)
        check("R7b. y el Codex sigue siendo utilizable: se abre y se cierra sin errores (paridad " .. offset .. ")",
            pcall(codex.Show, codex) and codex:IsVisible() and pcall(codex.Hide, codex) and not codex:IsVisible())
    end
    local d = Disc()
    d.EVENT_DISCOVERED = nil
    local bus = SpyBus()
    local m = Mount(reg2, loc2, d, { events = bus })
    local d2 = Disc()
    d2.EVENT_DISCOVERED = 42
    local bus2 = SpyBus()
    local m2 = Mount(reg2, loc2, d2, { events = bus2 })
    check("R7c. si Discovery no da un nombre de evento válido no se registra nada, y el Codex funciona (se repinta al abrir)",
        m.codex:IsReady() and bus.calls == 0 and m2.codex:IsReady() and bus2.calls == 0)
end

do
    -- 7. a nivel del addon completo: Discovery roto no impide arrancar al resto ni al Codex
    local registrations = 0
    Boot(function()
        Chronicle.Discovery.IsReady = function() error("IsReady roto en el arranque") end
        Chronicle.DiscoveryNotice.Init = function() end -- (ver arriba)
        local events = Chronicle.Events
        local original = events.Register
        events.Register = function(self, name, callback)
            if name == EVENT then registrations = registrations + 1 end
            return original(self, name, callback)
        end
    end, true)
    local ui = Inspect(bootedFrames)
    check("R5. con Discovery:IsReady roto en el arranque completo, el Codex se inicializa igual (no falla ni se omite) y no hay registros del aviso",
        Chronicle.Codex:IsReady() == true and Chronicle.Init.failed.Codex == nil and Chronicle.Init.skipped.Codex == nil and registrations == 0)
    check("R5b. los demás servicios y la interfaz arrancan: Registry, Localization, Resolver, Theme y Popup listos",
        Chronicle.Registry:IsValidated() and Chronicle.Localization:IsReady() and Chronicle.Resolver:IsReady()
            and Chronicle.Theme:IsReady() and Chronicle.Popup:IsReady())
    check("R5c. el Codex abre y cierra sin errores y todo está bloqueado",
        pcall(Chronicle.Codex.Show, Chronicle.Codex) and Chronicle.Codex:IsVisible() and allLocked(ui)
            and (function() Chronicle.Codex:Hide(); return not Chronicle.Codex:IsVisible() end)())
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
check("17. ningún módulo del Codex lee o escribe ChronicleCharDB ni llama a Discover/State, y el modelo no nombra a Discovery (se lo inyectan)",
    (function()
        for _, name in ipairs({ "UI/CodexModel.lua", "UI/CodexScroll.lua", "UI/CodexNavigation.lua", "UI/CodexPage.lua", "UI/Codex.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", ":Discover(", ".Discover(", "State:Get", "State:Set" }) do
                    if line:find(word, 1, true) then return false, name .. ": " .. word end
                end
            end
        end
        for _, line in ipairs(codeOf("UI/CodexModel.lua")) do
            if line:find("Chronicle.Discovery", 1, true) then return false end
        end
        return true
    end)())
check("17b. las vistas no conocen el estado de descubrimiento: solo pintan lo que da el modelo (no nombran Discovery)",
    (function()
        for _, name in ipairs({ "UI/CodexNavigation.lua", "UI/CodexPage.lua", "UI/CodexScroll.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                if line:find("Discovery", 1, true) or line:find("IsDiscovered", 1, true) then return false, name end
            end
        end
        return true
    end)())
check("17c. el color de lo bloqueado sale de Theme (colors.LOCKED); las vistas no definen ningún color propio",
    Chronicle.Theme:GetColor("LOCKED") ~= nil and (function()
        for _, name in ipairs({ "UI/CodexModel.lua", "UI/CodexNavigation.lua", "UI/CodexPage.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                if line:find("0%.%d+%s*,%s*0%.%d+") then return false, name end
            end
        end
        return true
    end)())
CreateFrame = realCreateFrame
