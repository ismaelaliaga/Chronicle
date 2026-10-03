Chronicle = Chronicle or {}

-- CodexPage: la zona derecha del Codex (la VISTA; los datos los da CodexModel). Una barra de herramientas con los botones
-- del historial (Atrás / Adelante) y los breadcrumbs, y debajo la página de la entidad actual dentro de una zona con
-- desplazamiento. Interno de la UI del Codex.
--
-- LA PÁGINA muestra SOLO lo que la entidad tiene, de arriba abajo: nombre (TITLE), tipo, ubicación contextual (`located_in`),
-- raza/rol (NPC), la DESCRIPCIÓN corta y, separado por una línea, el CUERPO del artículo de lore. Lo que falte no se rellena
-- ni deja hueco. Los textos se muestran ENTEROS (nada se recorta): el alto de la página se mide con el texto ya puesto y la
-- zona se desplaza con la rueda del ratón. Sin página actual se muestra una indicación discreta.
--
-- VISOR 3D Y ENLACES (Fase 11). Si el modelo da `page.model` (un NPC descubierto con un displayID válido) y el visor
-- (CodexNpcModel, opcional) está disponible y consigue mostrarlo, se reserva su recuadro bajo los datos del personaje; si no,
-- la página no deja hueco ni marco. El visor se oculta y se vacía en CADA repintado antes de decidir, así que nunca queda a la
-- vista el modelo de la página anterior. Después del texto, cada sección de `page.links` (ver CodexModel) se pinta como una
-- cabecera y una lista de botones: pulsar uno hace model:Select(id), es decir, la navegación y el historial de siempre. Un destino
-- bloqueado se pinta como «???» en el color LOCKED. Las filas de enlaces son un conjunto reutilizado: lo que sobra se oculta y se
-- vacía (sin texto ni ID residuales).
--
-- PÁGINA BLOQUEADA (Fase 10): si el modelo dice que la entidad no está descubierta, la página es solo «???» (color LOCKED) y
-- una línea que explica el motivo; nada más. La vista no conoce el ID ni el nombre real, no se los dan.
--
-- BREADCRUMBS: la ruta de `parent` hasta la página actual; cada tramo anterior es un botón que navega a esa entidad y el
-- último (la página actual) es solo texto. Si no caben en el ancho disponible se quitan tramos por el principio y se
-- antepone «...». Los breadcrumbs NO son el historial: este es el de Atrás/Adelante.
--
-- API: Chronicle.CodexPage.New({ theme, createFrame, scroll [, npcModel] }) -> vista   (`npcModel` = el módulo CodexNpcModel)
--   vista:Attach(parent, width, height, model)   construye los widgets (lanza error si algo falla)
--   vista:Refresh()                              repinta desde el modelo
-- Colores, fuentes y medidas salen de Theme. Literales de esta vista: los símbolos de los botones («<», «>»), el separador
-- de breadcrumbs («/»), «...» y los rótulos «Ubicado en» y la indicación sin página.

local TEXT_BACK, TEXT_FORWARD = "<", ">"
local TEXT_SEPARATOR, TEXT_ELLIPSIS = "/", "..."
local TEXT_LOCATION = "Ubicado en: "
local TEXT_EMPTY = "Selecciona una entrada de la navegación."
local TEXT_LOCKED = "Aún no has descubierto esta entrada."

local function IsFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function NewPage(deps)
    if type(deps) ~= "table" or type(deps.theme) ~= "table" or type(deps.createFrame) ~= "function"
        or type(deps.scroll) ~= "table" then
        error("Chronicle.CodexPage.New: se esperaba una tabla { theme, createFrame, scroll }", 2)
    end
    local theme, createFrame = deps.theme, deps.createFrame
    local self = {}
    local model, scroll, child, toolbar
    local back, forward, backLabel, forwardLabel, ellipsis
    local crumbs, separators = {}, {}
    local title, kind, location, details, descriptionText, rule, bodyText, empty
    local modelView -- el visor 3D (nil si no hay módulo)
    local linkHeaders, linkRows = {}, {} -- cabeceras y botones de enlace (se crean al hacer falta y se reutilizan)
    local width
    local renderedId = false -- página pintada (false = ninguna vez); solo se repinta si cambia

    local function Apply(fontString, role)
        local ok, reason = theme:ApplyText(fontString, role)
        if not ok then
            error("Theme:ApplyText(" .. role .. ") falló: " .. tostring(reason), 0)
        end
    end

    local function Tint(fontString, colorName)
        local color = theme:GetColor(colorName)
        fontString:SetTextColor(color[1], color[2], color[3], color[4])
    end

    local function NewText(owner, role, template)
        local fontString = owner:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
        fontString:SetJustifyH("LEFT")
        fontString:SetJustifyV("TOP")
        Apply(fontString, role)
        return fontString
    end

    local function NewButtonWithLabel(label)
        local button = createFrame("Button", nil, toolbar)
        local text = NewText(button, "BODY")
        text:SetPoint("LEFT", button, "LEFT", 0, 0)
        text:SetText(label or "")
        return button, text
    end

    local function NewCrumb()
        local crumb = {}
        crumb.button, crumb.label = NewButtonWithLabel("")
        crumb.button:SetScript("OnClick", function() if crumb.id then model:Select(crumb.id) end end)
        return crumb
    end

    local function NewLinkRow()
        local row = {}
        row.button = createFrame("Button", nil, child)
        row.label = NewText(row.button, "BODY")
        row.label:SetPoint("LEFT", row.button, "LEFT", 0, 0)
        row.button:SetScript("OnClick", function() if row.id then model:Select(row.id) end end)
        return row
    end

    local function NewSeparator()
        local text = NewText(toolbar, "SECONDARY")
        text:SetText(TEXT_SEPARATOR)
        return text
    end

    function self:Attach(parent, theWidth, height, theModel)
        model, width = theModel, theWidth
        local toolbarHeight = theme:GetLayout("CODEX_TOOLBAR_HEIGHT")
        local line = theme:GetLayout("CODEX_DIVIDER_THICKNESS")
        local pad = theme:GetSpacing("LG")
        local buttonWidth = theme:GetLayout("CODEX_BUTTON_WIDTH")

        toolbar = createFrame("Frame", nil, parent)
        toolbar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        toolbar:SetSize(width, toolbarHeight)

        back = createFrame("Button", nil, toolbar)
        back:SetSize(buttonWidth, toolbarHeight)
        back:SetPoint("TOPLEFT", toolbar, "TOPLEFT", pad / 2, 0)
        backLabel = NewText(back, "BODY")
        backLabel:SetPoint("CENTER", back, "CENTER", 0, 0)
        backLabel:SetText(TEXT_BACK)
        back:SetScript("OnClick", function() model:Back() end)
        forward = createFrame("Button", nil, toolbar)
        forward:SetSize(buttonWidth, toolbarHeight)
        forward:SetPoint("TOPLEFT", back, "TOPRIGHT", 0, 0)
        forwardLabel = NewText(forward, "BODY")
        forwardLabel:SetPoint("CENTER", forward, "CENTER", 0, 0)
        forwardLabel:SetText(TEXT_FORWARD)
        forward:SetScript("OnClick", function() model:Forward() end)

        ellipsis = NewText(toolbar, "SECONDARY")
        ellipsis:SetText(TEXT_ELLIPSIS)

        local divider = parent:CreateTexture(nil, "ARTWORK")
        divider:SetTexture(theme:GetTexture("SOLID"))
        local dividerColor = theme:GetColor("DIVIDER")
        divider:SetVertexColor(dividerColor[1], dividerColor[2], dividerColor[3], dividerColor[4])
        divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -toolbarHeight)
        divider:SetSize(width, line)

        scroll = deps.scroll:Create(parent, 0, toolbarHeight + line, width, height - toolbarHeight - line)
        child = scroll:GetChild()

        title = NewText(child, "TITLE", "GameFontNormalLarge")
        kind = NewText(child, "SECONDARY", "GameFontNormalSmall")
        location = NewText(child, "SECONDARY", "GameFontNormalSmall")
        details = NewText(child, "SECONDARY", "GameFontNormalSmall")
        descriptionText = NewText(child, "BODY")
        descriptionText:SetSpacing(theme:GetLayout("POPUP_LINE_SPACING"))
        rule = child:CreateTexture(nil, "ARTWORK")
        rule:SetTexture(theme:GetTexture("SOLID"))
        rule:SetVertexColor(dividerColor[1], dividerColor[2], dividerColor[3], dividerColor[4])
        bodyText = NewText(child, "BODY")
        bodyText:SetSpacing(theme:GetLayout("POPUP_LINE_SPACING"))
        empty = NewText(child, "SECONDARY", "GameFontNormalSmall")
        empty:SetText(TEXT_EMPTY)
        if deps.npcModel and type(deps.npcModel.New) == "function" then
            modelView = deps.npcModel.New({ theme = theme, createFrame = createFrame })
            modelView:Attach(child, scroll:GetContentWidth() - 2 * pad) -- no lanza errores: sin visor, la página sigue igual
        end
    end

    local function MeasuredHeight(fontString)
        local h = fontString:GetStringHeight()
        return IsFinite(h) and h or 0
    end

    -- Coloca un texto en la columna de la página y devuelve la nueva posición vertical.
    local function Place(fontString, text, y, textWidth, pad, gap)
        fontString:ClearAllPoints()
        fontString:SetPoint("TOPLEFT", child, "TOPLEFT", pad, -y)
        fontString:SetWidth(textWidth)
        fontString:SetText(text)
        fontString:Show()
        return y + MeasuredHeight(fontString) + gap
    end

    local function RefreshPage()
        local pad, gap = theme:GetSpacing("LG"), theme:GetSpacing("SM")
        local textWidth = scroll:GetContentWidth() - 2 * pad
        local current = model:GetCurrent()
        local page = current and model:GetPage(current) or nil
        for _, widget in ipairs({ title, kind, location, details, descriptionText, bodyText, empty }) do
            widget:SetText("")
            widget:Hide()
        end
        rule:Hide()
        -- Se vacía todo lo que depende de la página anterior (visor y enlaces) ANTES de decidir qué hay en la nueva.
        if modelView then modelView:Hide() end
        for _, header in ipairs(linkHeaders) do
            header:SetText("")
            header:Hide()
        end
        for _, row in ipairs(linkRows) do
            row.id = nil
            row.label:SetText("")
            row.button:Hide()
        end

        if not page then
            local y = Place(empty, TEXT_EMPTY, pad, textWidth, pad, gap)
            scroll:SetContentHeight(y + pad)
            scroll:ScrollTo(0)
            return
        end
        local y = pad
        y = Place(title, page.name, y, textWidth, pad, gap / 2)
        if page.locked then
            Tint(title, "LOCKED")
            y = Place(kind, TEXT_LOCKED, y, textWidth, pad, gap / 2)
            scroll:SetContentHeight(y + pad)
            scroll:ScrollTo(0)
            return
        end
        Tint(title, page.nameIsFallback and "TEXT_MUTED" or "GOLD")
        y = Place(kind, page.typeLabel, y, textWidth, pad, gap / 2)
        if page.location then
            y = Place(location, TEXT_LOCATION .. page.location.name, y, textWidth, pad, gap / 2)
            if page.location.locked then Tint(location, "LOCKED") else Tint(location, "TEXT_MUTED") end
        end
        if #page.details > 0 then
            local parts = {}
            for _, item in ipairs(page.details) do
                parts[#parts + 1] = item.label .. ": " .. item.value
            end
            y = Place(details, table.concat(parts, "   "), y, textWidth, pad, gap / 2)
        end
        y = y + gap / 2
        if page.model and modelView and modelView:Show(page.model, pad, y) then
            local _, modelHeight = modelView:GetSize()
            y = y + modelHeight + gap
        end
        if page.description then
            y = Place(descriptionText, page.description, y, textWidth, pad, gap * 2)
        end
        if page.body then
            local line = theme:GetLayout("CODEX_DIVIDER_THICKNESS")
            rule:ClearAllPoints()
            rule:SetPoint("TOPLEFT", child, "TOPLEFT", pad, -y)
            rule:SetSize(textWidth, line)
            rule:Show()
            y = y + line + gap
            y = Place(bodyText, page.body, y, textWidth, pad, gap * 2)
        end
        -- Enlaces a otras entidades (cada sección: una cabecera y un botón por destino)
        local indent, rowHeight = theme:GetLayout("CODEX_ROW_INDENT"), theme:GetLayout("CODEX_ROW_HEIGHT")
        local rowIndex = 0
        for sectionIndex, section in ipairs(page.links or {}) do
            local header = linkHeaders[sectionIndex]
            if not header then
                header = NewText(child, "SECONDARY", "GameFontNormalSmall")
                linkHeaders[sectionIndex] = header
            end
            y = Place(header, section.label, y, textWidth, pad, gap / 2)
            for _, item in ipairs(section.items) do
                rowIndex = rowIndex + 1
                local row = linkRows[rowIndex]
                if not row then
                    row = NewLinkRow()
                    linkRows[rowIndex] = row
                end
                row.id = item.id
                row.button:ClearAllPoints()
                row.button:SetPoint("TOPLEFT", child, "TOPLEFT", pad + indent, -y)
                row.button:SetSize(textWidth - indent, rowHeight)
                row.label:SetWidth(textWidth - indent)
                row.label:SetText(item.name)
                Tint(row.label, item.locked and "LOCKED" or (item.nameIsFallback and "TEXT_MUTED" or "GOLD_DIM"))
                row.button:Show()
                y = y + rowHeight
            end
            y = y + gap
        end
        scroll:SetContentHeight(y)
        scroll:ScrollTo(0) -- cada página nueva empieza arriba
    end

    local function RefreshToolbar()
        Tint(backLabel, model:CanBack() and "GOLD" or "TEXT_MUTED")
        Tint(forwardLabel, model:CanForward() and "GOLD" or "TEXT_MUTED")

        local pad = theme:GetSpacing("LG")
        local sepGap = theme:GetSpacing("XS")
        local items = model:GetCurrent() and model:GetBreadcrumbs(model:GetCurrent()) or {}
        for _, crumb in ipairs(crumbs) do
            crumb.label:SetText("") -- los tramos sin usar no conservan el nombre de la ruta anterior
            crumb.button:Hide()
        end
        for _, separator in ipairs(separators) do separator:Hide() end
        ellipsis:Hide()

        local x0 = pad / 2 + 2 * theme:GetLayout("CODEX_BUTTON_WIDTH") + sepGap
        local available = width - x0 - pad
        -- Se miden los textos reales para decidir cuántos tramos caben.
        local function WidthOf(item, i)
            local crumb = crumbs[i] or NewCrumb()
            crumbs[i] = crumb
            crumb.label:SetText(item.name)
            local w = crumb.label:GetStringWidth()
            return IsFinite(w) and w or 0
        end
        local widths, total = {}, 0
        for i, item in ipairs(items) do
            widths[i] = WidthOf(item, i)
            total = total + widths[i]
        end
        local sepWidth = 0
        if #separators > 0 or #items > 1 then
            separators[1] = separators[1] or NewSeparator()
            local w = separators[1]:GetStringWidth()
            sepWidth = (IsFinite(w) and w or 0) + 2 * sepGap
        end
        local ellipsisWidth = 0
        do
            local w = ellipsis:GetStringWidth()
            ellipsisWidth = (IsFinite(w) and w or 0) + sepGap
        end

        local first = 1
        local function Needed(from)
            local count = #items - from + 1
            local sum = 0
            for i = from, #items do sum = sum + widths[i] end
            return sum + math.max(0, count - 1) * sepWidth + (from > 1 and (ellipsisWidth + sepWidth) or 0)
        end
        while first < #items and Needed(first) > available do
            first = first + 1
        end

        local x = x0
        if first > 1 then
            ellipsis:ClearAllPoints()
            ellipsis:SetPoint("LEFT", toolbar, "LEFT", x, 0)
            ellipsis:Show()
            x = x + ellipsisWidth
        end
        local shownIndex = 0
        for i = first, #items do
            local item, crumb = items[i], crumbs[i]
            crumb.id = item.id
            crumb.label:SetText(item.name)
            local isLast = i == #items
            Tint(crumb.label, item.locked and "LOCKED" or (isLast and "GOLD" or (item.nameIsFallback and "TEXT_MUTED" or "TEXT_IVORY")))
            crumb.button:ClearAllPoints()
            crumb.button:SetPoint("LEFT", toolbar, "LEFT", x, 0)
            crumb.button:SetSize(math.max(1, widths[i]), theme:GetLayout("CODEX_TOOLBAR_HEIGHT"))
            crumb.button:Show()
            if isLast then
                crumb.id = nil -- la página actual no es un enlace
            end
            x = x + widths[i]
            if not isLast then
                shownIndex = shownIndex + 1
                local separator = separators[shownIndex] or NewSeparator()
                separators[shownIndex] = separator
                separator:ClearAllPoints()
                separator:SetPoint("LEFT", toolbar, "LEFT", x + sepGap, 0)
                separator:Show()
                x = x + sepWidth
            end
        end
    end

    -- `forcePage`: repinta la página aunque sea la misma (cuando cambia lo que se puede ver de ella, p. ej. al descubrirla).
    function self:Refresh(forcePage)
        -- Expandir o contraer el árbol no cambia la página: no se repinta ni se pierde el desplazamiento de lectura.
        local current = model:GetCurrent()
        if forcePage or current ~= renderedId then
            RefreshPage()
            renderedId = current
        end
        RefreshToolbar()
    end

    return self
end

Chronicle.CodexPage = { New = NewPage }
