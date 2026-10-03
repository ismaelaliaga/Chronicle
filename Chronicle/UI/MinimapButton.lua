Chronicle = Chronicle or {}

-- MinimapButton: un botón junto al minimapa que abre y cierra el Codex. Reconstruye UI/MinimapButton.lua del addon original (leído en
-- solo lectura) con las diferencias que impone esta arquitectura. Módulo aislado de API pequeña; el botón NO contiene lógica de abrir o
-- cerrar: llama a Codex:Toggle(), la API pública del Codex.
--
-- QUÉ CONSERVA DEL ORIGINAL: el botón de 31x31 anclado al borde del minimapa, el icono y el borde del propio juego, el clic izquierdo que
-- abre el Codex, el arrastre con el botón izquierdo alrededor del minimapa y la información al pasar el ratón (tooltip). Posición:
-- ángulo en grados, radio fijo de 80.
-- QUÉ CAMBIA: el ángulo se guarda a través de Options (State), nunca directamente; se valida al leerlo; y se guarda UNA vez, al soltar el
-- botón, no en cada fotograma.
-- OnUpdate: SOLO existe mientras se arrastra (para que el botón siga al cursor) y se retira al soltar o al ocultarse el botón. Fuera del
-- arrastre no hay ningún OnUpdate ni temporizador.
--
-- APIs DEL CLIENTE (ninguna verificada en un cliente real de Classic Era; las usaba el original): el frame global Minimap
-- (GetCenter, GetEffectiveScale), GetCursorPosition, GameTooltip, las texturas del icono y del borde (rutas en Theme: MINIMAP_ICON y
-- MINIMAP_BORDER) y el radio de 80, que asume el minimapa redondo de siempre (un minimapa de otra forma
-- dejaría el botón fuera de su borde). Si falta el Minimap, el módulo se degrada: no crea nada, lo comunica UNA vez y Init no falla.
--
-- CONTRATO
--   MinimapButton:Init()        idempotente: crea UN botón. -> nada. Lanza error solo si falta lo imprescindible (CreateFrame).
--   MinimapButton:IsReady()     true si el botón existe
--   MinimapButton:GetAngle()    ángulo actual en grados [0, 360) (Options:Get; el predeterminado si no hay Options)
--   MinimapButton:SetAngle(a)   -> true | false, motivo   recoloca y guarda con Options:Set (la posición se aplica aunque no se pueda guardar)
--   MinimapButton:Toggle()      -> lo que devuelva Codex:Toggle(); si el Codex no está disponible, lo dice en el chat (una línea)
--   MinimapButton.New({ createFrame, minimap, theme, options, codex, tooltip, cursor, print }) crea otra instancia (pruebas).

local FRAME_NAME = "ChronicleMinimapButton"
local RADIUS = 80
local DEFAULT_ANGLE = 215
local TEXT_TITLE = "Chronicle"
local TEXT_CLICK = "Clic: abrir o cerrar el Codex"
local TEXT_DRAG = "Arrastrar: mover este icono"
local TEXT_CODEX_UNAVAILABLE = "el Codex no está disponible."

-- math.atan2 existe en Lua 5.1 (el del cliente); math.atan(y, x) en Lua 5.3 (el de las pruebas). Se usa la que haya.
local Atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function ReportError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function NewButton(deps)
    if type(deps) ~= "table" then
        error("Chronicle.MinimapButton.New: se esperaba una tabla de dependencias", 2)
    end
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" and name ~= "cursor" and name ~= "print" then
            return dep()
        end
        return dep
    end

    local self = {}
    local button
    local initError -- fallo definitivo de una construcción a medias: reintentar no crea otro botón con el mismo nombre
    local reported = {}
    local angle = DEFAULT_ANGLE

    local function ReportOnce(message)
        if not reported[message] then
            reported[message] = true
            ReportError(message)
        end
    end

    local function Normalize(value)
        local result = value % 360
        if result < 0 then result = result + 360 end
        return result
    end

    local function Options()
        local options = Dep("options")
        if IsObject(options) and type(options.Get) == "function" and type(options.Set) == "function" then
            return options
        end
        return nil
    end

    local function Place()
        local minimap = Dep("minimap")
        if not button or not IsObject(minimap) then
            return
        end
        local radians = math.rad(angle)
        local ok, err = pcall(function()
            button:ClearAllPoints()
            button:SetPoint("CENTER", minimap, "CENTER", RADIUS * math.cos(radians), RADIUS * math.sin(radians))
        end)
        if not ok then
            ReportOnce("Chronicle.MinimapButton: no se pudo colocar el botón: " .. tostring(err))
        end
    end

    function self:GetAngle()
        local options = Options()
        if options then
            local ok, value = pcall(options.Get, options, "minimapAngle")
            if ok and IsFinite(value) then
                return Normalize(value)
            end
        end
        return DEFAULT_ANGLE
    end

    function self:SetAngle(value)
        if not IsFinite(value) then
            return false, "invalid_value"
        end
        angle = Normalize(value)
        Place()
        local options = Options()
        if not options then
            return false, "not_ready"
        end
        local ok, saved, reason = pcall(options.Set, options, "minimapAngle", angle)
        if not ok then
            ReportOnce("Chronicle.MinimapButton: no se pudo guardar la posición: " .. tostring(saved))
            return false, "persist_failed"
        end
        return saved == true, reason
    end

    function self:Toggle()
        local codex = Dep("codex")
        if not IsObject(codex) or type(codex.Toggle) ~= "function" then
            local print = deps.print
            if type(print) == "function" then print(TEXT_CODEX_UNAVAILABLE) end
            return false, "not_ready"
        end
        local ok, result, reason = pcall(codex.Toggle, codex)
        if not ok then
            ReportError("Chronicle.MinimapButton: error al abrir el Codex: " .. tostring(result))
            return false, "ui_error"
        end
        if result ~= true then
            local print = deps.print
            if type(print) == "function" then print(TEXT_CODEX_UNAVAILABLE) end
        end
        return result, reason
    end

    local function FollowCursor(minimap)
        local cursor = deps.cursor
        if type(cursor) ~= "function" then
            return
        end
        local okCenter, cx, cy = pcall(minimap.GetCenter, minimap)
        local okScale, scale = pcall(minimap.GetEffectiveScale, minimap)
        local px, py = cursor()
        if not okCenter or not okScale or not IsFinite(cx) or not IsFinite(cy) or not IsFinite(scale) or scale == 0
            or not IsFinite(px) or not IsFinite(py) then
            return
        end
        angle = Normalize(math.deg(Atan2(py / scale - cy, px / scale - cx)))
        Place()
    end

    local function StopDragging()
        if button then
            button:SetScript("OnUpdate", nil)
        end
    end

    function self:Init()
        if button then
            return
        end
        if initError then
            error(initError, 0)
        end
        if type(deps.createFrame) ~= "function" then
            error("MinimapButton: CreateFrame no está disponible", 0)
        end
        local minimap = Dep("minimap")
        if not IsObject(minimap) then
            ReportOnce("Chronicle.MinimapButton: el cliente no tiene Minimap; el botón no se crea")
            return
        end
        local theme = Dep("theme")
        if not IsObject(theme) or type(theme.IsReady) ~= "function" or not theme:IsReady()
            or not theme:GetTexture("MINIMAP_ICON") or not theme:GetTexture("MINIMAP_BORDER") then
            ReportOnce("Chronicle.MinimapButton: Theme no está listo o no tiene las texturas del botón; el botón no se crea")
            return
        end
        local created = deps.createFrame("Button", FRAME_NAME, minimap)
        if not IsObject(created) then
            error("MinimapButton: CreateFrame no devolvió un frame", 0)
        end
        created:Hide() -- un frame recién creado es visible; se muestra al terminar de construirlo
        local ok, err = pcall(function()
        created:SetSize(31, 31)
        created:SetFrameStrata("MEDIUM")
        created:SetFrameLevel(8)
        created:RegisterForClicks("LeftButtonUp")
        created:RegisterForDrag("LeftButton")

        local icon = created:CreateTexture(nil, "BACKGROUND")
        icon:SetTexture(theme:GetTexture("MINIMAP_ICON"))
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", created, "CENTER", 0, 0)
        local border = created:CreateTexture(nil, "OVERLAY")
        border:SetTexture(theme:GetTexture("MINIMAP_BORDER"))
        border:SetSize(54, 54)
        border:SetPoint("TOPLEFT", created, "TOPLEFT", 0, 0)

        created:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "LeftButton" then self:Toggle() end
        end)
        created:SetScript("OnEnter", function(owner)
            local tooltip = Dep("tooltip")
            if IsObject(tooltip) then
                pcall(function()
                    tooltip:SetOwner(owner, "ANCHOR_LEFT")
                    tooltip:AddLine(TEXT_TITLE)
                    tooltip:AddLine(TEXT_CLICK, 1, 1, 1)
                    tooltip:AddLine(TEXT_DRAG, 1, 1, 1)
                    tooltip:Show()
                end)
            end
        end)
        created:SetScript("OnLeave", function()
            local tooltip = Dep("tooltip")
            if IsObject(tooltip) then pcall(tooltip.Hide, tooltip) end
        end)
        created:SetScript("OnDragStart", function(owner)
            owner:SetScript("OnUpdate", function() FollowCursor(minimap) end)
        end)
        created:SetScript("OnDragStop", function()
            StopDragging()
            self:SetAngle(angle) -- se guarda una sola vez, al soltar
        end)
        created:SetScript("OnHide", StopDragging)
        end)
        if not ok then
            -- El botón a medias queda oculto; reintentar repite el mismo error en vez de crear otro botón con el mismo nombre.
            initError = "MinimapButton: no se pudo construir el botón: " .. tostring(err)
            error(initError, 0)
        end

        button = created
        angle = self:GetAngle()
        Place()
        button:Show()
    end

    function self:IsReady()
        return button ~= nil
    end

    return self
end

Chronicle.MinimapButton = NewButton({
    createFrame = function(...) return CreateFrame(...) end,
    minimap = function() return Minimap end,
    theme = function() return Chronicle.Theme end,
    options = function() return Chronicle.Options end,
    codex = function() return Chronicle.Codex end,
    tooltip = function() return GameTooltip end,
    cursor = function() if GetCursorPosition then return GetCursorPosition() end end,
    print = function(message) Chronicle.Utils.Print(message) end,
})
Chronicle.MinimapButton.New = NewButton
