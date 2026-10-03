Chronicle = Chronicle or {}

-- OptionsPanel: el panel de opciones de Chronicle dentro de las opciones de interfaz del juego. Reconstruye UI/OptionsPanel.lua del addon
-- original (leído en solo lectura) pero SOLO con los controles que hacen algo en esta arquitectura.
--
-- CONTROLES (uno por preferencia con consumidor; ver Core/Options.lua)
--   «Curiosidades ocasionales (al morir o al volar)»  ->  Options triviaEnabled (lo consume Services/Trivia.lua). Predeterminado: activada.
-- NO están (pospuestos, ver docs/fase12_integraciones.md): «Avisos automáticos» y «tema pergamino» (no tienen consumidor en la
-- reconstrucción) y «Reiniciar progreso» (Discovery no tiene operación de reinicio). Un control que no hace nada no se pone.
--
-- LA CASILLA NUNCA GUARDA NADA POR SU CUENTA: al pulsarla pide Options:Set; si no se puede guardar, vuelve a mostrar el valor real y lo
-- comunica. Se vuelve a leer de Options cada vez que se abre el panel (por si cambió por otro camino).
--
-- APIs DEL CLIENTE (no verificadas en un cliente real de Classic Era; el original comprobaba las dos y se usa igual): para registrar el panel,
-- la API moderna Settings.RegisterCanvasLayoutCategory + Settings.RegisterAddOnCategory o, si no existe, la clásica InterfaceOptions_AddCategory;
-- para abrirlo, Settings.OpenToCategory o InterfaceOptionsFrame_OpenToCategory. La plantilla InterfaceOptionsCheckButtonTemplate de la casilla
-- también se supone existente. Si no hay ninguna API de registro o no se puede crear la casilla, el módulo queda NO listo, lo comunica una
-- vez y no registra nada (Open devuelve false, "unavailable").
-- Estilos: fuentes y colores de Theme (ApplyText); las etiquetas son literales de este fichero (Localization solo guarda textos de entidades).
--
-- CONTRATO
--   OptionsPanel:Init()   idempotente: crea UN panel y lo registra UNA vez. Lanza error si falta Theme, Options o CreateFrame.
--   OptionsPanel:IsReady() / OptionsPanel:Open() -> true | false, "not_ready" | "unavailable" | "ui_error"
--   OptionsPanel:Refresh()  vuelve a leer las preferencias en la casilla
--   OptionsPanel.New({ theme, options, createFrame, uiParent, settings, interfaceOptions }) crea otra instancia (pruebas).

local PANEL_NAME = "Chronicle"
local TEXT_SUBTITLE = "Compañero de lore para una progresión lenta y explorativa."
local TEXT_TRIVIA = "Curiosidades ocasionales (al morir o al volar)"

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

local function NewPanel(deps)
    if type(deps) ~= "table" then
        error("Chronicle.OptionsPanel.New: se esperaba una tabla de dependencias", 2)
    end
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" then
            return dep()
        end
        return dep
    end

    local self = {}
    local panel, checkbox, registered, category
    local reported = {}

    local function ReportOnce(message)
        if not reported[message] then
            reported[message] = true
            ReportError(message)
        end
    end

    function self:Refresh()
        local options = Dep("options")
        if checkbox and IsObject(options) then
            local ok, value = pcall(options.Get, options, "triviaEnabled")
            checkbox:SetChecked(ok and value == true)
        end
    end

    -- Registra el panel en las opciones del juego con la API que exista. Devuelve true si quedó registrado.
    local function Register()
        local settings = Dep("settings")
        if IsObject(settings) and type(settings.RegisterCanvasLayoutCategory) == "function"
            and type(settings.RegisterAddOnCategory) == "function" then
            local ok, result = pcall(function()
                local created = settings.RegisterCanvasLayoutCategory(panel, panel.name)
                settings.RegisterAddOnCategory(created)
                return created
            end)
            if ok then
                category = result
                return true
            end
            ReportOnce("Chronicle.OptionsPanel: no se pudo registrar el panel (Settings): " .. tostring(result))
            return false
        end
        local classic = Dep("interfaceOptions")
        if IsObject(classic) and type(classic.AddCategory) == "function" then
            local ok, err = pcall(classic.AddCategory, panel)
            if ok then
                return true
            end
            ReportOnce("Chronicle.OptionsPanel: no se pudo registrar el panel (InterfaceOptions): " .. tostring(err))
            return false
        end
        ReportOnce("Chronicle.OptionsPanel: el cliente no ofrece ninguna API para registrar el panel de opciones")
        return false
    end

    function self:Init()
        if panel then
            return
        end
        local theme, options = Dep("theme"), Dep("options")
        if not IsObject(theme) or type(theme.IsReady) ~= "function" or not theme:IsReady() then
            error("OptionsPanel: Theme no está listo (OptionsPanel se inicializa después de Theme)", 0)
        end
        if not IsObject(options) or type(options.Get) ~= "function" or type(options.Set) ~= "function" then
            error("OptionsPanel: Options no está disponible", 0)
        end
        if type(deps.createFrame) ~= "function" then
            error("OptionsPanel: CreateFrame no está disponible", 0)
        end
        local parent = Dep("uiParent")
        if not IsObject(parent) then
            error("OptionsPanel: UIParent no está disponible", 0)
        end

        local created = deps.createFrame("Frame", "ChronicleOptionsPanel", parent)
        if not IsObject(created) then
            error("OptionsPanel: CreateFrame no devolvió un frame", 0)
        end
        created:Hide()
        created.name = PANEL_NAME
        panel = created -- desde aquí un segundo Init no crea otro frame, aunque la construcción falle más abajo

        local function Text(template, role)
            local fontString = created:CreateFontString(nil, "ARTWORK", template)
            local ok, reason = theme:ApplyText(fontString, role)
            if not ok then
                error("Theme:ApplyText(" .. role .. ") falló: " .. tostring(reason), 0)
            end
            return fontString
        end
        local spacing = theme:GetSpacing("LG")
        local title = Text("GameFontNormalLarge", "TITLE")
        title:SetPoint("TOPLEFT", created, "TOPLEFT", spacing, -spacing)
        title:SetText(PANEL_NAME)
        local subtitle = Text("GameFontHighlightSmall", "SECONDARY")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -theme:GetSpacing("SM"))
        subtitle:SetJustifyH("LEFT")
        subtitle:SetText(TEXT_SUBTITLE)

        -- La casilla usa la plantilla estándar del cliente (no verificada): si no se puede crear, no hay panel sin controles.
        local okBox, box = pcall(deps.createFrame, "CheckButton", nil, created, "InterfaceOptionsCheckButtonTemplate")
        if not okBox or not IsObject(box) then
            ReportOnce("Chronicle.OptionsPanel: no se pudo crear la casilla; el panel no se registra: " .. tostring(box))
            return
        end
        box:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -theme:GetSpacing("MD"))
        local label = Text("GameFontHighlight", "BODY")
        label:SetPoint("LEFT", box, "RIGHT", theme:GetSpacing("XS"), 1)
        label:SetText(TEXT_TRIVIA)
        box:SetScript("OnClick", function(owner)
            local wanted = owner:GetChecked() == true
            local ok, saved, reason = pcall(options.Set, options, "triviaEnabled", wanted)
            if not ok or saved ~= true then
                ReportOnce("Chronicle.OptionsPanel: no se pudo guardar la preferencia: " .. tostring(ok and reason or saved))
                self:Refresh() -- vuelve a mostrar el valor real
            end
        end)
        created:SetScript("OnShow", function() self:Refresh() end)

        checkbox = box
        self:Refresh()
        registered = Register()
    end

    function self:IsReady()
        return panel ~= nil and checkbox ~= nil and registered == true
    end

    function self:Open()
        if not panel then
            return false, "not_ready"
        end
        if not registered then
            return false, "unavailable"
        end
        local settings = Dep("settings")
        if IsObject(settings) and category and type(settings.OpenToCategory) == "function" then
            local ok, err = pcall(settings.OpenToCategory, category.ID or panel.name)
            if not ok then
                ReportError("Chronicle.OptionsPanel: no se pudo abrir el panel: " .. tostring(err))
                return false, "ui_error"
            end
            return true
        end
        local classic = Dep("interfaceOptions")
        if IsObject(classic) and type(classic.OpenToCategory) == "function" then
            local ok, err = pcall(classic.OpenToCategory, panel)
            if not ok then
                ReportError("Chronicle.OptionsPanel: no se pudo abrir el panel: " .. tostring(err))
                return false, "ui_error"
            end
            return true
        end
        return false, "unavailable"
    end

    return self
end

Chronicle.OptionsPanel = NewPanel({
    theme = function() return Chronicle.Theme end,
    options = function() return Chronicle.Options end,
    createFrame = function(...) return CreateFrame(...) end,
    uiParent = function() return UIParent end,
    settings = function() return Settings end,
    interfaceOptions = function()
        return {
            AddCategory = InterfaceOptions_AddCategory,
            OpenToCategory = InterfaceOptionsFrame_OpenToCategory,
        }
    end,
})
Chronicle.OptionsPanel.New = NewPanel
