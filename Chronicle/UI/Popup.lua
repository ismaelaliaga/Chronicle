Chronicle = Chronicle or {}

-- Popup: la ventana emergente de Chronicle, reutilizable. Responsabilidad única: mostrar un título y un cuerpo de
-- texto que LE DAN, con el aspecto de Theme, y gestionar su ciclo de vida. No decide QUÉ mostrar: no sabe de
-- entidades, descubrimientos, nombres ni lore, no lee State ni ChronicleCharDB ni Discovery, y no escucha eventos del
-- cliente. Quien la use (el Codex, un aviso de descubrimiento...) construye el contenido y lo pasa.
--
-- COMPORTAMIENTO TOMADO DEL POPUP ORIGINAL (UI/LoreFrame.lua) Y QUÉ SE CAMBIÓ
--   Conservado: una única ventana reutilizada (nunca se crea otra); título + separador + cuerpo; altura que se ajusta al
--   texto (mínimo 140); botón de cierre estándar; cierre con Escape (UISpecialFrames); capa HIGH; arrastrable; y una
--   COLA FIFO: el contenido que llega mientras hay uno visible no lo pisa, espera su turno.
--   Cambiado: la cola ya no avanza con un temporizador (C_Timer) ni la ventana se cierra sola a los 12 s ni hace fundidos
--   (son de un aviso transitorio, no de una ventana de lectura; no hay temporizadores ni animaciones en esta fase);
--   un clic en el cuerpo ya no la cierra (el texto tendrá enlaces más adelante); no hay aspecto "pergamino" (solo un
--   tema, ver Theme); la posición arrastrada no se guarda en SavedVariables (la UI no toca State): se emite un evento
--   con la nueva posición para que, si se decide persistirla, lo haga otro módulo; y el interruptor global de avisos
--   (Chronicle.enabled) no existe aquí: decidir si se muestra algo es cosa de quien llama.
--   En el original TODO pasaba por un único canal (zonas, lugares, misiones, curiosidades, proximidad); no había un
--   popup "de lore" distinto de otros avisos. Aquí también hay un solo tipo.
--
-- CONTENIDO: una tabla { title = cadena, body = cadena }.
--   * Cualquiera de los dos campos puede faltar (cuenta como ""), pero NO ambos vacíos: el contenido vacío o de solo
--     espacios se rechaza. Si no es una tabla, o un campo no es una cadena, también.
--   * Los textos se muestran TAL CUAL. Las secuencias de color del cliente (|cff...|r) se interpretarían: quien pasa el
--     texto es responsable de él.
--   * Nunca lanza error por contenido o argumentos inválidos: devuelve false y un motivo ("invalid_content",
--     "empty_content", "not_ready", "queue_full", "invalid_position", "ui_error").
--
-- API (todas devuelven false + motivo en vez de lanzar error, salvo Init)
--   Popup:Init()                 crea la ventana (idempotente). Lanza un error descriptivo si falla.
--   Popup:IsReady()
--   Popup:Show(content)          -> true | false, motivo. Muestra el contenido AHORA, reemplazando el que hubiera en la
--                                   misma ventana. La cola de pendientes no se toca.
--   Popup:Enqueue(content)       -> true, "shown" | true, "queued" | false, motivo. Si no hay nada visible lo muestra;
--                                   si hay algo, lo pone al final de la cola (máximo 50; después "queue_full").
--   Popup:Close()                -> true si había algo visible y se ha cerrado; false si no (cerrar algo cerrado es
--                                   seguro). Al cerrar, por cualquier vía (este método, la X o Escape), se muestra
--                                   enseguida el siguiente de la cola, si lo hay.
--   Popup:CloseAll()             -> igual que Close pero antes vacía la cola.
--   Popup:IsVisible()            Popup:GetQueueSize()            Popup:GetContent() -> copia { title, body } | nil
--   Popup:GetPosition()          -> { point, relativePoint, x, y } | nil       (relativa a UIParent)
--   Popup:SetPosition(point, relativePoint, x, y) -> true | false, motivo    Popup:ResetPosition()
--   Popup:GetSize()              -> ancho, alto. El ancho es fijo (Theme) y el alto sigue al texto: no hay SetSize.
--   Evento "Chronicle.Popup.Moved" (Popup.EVENT_MOVED), por Chronicle.Events, al soltar tras arrastrar:
--   (point, relativePoint, x, y).
--
-- CICLO DE VIDA: Init crea la ventana, oculta, una sola vez. Un Init fallido es definitivo en la sesión (repetirlo
-- devuelve el mismo error sin crear otra ventana), para no dejar ventanas huérfanas. Show/Enqueue/Close antes de Init
-- devuelven "not_ready" (nunca crean la ventana por su cuenta). El estado "visible" es siempre el del frame real.
-- Si una llamada a la API de interfaz falla: se comunica por geterrorhandler, se devuelve "ui_error" y la ventana queda
-- con el contenido que tenía (o cerrada), no a medias.
--
-- DEPENDENCIAS INYECTABLES: Popup.New({ theme, events, createFrame, uiParent, specialFrames }); cada una puede ser el
-- objeto o una función que lo devuelve (createFrame es la propia función). La instancia por defecto usa los globales del
-- cliente y Chronicle.Theme/Chronicle.Events.
--
-- NO verificado en un cliente real de Classic Era: BackdropTemplate, UIPanelCloseButton, UISpecialFrames y los métodos
-- de frame usados son los mismos que ya usaba el popup original (que su autor probó jugando), pero esta implementación
-- no se ha ejecutado dentro del juego.

local FRAME_NAME = "ChroniclePopupFrame"
local MAX_QUEUE = 50
local EVENT_MOVED = "Chronicle.Popup.Moved"

local VALID_POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

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

-- Devuelve una copia normalizada { title, body }, o nil y el motivo.
local function NormalizeContent(content)
    if type(content) ~= "table" then
        return nil, "invalid_content"
    end
    local title, body = content.title, content.body
    if title == nil then title = "" end
    if body == nil then body = "" end
    if type(title) ~= "string" or type(body) ~= "string" then
        return nil, "invalid_content"
    end
    if title:match("^%s*$") and body:match("^%s*$") then
        return nil, "empty_content"
    end
    return { title = title, body = body }
end

local function NewPopup(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Popup.New: se esperaba una tabla { theme, events, createFrame, uiParent, specialFrames }", 2)
    end

    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" then
            return dep()
        end
        return dep
    end

    -- Estado privado
    local frame, title, body -- la ventana y sus textos; nil hasta que Init termina
    local ready = false
    local initError = nil
    local current = nil -- contenido mostrado (copia) mientras la ventana está visible
    local queue = {}
    local self = {}
    self.EVENT_MOVED = EVENT_MOVED

    local function Theme()
        local theme = Dep("theme")
        if IsObject(theme) and type(theme.IsReady) == "function" and theme:IsReady() then
            return theme
        end
        return nil
    end

    local function IsVisible()
        if not frame then
            return false
        end
        local ok, shown = pcall(frame.IsShown, frame)
        return ok and shown == true
    end

    -- Pone el contenido en la ventana y la muestra. Devuelve true, o false y el motivo; en caso de fallo la ventana
    -- conserva el contenido anterior (o queda cerrada si no lo había).
    local function Present(content)
        local theme = Theme()
        if not theme then
            return false, "not_ready"
        end
        local function Fill(c)
            title:SetText(c.title)
            body:SetText(c.body)
            local textHeight = body:GetStringHeight()
            if not IsFinite(textHeight) then
                textHeight = 0
            end
            frame:SetHeight(math.max(theme:GetLayout("POPUP_MIN_HEIGHT"),
                theme:GetLayout("POPUP_BODY_TOP") + textHeight + theme:GetLayout("POPUP_BODY_BOTTOM")))
        end

        local previous = current
        local ok, err = pcall(Fill, content)
        if not ok then
            ReportError("Chronicle.Popup: error al actualizar la ventana: " .. tostring(err))
            if previous then
                pcall(Fill, previous)
            end
            return false, "ui_error"
        end
        current = content

        if not IsVisible() then
            local okShow, errShow = pcall(frame.Show, frame)
            if not okShow or not IsVisible() then
                ReportError("Chronicle.Popup: no se pudo mostrar la ventana: " .. tostring(errShow))
                current = nil
                return false, "ui_error"
            end
        end
        return true
    end

    -- Muestra el siguiente pendiente. Si alguno no se puede mostrar, se descarta (el fallo ya se comunicó) y se
    -- sigue con el siguiente: la cola no se queda atascada.
    local function Advance()
        while #queue > 0 do
            local nextContent = table.remove(queue, 1)
            if Present(nextContent) then
                return
            end
        end
    end

    -- La ventana se ha ocultado (X, Escape o Close): ya no hay contenido visible, y toca el siguiente.
    local function OnHidden()
        current = nil
        Advance()
    end

    local function NotifyMoved()
        local position = self:GetPosition()
        local events = Dep("events")
        if position and IsObject(events) and type(events.Emit) == "function" then
            pcall(events.Emit, events, EVENT_MOVED, position.point, position.relativePoint, position.x, position.y)
        end
    end

    -- Crea la ventana. Lanza error si algo falla; no asigna nada del estado (lo hace Init si todo va bien).
    local function Build(theme, parent, createFrame, specialFrames)
        local function layout(name) return theme:GetLayout(name) end
        local function must(what, ok, reason)
            if not ok then
                error(what .. " falló: " .. tostring(reason), 0)
            end
        end

        local f = createFrame("Frame", FRAME_NAME, parent, "BackdropTemplate")
        if not IsObject(f) then
            error("createFrame no devolvió un frame", 0)
        end
        f:SetSize(layout("POPUP_WIDTH"), layout("POPUP_MIN_HEIGHT"))
        f:SetPoint("TOP", parent, "TOP", 0, layout("POPUP_DEFAULT_OFFSET_Y"))
        f:SetFrameStrata(theme:GetStrata("POPUP"))
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        if f.SetClampedToScreen then
            f:SetClampedToScreen(true) -- que no se pueda arrastrar fuera de la pantalla
        end
        must("Theme:ApplyBackdrop", theme:ApplyBackdrop(f, "WINDOW", "BG_WINDOW", "BORDER"))

        local t = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        t:SetPoint("TOP", f, "TOP", 0, -layout("POPUP_TITLE_TOP"))
        t:SetWidth(layout("POPUP_WIDTH") - 2 * layout("POPUP_PADDING_X"))
        must("Theme:ApplyText(TITLE)", theme:ApplyText(t, "TITLE"))

        local divider = f:CreateTexture(nil, "ARTWORK")
        divider:SetTexture(theme:GetTexture("SOLID"))
        local dividerColor = theme:GetColor("DIVIDER")
        divider:SetVertexColor(dividerColor[1], dividerColor[2], dividerColor[3], dividerColor[4])
        divider:SetSize(layout("POPUP_DIVIDER_WIDTH"), 1)
        divider:SetPoint("TOP", f, "TOP", 0, -layout("POPUP_DIVIDER_TOP"))

        local b = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b:SetPoint("TOPLEFT", f, "TOPLEFT", layout("POPUP_PADDING_X"), -layout("POPUP_BODY_TOP"))
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -layout("POPUP_PADDING_X"), -layout("POPUP_BODY_TOP"))
        b:SetJustifyH("LEFT")
        b:SetJustifyV("TOP")
        b:SetSpacing(layout("POPUP_LINE_SPACING"))
        must("Theme:ApplyText(BODY)", theme:ApplyText(b, "BODY"))

        -- El botón de cierre estándar del cliente oculta su ventana padre por sí mismo.
        local close = createFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", layout("POPUP_CLOSE_OFFSET"), layout("POPUP_CLOSE_OFFSET"))

        f:SetScript("OnDragStart", function(window) pcall(window.StartMoving, window) end)
        f:SetScript("OnDragStop", function(window)
            pcall(window.StopMovingOrSizing, window)
            NotifyMoved()
        end)
        f:SetScript("OnHide", OnHidden)
        f:Hide()

        -- Escape cierra la ventana como a cualquier panel nativo. Se registra una sola vez.
        local registered = false
        for _, name in ipairs(specialFrames) do
            if name == FRAME_NAME then registered = true end
        end
        if not registered then
            table.insert(specialFrames, FRAME_NAME)
        end
        return f, t, b
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
            error("Popup: Theme no está listo (Popup se inicializa después de Theme)", 0)
        end
        local createFrame = deps.createFrame
        if type(createFrame) ~= "function" then
            error("Popup: CreateFrame no está disponible", 0)
        end
        local parent = Dep("uiParent")
        if not IsObject(parent) then
            error("Popup: UIParent no está disponible", 0)
        end
        local specialFrames = Dep("specialFrames")
        if type(specialFrames) ~= "table" then
            error("Popup: UISpecialFrames no está disponible (Escape no podría cerrar la ventana)", 0)
        end

        local ok, f, t, b = pcall(Build, theme, parent, createFrame, specialFrames)
        if not ok then
            initError = "Popup: no se pudo crear la ventana: " .. tostring(f)
            error(initError, 0)
        end
        frame, title, body = f, t, b
        ready = true
    end

    function self:IsReady()
        return ready
    end

    function self:IsVisible()
        return ready and IsVisible()
    end

    function self:GetQueueSize()
        return #queue
    end

    function self:GetContent()
        if ready and IsVisible() and current then
            return { title = current.title, body = current.body }
        end
        return nil
    end

    function self:Show(content)
        if not ready then
            return false, "not_ready"
        end
        local normalized, reason = NormalizeContent(content)
        if not normalized then
            return false, reason
        end
        return Present(normalized)
    end

    function self:Enqueue(content)
        if not ready then
            return false, "not_ready"
        end
        local normalized, reason = NormalizeContent(content)
        if not normalized then
            return false, reason
        end
        if not IsVisible() and #queue == 0 then
            local ok, why = Present(normalized)
            if not ok then
                return false, why
            end
            return true, "shown"
        end
        if #queue >= MAX_QUEUE then
            return false, "queue_full"
        end
        queue[#queue + 1] = normalized
        if not IsVisible() then
            Advance() -- ventana cerrada con pendientes (solo tras un fallo anterior): se retoma la cola
        end
        return true, "queued"
    end

    function self:Close()
        if not ready or not IsVisible() then
            return false
        end
        local ok, err = pcall(frame.Hide, frame)
        if not ok then
            ReportError("Chronicle.Popup: no se pudo cerrar la ventana: " .. tostring(err))
            return false, "ui_error"
        end
        return true
    end

    function self:CloseAll()
        queue = {}
        return self:Close()
    end

    function self:GetPosition()
        if not ready then
            return nil
        end
        local ok, point, _, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
        if not ok or type(point) ~= "string" then
            return nil
        end
        return { point = point, relativePoint = relativePoint or point, x = x or 0, y = y or 0 }
    end

    function self:SetPosition(point, relativePoint, x, y)
        if not ready then
            return false, "not_ready"
        end
        if not VALID_POINTS[point] or not VALID_POINTS[relativePoint] or not IsFinite(x) or not IsFinite(y) then
            return false, "invalid_position"
        end
        local previous = self:GetPosition()
        local ok, err = pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(point, Dep("uiParent"), relativePoint, x, y)
        end)
        if not ok then
            ReportError("Chronicle.Popup: no se pudo mover la ventana: " .. tostring(err))
            if previous then
                pcall(function()
                    frame:ClearAllPoints()
                    frame:SetPoint(previous.point, Dep("uiParent"), previous.relativePoint, previous.x, previous.y)
                end)
            end
            return false, "ui_error"
        end
        return true
    end

    function self:ResetPosition()
        local theme = Theme()
        if not theme then
            return false, "not_ready"
        end
        return self:SetPosition("TOP", "TOP", 0, theme:GetLayout("POPUP_DEFAULT_OFFSET_Y"))
    end

    function self:GetSize()
        if not ready then
            return nil
        end
        local ok, width, height = pcall(function() return frame:GetWidth(), frame:GetHeight() end)
        if not ok or not IsFinite(width) or not IsFinite(height) then
            return nil
        end
        return width, height
    end

    return self
end

-- Instancia por defecto: usa los globales del cliente (a través de funciones, para leerlos al usarlos) y los módulos
-- Chronicle.Theme y Chronicle.Events. Chronicle.Popup.New({...}) crea otras (pruebas).
Chronicle.Popup = NewPopup({
    theme = function() return Chronicle.Theme end,
    events = function() return Chronicle.Events end,
    createFrame = function(...) return CreateFrame(...) end,
    uiParent = function() return UIParent end,
    specialFrames = function() return UISpecialFrames end,
})
Chronicle.Popup.New = NewPopup
