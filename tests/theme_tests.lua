-- Escenarios de prueba de Theme (Fase 7): estilos visuales centralizados. Los valores esperados se escriben a mano a
-- partir del addon original (maqueta del Códex y popup original), de forma independiente del código. Todo se prueba
-- contra el mock de la interfaz: NO demuestra cómo se ve en el cliente real de Classic Era.

LoadAddon()
local Theme = Chronicle.Theme

local function copy(t) return Chronicle.Utils.DeepCopy(t) end

local function sourceCode(name)
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

-- Definiciones mínimas pero completas (todo lo que la interfaz actual da por existente), para fabricar variantes.
local function ValidDefs()
    return {
        colors = {
            BG_WINDOW = { 0.1, 0.1, 0.1, 1 }, BORDER = { 0.5, 0.4, 0.2, 1 }, DIVIDER = { 0.4, 0.3, 0.1, 0.5 },
            GOLD = { 0.8, 0.6, 0.3, 1 }, TEXT_IVORY = { 0.9, 0.9, 0.8, 1 }, TEXT_MUTED = { 0.6, 0.5, 0.4, 1 },
            SHADOW = { 0, 0, 0, 1 },
        },
        fonts = {
            TITLE = { font = "Fonts\\A.ttf", size = 20, color = "GOLD", shadow = true },
            BODY = { font = "Fonts\\B.ttf", size = 13, color = "TEXT_IVORY" },
            SECONDARY = { font = "Fonts\\B.ttf", size = 11, color = "TEXT_MUTED", flags = "OUTLINE" },
        },
        spacing = { XS = 4, SM = 8 },
        layout = { POPUP_WIDTH = 420, POPUP_MIN_HEIGHT = 140, POPUP_PADDING_X = 24, POPUP_TITLE_TOP = 20,
            POPUP_DIVIDER_TOP = 44, POPUP_DIVIDER_WIDTH = 300, POPUP_BODY_TOP = 54, POPUP_BODY_BOTTOM = 16,
            POPUP_LINE_SPACING = 3, POPUP_DEFAULT_OFFSET_Y = -160, POPUP_CLOSE_OFFSET = -2 },
        strata = { POPUP = "HIGH" },
        backdrops = { WINDOW = { bgFile = "a", edgeFile = "b", tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } } },
        textures = { SOLID = "Interface\\Buttons\\WHITE8X8" },
    }
end

-- ===================== API pública =====================
local keys = {}
for key in pairs(Theme) do keys[#keys + 1] = key end
table.sort(keys)
check("1. Theme existe y expone su API documentada (y New en la instancia por defecto)",
    type(Theme) == "table" and table.concat(keys, ",")
        == "ApplyBackdrop,ApplyText,GetBackdrop,GetColor,GetFontRole,GetLayout,GetSpacing,GetStrata,GetTexture,Init,IsReady,New",
    table.concat(keys, ","))
check("Theme.New(definiciones) crea otro Theme independiente", type(Theme.New) == "function"
    and Theme.New(ValidDefs()) ~= Theme)
check("la API de Theme no incluye ningún setter: los estilos no se modifican en tiempo de ejecución",
    (function() for key in pairs(Theme) do if key:match("^Set") then return false end end return true end)())

-- ===================== Estilos definidos y con tipos válidos =====================
Theme:Init()
local colorNames = { "BG_WINDOW", "BG_PANEL", "BORDER", "DIVIDER", "GOLD", "GOLD_DIM", "TEXT_IVORY", "TEXT_MUTED", "SHADOW" }
check("2. los 9 colores (fondo, superficie, borde, separador, destacados, texto principal y secundario, sombra) están definidos con 4 componentes en [0, 1]",
    (function()
        for _, name in ipairs(colorNames) do
            local c = Theme:GetColor(name)
            if type(c) ~= "table" or #c ~= 4 then return false, name end
            for i = 1, 4 do
                if type(c[i]) ~= "number" or c[i] ~= c[i] or c[i] < 0 or c[i] > 1 then return false, name end
            end
        end
        return true
    end)())
check("2b. los roles tipográficos TITLE, BODY y SECONDARY: fuente, tamaño numérico razonable, color resuelto y sombra booleana",
    (function()
        for _, role in ipairs({ "TITLE", "BODY", "SECONDARY" }) do
            local r = Theme:GetFontRole(role)
            if type(r) ~= "table" or type(r.font) ~= "string" or r.font == "" or type(r.size) ~= "number"
                or r.size < 6 or r.size > 64 or type(r.color) ~= "table" or #r.color ~= 4 or type(r.shadow) ~= "boolean" then
                return false, role
            end
        end
        return true
    end)())
check("2c. espaciado: XS < SM < MD < LG < XL, todos números",
    (function()
        local last = 0
        for _, name in ipairs({ "XS", "SM", "MD", "LG", "XL" }) do
            local v = Theme:GetSpacing(name)
            if type(v) ~= "number" or v <= last then return false, name end
            last = v
        end
        return true
    end)())
check("2d. dimensiones del popup definidas como números finitos",
    (function()
        for _, name in ipairs({ "POPUP_WIDTH", "POPUP_MIN_HEIGHT", "POPUP_PADDING_X", "POPUP_TITLE_TOP", "POPUP_DIVIDER_TOP",
            "POPUP_DIVIDER_WIDTH", "POPUP_BODY_TOP", "POPUP_BODY_BOTTOM", "POPUP_LINE_SPACING", "POPUP_DEFAULT_OFFSET_Y",
            "POPUP_CLOSE_OFFSET" }) do
            local v = Theme:GetLayout(name)
            if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return false, name end
        end
        return true
    end)())
check("2e. strata del popup, backdrop de ventana y textura de relleno definidos",
    Theme:GetStrata("POPUP") == "HIGH" and type(Theme:GetBackdrop("WINDOW")) == "table"
        and type(Theme:GetBackdrop("WINDOW").bgFile) == "string" and type(Theme:GetBackdrop("WINDOW").insets) == "table"
        and type(Theme:GetTexture("SOLID")) == "string")
check("2f. un título y un destacado son más vivos que el texto secundario (el contraste es coherente: oro > marfil > apagado en brillo)",
    (function()
        local function lum(c) return c[1] * 0.3 + c[2] * 0.59 + c[3] * 0.11 end
        return lum(Theme:GetColor("TEXT_IVORY")) > lum(Theme:GetColor("TEXT_MUTED"))
            and lum(Theme:GetColor("TEXT_IVORY")) > lum(Theme:GetColor("BG_WINDOW")) * 4
    end)())

-- Valores tomados del diseño original (escritos a mano)
check("los colores son los de la maqueta del Códex original (oro, bronce, marfil, apagado, fondo)",
    deepEqual(Theme:GetColor("GOLD"), { 0.80, 0.64, 0.30, 1 }) and deepEqual(Theme:GetColor("GOLD_DIM"), { 0.55, 0.45, 0.25, 1 })
        and deepEqual(Theme:GetColor("TEXT_IVORY"), { 0.90, 0.86, 0.76, 1 }) and deepEqual(Theme:GetColor("TEXT_MUTED"), { 0.58, 0.53, 0.46, 1 })
        and deepEqual(Theme:GetColor("BORDER"), { 0.42, 0.30, 0.14, 1 }) and deepEqual(Theme:GetColor("BG_WINDOW"), { 0.045, 0.038, 0.03, 0.98 })
        and deepEqual(Theme:GetColor("DIVIDER"), { 0.40, 0.30, 0.15, 0.5 }) and deepEqual(Theme:GetColor("SHADOW"), { 0, 0, 0, 1 }))
check("las fuentes son las del original: Morpheus 20 para títulos y Friz Quadrata 13 / 11 para texto",
    Theme:GetFontRole("TITLE").font == "Fonts\\MORPHEUS.ttf" and Theme:GetFontRole("TITLE").size == 20
        and Theme:GetFontRole("BODY").font == "Fonts\\FRIZQT__.ttf" and Theme:GetFontRole("BODY").size == 13
        and Theme:GetFontRole("SECONDARY").size == 11 and Theme:GetFontRole("TITLE").shadow == true
        and Theme:GetFontRole("BODY").shadow == false)
check("las medidas del popup son las del original: 420 de ancho, alto mínimo 140, título a 20, separador a 44, cuerpo a 54, 160 bajo el borde",
    Theme:GetLayout("POPUP_WIDTH") == 420 and Theme:GetLayout("POPUP_MIN_HEIGHT") == 140 and Theme:GetLayout("POPUP_TITLE_TOP") == 20
        and Theme:GetLayout("POPUP_DIVIDER_TOP") == 44 and Theme:GetLayout("POPUP_BODY_TOP") == 54
        and Theme:GetLayout("POPUP_BODY_TOP") + Theme:GetLayout("POPUP_BODY_BOTTOM") == 70 -- el "70 + texto" del original
        and Theme:GetLayout("POPUP_DEFAULT_OFFSET_Y") == -160 and Theme:GetLayout("POPUP_PADDING_X") == 24)
check("el backdrop de ventana usa las texturas del propio juego del popup original",
    Theme:GetBackdrop("WINDOW").bgFile == "Interface/DialogFrame/UI-DialogBox-Background"
        and Theme:GetBackdrop("WINDOW").edgeFile == "Interface/DialogFrame/UI-DialogBox-Border"
        and Theme:GetBackdrop("WINDOW").insets.left == 11 and Theme:GetBackdrop("WINDOW").insets.right == 12)

-- ===================== Consultas: copias y nombres desconocidos =====================
local gold = Theme:GetColor("GOLD")
gold[1] = 9; table.insert(gold, 7)
local role = Theme:GetFontRole("TITLE")
role.color[1] = 9; role.size = 99
local backdrop = Theme:GetBackdrop("WINDOW")
backdrop.insets.left = 99; backdrop.bgFile = "roto"
check("las consultas devuelven copias: modificarlas no altera los estilos",
    deepEqual(Theme:GetColor("GOLD"), { 0.80, 0.64, 0.30, 1 }) and Theme:GetFontRole("TITLE").size == 20
        and Theme:GetFontRole("TITLE").color[1] == 0.80 and Theme:GetBackdrop("WINDOW").insets.left == 11
        and Theme:GetBackdrop("WINDOW").bgFile == "Interface/DialogFrame/UI-DialogBox-Background")
check("un nombre desconocido o un argumento que no es cadena devuelve nil, sin error",
    Theme:GetColor("PURPLE") == nil and Theme:GetColor(nil) == nil and Theme:GetColor(5) == nil and Theme:GetColor({}) == nil
        and Theme:GetFontRole("HUGE") == nil and Theme:GetFontRole(nil) == nil and Theme:GetSpacing("XXL") == nil
        and Theme:GetLayout(7) == nil and Theme:GetStrata("NOPE") == nil and Theme:GetBackdrop("NOPE") == nil
        and Theme:GetTexture(false) == nil)

-- ===================== ApplyText =====================
local mockFont = function() return CreateFrame("Frame"):CreateFontString(nil, "ARTWORK") end
do
    local fs = mockFont()
    local ok, why = Theme:ApplyText(fs, "TITLE")
    check("ApplyText aplica fuente, tamaño, color y sombra de un rol con sombra",
        ok == true and why == nil and fs.font[1] == "Fonts\\MORPHEUS.ttf" and fs.font[2] == 20
            and deepEqual(fs.color, { 0.80, 0.64, 0.30, 1 }) and deepEqual(fs.shadowColor, { 0, 0, 0, 1 })
            and deepEqual(fs.shadowOffset, { 1, -1 }))
    local plain = mockFont()
    check("un rol sin sombra no pone sombra", Theme:ApplyText(plain, "BODY") == true and plain.shadowColor == nil
        and deepEqual(plain.color, { 0.90, 0.86, 0.76, 1 }) and plain.font[2] == 13)
    check("rol desconocido -> false, 'unknown_role', sin tocar el texto",
        (function() local f = mockFont(); local ok2, w = Theme:ApplyText(f, "NOPE"); return ok2 == false and w == "unknown_role" and f.font == nil end)())
    check("destino inválido (nil, número, cadena) -> false, 'invalid_target', sin error",
        select(2, Theme:ApplyText(nil, "BODY")) == "invalid_target" and select(2, Theme:ApplyText(5, "BODY")) == "invalid_target"
            and select(2, Theme:ApplyText("x", "TITLE")) == "invalid_target")
    check("si SetFont devuelve false (fuente inexistente) el texto conserva su fuente pero recibe el color: sigue siendo true",
        (function()
            local f = mockFont()
            f.SetFont = function() return false end
            local ok2 = Theme:ApplyText(f, "TITLE")
            return ok2 == true and f.font == nil and deepEqual(f.color, { 0.80, 0.64, 0.30, 1 })
        end)())
    check("si la API de interfaz lanza error -> false, 'ui_error', sin propagar",
        (function()
            local f = mockFont()
            f.SetTextColor = function() error("boom") end
            local ok2, w = Theme:ApplyText(f, "BODY")
            return ok2 == false and w == "ui_error"
        end)())
    check("un objeto sin los métodos de texto -> false, 'ui_error'", select(2, Theme:ApplyText({}, "BODY")) == "ui_error")
end

-- ===================== ApplyBackdrop =====================
do
    local frame = CreateFrame("Frame")
    local ok, why = Theme:ApplyBackdrop(frame, "WINDOW", "BG_WINDOW", "BORDER")
    check("ApplyBackdrop aplica el backdrop y los colores de fondo y borde",
        ok == true and why == nil and frame.backdrop.bgFile == "Interface/DialogFrame/UI-DialogBox-Background"
            and deepEqual(frame.backdropColor, { 0.045, 0.038, 0.03, 0.98 }) and deepEqual(frame.backdropBorderColor, { 0.42, 0.30, 0.14, 1 }))
    frame.backdrop.insets.left = 99
    check("el backdrop aplicado es una copia: modificarlo no altera el tema", Theme:GetBackdrop("WINDOW").insets.left == 11)
    check("backdrop o color desconocido -> motivos 'unknown_backdrop' / 'unknown_color'",
        select(2, Theme:ApplyBackdrop(CreateFrame("Frame"), "NOPE", "BG_WINDOW", "BORDER")) == "unknown_backdrop"
            and select(2, Theme:ApplyBackdrop(CreateFrame("Frame"), "WINDOW", "NOPE", "BORDER")) == "unknown_color"
            and select(2, Theme:ApplyBackdrop(CreateFrame("Frame"), "WINDOW", "BG_WINDOW", nil)) == "unknown_color")
    check("destino inválido -> 'invalid_target'; frame sin SetBackdrop o que falla -> 'ui_error'",
        select(2, Theme:ApplyBackdrop(nil, "WINDOW", "BG_WINDOW", "BORDER")) == "invalid_target"
            and select(2, Theme:ApplyBackdrop({}, "WINDOW", "BG_WINDOW", "BORDER")) == "ui_error"
            and (function() local f = CreateFrame("Frame"); f.SetBackdrop = function() error("boom") end
                return select(2, Theme:ApplyBackdrop(f, "WINDOW", "BG_WINDOW", "BORDER")) == "ui_error" end)())
end

-- ===================== Inicialización y diagnóstico de errores =====================
do
    local t = Theme.New(ValidDefs())
    check("antes de Init el tema no está listo y ApplyText/ApplyBackdrop lo dicen ('not_ready'), sin aplicar nada",
        t:IsReady() == false and select(2, t:ApplyText(mockFont(), "BODY")) == "not_ready"
            and select(2, t:ApplyBackdrop(CreateFrame("Frame"), "WINDOW", "BG_WINDOW", "BORDER")) == "not_ready")
    check("unas definiciones completas pasan Init y dejan el tema listo", pcall(t.Init, t) and t:IsReady())
    check("Init es repetible", pcall(t.Init, t) and t:IsReady())
end
local invalidCases = {
    { "definiciones nil", function() return nil end },
    { "definiciones que no son tabla", function() return "x" end },
    { "sin la sección 'colors'", function() local d = ValidDefs(); d.colors = nil; return d end },
    { "sin la sección 'backdrops'", function() local d = ValidDefs(); d.backdrops = nil; return d end },
    { "un color con 3 componentes", function() local d = ValidDefs(); d.colors.GOLD = { 1, 1, 1 }; return d end },
    { "un color con un componente > 1", function() local d = ValidDefs(); d.colors.GOLD = { 1.5, 0, 0, 1 }; return d end },
    { "un color con un componente NaN", function() local d = ValidDefs(); d.colors.GOLD = { 0 / 0, 0, 0, 1 }; return d end },
    { "un color con un componente cadena", function() local d = ValidDefs(); d.colors.GOLD = { "1", 0, 0, 1 }; return d end },
    { "un color con nombre en minúsculas", function() local d = ValidDefs(); d.colors.oro = { 1, 1, 1, 1 }; return d end },
    { "un rol que usa un color inexistente", function() local d = ValidDefs(); d.fonts.TITLE.color = "NOPE"; return d end },
    { "un rol con tamaño 0", function() local d = ValidDefs(); d.fonts.BODY.size = 0; return d end },
    { "un rol con tamaño enorme", function() local d = ValidDefs(); d.fonts.BODY.size = 500; return d end },
    { "un rol sin fuente", function() local d = ValidDefs(); d.fonts.BODY.font = nil; return d end },
    { "un rol con sombra que no es booleana", function() local d = ValidDefs(); d.fonts.BODY.shadow = "si"; return d end },
    { "un strata inválido", function() local d = ValidDefs(); d.strata.POPUP = "ENCIMA"; return d end },
    { "una medida que no es número", function() local d = ValidDefs(); d.layout.POPUP_WIDTH = "420"; return d end },
    { "una medida infinita", function() local d = ValidDefs(); d.layout.POPUP_WIDTH = 1 / 0; return d end },
    { "falta una medida que usa el popup", function() local d = ValidDefs(); d.layout.POPUP_WIDTH = nil; return d end },
    { "falta el color SHADOW que usan los textos", function() local d = ValidDefs(); d.colors.SHADOW = nil; return d end },
    { "falta el rol TITLE", function() local d = ValidDefs(); d.fonts.TITLE = nil; return d end },
    { "falta el backdrop WINDOW", function() local d = ValidDefs(); d.backdrops.WINDOW = nil; return d end },
    { "un backdrop sin insets", function() local d = ValidDefs(); d.backdrops.WINDOW.insets = nil; return d end },
    { "un backdrop con tile que no es booleano", function() local d = ValidDefs(); d.backdrops.WINDOW.tile = 1; return d end },
    { "falta la textura SOLID", function() local d = ValidDefs(); d.textures.SOLID = nil; return d end },
}
for _, case in ipairs(invalidCases) do
    local t = Theme.New(case[2]())
    local ok, err = pcall(t.Init, t)
    check("4. Init rechaza unas definiciones inválidas (" .. case[1] .. "): lanza un error descriptivo y el tema no queda listo",
        ok == false and tostring(err):find("Theme: definiciones inválidas", 1, true) ~= nil and t:IsReady() == false, tostring(err))
end
check("un tema que falló en Init no aplica nada: ApplyText devuelve 'not_ready' (sin lanzar error)",
    (function()
        local t = Theme.New(nil)
        pcall(t.Init, t)
        local okCall, applied, why = pcall(t.ApplyText, t, mockFont(), "BODY")
        return okCall and applied == false and why == "not_ready" and t:IsReady() == false
    end)())

-- ===================== Los consumidores usan Theme, no sus propias constantes =====================
check("3. el único fichero con rutas de fuente es UI/Theme.lua (nadie más define fuentes)",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name ~= "UI/Theme.lua" then
                for _, line in ipairs(sourceCode(file.name)) do
                    if line:find("MORPHEUS", 1, true) or line:find("FRIZQT", 1, true) or line:find("Fonts\\\\", 1, true) then
                        return false, file.name
                    end
                end
            end
        end
        return true
    end)())
check("3b. el único fichero con rutas de texturas de interfaz es UI/Theme.lua",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name ~= "UI/Theme.lua" then
                for _, line in ipairs(sourceCode(file.name)) do
                    if line:find("Interface/", 1, true) or line:find("Interface\\\\", 1, true) then return false, file.name end
                end
            end
        end
        return true
    end)())
check("3c. Popup no fija colores, fuentes, backdrops ni medidas por su cuenta: todo viene de Theme",
    (function()
        for _, line in ipairs(sourceCode("UI/Popup.lua")) do
            for _, word in ipairs({ "SetTextColor", "SetBackdrop(", "SetBackdropColor", "SetBackdropBorderColor", "SetFont(",
                "SetShadowColor", "SetShadowOffset" }) do
                if line:find(word, 1, true) then return false, word end
            end
            if line:find("%d%.%d+%s*,%s*%d%.%d+%s*,%s*%d%.%d+") then return false, "color literal" end
            for _, number in ipairs({ "420", "140", "160", "300", "54", "44", "24" }) do
                if line:find("%f[%w]" .. number .. "%f[%W]") then return false, number end
            end
        end
        return true
    end)())
check("3d. Popup obtiene sus estilos llamando a Theme (GetLayout, GetStrata, GetColor, GetTexture, ApplyText, ApplyBackdrop)",
    (function()
        local used = {}
        for _, line in ipairs(sourceCode("UI/Popup.lua")) do
            for _, word in ipairs({ "GetLayout", "GetStrata", "GetColor", "GetTexture", "ApplyText", "ApplyBackdrop" }) do
                if line:find(word, 1, true) then used[word] = true end
            end
        end
        return used.GetLayout and used.GetStrata and used.GetColor and used.GetTexture and used.ApplyText and used.ApplyBackdrop
    end)())

-- ===================== Independencia =====================
check("Theme es independiente del contenido y del resto de Chronicle: no usa Registry, Localization, Discovery, State, Resolver ni ChronicleCharDB",
    (function()
        for _, line in ipairs(sourceCode("UI/Theme.lua")) do
            for _, word in ipairs({ "Chronicle.Registry", "Chronicle.Localization", "Chronicle.Discovery", "Chronicle.State",
                "Chronicle.Resolver", "Chronicle.Events", "ChronicleCharDB", "LegacyText" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("Theme no crea frames ni usa temporizadores, sonidos o animaciones",
    (function()
        for _, line in ipairs(sourceCode("UI/Theme.lua")) do
            for _, word in ipairs({ "CreateFrame", "C_Timer", "OnUpdate", "PlaySound", "CreateAnimationGroup", "UIFrameFade" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())

-- ===================== Arranque =====================
local function Boot(prepare)
    LoadAddon(); ChronicleCharDB = nil
    if prepare then prepare() end
    local n = 0
    if Chronicle.Events then Chronicle.Events:Register("Chronicle.Initialized", function() n = n + 1 end) end
    FireEvent("ADDON_LOADED", "Chronicle")
    return n
end
local announced = Boot()
check("arranque normal: Theme listo, sin fallos ni omitidos, y el arranque se anuncia una vez",
    Chronicle.Theme:IsReady() and Chronicle.Init.ready == true and announced == 1
        and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)
announced = Boot(function() Chronicle.Theme.Init = function() error("tema roto") end end)
check("4b. un error de inicialización de Theme se diagnostica en Init.failed y por el mecanismo de errores",
    Chronicle.Init.failed.Theme ~= nil and Chronicle.Init.failed.Theme:find("tema roto", 1, true) ~= nil
        and (function() for _, m in ipairs(ReportedErrors) do if m:find("Theme", 1, true) then return true end end end)())
check("4c. Theme es un módulo OPCIONAL: su fallo no impide anunciar el arranque ni los servicios del Core",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Discovery:IsReady() and Chronicle.Resolver:IsReady()
        and Chronicle.ZoneDiscovery:IsReady())
check("4d. y Popup, que depende de Theme, no se intenta: queda en Init.skipped por 'Theme'",
    Chronicle.Init.failed.Popup == nil and Chronicle.Init.skipped.Popup ~= nil and Chronicle.Init.skipped.Popup:find("'Theme'", 1, true) ~= nil
        and Chronicle.Popup:IsReady() == false)
announced = Boot(function() Chronicle.Theme = nil end)
check("Theme ausente: se diagnostica como no cargado, el arranque se anuncia igual y Popup queda omitido",
    Chronicle.Init.failed.Theme:find("no está cargado", 1, true) ~= nil and Chronicle.Init.ready == true and announced == 1
        and Chronicle.Init.skipped.Popup ~= nil)
check("Theme va después de los servicios y antes de Core/Init en el orden de carga",
    (function()
        local pos = {}
        for i, f in ipairs(ADDON_FILES) do pos[f.name] = i end
        return pos["Services/ZoneDiscovery.lua"] < pos["UI/Theme.lua"] and pos["UI/Theme.lua"] < pos["UI/Popup.lua"]
            and pos["UI/Popup.lua"] < pos["Core/Init.lua"] and pos["Core/Init.lua"] == #ADDON_FILES
    end)())
