Chronicle = Chronicle or {}

-- Theme: los estilos visuales compartidos por la interfaz de Chronicle, en un único sitio. Ningún módulo de UI
-- define colores, fuentes, tamaños ni texturas por su cuenta: los pide aquí. Es independiente del contenido (no
-- sabe nada de lore, entidades ni textos) y no depende de ningún otro módulo de Chronicle.
--
-- UN SOLO TEMA. Los valores salen del diseño original de Chronicle: la paleta oscura/bronce/oro y las fuentes de la
-- maqueta del Códex (UI/Codex/Theme del addon original, pedida para que se sintiera integrada en WoW Classic y no como
-- "una web"), y las texturas y medidas del popup original (UI/LoreFrame.lua). El aspecto "pergamino" del popup
-- original (activable por un ajuste) NO se conserva: no hay panel de opciones en esta fase ni sistema de múltiples
-- temas. No hay API para cambiar estilos en tiempo de ejecución porque nada lo necesita: los estilos son constantes.
--
-- FUENTES: "Fonts\MORPHEUS.ttf" (títulos, la fuente de los encabezados del propio WoW) y "Fonts\FRIZQT__.ttf" (la fuente
-- de interfaz por defecto). El addon original las dio por existentes desde Vanilla; aquí NO se han comprobado en un
-- cliente. Cubren el alfabeto latino (español, inglés); en clientes con otros alfabetos podrían faltar glifos.
-- Si SetFont falla, el texto conserva la fuente de su plantilla en vez de romperse.
--
-- BOTONES: el popup usa el botón de cierre estándar del cliente (UIPanelCloseButton) y no define un estilo propio;
-- cuando una fase posterior lo necesite, se añadirá aquí.
--
-- API (todas las consultas devuelven COPIAS: nada permite alterar los estilos por accidente):
--   Theme:GetColor("GOLD")            -> { r, g, b, a } | nil
--   Theme:GetFontRole("TITLE")        -> { font, size, flags, color = {r,g,b,a}, shadow } | nil
--   Theme:GetSpacing("MD")            -> número | nil
--   Theme:GetLayout("POPUP_WIDTH")    -> número | nil
--   Theme:GetStrata("POPUP")          -> cadena | nil
--   Theme:GetBackdrop("WINDOW")       -> tabla de backdrop | nil
--   Theme:ApplyText(fontString, rol)  -> true | false, motivo        fuente, color y sombra del rol
--   Theme:ApplyBackdrop(frame, nombre, colorFondo, colorBorde) -> true | false, motivo
--   Theme:Init() / Theme:IsReady()    Init valida las definiciones y lanza un error descriptivo si son incoherentes.
--   Chronicle.Theme.New(definiciones) crea otro Theme (pruebas); la instancia por defecto es Chronicle.Theme.
--   Motivos de ApplyText/ApplyBackdrop: "not_ready", "unknown_role", "unknown_backdrop", "unknown_color",
--   "invalid_target", "ui_error".

local Utils = Chronicle.Utils

local VALID_STRATA = {
    BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
    FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}

local DEFAULT_DEFINITIONS = {
    -- Paleta oscura / bronce / oro viejo (maqueta del Códex original).
    colors = {
        BG_WINDOW = { 0.045, 0.038, 0.03, 0.98 }, -- fondo de ventana
        BG_PANEL = { 0.07, 0.06, 0.05, 0.95 }, -- superficie de un panel dentro de una ventana
        BORDER = { 0.42, 0.30, 0.14, 1 }, -- borde bronce
        DIVIDER = { 0.40, 0.30, 0.15, 0.5 }, -- separadores
        GOLD = { 0.80, 0.64, 0.30, 1 }, -- títulos y elementos destacados
        GOLD_DIM = { 0.55, 0.45, 0.25, 1 }, -- destacado atenuado
        TEXT_IVORY = { 0.90, 0.86, 0.76, 1 }, -- texto principal
        TEXT_MUTED = { 0.58, 0.53, 0.46, 1 }, -- texto secundario
        SHADOW = { 0, 0, 0, 1 }, -- sombra de texto
    },
    -- Roles tipográficos: cada texto pide un rol en vez de fijar fuente/tamaño/color.
    fonts = {
        TITLE = { font = "Fonts\\MORPHEUS.ttf", size = 20, color = "GOLD", shadow = true },
        BODY = { font = "Fonts\\FRIZQT__.ttf", size = 13, color = "TEXT_IVORY", shadow = false },
        SECONDARY = { font = "Fonts\\FRIZQT__.ttf", size = 11, color = "TEXT_MUTED", shadow = false },
    },
    -- Escala de espaciado (maqueta del Códex).
    spacing = { XS = 4, SM = 8, MD = 12, LG = 20, XL = 32 },
    -- Medidas del popup (popup original: 420 de ancho, alto mínimo 140, título a 20, separador a 44, cuerpo a 54;
    -- alto = 54 + texto + 16 = el "70 + texto" del original).
    layout = {
        POPUP_WIDTH = 420,
        POPUP_MIN_HEIGHT = 140,
        POPUP_PADDING_X = 24,
        POPUP_TITLE_TOP = 20,
        POPUP_DIVIDER_TOP = 44,
        POPUP_DIVIDER_WIDTH = 300,
        POPUP_BODY_TOP = 54,
        POPUP_BODY_BOTTOM = 16,
        POPUP_LINE_SPACING = 3,
        POPUP_DEFAULT_OFFSET_Y = -160, -- posición por defecto: arriba y centrado, 160 bajo el borde superior
        POPUP_CLOSE_OFFSET = -2,
        -- Ventana principal del Codex (Fase 8). Proporción 3:2 apaisada, la de una ventana de consulta; la navegación ocupa
        -- algo menos de un tercio del ancho para dejar sitio al contenido. INSET deja libre el borde del backdrop WINDOW
        -- (sus insets son 11-12); HEADER_HEIGHT es el alto del encabezado (título y botón de cierre).
        CODEX_WIDTH = 840,
        CODEX_HEIGHT = 560,
        CODEX_INSET = 14,
        CODEX_HEADER_HEIGHT = 40,
        CODEX_NAV_WIDTH = 240,
        CODEX_DIVIDER_THICKNESS = 1,
    },
    -- La ventana del Codex queda POR DEBAJO del popup (HIGH) para que un aviso nunca quede tapado por ella.
    strata = { POPUP = "HIGH", CODEX = "MEDIUM" },
    -- Texturas del propio juego (las del popup original y la maqueta del Códex).
    backdrops = {
        WINDOW = {
            bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
            edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        },
    },
    -- Textura de relleno plano que usan los separadores (se tiñe con SetVertexColor).
    textures = { SOLID = "Interface\\Buttons\\WHITE8X8" },
}

-- Lo que los módulos de UI actuales (Popup) dan por existente. Init falla si falta algo de esto.
local REQUIRED = {
    colors = { "BG_WINDOW", "BORDER", "DIVIDER", "GOLD", "TEXT_IVORY", "TEXT_MUTED", "SHADOW" },
    fonts = { "TITLE", "BODY", "SECONDARY" },
    layout = { "POPUP_WIDTH", "POPUP_MIN_HEIGHT", "POPUP_PADDING_X", "POPUP_TITLE_TOP", "POPUP_DIVIDER_TOP",
        "POPUP_DIVIDER_WIDTH", "POPUP_BODY_TOP", "POPUP_BODY_BOTTOM", "POPUP_LINE_SPACING",
        "POPUP_DEFAULT_OFFSET_Y", "POPUP_CLOSE_OFFSET" },
    strata = { "POPUP" },
    backdrops = { "WINDOW" },
    textures = { "SOLID" },
}

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsName(value)
    return type(value) == "string" and value:match("^[A-Z][A-Z0-9_]*$") ~= nil
end

-- Devuelve nil si las definiciones son coherentes, o un mensaje que dice qué falla.
local function Validate(defs)
    if type(defs) ~= "table" then
        return "las definiciones deben ser una tabla"
    end
    for _, section in ipairs({ "colors", "fonts", "spacing", "layout", "strata", "backdrops", "textures" }) do
        if type(defs[section]) ~= "table" then
            return "falta la sección '" .. section .. "'"
        end
    end

    for name, color in pairs(defs.colors) do
        if not IsName(name) then return "nombre de color inválido " .. tostring(name) end
        if type(color) ~= "table" or #color ~= 4 then return "el color " .. name .. " debe ser { r, g, b, a }" end
        for i = 1, 4 do
            if not IsFinite(color[i]) or color[i] < 0 or color[i] > 1 then
                return "el color " .. name .. " tiene un componente fuera de [0, 1]"
            end
        end
    end
    for role, spec in pairs(defs.fonts) do
        if not IsName(role) then return "nombre de rol inválido " .. tostring(role) end
        if type(spec) ~= "table" then return "el rol " .. role .. " debe ser una tabla" end
        if type(spec.font) ~= "string" or spec.font == "" then return "el rol " .. role .. " necesita una fuente" end
        if not IsFinite(spec.size) or spec.size < 6 or spec.size > 64 then return "el rol " .. role .. " tiene un tamaño inválido" end
        if spec.flags ~= nil and type(spec.flags) ~= "string" then return "los flags del rol " .. role .. " deben ser una cadena" end
        if spec.shadow ~= nil and type(spec.shadow) ~= "boolean" then return "la sombra del rol " .. role .. " debe ser booleana" end
        if type(spec.color) ~= "string" or defs.colors[spec.color] == nil then
            return "el rol " .. role .. " usa un color que no existe: " .. tostring(spec.color)
        end
    end
    for _, section in ipairs({ "spacing", "layout" }) do
        for name, value in pairs(defs[section]) do
            if not IsName(name) then return "nombre inválido en " .. section .. ": " .. tostring(name) end
            if not IsFinite(value) then return section .. "." .. name .. " debe ser un número finito" end
        end
    end
    for name, value in pairs(defs.strata) do
        if not IsName(name) or not VALID_STRATA[value] then return "strata inválido: " .. tostring(name) .. " = " .. tostring(value) end
    end
    for name, spec in pairs(defs.backdrops) do
        if not IsName(name) or type(spec) ~= "table" then return "backdrop inválido: " .. tostring(name) end
        if type(spec.bgFile) ~= "string" or type(spec.edgeFile) ~= "string" then return "el backdrop " .. name .. " necesita bgFile y edgeFile" end
        if type(spec.tile) ~= "boolean" or not IsFinite(spec.tileSize) or not IsFinite(spec.edgeSize) then
            return "el backdrop " .. name .. " tiene tile/tileSize/edgeSize inválidos"
        end
        local insets = spec.insets
        if type(insets) ~= "table" or not IsFinite(insets.left) or not IsFinite(insets.right)
            or not IsFinite(insets.top) or not IsFinite(insets.bottom) then
            return "el backdrop " .. name .. " tiene insets inválidos"
        end
    end
    for name, path in pairs(defs.textures) do
        if not IsName(name) or type(path) ~= "string" or path == "" then return "textura inválida: " .. tostring(name) end
    end

    for section, names in pairs(REQUIRED) do
        for _, name in ipairs(names) do
            if defs[section][name] == nil then return "falta " .. section .. "." .. name .. ", que usa la interfaz" end
        end
    end
    return nil
end

local function NewTheme(definitions)
    -- Copia privada: nadie puede alterar los estilos después de construir el tema.
    local defs = Utils.DeepCopy(definitions)
    if type(defs) ~= "table" then
        defs = {} -- Init lo diagnostica: "falta la sección 'colors'"
    end
    local ready = false
    local self = {}

    function self:Init()
        ready = false
        local problem = Validate(defs)
        if problem then
            error("Theme: definiciones inválidas: " .. problem, 0)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    function self:GetColor(name)
        return Utils.DeepCopy(type(name) == "string" and defs.colors and defs.colors[name] or nil)
    end

    function self:GetFontRole(role)
        local spec = type(role) == "string" and defs.fonts and defs.fonts[role] or nil
        if not spec then
            return nil
        end
        local copy = Utils.DeepCopy(spec)
        copy.color = Utils.DeepCopy(defs.colors[spec.color])
        return copy
    end

    local function Lookup(section, name)
        local group = type(defs) == "table" and defs[section] or nil
        if type(name) == "string" and type(group) == "table" then
            return group[name]
        end
        return nil
    end

    function self:GetSpacing(name) return Lookup("spacing", name) end
    function self:GetLayout(name) return Lookup("layout", name) end
    function self:GetStrata(name) return Lookup("strata", name) end
    function self:GetTexture(name) return Lookup("textures", name) end
    function self:GetBackdrop(name) return Utils.DeepCopy(Lookup("backdrops", name)) end

    local function IsObject(value)
        return type(value) == "table" or type(value) == "userdata"
    end

    -- Aplica fuente, color y sombra de un rol. Un fallo de la API de interfaz no lanza error: devuelve false.
    function self:ApplyText(fontString, roleName)
        if not ready then
            return false, "not_ready"
        end
        local spec = defs.fonts[roleName]
        if not spec then
            return false, "unknown_role"
        end
        if not IsObject(fontString) then
            return false, "invalid_target"
        end
        local color = defs.colors[spec.color]
        local shadow = defs.colors.SHADOW
        local ok = pcall(function()
            -- SetFont devuelve false si la fuente no existe: el texto conserva entonces la de su plantilla.
            fontString:SetFont(spec.font, spec.size, spec.flags)
            fontString:SetTextColor(color[1], color[2], color[3], color[4])
            if spec.shadow then
                fontString:SetShadowColor(shadow[1], shadow[2], shadow[3], shadow[4])
                fontString:SetShadowOffset(1, -1)
            end
        end)
        if not ok then
            return false, "ui_error"
        end
        return true
    end

    -- Aplica un backdrop con sus colores de fondo y de borde (por nombre de color).
    function self:ApplyBackdrop(frame, backdropName, bgColorName, borderColorName)
        if not ready then
            return false, "not_ready"
        end
        local backdrop = Lookup("backdrops", backdropName)
        if not backdrop then
            return false, "unknown_backdrop"
        end
        local bg, border = defs.colors[bgColorName], defs.colors[borderColorName]
        if not bg or not border then
            return false, "unknown_color"
        end
        if not IsObject(frame) then
            return false, "invalid_target"
        end
        local ok = pcall(function()
            frame:SetBackdrop(Utils.DeepCopy(backdrop))
            frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        end)
        if not ok then
            return false, "ui_error"
        end
        return true
    end

    return self
end

-- Instancia por defecto: Chronicle.Theme. Chronicle.Theme.New(definiciones) crea otros (pruebas).
Chronicle.Theme = NewTheme(DEFAULT_DEFINITIONS)
Chronicle.Theme.New = NewTheme
