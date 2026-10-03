-- Escenarios de prueba del Codex (Fase 8): SOLO la estructura de la ventana principal. Se prueban con el mock ESTRICTO de
-- la interfaz (tests/mock.lua) y con frames manipulados para provocar fallos. Esto verifica la lógica (ciclo de vida,
-- visibilidad, limpieza ante fallos, uso de Theme); NO demuestra que la ventana se vea o se comporte bien dentro del
-- cliente real de Classic Era.

local FRAME_NAME = "ChronicleCodexFrame"

local realCreateFrame = CreateFrame
local created = {}

-- Arranca el addon completo registrando qué frames se crean. `hook(kind, name, parent, template)` puede lanzar un error
-- para simular que el cliente falla al crear ese frame.
local function Boot(prepare, hook)
    created = {}
    CreateFrame = function(kind, name, parent, template)
        if hook then hook(kind, name, parent, template) end
        local frame = realCreateFrame(kind, name, parent, template)
        created[#created + 1] = { kind = kind, name = name, template = template, frame = frame, parent = parent }
        return frame
    end
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    if Chronicle.Events then
        Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    end
    FireEvent("ADDON_LOADED", "Chronicle")
    CreateFrame = realCreateFrame
    return announced
end

local function windowOf() return _G[FRAME_NAME] end
local function named(name)
    local n = 0
    for _, entry in ipairs(created) do if entry.name == name then n = n + 1 end end
    return n
end
local function countIn(list, value)
    local n = 0
    for _, v in ipairs(list) do if v == value then n = n + 1 end end
    return n
end
-- Hijos de la ventana creados con CreateFrame: las dos zonas (Frame sin nombre) y el botón de cierre.
local function panes()
    local list = {}
    for _, entry in ipairs(created) do
        if entry.parent == windowOf() and entry.kind == "Frame" then list[#list + 1] = entry.frame end
    end
    return list[1], list[2]
end
local function closeButton()
    for _, entry in ipairs(created) do
        if entry.template == "UIPanelCloseButton" and entry.parent == windowOf() then return entry.frame end
    end
end

-- Una instancia propia (Codex.New) con dependencias reales del mock, o saboteadas.
local function Make(over)
    over = over or {}
    local function pick(value, default)
        if value == false then return nil end
        if value == nil then return default end
        return value
    end
    local ctx = { frames = {}, special = (over.special ~= nil and over.special ~= false) and over.special or {}, factoryCalls = 0 }
    local realFactory = function(...)
        local frame = realCreateFrame(...)
        ctx.frames[#ctx.frames + 1] = frame
        return frame
    end
    local factory = function(...)
        ctx.factoryCalls = ctx.factoryCalls + 1
        return realFactory(...)
    end
    if over.createFrame then
        local inner = over.createFrame
        factory = function(...) ctx.factoryCalls = ctx.factoryCalls + 1 return inner(realFactory, ...) end
    end
    ctx.codex = Chronicle.Codex.New({
        theme = pick(over.theme, Chronicle.Theme),
        registry = pick(over.registry, Chronicle.Registry),
        localization = pick(over.localization, Chronicle.Localization),
        createFrame = (not over.noCreateFrame) and factory or nil,
        uiParent = pick(over.uiParent, UIParent),
        specialFrames = pick(over.special, ctx.special),
    })
    return ctx
end

-- ===================== Arranque =====================
local announced = Boot()
local Codex = Chronicle.Codex
check("el addon arranca con Theme, Popup y Codex listos, sin fallos ni omitidos, y el arranque se anuncia una vez",
    Codex:IsReady() == true and Chronicle.Theme:IsReady() and Chronicle.Popup:IsReady() and Chronicle.Init.ready == true
        and announced == 1 and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)
check("1. el Codex se inicializa correctamente: existe un único frame con su nombre y el módulo está listo",
    windowOf() ~= nil and named(FRAME_NAME) == 1 and Codex:IsReady() == true)
if not windowOf() then do return end end -- sin ventana, lo demás no se puede comprobar (ya falló lo anterior)
check("3. la ventana empieza oculta (aunque el cliente cree los frames visibles)", windowOf():IsShown() == false and Codex:IsVisible() == false)
local w = windowOf()
check("1b. atributos tomados de Theme: capa MEDIUM (bajo el Popup), 840x560, centrada, movible, arrastrable con el botón izquierdo y dentro de la pantalla",
    w.strata == "MEDIUM" and w.width == Chronicle.Theme:GetLayout("CODEX_WIDTH") and w.height == Chronicle.Theme:GetLayout("CODEX_HEIGHT")
        and w.width == 840 and w.height == 560 and w:GetPoint(1) == "CENTER" and select(2, w:GetPoint(1)) == UIParent
        and w.movable == true and w.mouse == true and w.dragButton == "LeftButton" and w.clamped == true)
check("1c. la capa del Codex queda por debajo de la del Popup", Chronicle.Theme:GetStrata("CODEX") == "MEDIUM" and Chronicle.Theme:GetStrata("POPUP") == "HIGH")
check("1d. el fondo y el borde son los de Theme (backdrop de ventana, fondo y borde bronce)",
    w.backdrop.bgFile == Chronicle.Theme:GetBackdrop("WINDOW").bgFile
        and deepEqual(w.backdropColor, Chronicle.Theme:GetColor("BG_WINDOW")) and deepEqual(w.backdropBorderColor, Chronicle.Theme:GetColor("BORDER")))
check("1e. la ventana está registrada en UISpecialFrames una sola vez (Escape la cierra)", countIn(UISpecialFrames, FRAME_NAME) == 1)

-- Estructura: encabezado, zona de navegación, separación, zona de contenido
local title, headerLine, separator = w.children[1], w.children[2], w.children[3]
local nav, content = panes()
local closeBtn = closeButton()
check("2b. encabezado: título «Chronicle» con el rol TITLE de Theme (fuente y color) y botón de cierre estándar",
    title.text == "Chronicle" and title.font[1] == Chronicle.Theme:GetFontRole("TITLE").font and title.font[2] == Chronicle.Theme:GetFontRole("TITLE").size
        and deepEqual(title.color, Chronicle.Theme:GetColor("GOLD")) and closeBtn ~= nil and closeBtn.template == "UIPanelCloseButton")
check("2c. hay una línea bajo el encabezado y una separación vertical entre las dos zonas, ambas con el color DIVIDER de Theme",
    headerLine ~= nil and separator ~= nil and deepEqual(headerLine.vertexColor, Chronicle.Theme:GetColor("DIVIDER"))
        and deepEqual(separator.vertexColor, Chronicle.Theme:GetColor("DIVIDER")) and headerLine.texture == Chronicle.Theme:GetTexture("SOLID")
        and separator.texture == Chronicle.Theme:GetTexture("SOLID") and separator.width == Chronicle.Theme:GetLayout("CODEX_DIVIDER_THICKNESS")
        and headerLine.height == Chronicle.Theme:GetLayout("CODEX_DIVIDER_THICKNESS"))
check("2d. zona de navegación (izquierda): contenedor del ancho de Theme, con superficie de panel (BG_PANEL); ya no lleva la etiqueta provisional de la Fase 8",
    nav ~= nil and nav.width == Chronicle.Theme:GetLayout("CODEX_NAV_WIDTH") and deepEqual(nav.children[1].vertexColor, Chronicle.Theme:GetColor("BG_PANEL"))
        and (function()
            for _, child in ipairs(nav.children) do if child.text == "Navegación" then return false end end
            return true
        end)())
check("2e. zona de contenido (derecha): contenedor con la página; ya no lleva la etiqueta provisional «Contenido» de la Fase 8",
    content ~= nil and (function()
        for _, child in ipairs(content.children) do if child.text == "Contenido" then return false end end
        return true
    end)())
check("2f. la navegación está a la izquierda y el contenido a la derecha de la separación (anclajes coherentes con las medidas de Theme)",
    (function()
        local inset, navW, line = Chronicle.Theme:GetLayout("CODEX_INSET"), Chronicle.Theme:GetLayout("CODEX_NAV_WIDTH"), Chronicle.Theme:GetLayout("CODEX_DIVIDER_THICKNESS")
        local np, cp, sp = nav.points[1], content.points[1], separator.points[1]
        return np[1] == "TOPLEFT" and np[4] == inset and sp[4] == inset + navW and cp[1] == "TOPLEFT" and cp[4] == inset + navW + line
            and nav.points[2][1] == "BOTTOMLEFT" and content.points[2][1] == "BOTTOMRIGHT"
    end)())
check("2g. no hay botones ni elementos funcionales aparte de la X: dos zonas, el botón de cierre y nada más creado con CreateFrame",
    (function()
        local n, buttons = 0, 0
        for _, entry in ipairs(created) do
            if entry.parent == windowOf() then
                n = n + 1
                if entry.kind == "Button" then buttons = buttons + 1 end
            end
        end
        return n == 3 and buttons == 1
    end)())
check("2h. la API pública no expone frames: ningún miembro del Codex devuelve ni guarda la ventana",
    (function()
        local expected = { Init = true, IsReady = true, IsVisible = true, Show = true, Hide = true, Toggle = true, New = true }
        for key, value in pairs(Codex) do
            if not expected[key] then return false, key end
            if type(value) ~= "function" then return false, key end
        end
        for _, result in ipairs({ { Codex:Show() }, { Codex:IsVisible() }, { Codex:Hide() }, { Codex:Toggle() }, { Codex:Toggle() } }) do
            for _, value in ipairs(result) do
                if type(value) == "table" or type(value) == "userdata" then return false end
            end
        end
        Codex:Hide()
        return true
    end)())

-- ===================== Visibilidad =====================
local before = #created
check("4. Show() la muestra y Hide() la oculta; el estado es el del frame real",
    Codex:Show() == true and w:IsShown() == true and Codex:IsVisible() == true
        and Codex:Hide() == true and w:IsShown() == false and Codex:IsVisible() == false)
check("5. Toggle() alterna en ambos sentidos: oculta -> visible -> oculta",
    Codex:Toggle() == true and w:IsShown() == true and Codex:IsVisible() == true
        and Codex:Toggle() == true and w:IsShown() == false and Codex:IsVisible() == false)
check("4b. Show y Hide son idempotentes: repetirlos es true y no cambia nada",
    Codex:Show() == true and Codex:Show() == true and w:IsShown() == true
        and Codex:Hide() == true and Codex:Hide() == true and w:IsShown() == false)
check("6. IsVisible() refleja el frame real, no una variable: ocultarlo o mostrarlo desde fuera se nota",
    (function()
        w:Show()
        local a = Codex:IsVisible()
        w:Hide()
        local b = Codex:IsVisible()
        w:Show()
        local c = Codex:IsVisible()
        w:Hide()
        return a == true and b == false and c == true and Codex:IsVisible() == false
    end)())
check("6b. IsVisible() devuelve false si el frame falla al responder, sin lanzar error",
    (function()
        local real = w.IsShown
        w.IsShown = function() error("frame roto") end
        local ok, visible = pcall(Codex.IsVisible, Codex)
        w.IsShown = real
        return ok and visible == false
    end)())
check("6c. el botón de cierre estándar y Escape (el cierre nativo) ocultan la ventana y IsVisible lo refleja",
    (function()
        Codex:Show()
        closeBtn:Click()
        local viaButton = Codex:IsVisible()
        Codex:Show()
        w:Hide() -- lo que hace el cliente al pulsar Escape sobre un frame de UISpecialFrames
        return viaButton == false and Codex:IsVisible() == false
    end)())
check("7. abrir y cerrar muchas veces no destruye ni recrea nada: mismo frame, mismos hijos, ningún CreateFrame nuevo, un único registro de Escape",
    (function()
        local childrenBefore, navBefore = #w.children, nav.children
        local survived = pcall(function()
            for _ = 1, 10 do Codex:Show(); Codex:Hide(); Codex:Toggle(); Codex:Toggle() end
        end)
        return survived and Codex:IsReady() and #created == before and windowOf() == w and #w.children == childrenBefore and nav.children == navBefore
            and title.text == "Chronicle" and #nav.children == #nav.children and countIn(UISpecialFrames, FRAME_NAME) == 1
            and named(FRAME_NAME) == 1
    end)())
check("7b. el arrastre mueve la ventana y no hace nada más (OnDragStart/OnDragStop)",
    (function()
        w.__scripts.OnDragStart(w)
        local moving = w.moving
        w.__scripts.OnDragStop(w)
        return moving == true and w.moving == false
    end)())
check("7c. no hay otros scripts: solo OnDragStart y OnDragStop (sin OnUpdate, OnHide ni temporizadores)",
    (function()
        local n = 0
        for key in pairs(w.__scripts) do n = n + 1 end
        return n == 2 and w.__scripts.OnDragStart ~= nil and w.__scripts.OnDragStop ~= nil
    end)())

-- ===================== Init idempotente =====================
do
    Boot()
    local f1, count = windowOf(), #created
    Chronicle.Codex:Init(); Chronicle.Codex:Init()
    check("2. Init es idempotente: repetirlo no crea otra ventana ni registra Escape de nuevo",
        named(FRAME_NAME) == 1 and windowOf() == f1 and #created == count and countIn(UISpecialFrames, FRAME_NAME) == 1 and Chronicle.Codex:IsReady())
    local ctx = Make()
    ctx.codex:Init()
    local afterFirst = #ctx.frames
    ctx.codex:Init(); ctx.codex:Init()
    check("2i. en una instancia propia, tres Init crean una sola ventana: los Init siguientes no crean ningún frame más",
        afterFirst >= 4 and #ctx.frames == afterFirst and ctx.factoryCalls == afterFirst and countIn(ctx.special, FRAME_NAME) == 1)
end

-- ===================== Antes de inicializar =====================
do
    Boot()
    local ctx = Make()
    local results = {}
    for _, name in ipairs({ "Show", "Hide", "Toggle" }) do
        local ok, r1, r2 = pcall(ctx.codex[name], ctx.codex)
        results[name] = { ok = ok, r1 = r1, r2 = r2 }
    end
    check("13. antes de Init: Show, Hide y Toggle devuelven false, 'not_ready' sin lanzar error; IsReady/IsVisible son false",
        results.Show.ok and results.Show.r1 == false and results.Show.r2 == "not_ready"
            and results.Hide.ok and results.Hide.r1 == false and results.Hide.r2 == "not_ready"
            and results.Toggle.ok and results.Toggle.r1 == false and results.Toggle.r2 == "not_ready"
            and ctx.codex:IsReady() == false and ctx.codex:IsVisible() == false)
    check("13b. esas operaciones no crean la ventana por su cuenta", #ctx.frames == 0 and ctx.factoryCalls == 0 and #ctx.special == 0)
end

-- ===================== Fallos de inicialización =====================
Boot()
do
    -- Una fábrica que devuelve el frame VISIBLE (como el cliente real; el mock los crea ocultos y enmascararía el defecto).
    -- `setup(frame, state)` sabotea la ventana (solo la que lleva nombre); `state.log` registra el orden de las llamadas.
    local function Visible(setup)
        local state = { log = {} }
        state.ctx = Make({ createFrame = function(real, kind, name, parent, template)
            local f = real(kind, name, parent, template)
            if name == FRAME_NAME then
                f.shown = true
                state.frame = f
                local realHide, realSetSize = f.Hide, f.SetSize
                f.Hide = function(self, ...) state.log[#state.log + 1] = "Hide"; return realHide(self, ...) end
                f.SetSize = function(self, ...) state.log[#state.log + 1] = "SetSize"; return realSetSize(self, ...) end
                if setup then setup(f, state) end
            end
            return f
        end })
        return state
    end
    local function Run(state)
        local ok, err = pcall(state.ctx.codex.Init, state.ctx.codex)
        return ok, tostring(err)
    end
    local function Clean(state)
        local f = state.frame
        return f ~= nil and f:IsShown() == false and state.ctx.codex:IsReady() == false
            and countIn(state.ctx.special, FRAME_NAME) == 0 and #state.ctx.special == 0
    end

    local fontFail = Visible(function(f) f.CreateFontString = function() error("sin fuentes") end end)
    local okF, errF = Run(fontFail)
    check("8. si falla CreateFontString, Init falla con ese motivo, el módulo NO queda listo y el frame parcial queda oculto y sin Escape",
        okF == false and errF:find("sin fuentes", 1, true) ~= nil and errF:find("no se pudo crear la ventana", 1, true) ~= nil and Clean(fontFail))
    check("8b. tras ese fallo todo devuelve 'not_ready' y nada lanza error",
        (function()
            local c = fontFail.ctx.codex
            local ok, r1, r2, r3 = pcall(function() return select(2, c:Show()), select(2, c:Hide()), select(2, c:Toggle()) end)
            return ok and r1 == "not_ready" and r2 == "not_ready" and r3 == "not_ready"
        end)() and fontFail.ctx.codex:IsVisible() == false and fontFail.frame:IsShown() == false)

    local backdropFail = Visible(function(f) f.SetBackdrop = function() error("sin backdrop") end end)
    local okB, errB = Run(backdropFail)
    check("8c. si Theme no puede aplicar el backdrop, Init falla con el motivo y el frame parcial queda oculto, sin Escape y no listo",
        okB == false and errB:find("ApplyBackdrop", 1, true) ~= nil and Clean(backdropFail))

    local pointFail = Visible(function(f) f.SetPoint = function() error("sin anclaje") end end)
    local okP, errP = Run(pointFail)
    check("9. un fallo de configuración (SetPoint) deja el frame parcial oculto, sin Escape y no listo",
        okP == false and errP:find("sin anclaje", 1, true) ~= nil and Clean(pointFail))

    local childFail = Visible()
    childFail.ctx = Make({ createFrame = function(real, kind, name, parent, template)
        if kind == "Frame" and name == nil then error("sin zonas") end
        local f = real(kind, name, parent, template)
        if name == FRAME_NAME then f.shown = true; childFail.frame = f end
        return f
    end })
    local okC, errC = Run(childFail)
    check("9b. si falla la creación de una zona (hijo), el frame principal queda oculto, sin Escape y no listo",
        okC == false and errC:find("sin zonas", 1, true) ~= nil and Clean(childFail))

    -- el frame se oculta INMEDIATAMENTE tras crearlo, antes de configurar nada
    local order = Visible(function(f) f.SetPoint = function() error("sin anclaje") end end)
    Run(order)
    check("9c. el frame se oculta lo primero tras crearlo, antes de SetSize y del resto de configuración",
        order.log[1] == "Hide" and order.log[2] == "SetSize")
    local seenShown
    local atFailure = Visible(function(f) f.SetPoint = function(self) seenShown = self.shown; error("sin anclaje") end end)
    Run(atFailure)
    check("9d. en el momento exacto del fallo de configuración el frame ya estaba oculto (no solo después de limpiar)", seenShown == false)

    -- fallo al final, con los scripts ya puestos (el registro de Escape): la limpieza los quita y oculta el frame
    local lateFail = { log = {} }
    local poisoned = setmetatable({}, { __index = function() error("sin registro de Escape") end })
    lateFail.ctx = Make({ special = poisoned, createFrame = function(real, kind, name, parent, template)
        local f = real(kind, name, parent, template)
        if name == FRAME_NAME then f.shown = true; lateFail.frame = f end
        return f
    end })
    local okL, errL = Run(lateFail)
    local scripts = lateFail.frame and lateFail.frame.__scripts or {}
    check("9e. fallo al final (registro de Escape): Init falla con ese motivo, el frame parcial queda oculto y SIN scripts, y no queda listo",
        okL == false and errL:find("sin registro de Escape", 1, true) ~= nil and lateFail.frame:IsShown() == false
            and scripts.OnDragStart == nil and scripts.OnDragStop == nil and lateFail.ctx.codex:IsReady() == false)

    -- un error en la propia limpieza no sustituye ni esconde el error original
    local hides = 0
    local dirty = Visible(function(f)
        f.SetPoint = function() error("fallo original de configuración") end
        local first = f.Hide
        f.Hide = function(self, ...)
            hides = hides + 1
            if hides >= 2 then error("Hide roto en la limpieza") end
            return first(self, ...)
        end
        f.SetScript = function() error("SetScript roto en la limpieza") end
    end)
    local okD, errD = Run(dirty)
    check("10. si la limpieza también falla, el error original sigue siendo el principal y los de la limpieza se añaden como nota",
        okD == false and errD:find("fallo original de configuración", 1, true) ~= nil
            and errD:find("fallo original de configuración", 1, true) < (errD:find("limpieza", 1, true) or 0)
            and errD:find("Hide roto en la limpieza", 1, true) ~= nil and errD:find("SetScript roto en la limpieza", 1, true) ~= nil
            and dirty.ctx.codex:IsReady() == false and #dirty.ctx.special == 0)
    local okD2, errD2 = Run(dirty)
    check("10b. tras una limpieza fallida el fallo sigue siendo definitivo, con el mismo error y sin crear otro frame",
        okD2 == false and errD2 == errD and dirty.ctx.factoryCalls == 1 and #dirty.ctx.frames == 1)

    -- repetir Init tras un fallo no acumula frames parciales
    local again = Visible(function(f) f.SetPoint = function() error("sin anclaje") end end)
    local _, first = Run(again); local _, second = Run(again); local _, third = Run(again)
    check("10c. repetir Init tras un fallo da el mismo error y no crea más frames (un único frame parcial, oculto, sin Escape)",
        first == second and second == third and again.ctx.factoryCalls == 1 and #again.ctx.frames == 1 and Clean(again))

    -- los fallos previos a crear nada no dejan rastro y se pueden reintentar
    local noTheme = Make({ theme = Chronicle.Theme.New({}) })
    check("10d. Theme no listo: Init falla, no crea nada y no es definitivo (se puede reintentar)",
        not pcall(noTheme.codex.Init, noTheme.codex) and #noTheme.frames == 0 and noTheme.factoryCalls == 0 and noTheme.codex:IsReady() == false)
    local noToken = {}
    for _, key in ipairs({ "IsReady", "GetColor", "GetFontRole", "GetSpacing", "GetStrata", "GetTexture", "GetBackdrop", "ApplyText", "ApplyBackdrop" }) do
        noToken[key] = function(_, ...) return Chronicle.Theme[key](Chronicle.Theme, ...) end
    end
    noToken.GetLayout = function(_, name) if name == "CODEX_NAV_WIDTH" then return nil end return Chronicle.Theme:GetLayout(name) end
    local missingToken = Make({ theme = noToken })
    local okT, errT = pcall(missingToken.codex.Init, missingToken.codex)
    check("10e. a Theme le falta un token CODEX_*: Init falla diciendo cuál, sin crear ningún frame",
        okT == false and tostring(errT):find("CODEX_NAV_WIDTH", 1, true) ~= nil and missingToken.factoryCalls == 0 and #missingToken.special == 0)
    local missing = Make({ theme = false })
    check("10f. sin Theme (nil) Init falla y no crea ventana", not pcall(missing.codex.Init, missing.codex) and #missing.frames == 0)
    local noFactory = Make({ noCreateFrame = true })
    check("10g. sin CreateFrame Init falla con un error descriptivo",
        (function() local ok, err = pcall(noFactory.codex.Init, noFactory.codex); return ok == false and tostring(err):find("CreateFrame", 1, true) ~= nil end)())
    local noParent = Make({ uiParent = false })
    check("10h. sin UIParent Init falla y no crea ventana", not pcall(noParent.codex.Init, noParent.codex) and #noParent.frames == 0)
    local noSpecial = Make({ special = false })
    check("10i. sin UISpecialFrames Init falla (Escape no podría cerrarla) y no crea ventana",
        not pcall(noSpecial.codex.Init, noSpecial.codex) and #noSpecial.frames == 0)
    local failing = Make({ createFrame = function() error("CreateFrame roto") end })
    local ok1, e1 = pcall(failing.codex.Init, failing.codex)
    local ok2, e2 = pcall(failing.codex.Init, failing.codex)
    check("10j. si CreateFrame falla, Init lanza un error descriptivo, es definitivo y no vuelve a intentarlo",
        ok1 == false and tostring(e1):find("no se pudo crear la ventana", 1, true) ~= nil and e1 == e2 and failing.factoryCalls == 1
            and failing.codex:IsReady() == false)

    -- el camino correcto no cambia
    local good = Visible()
    local okG = Run(good)
    check("10k. Init correcto (aunque el frame nazca visible): una sola ventana oculta, lista y registrada en Escape una vez, que se oculta lo primero",
        okG == true and good.ctx.codex:IsReady() and good.frame:IsShown() == false and countIn(good.ctx.special, FRAME_NAME) == 1
            and good.frame.__scripts.OnDragStart ~= nil and good.log[1] == "Hide")
    check("10l. tras un Init correcto el Codex funciona con normalidad", good.ctx.codex:Show() == true and good.ctx.codex:IsVisible()
        and good.ctx.codex:Toggle() == true and good.ctx.codex:IsVisible() == false)
end

-- ===================== Fallos de la interfaz en uso =====================
do
    local ctx = Make()
    ctx.codex:Init()
    local f = ctx.frames[1]
    local before = #ReportedErrors
    local realShow = f.Show
    f.Show = function() error("Show roto") end
    local okS, r1, r2 = pcall(ctx.codex.Show, ctx.codex)
    f.Show = function() end -- no hace nada: el frame no llega a mostrarse
    local okS2, q1, q2 = pcall(ctx.codex.Show, ctx.codex)
    f.Show = realShow
    check("11a. si el frame falla al mostrarse, Show devuelve false, 'ui_error', lo comunica por geterrorhandler y no lanza error",
        okS and r1 == false and r2 == "ui_error" and #ReportedErrors > before)
    check("11b. si Show no tiene efecto en el frame real, tampoco se afirma el éxito", okS2 and q1 == false and q2 == "ui_error" and ctx.codex:IsVisible() == false)
    ctx.codex:Show()
    local realHide = f.Hide
    f.Hide = function() error("Hide roto") end
    local okH, h1, h2 = pcall(ctx.codex.Hide, ctx.codex)
    local okT, t1, t2 = pcall(ctx.codex.Toggle, ctx.codex)
    f.Hide = realHide
    check("11c. si el frame falla al ocultarse, Hide y Toggle devuelven false, 'ui_error' sin lanzar error, y IsVisible sigue diciendo la verdad",
        okH and h1 == false and h2 == "ui_error" and okT and t1 == false and t2 == "ui_error" and ctx.codex:IsVisible() == true)
end

-- ===================== Theme es la única fuente de estilos =====================
do
    Boot()
    -- Un Theme con valores DISTINTOS: si el Codex usara los suyos, la ventana no los reflejaría.
    local real = Chronicle.Theme
    local altered = {}
    for _, key in ipairs({ "IsReady", "GetFontRole", "GetSpacing", "GetTexture", "GetBackdrop", "ApplyBackdrop" }) do
        altered[key] = function(_, ...) return real[key](real, ...) end
    end
    altered.GetLayout = function(_, name)
        local overrides = { CODEX_WIDTH = 1000, CODEX_HEIGHT = 700, CODEX_NAV_WIDTH = 300, CODEX_INSET = 20, CODEX_HEADER_HEIGHT = 50, CODEX_DIVIDER_THICKNESS = 2 }
        return overrides[name] or real:GetLayout(name)
    end
    altered.GetStrata = function(_, name) if name == "CODEX" then return "DIALOG" end return real:GetStrata(name) end
    altered.GetColor = function(_, name)
        if name == "BG_PANEL" then return { 0.2, 0.3, 0.4, 0.5 } end
        if name == "DIVIDER" then return { 0.9, 0.8, 0.7, 0.6 } end
        return real:GetColor(name)
    end
    local rolesSeen = {}
    altered.ApplyText = function(_, fs, role) fs.roleApplied = role; rolesSeen[role] = true return real:ApplyText(fs, role) end
    local ctx = Make({ theme = altered })
    ctx.codex:Init()
    local win = ctx.frames[1]
    local sepTexture, lineTexture = win.children[3], win.children[2]
    check("12. el Codex toma de Theme medidas, capa y colores: con otro tema la ventana cambia (1000x700, capa DIALOG, colores y grosor del tema)",
        win.width == 1000 and win.height == 700 and win.strata == "DIALOG" and ctx.frames[2].width == 300
            and deepEqual(ctx.frames[2].children[1].vertexColor, { 0.2, 0.3, 0.4, 0.5 })
            and deepEqual(sepTexture.vertexColor, { 0.9, 0.8, 0.7, 0.6 }) and sepTexture.width == 2 and lineTexture.height == 2
            and ctx.frames[2].points[1][4] == 20)
    check("12b. los textos usan los roles de Theme (TITLE para el título; BODY y SECONDARY en el árbol y la página)",
        win.children[1].roleApplied == "TITLE" and rolesSeen.TITLE and rolesSeen.BODY and rolesSeen.SECONDARY)

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
    check("12c. el código del Codex no define colores, fuentes, rutas de textura ni tamaños de fuente propios",
        (function()
            local lines = codeOf("UI/Codex.lua")
            if not lines then return false, "UI/Codex.lua no está en el .toc" end
            for _, line in ipairs(lines) do
                for _, word in ipairs({ "SetTextColor", "SetBackdropColor", "SetBackdropBorderColor", "SetFont(", "SetBackdrop(", "Fonts\\", "Interface\\", "Interface/", "SetColorTexture" }) do
                    if line:find(word, 1, true) then return false, word end
                end
                if line:find("0%.%d+%s*,%s*0%.%d+") then return false, line end
            end
            return true
        end)())
    check("12d. Codex solo depende de Theme, Registry, Localization, Discovery y Events (inyectados) y sus módulos internos; no toca State, Popup ni ChronicleCharDB",
        (function()
            local deps = {}
            for _, line in ipairs(codeOf("UI/Codex.lua")) do
                if line:find("ChronicleCharDB", 1, true) then return false, "ChronicleCharDB" end
                for name in line:gmatch("Chronicle%.(%w+)") do deps[name] = true end
            end
            deps.Codex = nil
            local list = {}
            for name in pairs(deps) do list[#list + 1] = name end
            table.sort(list)
            return table.concat(list, ",") == "CodexModel,CodexNavigation,CodexPage,CodexScroll,Discovery,Events,Localization,Registry,Theme"
        end)())
    check("12e. el Codex no usa temporizadores, animaciones, sonidos ni eventos del cliente",
        (function()
            for _, line in ipairs(codeOf("UI/Codex.lua")) do
                for _, word in ipairs({ "C_Timer", "OnUpdate", "UIFrameFade", "PlaySound", "CreateAnimationGroup", "RegisterEvent", "GetTime", "SLASH_", "Minimap" }) do
                    if line:find(word, 1, true) then return false, word end
                end
            end
            return true
        end)())
    check("12f. usar el Codex no escribe nada en ChronicleCharDB: queda exactamente el estado inicial del Core",
        (function() ctx.codex:Show(); ctx.codex:Hide(); ctx.codex:Toggle(); return true end)()
            and deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} } }))
    check("12g. Theme añade los tokens del Codex sin alterar los del Popup (420x140, capa HIGH)",
        real:GetLayout("POPUP_WIDTH") == 420 and real:GetLayout("POPUP_MIN_HEIGHT") == 140 and real:GetStrata("POPUP") == "HIGH"
            and real:GetLayout("CODEX_WIDTH") == 840 and real:GetLayout("CODEX_HEIGHT") == 560)
end

-- ===================== Integración con el arranque =====================
announced = Boot(nil, function(kind, name) if name == FRAME_NAME then error("frame del Codex roto") end end)
check("11. un fallo del Codex se diagnostica en Init.failed y por el mecanismo de errores",
    Chronicle.Init.failed.Codex ~= nil and Chronicle.Init.failed.Codex:find("frame del Codex roto", 1, true) ~= nil
        and (function() for _, m in ipairs(ReportedErrors) do if m:find("Codex", 1, true) then return true end end end)())
check("11b. el Codex es OPCIONAL: su fallo no impide anunciar el arranque ni afecta a Discovery, a los servicios ni al Popup",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Discovery:IsReady() and Chronicle.ZoneDiscovery:IsReady()
        and Chronicle.Resolver:IsReady() and Chronicle.Proximity:IsReady() and Chronicle.Popup:IsReady() and Chronicle.Theme:IsReady()
        and Chronicle.Codex:IsReady() == false)
check("11c. con el Codex fallido sus operaciones devuelven 'not_ready'", select(2, Chronicle.Codex:Show()) == "not_ready" and Chronicle.Codex:IsVisible() == false)
announced = Boot(function() Chronicle.Codex.Init = function() error("codex roto") end end)
check("11d. un Init que lanza error también queda diagnosticado y el arranque se anuncia igual",
    Chronicle.Init.failed.Codex ~= nil and Chronicle.Init.failed.Codex:find("codex roto", 1, true) ~= nil and Chronicle.Init.ready == true and announced == 1)
announced = Boot(function() Chronicle.Theme.Init = function() error("theme roto") end end)
check("11e. si Theme falla, el Codex depende de Theme: se omite (Init.skipped) sin intentarlo y sin crear ventanas; el arranque se anuncia igual",
    Chronicle.Init.failed.Theme ~= nil and Chronicle.Init.skipped.Codex ~= nil and Chronicle.Init.failed.Codex == nil and windowOf() == nil
        and Chronicle.Codex:IsReady() == false and Chronicle.Init.ready == true and announced == 1)
announced = Boot(function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
check("11i. el Codex no depende de Discovery: con Discovery caído (Init.ready = false) el Codex se inicializa igual, sin omitirse",
    Chronicle.Init.failed.Discovery ~= nil and Chronicle.Init.ready == false and Chronicle.Codex:IsReady() == true
        and Chronicle.Init.skipped.Codex == nil and Chronicle.Init.failed.Codex == nil and windowOf() ~= nil)
announced = Boot(function() Chronicle.Codex = nil end)
check("11f. Codex ausente: se diagnostica como no cargado y el arranque se anuncia igual",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Popup:IsReady()
        and (Chronicle.Init.failed.Codex ~= nil or Chronicle.Init.skipped.Codex ~= nil))
announced = Boot()
check("11g. con todo correcto, Codex y Popup conviven: dos ventanas distintas, cada una con su nombre y su registro de Escape",
    windowOf() ~= nil and _G["ChroniclePopupFrame"] ~= nil and windowOf() ~= _G["ChroniclePopupFrame"]
        and countIn(UISpecialFrames, "ChronicleCodexFrame") == 1 and countIn(UISpecialFrames, "ChroniclePopupFrame") == 1)
check("11h. mostrar el Codex no afecta al Popup ni al revés",
    (function()
        Chronicle.Codex:Show()
        local popupShown = Chronicle.Popup:Show({ title = "Aviso", body = "Texto" })
        local both = Chronicle.Codex:IsVisible() and Chronicle.Popup:IsVisible()
        Chronicle.Popup:Close()
        local codexStill = Chronicle.Codex:IsVisible()
        Chronicle.Codex:Hide()
        return popupShown == true and both and codexStill and not Chronicle.Codex:IsVisible()
    end)())
