-- Mock de la API de WoW: solo lo que usa Chronicle. Crece cuando lo haga el addon, no antes.
-- Los frames son ESTRICTOS a propósito: tienen estado real (visibilidad, anclajes, textos) pero solo los métodos que
-- el addon usa; llamar a otro lanza "attempt to call a nil value", igual que el cliente real si el método no existe.
-- Aun así es un mock: no dibuja nada y NO sustituye probar la interfaz dentro del juego.

-- Utilidades globales del cliente (Lua 5.1 en el juego; este mock corre en 5.3).
function strlower(s) return string.lower(s or "") end
if not unpack then unpack = table.unpack end

-- Chat: se guarda lo escrito para poder comprobarlo.
ChatLog = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg)
        table.insert(ChatLog, msg)
        print("[CHAT] " .. tostring(msg))
    end,
}

SlashCmdList = {}

-- Errores reportados por geterrorhandler() (Events/Init los usan al fallar un callback).
ReportedErrors = {}
function geterrorhandler()
    return function(msg) table.insert(ReportedErrors, tostring(msg)) end
end

-- Metadatos del .toc (en el juego los lee el cliente).
function GetAddOnMetadata(addon, field)
    if addon == "Chronicle" and field == "Version" then
        return "0.2.0-dev"
    end
    return nil
end

-- Frames y eventos del cliente.
local EventRegistry = {}
local NamedGlobals = {}

local FrameMethods = {}
FrameMethods.__index = FrameMethods
local FontStringMethods = {}
FontStringMethods.__index = FontStringMethods
local TextureMethods = {}
TextureMethods.__index = TextureMethods

-- SetPoint admite (point), (point, x, y), (point, relativeTo, relativePoint) y (point, relativeTo, relativePoint, x, y).
local function NormalizePoint(point, a, b, c, d)
    local relativeTo, relativePoint, x, y
    if type(a) == "number" then
        x, y = a, b
    else
        relativeTo, relativePoint, x, y = a, b, c, d
    end
    return { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end

local function AddPointMethods(class)
    function class:SetPoint(point, a, b, c, d)
        self.points = self.points or {}
        table.insert(self.points, NormalizePoint(point, a, b, c, d))
    end
    function class:ClearAllPoints() self.points = {} end
    function class:GetPoint(index)
        local p = (self.points or {})[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function class:GetNumPoints() return #(self.points or {}) end
end
AddPointMethods(FrameMethods)
AddPointMethods(FontStringMethods)
AddPointMethods(TextureMethods)

function FrameMethods:RegisterEvent(eventName)
    EventRegistry[eventName] = EventRegistry[eventName] or {}
    table.insert(EventRegistry[eventName], self)
end

function FrameMethods:UnregisterEvent(eventName)
    local list = EventRegistry[eventName] or {}
    for i = #list, 1, -1 do
        if list[i] == self then table.remove(list, i) end
    end
end

function FrameMethods:SetScript(name, fn)
    self.__scripts = self.__scripts or {}
    self.__scripts[name] = fn
end

function FrameMethods:GetName() return self.name end
function FrameMethods:IsShown() return self.shown == true end
function FrameMethods:Show()
    if not self.shown then
        self.shown = true
        local onShow = self.__scripts and self.__scripts.OnShow
        if onShow then onShow(self) end
    end
end
function FrameMethods:Hide()
    if self.shown then
        self.shown = false
        local onHide = self.__scripts and self.__scripts.OnHide
        if onHide then onHide(self) end
    end
end
function FrameMethods:SetSize(w, h) self.width, self.height = w, h end
function FrameMethods:SetWidth(w) self.width = w end
function FrameMethods:SetHeight(h) self.height = h end
function FrameMethods:GetWidth() return self.width or 0 end
function FrameMethods:GetHeight() return self.height or 0 end
function FrameMethods:SetFrameStrata(strata) self.strata = strata end
function FrameMethods:EnableMouse(enabled) self.mouse = enabled end
function FrameMethods:SetMovable(enabled) self.movable = enabled end
function FrameMethods:RegisterForDrag(button) self.dragButton = button end
function FrameMethods:SetClampedToScreen(enabled) self.clamped = enabled end
function FrameMethods:StartMoving() self.moving = true end
function FrameMethods:StopMovingOrSizing() self.moving = false end
function FrameMethods:SetBackdrop(backdrop) self.backdrop = backdrop end
function FrameMethods:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function FrameMethods:SetBackdropBorderColor(r, g, b, a) self.backdropBorderColor = { r, g, b, a } end
function FrameMethods:CreateFontString(name, layer, template)
    local fs = setmetatable({ layer = layer, template = template, text = "", shown = true }, FontStringMethods)
    self.children = self.children or {}
    table.insert(self.children, fs)
    return fs
end
function FrameMethods:CreateTexture(name, layer)
    local tex = setmetatable({ layer = layer, shown = true }, TextureMethods)
    self.children = self.children or {}
    table.insert(self.children, tex)
    return tex
end
-- Zonas con desplazamiento (ScrollFrame): solo lo que usa Chronicle. Guardan el hijo y el desplazamiento tal cual; no recortan
-- ni recalculan rangos (el cliente real sí): quien las usa calcula su propio máximo.
function FrameMethods:SetScrollChild(child) self.scrollChild = child end
function FrameMethods:GetScrollChild() return self.scrollChild end
function FrameMethods:EnableMouseWheel(enabled) self.mouseWheel = enabled end
function FrameMethods:SetVerticalScroll(offset) self.verticalScroll = offset end
function FrameMethods:GetVerticalScroll() return self.verticalScroll or 0 end
-- Botones: Click() ejecuta el OnClick del botón, como un clic del usuario.
function FrameMethods:Click()
    local onClick = self.__scripts and self.__scripts.OnClick
    if onClick then onClick(self) end
end

function FontStringMethods:SetText(text) self.text = text or "" end
-- Ancho simulado y determinista: 7 por carácter (no mide texto real).
function FontStringMethods:GetStringWidth() return #(self.text or "") * 7 end
function FontStringMethods:GetText() return self.text end
function FontStringMethods:SetFont(path, size, flags)
    self.font = { path, size, flags }
    return true
end
function FontStringMethods:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
function FontStringMethods:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
function FontStringMethods:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
function FontStringMethods:SetWidth(w) self.width = w end
function FontStringMethods:GetWidth() return self.width or 0 end
function FontStringMethods:SetJustifyH(v) self.justifyH = v end
function FontStringMethods:SetJustifyV(v) self.justifyV = v end
function FontStringMethods:SetSpacing(v) self.spacing = v end
function FontStringMethods:Show() self.shown = true end
function FontStringMethods:Hide() self.shown = false end
-- Altura simulada y determinista: 16 por línea de 60 caracteres (no mide texto real).
function FontStringMethods:GetStringHeight()
    if self.text == "" then return 0 end
    return math.ceil(#self.text / 60) * 16
end

function TextureMethods:SetTexture(path) self.texture = path end
function TextureMethods:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
function TextureMethods:SetSize(w, h) self.width, self.height = w, h end
function TextureMethods:SetHeight(h) self.height = h end
function TextureMethods:SetWidth(w) self.width = w end
function TextureMethods:Show() self.shown = true end
function TextureMethods:Hide() self.shown = false end

function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, template = template, points = {} }, FrameMethods)
    if name then
        _G[name] = frame
        NamedGlobals[#NamedGlobals + 1] = name
    end
    -- UIPanelCloseButton, la plantilla estándar del cliente, oculta el frame padre al pulsarse.
    if template == "UIPanelCloseButton" and parent then
        frame.__scripts = { OnClick = function() parent:Hide() end }
    end
    return frame
end

function FireEvent(eventName, ...)
    local snapshot = {}
    for _, frame in ipairs(EventRegistry[eventName] or {}) do
        table.insert(snapshot, frame)
    end
    for _, frame in ipairs(snapshot) do
        local onEvent = frame.__scripts and frame.__scripts["OnEvent"]
        if onEvent then onEvent(frame, eventName, ...) end
    end
end

-- Vuelve a un "cliente recién arrancado": sin frames registrados, chat vacío, sin
-- comandos slash. NO toca ChronicleCharDB (es lo único que persiste entre sesiones).
function ResetMockRuntime()
    for _, name in ipairs(NamedGlobals) do _G[name] = nil end
    NamedGlobals = {}
    UIParent = CreateFrame("Frame", nil, nil)
    UIParent.shown = true
    UISpecialFrames = {}
    EventRegistry = {}
    ChatLog = {}
    ReportedErrors = {}
    SlashCmdList = {}
    SLASH_CHRONICLE1 = nil
end

-- Estado inicial (la primera carga, antes de cualquier ResetMockRuntime).
if not tinsert then tinsert = table.insert end
UIParent = CreateFrame("Frame", nil, nil)
UIParent.shown = true
UISpecialFrames = {}
