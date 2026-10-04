-- Regresión del árbol del Codex que NO respondía a los clics en WoW Classic Era (rama correccion-codex-arbol). Con el addon real y el mock estricto:
-- lo que se comprueba es la LÓGICA de la fila (expandir/contraer, nombres, orden, reutilización) y los NIVELES de frame de los dos botones de cada fila.
-- El mock NO simula qué frame recibe un clic cuando dos se solapan, así que estas pruebas NO demuestran que el clic funcione en el cliente real.

local realCreateFrame = CreateFrame
local created = {}

created = {}
CreateFrame = function(kind, name, parent, template)
    local frame = realCreateFrame(kind, name, parent, template)
    created[#created + 1] = { kind = kind, name = name, template = template, frame = frame, parent = parent }
    return frame
end
LoadAddon()
ChronicleCharDB = nil
FireEvent("ADDON_LOADED", "Chronicle")
-- Se mantiene el registro de frames: las filas del árbol se crean al repintar.

local codex, loc, discovery = Chronicle.Codex, Chronicle.Localization, Chronicle.Discovery
local win = _G["ChronicleCodexFrame"]
if not win then
    check("T0. el Codex crea su ventana al arrancar (sin ella no se puede comprobar el árbol)", false)
    CreateFrame = realCreateFrame
    do return end
end
-- Como en la prueba real: solo la zona y la subzona del jugador están descubiertas; el continente, no.
discovery:Discover("zone:dun_morogh")
discovery:Discover("subzone:kharanos")
codex:Show()

local panes = {}
for _, entry in ipairs(created) do
    if entry.parent == win and entry.kind == "Frame" then panes[#panes + 1] = entry.frame end
end
local navPane, contentPane = panes[1], panes[2]
local navChild, toolbar
for _, entry in ipairs(created) do
    if entry.kind == "ScrollFrame" and entry.parent == navPane then navChild = entry.frame.scrollChild end
    if entry.parent == contentPane and entry.kind == "Frame" and not toolbar then toolbar = entry.frame end
end
local function textOf(frame)
    for _, child in ipairs(frame.children or {}) do
        if child.text ~= nil then return child.text, child end
    end
end
local function allRows()
    local rows, pending = {}, nil
    for _, entry in ipairs(created) do
        if entry.kind == "Button" and entry.parent == navChild then
            if not pending then pending = entry.frame else rows[#rows + 1] = { select = pending, toggle = entry.frame }; pending = nil end
        end
    end
    return rows
end
local function visibleRows()
    local out = {}
    for _, row in ipairs(allRows()) do if row.select.shown == true then out[#out + 1] = row end end
    return out
end
local function names()
    local out = {}
    for _, row in ipairs(visibleRows()) do out[#out + 1] = textOf(row.select) end
    return out
end
local function click(frame)
    local handler = frame and frame.__scripts and frame.__scripts.OnClick
    if handler then handler(frame) end
end
local function nameOf(id) return (loc:Get(id, "name")) end
local LOCKED = "???"

-- ===================== Estado de partida =====================
local rows = visibleRows()
check("T1. el árbol arranca con una sola fila: el continente bloqueado, con «???» (nunca su nombre real) y un control «+» visible",
    #rows == 1 and textOf(rows[1].select) == LOCKED and rows[1].toggle.shown == true and textOf(rows[1].toggle) == "+")

-- ===================== Niveles de frame (superposición) =====================
-- El botón de selección ocupa TODA la fila y el +/- se coloca sobre él, así que ambos se solapan. El orden entre frames del MISMO nivel no está
-- garantizado por el cliente: el +/- debe tener un nivel EXPLÍCITAMENTE superior al del botón de selección de su fila.
local function togglesAboveSelects()
    for i, row in ipairs(allRows()) do
        if not (row.toggle:GetFrameLevel() > row.select:GetFrameLevel()) then return false, i end
    end
    return #allRows() > 0
end
check("T2. el control +/- de cada fila tiene un nivel de frame ESTRICTAMENTE mayor que el botón de selección que lo solapa", togglesAboveSelects())

-- ===================== Expandir y contraer =====================
click(rows[1].toggle)
check("T3. un clic en el «+» de una raíz BLOQUEADA la expande y cambia su símbolo a «-»: «???» no significa «sin hijos»",
    #visibleRows() == 4 and textOf(rows[1].toggle) == "-" and Chronicle.Codex:IsReady())
check("T3b. los hijos salen en el orden jerárquico del modelo (zona, zona, ciudad); el descubierto con su nombre real y los demás con «???»",
    (function()
        local n = names()
        return n[1] == LOCKED and n[2] == nameOf("zone:dun_morogh") and n[3] == LOCKED and n[4] == LOCKED
    end)())
check("T3c. los hijos no descubiertos no filtran su nombre real en ningún widget visible",
    (function()
        for _, row in ipairs(visibleRows()) do
            local text = textOf(row.select)
            if text == nameOf("zone:loch_modan") or text == nameOf("city:ironforge") or text == nameOf("continent:eastern_kingdoms") then return false end
        end
        return true
    end)())
check("T3d. los hijos están sangrados un nivel respecto a su padre",
    visibleRows()[2].select.children[2].points[1][4] > visibleRows()[1].select.children[2].points[1][4])
check("T3e. los controles de las filas nuevas (creadas al expandir) también están por encima de su botón de selección", togglesAboveSelects())

click(visibleRows()[1].toggle)
check("T4. un segundo clic en el «-» contrae la rama: queda una fila y el símbolo vuelve a «+»", #visibleRows() == 1 and textOf(visibleRows()[1].toggle) == "+")

-- ===================== Filas reutilizadas =====================
do
    local hidden = {}
    for _, row in ipairs(allRows()) do if row.select.shown ~= true then hidden[#hidden + 1] = row end end
    local before = table.concat(names(), "|")
    for _, row in ipairs(hidden) do click(row.toggle); click(row.select) end
    check("T5. las filas sobrantes (ocultas) no conservan ni el texto ni el ID de lo que mostraron: pulsarlas no expande, no selecciona y no cambia nada",
        #hidden == 3 and table.concat(names(), "|") == before and #visibleRows() == 1 and Chronicle.Codex:IsReady()
            and (function()
                for _, row in ipairs(hidden) do
                    if textOf(row.select) ~= "" or textOf(row.toggle) ~= "" then return false end
                end
                return true
            end)())
end
click(visibleRows()[1].toggle)
check("T5b. al volver a expandir se reutilizan las mismas filas (no se crean más) y cada una muestra de nuevo SU entidad",
    #allRows() == 4 and #visibleRows() == 4 and names()[2] == nameOf("zone:dun_morogh"))

-- ===================== Rama descubierta, hoja y navegación =====================
click(visibleRows()[2].toggle) -- expandir Dun Morogh (cuelga bajo un ancestro bloqueado)
local n = names()
check("T6. expandir una zona descubierta bajo un continente bloqueado muestra sus subzonas; la descubierta (Kharanos) con su nombre real y las demás con «???»",
    (function()
        local found, locked = false, 0
        for _, name in ipairs(n) do
            if name == nameOf("subzone:kharanos") then found = true end
            if name == LOCKED then locked = locked + 1 end
        end
        return found and locked >= 2 and #n > 4
    end)())
-- Hoja: una fila visible sin hijos (p. ej. una subzona sin personajes). Kharanos NO lo es (tiene personajes situados en ella).
local leaf, leafName
for _, row in ipairs(visibleRows()) do
    if row.toggle.shown ~= true and not leaf then leaf = row end
end
check("T7. una fila SIN hijos no muestra control de expansión: ni símbolo ni botón visible, y pulsarla no expande nada",
    leaf ~= nil and leaf.toggle.shown ~= true and textOf(leaf.toggle) == "" and (function()
        local before = #visibleRows()
        click(leaf.toggle)
        return #visibleRows() == before
    end)())
for _, row in ipairs(visibleRows()) do if textOf(row.select) == nameOf("subzone:kharanos") then leaf = row end end
click(leaf.select) -- Kharanos
local crumbs, toolbarButtons = {}, {}
for _, entry in ipairs(created) do
    if entry.kind == "Button" and entry.parent == toolbar then toolbarButtons[#toolbarButtons + 1] = entry.frame end
end
-- Los dos primeros botones de la barra son Atrás y Adelante; el resto son los tramos del breadcrumb (solo los visibles).
for i = 3, #toolbarButtons do
    if toolbarButtons[i].shown == true then crumbs[#crumbs + 1] = textOf(toolbarButtons[i]) end
end
check("T8. seleccionar Kharanos sigue funcionando: el breadcrumb es «???» (continente bloqueado) > zona > subzona, sin revelar el continente",
    table.concat(crumbs, "|") == LOCKED .. "|" .. nameOf("zone:dun_morogh") .. "|" .. nameOf("subzone:kharanos"))
click(visibleRows()[1].toggle)
check("T9. expandir o contraer no cambia la selección: tras contraer el continente la página sigue siendo Kharanos y el árbol vuelve a una fila",
    #visibleRows() == 1 and (function()
        click(visibleRows()[1].toggle)
        for _, row in ipairs(visibleRows()) do
            if textOf(row.select) == nameOf("subzone:kharanos") then return row.select.children[1].shown == true end
        end
        return false
    end)())

CreateFrame = realCreateFrame
