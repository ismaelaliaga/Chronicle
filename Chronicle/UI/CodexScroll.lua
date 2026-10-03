Chronicle = Chronicle or {}

-- CodexScroll: una zona con desplazamiento vertical, compartida por el árbol y las páginas del Codex. Interno de la UI del
-- Codex (nadie fuera de ella lo usa).
--
-- Se construye SOLO con APIs básicas de widgets: un ScrollFrame con SetScrollChild/SetVerticalScroll, la rueda del ratón
-- (EnableMouseWheel + OnMouseWheel) y, como indicador, un Frame y una textura planos. No se usa UIPanelScrollFrameTemplate
-- ni Slider: sus nombres de hijos y su comportamiento en Classic Era no están verificados aquí. Consecuencia: la barra es un
-- INDICADOR de posición (no se arrastra); se desplaza con la rueda.
-- El desplazamiento máximo se calcula aquí (alto del contenido - alto visible), sin depender de que el cliente haya
-- recalculado ya el rango del ScrollFrame.
--
-- API: Chronicle.CodexScroll.New({ theme, createFrame }) -> factory
--   factory:Create(parent, left, top, width, height) -> scroll
--   scroll:GetChild()                 el frame sobre el que se coloca el contenido (ancho = width - barra)
--   scroll:GetContentWidth()          ancho útil del contenido
--   scroll:SetContentHeight(h)        fija el alto del contenido y reajusta el desplazamiento y el indicador
--   scroll:ScrollTo(offset)           lo limita a [0, máximo]
--   scroll:GetOffset() / scroll:GetRange()
--   scroll:Reveal(top, bottom)        desplaza lo mínimo para que el tramo [top, bottom] del contenido sea visible
-- Lanza error si algo falla: lo recoge la construcción del Codex (que lo trata como un fallo de inicialización).

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function NewScroll(deps)
    if type(deps) ~= "table" or type(deps.theme) ~= "table" or type(deps.createFrame) ~= "function" then
        error("Chronicle.CodexScroll.New: se esperaba una tabla { theme, createFrame }", 2)
    end
    local theme, createFrame = deps.theme, deps.createFrame
    local factory = {}

    function factory:Create(parent, left, top, width, height)
        local barWidth = theme:GetLayout("CODEX_SCROLLBAR_WIDTH")
        local step = theme:GetLayout("CODEX_SCROLL_STEP")
        local minThumb = theme:GetLayout("CODEX_MIN_THUMB_HEIGHT")
        local gap = theme:GetSpacing("XS")
        local viewWidth = width - barWidth - gap

        local frame = createFrame("ScrollFrame", nil, parent)
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
        frame:SetSize(viewWidth, height)
        local child = createFrame("Frame", nil, frame)
        child:SetSize(viewWidth, height)
        frame:SetScrollChild(child)
        frame:EnableMouseWheel(true)

        -- Indicador de posición: una pista y un tramo (los dos de Theme).
        local track = parent:CreateTexture(nil, "ARTWORK")
        track:SetTexture(theme:GetTexture("SOLID"))
        local trackColor = theme:GetColor("DIVIDER")
        track:SetVertexColor(trackColor[1], trackColor[2], trackColor[3], trackColor[4])
        track:SetPoint("TOPLEFT", parent, "TOPLEFT", left + width - barWidth, -top)
        track:SetSize(barWidth, height)
        local thumb = parent:CreateTexture(nil, "OVERLAY")
        thumb:SetTexture(theme:GetTexture("SOLID"))
        local thumbColor = theme:GetColor("GOLD_DIM")
        thumb:SetVertexColor(thumbColor[1], thumbColor[2], thumbColor[3], thumbColor[4])

        local scroll = {}
        local contentHeight, offset = height, 0

        local function Range()
            return math.max(0, contentHeight - height)
        end

        local function Apply()
            local range = Range()
            if offset > range then offset = range end
            if offset < 0 then offset = 0 end
            frame:SetVerticalScroll(offset)
            if range <= 0 then
                track:Hide()
                thumb:Hide()
                return
            end
            local thumbHeight = math.max(minThumb, height * height / contentHeight)
            local travel = height - thumbHeight
            thumb:SetSize(barWidth, thumbHeight)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPLEFT", parent, "TOPLEFT", left + width - barWidth, -(top + travel * offset / range))
            track:Show()
            thumb:Show()
        end

        function scroll:GetChild() return child end
        function scroll:GetContentWidth() return viewWidth end
        function scroll:GetOffset() return offset end
        function scroll:GetRange() return Range() end

        function scroll:SetContentHeight(value)
            contentHeight = IsFinite(value) and math.max(value, height) or height
            child:SetSize(viewWidth, contentHeight)
            Apply()
        end

        function scroll:ScrollTo(value)
            offset = IsFinite(value) and value or 0
            Apply()
        end

        function scroll:Reveal(topEdge, bottomEdge)
            if not IsFinite(topEdge) or not IsFinite(bottomEdge) then
                return
            end
            if topEdge < offset then
                offset = topEdge
            elseif bottomEdge > offset + height then
                offset = bottomEdge - height
            end
            Apply()
        end

        frame:SetScript("OnMouseWheel", function(_, delta)
            if IsFinite(delta) then
                offset = offset - delta * step
                Apply()
            end
        end)
        Apply()
        return scroll
    end

    return factory
end

Chronicle.CodexScroll = { New = NewScroll }
