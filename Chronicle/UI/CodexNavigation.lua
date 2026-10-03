Chronicle = Chronicle or {}

-- CodexNavigation: el árbol navegable de la zona izquierda del Codex (la VISTA; la lógica está en CodexModel). Pinta las
-- filas visibles que da el modelo, con una sangría por nivel, un botón +/- para expandir o contraer y el nombre como botón
-- de selección. Interno de la UI del Codex.
--
--   · Seleccionar (clic en el nombre)     model:Select(id)  -> cambia la página y queda registrada en el historial.
--   · Expandir/contraer (clic en +/-)     model:Toggle(id)  -> NO cambia la página: es otro botón.
--   · La fila seleccionada lleva un fondo (color SELECTION) y el texto en oro; un nombre que es un fallback (el ID) va atenuado.
--   · Las filas son un conjunto que se REUTILIZA: crece cuando hace falta y las sobrantes se ocultan; nunca se destruyen.
--   · Al cambiar la selección se desplaza la lista lo mínimo para que la fila seleccionada sea visible.
--
-- API: Chronicle.CodexNavigation.New({ theme, createFrame, scroll }) -> vista
--   vista:Attach(parent, width, height, model)   construye los widgets (lanza error si algo falla)
--   vista:Refresh()                              repinta desde el modelo
-- Colores, fuentes y medidas salen de Theme. Los únicos literales son los símbolos «+» y «-» de los botones.

local SYMBOL_COLLAPSED, SYMBOL_EXPANDED = "+", "-"

local function NewNavigation(deps)
    if type(deps) ~= "table" or type(deps.theme) ~= "table" or type(deps.createFrame) ~= "function"
        or type(deps.scroll) ~= "table" then
        error("Chronicle.CodexNavigation.New: se esperaba una tabla { theme, createFrame, scroll }", 2)
    end
    local theme, createFrame = deps.theme, deps.createFrame
    local self = {}
    local model, scroll, child
    local rows = {}
    local lastSelected

    local function ApplyColor(fontString, colorName)
        local color = theme:GetColor(colorName)
        fontString:SetTextColor(color[1], color[2], color[3], color[4])
    end

    local function NewRow()
        local row = {}
        local rowHeight = theme:GetLayout("CODEX_ROW_HEIGHT")
        row.select = createFrame("Button", nil, child)
        row.select:SetHeight(rowHeight)
        row.highlight = row.select:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetTexture(theme:GetTexture("SOLID"))
        local selection = theme:GetColor("SELECTION")
        row.highlight:SetVertexColor(selection[1], selection[2], selection[3], selection[4])
        row.highlight:SetPoint("TOPLEFT", row.select, "TOPLEFT", 0, 0)
        row.highlight:SetPoint("BOTTOMRIGHT", row.select, "BOTTOMRIGHT", 0, 0)
        row.label = row.select:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.label:SetJustifyH("LEFT")
        local ok, reason = theme:ApplyText(row.label, "BODY")
        if not ok then error("Theme:ApplyText(BODY) falló: " .. tostring(reason), 0) end
        row.select:SetScript("OnClick", function() model:Select(row.id) end)

        -- Se crea DESPUÉS del botón de selección: queda por encima de él y recibe sus propios clics.
        row.toggle = createFrame("Button", nil, child)
        row.toggle:SetSize(theme:GetLayout("CODEX_TOGGLE_WIDTH"), rowHeight)
        row.symbol = row.toggle:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.symbol:SetPoint("CENTER", row.toggle, "CENTER", 0, 0)
        ok, reason = theme:ApplyText(row.symbol, "BODY")
        if not ok then error("Theme:ApplyText(BODY) falló: " .. tostring(reason), 0) end
        ApplyColor(row.symbol, "GOLD")
        row.toggle:SetScript("OnClick", function() model:Toggle(row.id) end)
        return row
    end

    function self:Attach(parent, width, height, theModel)
        model = theModel
        scroll = deps.scroll:Create(parent, 0, 0, width, height)
        child = scroll:GetChild()
    end

    function self:Refresh()
        local list = model:GetRows()
        local rowHeight = theme:GetLayout("CODEX_ROW_HEIGHT")
        local indent = theme:GetLayout("CODEX_ROW_INDENT")
        local toggleWidth = theme:GetLayout("CODEX_TOGGLE_WIDTH")
        local gap = theme:GetSpacing("XS")
        local contentWidth = scroll:GetContentWidth()
        local selectedIndex

        for i, item in ipairs(list) do
            local row = rows[i]
            if not row then
                row = NewRow()
                rows[i] = row
            end
            row.id = item.id
            local top = (i - 1) * rowHeight
            local x = (item.depth or 0) * indent
            row.select:ClearAllPoints()
            row.select:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -top)
            row.select:SetWidth(contentWidth)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.select, "LEFT", x + toggleWidth + gap, 0)
            row.label:SetWidth(math.max(1, contentWidth - x - toggleWidth - gap))
            row.label:SetText(item.name)
            ApplyColor(row.label, item.selected and "GOLD" or (item.nameIsFallback and "TEXT_MUTED" or "TEXT_IVORY"))
            if item.selected then
                row.highlight:Show()
                selectedIndex = i
            else
                row.highlight:Hide()
            end
            row.toggle:ClearAllPoints()
            row.toggle:SetPoint("TOPLEFT", child, "TOPLEFT", x, -top)
            if item.hasChildren then
                row.symbol:SetText(item.expanded and SYMBOL_EXPANDED or SYMBOL_COLLAPSED)
                row.toggle:Show()
            else
                row.symbol:SetText("")
                row.toggle:Hide()
            end
            row.select:Show()
        end
        for i = #list + 1, #rows do
            rows[i].id = nil
            rows[i].select:Hide()
            rows[i].toggle:Hide()
        end

        scroll:SetContentHeight(#list * rowHeight)
        -- Solo se «revela» la fila cuando cambia la selección: expandir o contraer no debe mover la lista.
        local current = model:GetCurrent()
        if selectedIndex and current ~= lastSelected then
            scroll:Reveal((selectedIndex - 1) * rowHeight, selectedIndex * rowHeight)
        end
        lastSelected = current
    end

    return self
end

Chronicle.CodexNavigation = { New = NewNavigation }
