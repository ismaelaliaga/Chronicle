Chronicle = Chronicle or {}

-- Codex: la ventana principal de consulta de lore. FASE 8: SOLO LA ESTRUCTURA VISUAL. Marco con el estilo de Chronicle,
-- encabezado (título y botón de cierre), una zona de navegación a la izquierda y una zona de contenido a la derecha,
-- separadas por una línea. Las dos zonas son contenedores VACÍOS con una etiqueta provisional: aquí no hay árbol de
-- navegación, ni páginas de lore, ni conexión con Discovery, ni comando /chronicle, ni botón de minimapa, ni opciones, ni
-- persistencia de posición o tamaño. Todo eso llegará en fases posteriores sobre estos contenedores.
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
--   Chronicle.Codex.New({ theme, createFrame, uiParent, specialFrames }) crea otra instancia (pruebas); cada dependencia
--   puede ser el objeto o una función que lo devuelve (createFrame es la propia función). La instancia por defecto es
--   Chronicle.Codex y usa los globales del cliente y Chronicle.Theme.
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

-- Etiquetas PROVISIONALES de las dos zonas (para que se entienda la distribución). Se retirarán cuando haya contenido real.
local TEXT_TITLE = "Chronicle"
local TEXT_NAV = "Navegación"
local TEXT_CONTENT = "Contenido"

-- Lo que este módulo da por existente en Theme. Init falla antes de crear nada si falta alguno.
local REQUIRED_LAYOUT = { "CODEX_WIDTH", "CODEX_HEIGHT", "CODEX_INSET", "CODEX_HEADER_HEIGHT", "CODEX_NAV_WIDTH",
    "CODEX_DIVIDER_THICKNESS", "POPUP_CLOSE_OFFSET" }

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
        error("Chronicle.Codex.New: se esperaba una tabla { theme, createFrame, uiParent, specialFrames }", 2)
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
    local function Build(theme, parent, createFrame, specialFrames, partial)
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
        local navLabel = nav:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        navLabel:SetPoint("TOPLEFT", nav, "TOPLEFT", spacing("MD"), -spacing("MD"))
        navLabel:SetText(TEXT_NAV)
        must("Theme:ApplyText(SECONDARY)", theme:ApplyText(navLabel, "SECONDARY"))

        -- Separación entre ambas zonas.
        local separator = Fill(f, "ARTWORK", "DIVIDER")
        separator:SetPoint("TOPLEFT", f, "TOPLEFT", inset + navWidth, -bodyTop)
        separator:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset + navWidth, inset)
        separator:SetWidth(line)

        -- Zona de contenido (derecha): contenedor vacío sobre el fondo de la ventana.
        local content = createFrame("Frame", nil, f)
        content:SetPoint("TOPLEFT", f, "TOPLEFT", inset + navWidth + line, -bodyTop)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        local contentLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        contentLabel:SetPoint("TOPLEFT", content, "TOPLEFT", spacing("LG"), -spacing("MD"))
        contentLabel:SetText(TEXT_CONTENT)
        must("Theme:ApplyText(SECONDARY)", theme:ApplyText(contentLabel, "SECONDARY"))

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
        return f
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
        local ok, f = pcall(Build, theme, parent, createFrame, specialFrames, partial)
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
        frame = f
        ready = true
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
    createFrame = function(...) return CreateFrame(...) end,
    uiParent = function() return UIParent end,
    specialFrames = function() return UISpecialFrames end,
})
Chronicle.Codex.New = NewCodex
