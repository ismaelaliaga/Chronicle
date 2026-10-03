Chronicle = Chronicle or {}

-- Codex: la ventana principal de consulta de lore. Marco con el estilo de Chronicle, encabezado (título y botón de cierre),
-- una zona de navegación a la izquierda y una zona de contenido a la derecha, separadas por una línea.
-- FASE 8: la ventana. FASE 9: la NAVEGACIÓN Y LAS PÁGINAS. La izquierda es un árbol de las entidades de Registry (con sus
-- nombres de Localization) y la derecha la página de la entidad elegida, con breadcrumbs e historial Atrás/Adelante. Este
-- fichero solo construye la ventana y CABLEA las piezas; la lógica está en UI/CodexModel.lua (sin frames) y las vistas en
-- UI/CodexNavigation.lua, UI/CodexPage.lua y UI/CodexScroll.lua. FASE 10: integración con Discovery. El Codex solo CONSULTA
-- qué entidades ha descubierto el personaje (Chronicle.Discovery, la única fuente de verdad; no lo duplica ni lo escribe) y
-- pinta las no descubiertas como «???» sin datos (ver UI/CodexModel.lua). Sigue sin haber comando /chronicle, botón de
-- minimapa, opciones, ni persistencia de posición, página o historial.
--
-- ACTUALIZACIÓN. Al terminar Init con éxito el Codex se suscribe UNA sola vez (con una función fija, que el bus no duplica ni
-- aunque se repita) al evento de Discovery (Discovery.EVENT_DISCOVERED, un único argumento: el ID descubierto). Con la
-- ventana VISIBLE repinta solo lo afectado (el árbol y los breadcrumbs siempre; la página solo si es la entidad descubierta
-- o su ubicación). Con la ventana OCULTA no pinta nada: anota que hay cambios y los aplica al mostrarla. Si no pudo
-- suscribirse (sin bus, sin Discovery listo o sin nombre de evento) la ventana se repinta por completo en cada apertura, así
-- que el estado mostrado es siempre el actual. Repintar nunca descubre nada, así que no hay bucle de eventos.
-- Discovery es una dependencia BLANDA: si falla o no está listo, el Codex se inicializa igual y todo queda bloqueado.
--
-- ESTILO: todo sale de Chronicle.Theme (colores, fuentes, medidas, textura, backdrop, capa). Este fichero no define
-- ninguna constante visual propia; los únicos literales son las dos etiquetas provisionales, el nombre del frame y las
-- anclas de posicionamiento. Los tokens CODEX_* se añadieron a Theme en esta fase (Theme:GetLayout/GetStrata).
-- La ventana va en la capa CODEX (MEDIUM), por debajo de la del Popup (HIGH): un aviso nunca queda tapado por el Codex.
--
-- API PÚBLICA (no expone ningún frame: nadie puede modificar la ventana desde fuera):
--   Codex:Init()          crea la ventana, oculta, UNA sola vez. Idempotente. Lanza un error descriptivo si no puede.
--   Codex:IsReady()       true solo si Init terminó con éxito.
--   Codex:IsVisible()     true si la ventana está visible; se pregunta al frame real, no a una variable.
--   Codex:Show()          muestra la ventana.  -> true | false, motivo
--   Codex:Hide()          la oculta (no la destruye; los elementos se conservan).  -> true | false, motivo
--   Codex:Toggle()        la muestra si está oculta y la oculta si está visible.  -> true | false, motivo
--   Show/Hide/Toggle son idempotentes: devuelven true si, al terminar, la ventana está en el estado pedido (mostrar algo ya
--   visible, u ocultar algo ya oculto, es true). Motivos: "not_ready" (antes de un Init válido, o tras uno fallido; nunca
--   crean la ventana por su cuenta ni lanzan error) y "ui_error" (la interfaz falló; se comunica por geterrorhandler).
--   La API pública NO cambia en la Fase 9: la navegación se hace con la propia interfaz (clics), no con métodos.
--   Chronicle.Codex.New({ theme, registry, localization, discovery, events, createFrame, uiParent, specialFrames }) crea otra
--   instancia (pruebas); cada dependencia puede ser el objeto o una función que lo devuelve (createFrame es la propia
--   función). `discovery` y `events` son opcionales: sin ellos todo queda bloqueado y no hay actualización en vivo. La
--   instancia por defecto es Chronicle.Codex y usa los globales del cliente y Chronicle.Theme/Registry/Localization/
--   Discovery/Events.
--
-- ARRASTRE: se mueve arrastrando con el botón izquierdo; SetClampedToScreen (si el cliente lo ofrece) evita sacarla de la
-- pantalla. La posición NO se guarda: cada sesión empieza centrada. Escape la cierra (UISpecialFrames).
--
-- INICIALIZACIÓN SEGURA (lecciones del Popup). En el cliente un frame recién creado es VISIBLE, así que se oculta nada más
-- crearlo, ANTES de configurarlo. No se registra en UISpecialFrames hasta el último paso. Si la construcción falla se
-- intenta dejar el frame parcial oculto y sin scripts con llamadas protegidas (pcall); un error de esa limpieza no
-- sustituye al original, se le añade como nota. El módulo nunca se marca listo si la construcción no terminó. Un Init
-- fallido por la construcción es DEFINITIVO en la sesión: repetirlo da el mismo error y no crea otro frame, para no
-- acumular ventanas parciales. LIMITACIÓN: WoW no ofrece un modo fiable de destruir un frame con nombre, así que el frame
-- parcial sigue existiendo hasta cerrar el juego (oculto, sin scripts, sin Escape); sus hijos con él. Si hasta ocultarlo
-- fallara, no hay otro mecanismo verificado y la limpieza lo comunica en el error en vez de afirmar que lo logró.
-- Un fallo ANTERIOR a crear nada (Theme no listo o sin los tokens CODEX_*, falta CreateFrame/UIParent/UISpecialFrames)
-- no crea ningún frame y se puede reintentar.
--
-- NO verificado en un cliente real de Classic Era: BackdropTemplate, UIPanelCloseButton, UISpecialFrames, SetClampedToScreen,
-- el aspecto y las proporciones. Se prueba con un mock estricto de la interfaz, que valida la lógica, no el dibujo.

local FRAME_NAME = "ChronicleCodexFrame"

local TEXT_TITLE = "Chronicle"
local DEFAULT_EVENT_DISCOVERED = nil -- el nombre del evento lo da Discovery (EVENT_DISCOVERED); no se duplica aquí

-- Módulos internos que cablea el Codex (y que se comprueban antes de crear nada). CodexNpcModel (el visor 3D, Fase 11) es
-- OPCIONAL: sin él las páginas funcionan igual, sin modelo.
local INTERNAL_MODULES = { "CodexModel", "CodexScroll", "CodexNavigation", "CodexPage" }

-- Lo que este módulo da por existente en Theme. Init falla antes de crear nada si falta alguno.
local REQUIRED_LAYOUT = { "CODEX_WIDTH", "CODEX_HEIGHT", "CODEX_INSET", "CODEX_HEADER_HEIGHT", "CODEX_NAV_WIDTH",
    "CODEX_DIVIDER_THICKNESS", "CODEX_ROW_HEIGHT", "CODEX_ROW_INDENT", "CODEX_TOGGLE_WIDTH", "CODEX_TOOLBAR_HEIGHT",
    "CODEX_BUTTON_WIDTH", "CODEX_SCROLLBAR_WIDTH", "CODEX_MIN_THUMB_HEIGHT", "CODEX_SCROLL_STEP", "CODEX_MODEL_WIDTH",
    "CODEX_MODEL_HEIGHT", "POPUP_CLOSE_OFFSET" }

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function NewCodex(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Codex.New: se esperaba una tabla { theme, registry, localization, createFrame, uiParent, specialFrames }", 2)
    end

    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" then
            return dep()
        end
        return dep
    end

    -- Estado privado
    local frame -- la ventana; nil hasta que Init termina
    local views -- { navigation, page }; nil hasta que Init termina
    local model -- el modelo de navegación; nil hasta que Init termina
    local subscribed = false -- ¿se registró el aviso de Discovery?
    local stale = false -- hubo cambios de Discovery con la ventana oculta
    local ready = false
    local initError = nil -- error definitivo de una construcción fallida
    local self = {}

    local function Theme()
        local theme = Dep("theme")
        if IsObject(theme) and type(theme.IsReady) == "function" and theme:IsReady() then
            return theme
        end
        return nil
    end

    -- La visibilidad es la del frame real.
    local function IsVisible()
        if not frame then
            return false
        end
        local ok, shown = pcall(frame.IsShown, frame)
        return ok and shown == true
    end

    -- Deja un frame parcial lo más inofensivo posible: sin scripts y oculto. Cada paso va protegido e independiente.
    -- Devuelve nil si todo fue bien, o un texto con lo que falló. Nunca lanza error.
    local function Cleanup(partial)
        local f = partial.frame
        if not IsObject(f) then
            return nil
        end
        local failures = {}
        local function try(what, fn, ...)
            local ok, err = pcall(fn, ...)
            if not ok then
                failures[#failures + 1] = what .. ": " .. tostring(err)
            end
        end
        for _, script in ipairs({ "OnDragStart", "OnDragStop" }) do
            try("SetScript(" .. script .. ")", f.SetScript, f, script, nil)
        end
        try("Hide", f.Hide, f)
        if #failures == 0 then
            return nil
        end
        return table.concat(failures, "; ")
    end

    -- Crea la ventana. Lanza error si algo falla; no asigna estado (lo hace Init si todo va bien). `partial` recibe el
    -- frame en cuanto existe, para que Init pueda limpiarlo si la construcción no termina.
    local function Build(theme, parent, createFrame, specialFrames, partial, model)
        local function layout(name) return theme:GetLayout(name) end
        local function spacing(name) return theme:GetSpacing(name) end
        local function must(what, ok, reason)
            if not ok then
                error(what .. " falló: " .. tostring(reason), 0)
            end
        end
        -- Textura plana teñida con un color de Theme.
        local function Fill(owner, layer, colorName)
            local texture = owner:CreateTexture(nil, layer)
            texture:SetTexture(theme:GetTexture("SOLID"))
            local color = theme:GetColor(colorName)
            texture:SetVertexColor(color[1], color[2], color[3], color[4])
            return texture
        end

        local inset = layout("CODEX_INSET")
        local line = layout("CODEX_DIVIDER_THICKNESS")
        local navWidth = layout("CODEX_NAV_WIDTH")
        local bodyTop = inset + layout("CODEX_HEADER_HEIGHT") + line -- bajo el encabezado y su línea

        local f = createFrame("Frame", FRAME_NAME, parent, "BackdropTemplate")
        if not IsObject(f) then
            error("createFrame no devolvió un frame", 0)
        end
        -- Un frame recién creado es VISIBLE en el cliente: se guarda para poder limpiarlo y se oculta antes de configurar.
        partial.frame = f
        f:Hide()
        f:SetSize(layout("CODEX_WIDTH"), layout("CODEX_HEIGHT"))
        f:SetPoint("CENTER", parent, "CENTER", 0, 0)
        f:SetFrameStrata(theme:GetStrata("CODEX"))
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        if f.SetClampedToScreen then
            f:SetClampedToScreen(true) -- que no se pueda arrastrar fuera de la pantalla
        end
        must("Theme:ApplyBackdrop", theme:ApplyBackdrop(f, "WINDOW", "BG_WINDOW", "BORDER"))

        -- Encabezado: título a la izquierda, botón de cierre a la derecha y una línea debajo.
        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", spacing("LG"), -(inset + spacing("SM")))
        title:SetText(TEXT_TITLE)
        must("Theme:ApplyText(TITLE)", theme:ApplyText(title, "TITLE"))

        local headerLine = Fill(f, "ARTWORK", "DIVIDER")
        headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -(bodyTop - line))
        headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -(bodyTop - line))
        headerLine:SetHeight(line)

        -- Zona de navegación (izquierda): contenedor vacío sobre una superficie de panel.
        local nav = createFrame("Frame", nil, f)
        nav:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -bodyTop)
        nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset)
        nav:SetWidth(navWidth)
        local navSurface = Fill(nav, "BACKGROUND", "BG_PANEL")
        navSurface:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
        navSurface:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", 0, 0)
        local paneHeight = layout("CODEX_HEIGHT") - bodyTop - inset
        local scroll = Chronicle.CodexScroll.New({ theme = theme, createFrame = createFrame })
        local navigation = Chronicle.CodexNavigation.New({ theme = theme, createFrame = createFrame, scroll = scroll })
        navigation:Attach(nav, navWidth, paneHeight, model)

        -- Separación entre ambas zonas.
        local separator = Fill(f, "ARTWORK", "DIVIDER")
        separator:SetPoint("TOPLEFT", f, "TOPLEFT", inset + navWidth, -bodyTop)
        separator:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset + navWidth, inset)
        separator:SetWidth(line)

        -- Zona de contenido (derecha): contenedor vacío sobre el fondo de la ventana.
        local content = createFrame("Frame", nil, f)
        content:SetPoint("TOPLEFT", f, "TOPLEFT", inset + navWidth + line, -bodyTop)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        local contentWidth = layout("CODEX_WIDTH") - 2 * inset - navWidth - line
        content:SetSize(contentWidth, paneHeight)
        local page = Chronicle.CodexPage.New({ theme = theme, createFrame = createFrame, scroll = scroll, npcModel = Chronicle.CodexNpcModel })
        page:Attach(content, contentWidth, paneHeight, model)
        navigation:Refresh()
        page:Refresh()

        -- El botón de cierre estándar del cliente oculta su ventana padre por sí mismo.
        local close = createFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", layout("POPUP_CLOSE_OFFSET"), layout("POPUP_CLOSE_OFFSET"))

        f:SetScript("OnDragStart", function(window) pcall(window.StartMoving, window) end)
        f:SetScript("OnDragStop", function(window) pcall(window.StopMovingOrSizing, window) end)

        -- Escape cierra la ventana como a cualquier panel nativo. Es el ÚLTIMO paso: hasta que la ventana está completa no
        -- se registra en UISpecialFrames. Se registra una sola vez.
        local registered = false
        for _, name in ipairs(specialFrames) do
            if name == FRAME_NAME then registered = true end
        end
        if not registered then
            table.insert(specialFrames, FRAME_NAME)
        end
        return f, { navigation = navigation, page = page }
    end

    -- Repinta las vistas tras un cambio del modelo. Un fallo de la interfaz se comunica, no se propaga al modelo.
    -- `forcePage`: rehace también la página aunque sea la misma.
    local function RefreshViews(forcePage)
        if not views then
            return
        end
        for _, name in ipairs({ "navigation", "page" }) do
            local ok, err = pcall(views[name].Refresh, views[name], name == "page" and forcePage == true or nil)
            if not ok then
                ReportError("Chronicle.Codex: error al actualizar " .. name .. ": " .. tostring(err))
            end
        end
    end

    -- Aviso de Discovery (una entidad recién descubierta). Es una función FIJA: registrarla otra vez no la duplica.
    local function OnDiscovered(id)
        if not ready or not model or type(id) ~= "string" then
            return
        end
        if not IsVisible() then
            stale = true -- no se pinta nada con la ventana oculta; se aplica al mostrarla
            return
        end
        RefreshViews(model:AffectsPage(id))
    end

    -- Se suscribe al evento de Discovery si hay con qué (bus, servicio listo y nombre del evento). Una sola vez. Discovery es
    -- una dependencia OPCIONAL, así que esta función NO PUEDE lanzar errores: se llama con la ventana ya construida y el
    -- Codex marcado como listo. Obtener un servicio o preguntarle si está listo puede fallar; en ese caso el servicio cuenta
    -- como no disponible (el modelo lo comunica una sola vez), no hay suscripción y cada apertura repinta por completo.
    local function Subscribe()
        if not model or not model:IsDiscoveryReady() then
            return
        end
        local okEvents, events = pcall(Dep, "events")
        local okDiscovery, discovery = pcall(Dep, "discovery")
        if not okEvents or not okDiscovery or not IsObject(events) or type(events.Register) ~= "function"
            or not IsObject(discovery) then
            return
        end
        local eventName = discovery.EVENT_DISCOVERED or DEFAULT_EVENT_DISCOVERED
        if type(eventName) ~= "string" or eventName == "" then
            return
        end
        local ok, added = pcall(events.Register, events, eventName, OnDiscovered)
        if not ok then
            ReportError("Chronicle.Codex: no se pudo suscribir al aviso de Discovery: " .. tostring(added))
        elseif added == true then
            -- Contrato de Events:Register: true = manejador añadido; false = esa misma función ya estaba (no es una
            -- suscripción nueva que este Codex pueda dar por hecha), así que solo `true` cuenta como suscripción activa.
            subscribed = true
        end
    end

    function self:Init()
        if initError then
            error(initError, 0)
        end
        if frame then
            ready = true
            return
        end
        local theme = Theme()
        if not theme then
            error("Codex: Theme no está listo (Codex se inicializa después de Theme)", 0)
        end
        for _, name in ipairs(REQUIRED_LAYOUT) do
            if theme:GetLayout(name) == nil then
                error("Codex: a Theme le falta layout." .. name, 0)
            end
        end
        if theme:GetStrata("CODEX") == nil then
            error("Codex: a Theme le falta strata.CODEX", 0)
        end
        for _, name in ipairs({ "SELECTION", "LOCKED" }) do
            if theme:GetColor(name) == nil then
                error("Codex: a Theme le falta colors." .. name, 0)
            end
        end
        local registry, localization = Dep("registry"), Dep("localization")
        if not IsObject(registry) or type(registry.Has) ~= "function" then
            error("Codex: Registry no está disponible", 0)
        end
        if not IsObject(localization) or type(localization.Get) ~= "function" then
            error("Codex: Localization no está disponible", 0)
        end
        for _, name in ipairs(INTERNAL_MODULES) do
            if type(Chronicle[name]) ~= "table" or type(Chronicle[name].New) ~= "function" then
                error("Codex: falta el módulo interno " .. name, 0)
            end
        end
        local createFrame = deps.createFrame
        if type(createFrame) ~= "function" then
            error("Codex: CreateFrame no está disponible", 0)
        end
        local parent = Dep("uiParent")
        if not IsObject(parent) then
            error("Codex: UIParent no está disponible", 0)
        end
        local specialFrames = Dep("specialFrames")
        if type(specialFrames) ~= "table" then
            error("Codex: UISpecialFrames no está disponible (Escape no podría cerrar la ventana)", 0)
        end

        local partial = {}
        local builtModel = Chronicle.CodexModel.New({
            registry = registry, localization = localization, onChange = RefreshViews,
            discovery = function() return Dep("discovery") end,
        })
        local ok, f, builtViews = pcall(Build, theme, parent, createFrame, specialFrames, partial, builtModel)
        if not ok then
            -- El error original va primero y completo; si además la limpieza falla, se añade como nota.
            local message = "Codex: no se pudo crear la ventana: " .. tostring(f)
            local cleanupError = Cleanup(partial)
            if cleanupError then
                message = message .. " (además, la limpieza del frame parcial falló: " .. cleanupError .. ")"
            end
            initError = message
            error(initError, 0)
        end
        frame, views, model = f, builtViews, builtModel
        ready = true
        Subscribe()
    end

    function self:IsReady()
        return ready
    end

    function self:IsVisible()
        return ready and IsVisible()
    end

    -- Pone la ventana en el estado pedido y comprueba en el frame real que lo consiguió.
    local function SetShown(visible)
        if not ready then
            return false, "not_ready"
        end
        if not frame then
            return false, "ui_error" -- invariante rota (listo pero sin ventana): se comunica en vez de lanzar un error
        end
        if IsVisible() ~= visible then
            local ok, err = pcall(visible and frame.Show or frame.Hide, frame)
            if not ok then
                ReportError("Chronicle.Codex: no se pudo " .. (visible and "mostrar" or "ocultar") .. " la ventana: " .. tostring(err))
                return false, "ui_error"
            end
            if IsVisible() ~= visible then
                ReportError("Chronicle.Codex: la ventana no quedó " .. (visible and "visible" or "oculta"))
                return false, "ui_error"
            end
            -- Al abrir se aplica lo que cambió mientras estaba oculta (o todo, si no hay aviso de Discovery).
            if visible and (stale or not subscribed) then
                stale = false
                RefreshViews(true)
            end
        end
        return true
    end

    function self:Show()
        return SetShown(true)
    end

    function self:Hide()
        return SetShown(false)
    end

    function self:Toggle()
        if not ready then
            return false, "not_ready"
        end
        return SetShown(not IsVisible())
    end

    return self
end

-- Instancia por defecto: usa los globales del cliente (a través de funciones, para leerlos al usarlos) y Chronicle.Theme.
Chronicle.Codex = NewCodex({
    theme = function() return Chronicle.Theme end,
    registry = function() return Chronicle.Registry end,
    localization = function() return Chronicle.Localization end,
    discovery = function() return Chronicle.Discovery end,
    events = function() return Chronicle.Events end,
    createFrame = function(...) return CreateFrame(...) end,
    uiParent = function() return UIParent end,
    specialFrames = function() return UISpecialFrames end,
})
Chronicle.Codex.New = NewCodex
