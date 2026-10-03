-- Escenarios de prueba del Popup (Fase 7). Se prueban con el mock ESTRICTO de la interfaz (tests/mock.lua) y con frames
-- manipulados para provocar fallos. Esto verifica la lógica (ciclo de vida, cola, validación, estados coherentes);
-- NO demuestra que la ventana se vea o se comporte bien dentro del cliente real de Classic Era.

local EVENT_MOVED = "Chronicle.Popup.Moved"
local FRAME_NAME = "ChroniclePopupFrame"

local realCreateFrame = CreateFrame
local created = {}

-- Arranca el addon completo registrando qué frames se crean y con qué nombre/plantilla.
local function Boot(prepare)
    created = {}
    CreateFrame = function(kind, name, parent, template)
        local frame = realCreateFrame(kind, name, parent, template)
        created[#created + 1] = { kind = kind, name = name, template = template, frame = frame, parent = parent }
        return frame
    end
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    if Chronicle.Events then
        Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    end
    FireEvent("ADDON_LOADED", "Chronicle")
    CreateFrame = realCreateFrame
    return announced
end

local function named(name)
    local n = 0
    for _, entry in ipairs(created) do if entry.name == name then n = n + 1 end end
    return n
end
local function windowOf() return _G[FRAME_NAME] end
local function titleOf(frame) return frame.children[1] end
local function bodyOf(frame) return frame.children[3] end
local function closeButton()
    for _, entry in ipairs(created) do
        if entry.template == "UIPanelCloseButton" and entry.parent == windowOf() then return entry.frame end
    end
end
local function countIn(list, value)
    local n = 0
    for _, v in ipairs(list) do if v == value then n = n + 1 end end
    return n
end
local function copy(t) return Chronicle.Utils.DeepCopy(t) end
local function titles(popupSeen) return table.concat(popupSeen, ",") end
-- Título del contenido mostrado, o "-" si no hay: así un defecto no provoca una excepción sino una aserción fallida.
local function titleNow() local c = Chronicle.Popup:GetContent(); return c and c.title or "-" end

-- Una instancia propia (Popup.New) con dependencias reales del mock, o saboteadas.
local function Make(over)
    over = over or {}
    -- false = "esta dependencia no existe" (nil); nil = valor por defecto.
    local function pick(value, default)
        if value == false then return nil end
        if value == nil then return default end
        return value
    end
    local ctx = { frames = {}, special = (over.special ~= nil and over.special ~= false) and over.special or {}, moved = {} }
    local realFactory = function(...)
        local frame = realCreateFrame(...)
        ctx.frames[#ctx.frames + 1] = frame
        return frame
    end
    ctx.factoryCalls = 0
    local factory = over.createFrame or function(...)
        ctx.factoryCalls = ctx.factoryCalls + 1
        return realFactory(...)
    end
    if over.createFrame then
        local inner = over.createFrame
        factory = function(...) ctx.factoryCalls = ctx.factoryCalls + 1 return inner(realFactory, ...) end
    end
    ctx.popup = Chronicle.Popup.New({
        theme = pick(over.theme, Chronicle.Theme),
        events = pick(over.events, Chronicle.Events),
        createFrame = (not over.noCreateFrame) and factory or nil,
        uiParent = pick(over.uiParent, UIParent),
        specialFrames = pick(over.special, ctx.special),
    })
    return ctx
end

local A = { title = "Dun Morogh", body = "La tierra ancestral del clan Bronzebeard." }
local B = { title = "Kharanos", body = "El primer asentamiento enano de cierta entidad." }
local C = { title = "Thelsamar", body = "El corazón de Loch Modan." }
local D = { title = "Forjaz", body = "La gran ciudad-fortaleza de los enanos." }

-- ===================== Arranque =====================
local announced = Boot()
local Popup = Chronicle.Popup
check("el addon arranca con Theme y Popup listos, sin fallos ni omitidos, y el arranque se anuncia una vez",
    Popup:IsReady() == true and Chronicle.Theme:IsReady() and Chronicle.Init.ready == true and announced == 1
        and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil)
check("1. Popup se inicializa correctamente: la ventana existe, está oculta y es un único frame con su nombre",
    windowOf() ~= nil and windowOf():IsShown() == false and Popup:IsVisible() == false and named(FRAME_NAME) == 1)
local w = windowOf()
check("1b. la ventana tiene los atributos de Theme: capa HIGH, 420x140, anclada arriba y centrada 160 bajo el borde, movible",
    w.strata == "HIGH" and w.width == 420 and w.height == 140 and w.movable == true and w.mouse == true and w.dragButton == "LeftButton"
        and w.clamped == true and select(1, w:GetPoint(1)) == "TOP" and select(3, w:GetPoint(1)) == "TOP"
        and select(5, w:GetPoint(1)) == -160 and w:GetPoint(1) == "TOP" and select(2, w:GetPoint(1)) == UIParent)
check("1c. el fondo y el borde son los de Theme (backdrop de ventana, fondo y borde bronce)",
    w.backdrop.bgFile == "Interface/DialogFrame/UI-DialogBox-Background"
        and deepEqual(w.backdropColor, Chronicle.Theme:GetColor("BG_WINDOW")) and deepEqual(w.backdropBorderColor, Chronicle.Theme:GetColor("BORDER")))
check("1d. título, separador y cuerpo: título y cuerpo con los roles TITLE y BODY de Theme; el separador con el color DIVIDER",
    deepEqual(titleOf(w).color, Chronicle.Theme:GetColor("GOLD")) and titleOf(w).font[1] == "Fonts\\MORPHEUS.ttf"
        and deepEqual(bodyOf(w).color, Chronicle.Theme:GetColor("TEXT_IVORY")) and bodyOf(w).font[2] == 13
        and deepEqual(w.children[2].vertexColor, Chronicle.Theme:GetColor("DIVIDER")) and w.children[2].texture == Chronicle.Theme:GetTexture("SOLID")
        and bodyOf(w).justifyH == "LEFT" and bodyOf(w).justifyV == "TOP" and bodyOf(w).spacing == 3)
check("1e. la ventana está registrada en UISpecialFrames una sola vez (Escape la cierra)", countIn(UISpecialFrames, FRAME_NAME) == 1)
check("1f. se crean exactamente dos frames de Popup: la ventana y su botón de cierre estándar; el único nombre global es el de la ventana",
    named(FRAME_NAME) == 1 and (function()
        local n = 0
        for _, entry in ipairs(created) do
            if entry.template == "UIPanelCloseButton" and entry.parent == windowOf() then n = n + 1 end
        end
        return n == 1
    end)() and (function()
        for _, entry in ipairs(created) do
            -- (el Codex, otro módulo, crea al arrancar su propia ventana con nombre: no es del Popup)
            if entry.name and entry.name ~= FRAME_NAME and entry.name ~= "ChronicleCodexFrame" then return false end
        end
        return true
    end)())

-- ===================== Init idempotente =====================
do
    Boot()
    local before = named(FRAME_NAME)
    local f1 = windowOf()
    Chronicle.Popup:Init(); Chronicle.Popup:Init()
    check("2. inicializar dos veces no crea una segunda ventana ni vuelve a registrar Escape",
        named(FRAME_NAME) == before and windowOf() == f1 and countIn(UISpecialFrames, FRAME_NAME) == 1 and Chronicle.Popup:IsReady())
    local ctx = Make()
    ctx.popup:Init(); ctx.popup:Init(); ctx.popup:Init()
    check("2b. en una instancia propia, tres Init crean una sola ventana", ctx.factoryCalls == 2 and #ctx.frames == 2
        and countIn(ctx.special, FRAME_NAME) == 1)
end

-- ===================== Mostrar contenido =====================
Boot()
Popup = Chronicle.Popup
do
    local ctx = Make({})
    check("3. Show antes de Init devuelve 'not_ready' y no crea ninguna ventana",
        select(2, ctx.popup:Show(A)) == "not_ready" and ctx.popup:Show(A) == false and #ctx.frames == 0)
    check("3b. Enqueue, Close y CloseAll antes de Init son seguros", select(2, ctx.popup:Enqueue(A)) == "not_ready"
        and ctx.popup:Close() == false and ctx.popup:CloseAll() == false and ctx.popup:IsVisible() == false
        and ctx.popup:GetContent() == nil and ctx.popup:GetPosition() == nil and ctx.popup:GetSize() == nil
        and select(2, ctx.popup:SetPosition("TOP", "TOP", 0, 0)) == "not_ready")
end

local windowBefore = windowOf()
local ok, extra = Popup:Show(A)
check("3c. Show muestra el contenido: devuelve true, la ventana pasa a visible y el título y el cuerpo son los dados",
    ok == true and extra == nil and Popup:IsVisible() == true and windowBefore:IsShown() == true
        and titleOf(windowBefore).text == A.title and bodyOf(windowBefore).text == A.body)
check("3d. Show reutiliza la ventana prevista: sigue habiendo un único frame con su nombre", windowOf() == windowBefore and named(FRAME_NAME) == 1)
check("3e. GetContent devuelve una copia del contenido mostrado", deepEqual(Popup:GetContent(), A) and Popup:GetContent() ~= A)
check("3f. con poco texto la altura es el mínimo (140); la anchura es la de Theme", select(1, Popup:GetSize()) == 420 and select(2, Popup:GetSize()) == 140)

-- ===================== Actualizar una ventana abierta =====================
local okB = Popup:Show(B)
check("4. mostrar contenido nuevo con la ventana abierta la ACTUALIZA: mismo frame, visible, textos nuevos y sin ventanas duplicadas",
    okB == true and windowOf() == windowBefore and named(FRAME_NAME) == 1 and Popup:IsVisible()
        and titleOf(windowBefore).text == B.title and bodyOf(windowBefore).text == B.body and deepEqual(Popup:GetContent(), B))
Popup:Show(B)
check("4b. mostrar lo mismo otra vez es idempotente", deepEqual(Popup:GetContent(), B) and Popup:GetQueueSize() == 0 and Popup:IsVisible())
Popup:Show({ title = "Largo", body = string.rep("a", 600) })
check("4c. con mucho texto la altura crece con él: 54 + 160 + 16 = 230", select(2, Popup:GetSize()) == 230 and select(1, Popup:GetSize()) == 420)
Popup:Show({ title = "Más largo", body = string.rep("a", 1200) })
check("4d. y crece más con más texto (390)", select(2, Popup:GetSize()) == 390)
Popup:Show(A)
check("4e. y vuelve al mínimo cuando el texto es corto", select(2, Popup:GetSize()) == 140)
check("4f. un título vacío con cuerpo, o un cuerpo vacío con título, son contenidos válidos",
    Popup:Show({ body = "solo cuerpo" }) == true and titleOf(windowBefore).text == "" and bodyOf(windowBefore).text == "solo cuerpo"
        and Popup:Show({ title = "solo título" }) == true and titleOf(windowBefore).text == "solo título" and bodyOf(windowBefore).text == "")
do
    local input = { title = "Con |cffff0000color|r y tildes: áéíóú ñ", body = "Línea 1\nLínea 2 -- «comillas» 'apóstrofos' \"dobles\"" }
    Popup:Show(input)
    check("5. los textos se muestran tal cual (tildes, saltos de línea, comillas y secuencias del cliente sin tocar)",
        titleOf(windowBefore).text == input.title and bodyOf(windowBefore).text == input.body)
    input.title = "CAMBIADO"; input.body = "CAMBIADO"
    local got = Popup:GetContent()
    got.title = "OTRO"
    check("5b. el Popup guarda copias: cambiar la tabla original o la devuelta no altera lo mostrado",
        Popup:GetContent().title ~= "CAMBIADO" and Popup:GetContent().title ~= "OTRO" and titleOf(windowBefore).text ~= "CAMBIADO")
end
do
    local spaced = { title = "  Título con espacios  ", body = "  Cuerpo con espacios al principio y al final   \n\n" }
    Popup:Show(spaced)
    check("5c. los espacios y saltos de línea del principio y del final se conservan: el texto se muestra EXACTAMENTE como se dio",
        titleOf(windowBefore).text == spaced.title and bodyOf(windowBefore).text == spaced.body
            and Popup:GetContent().title == spaced.title and Popup:GetContent().body == spaced.body)
end
Popup:Show(A)

-- ===================== Cerrar =====================
check("6. Close cierra la ventana: devuelve true, IsVisible pasa a false y GetContent a nil",
    Popup:Close() == true and Popup:IsVisible() == false and windowBefore:IsShown() == false and Popup:GetContent() == nil)
check("6b. cerrar una ventana ya cerrada es seguro: false, sin error y sin cambios",
    Popup:Close() == false and Popup:Close() == false and Popup:IsVisible() == false and named(FRAME_NAME) == 1)
check("6c. CloseAll con la ventana cerrada también es seguro", Popup:CloseAll() == false and Popup:GetQueueSize() == 0)
check("6d. la ventana se puede volver a abrir tras cerrarla (la misma ventana)",
    Popup:Show(C) == true and Popup:IsVisible() and windowOf() == windowBefore and titleOf(windowBefore).text == C.title and named(FRAME_NAME) == 1)

-- Cierre por las vías del cliente
Popup:Show(A)
local x = closeButton()
x:Click()
check("7. el botón X estándar cierra la ventana y el estado de visibilidad se actualiza", Popup:IsVisible() == false and windowBefore:IsShown() == false
    and Popup:GetContent() == nil)
Popup:Show(A)
for _, name in ipairs(UISpecialFrames) do
    local f = _G[name]
    if f and f:IsShown() then f:Hide() end
end
check("7b. Escape (el cliente oculta los UISpecialFrames visibles) cierra la ventana y actualiza el estado",
    Popup:IsVisible() == false and Popup:GetContent() == nil)

-- ===================== Argumentos inválidos y contenido vacío =====================
Popup:Show(A)
local invalid = {
    { "nil", nil, "invalid_content" }, { "una cadena", "texto", "invalid_content" }, { "un número", 5, "invalid_content" },
    { "un booleano", true, "invalid_content" }, { "una función", print, "invalid_content" },
    { "una tabla vacía", {}, "empty_content" }, { "título y cuerpo vacíos", { title = "", body = "" }, "empty_content" },
    { "solo espacios y saltos", { title = "  ", body = "\n\t " }, "empty_content" },
    { "un título que no es cadena", { title = 5, body = "x" }, "invalid_content" },
    { "un cuerpo que no es cadena", { title = "x", body = {} }, "invalid_content" },
    { "un título booleano", { title = false, body = "x" }, "invalid_content" },
}
for _, case in ipairs(invalid) do
    local okCall, r1, r2 = pcall(Popup.Show, Popup, case[2])
    local okQ, q1, q2 = pcall(Popup.Enqueue, Popup, case[2])
    check("8. contenido inválido (" .. case[1] .. "): Show y Enqueue devuelven false + '" .. case[3] .. "', sin error, y NO cambian lo mostrado ni la cola",
        okCall and r1 == false and r2 == case[3] and okQ and q1 == false and q2 == case[3]
            and deepEqual(Popup:GetContent(), A) and Popup:GetQueueSize() == 0 and Popup:IsVisible())
end
check("8b. un contenido inválido con la ventana cerrada tampoco la abre",
    (function() Popup:Close(); local r = Popup:Show({}) == false and Popup:Enqueue(nil) == false; return r and Popup:IsVisible() == false end)())

-- ===================== Cola =====================
Popup:CloseAll()
local r1, r2 = Popup:Enqueue(A)
check("9. Enqueue con la ventana cerrada y sin cola la muestra al instante: true, 'shown'",
    r1 == true and r2 == "shown" and Popup:IsVisible() and deepEqual(Popup:GetContent(), A) and Popup:GetQueueSize() == 0)
check("9b. Enqueue con la ventana visible NO pisa el contenido: true, 'queued', sigue A y la cola crece",
    select(2, Popup:Enqueue(B)) == "queued" and select(2, Popup:Enqueue(C)) == "queued" and select(2, Popup:Enqueue(D)) == "queued"
        and deepEqual(Popup:GetContent(), A) and Popup:GetQueueSize() == 3)
local seen = {}
local function record() local c = Popup:GetContent(); seen[#seen + 1] = c and c.title or "-" end
Popup:Close(); record()
check("9c. al cerrar, se muestra el siguiente de la cola enseguida (sin temporizadores) y en orden: B", seen[1] == B.title and Popup:IsVisible() and Popup:GetQueueSize() == 2)
Popup:Close(); record(); Popup:Close(); record()
check("9d. el orden es FIFO: A, B, C, D sin perder ni duplicar ninguno", titles(seen) == "Kharanos,Thelsamar,Forjaz"
    and deepEqual(Popup:GetContent(), D) and Popup:GetQueueSize() == 0)
Popup:Close()
check("9e. con la cola vacía, cerrar la última deja la ventana cerrada", Popup:IsVisible() == false and Popup:GetQueueSize() == 0 and Popup:GetContent() == nil)
check("9f. cerrar y abrir de nuevo es consistente: un nuevo Enqueue la vuelve a mostrar al instante, sin restos de la cola",
    select(2, Popup:Enqueue(A)) == "shown" and deepEqual(Popup:GetContent(), A) and Popup:GetQueueSize() == 0)
Popup:Enqueue(B); Popup:Enqueue(C)
Popup:Show(D)
check("10. Show durante una cola REEMPLAZA lo mostrado pero no toca los pendientes",
    deepEqual(Popup:GetContent(), D) and Popup:GetQueueSize() == 2)
local afterShow = {}
Popup:Close(); afterShow[#afterShow + 1] = titleNow()
Popup:Close(); afterShow[#afterShow + 1] = titleNow()
check("10b. y los pendientes salen después, en su orden", titles(afterShow) == "Kharanos,Thelsamar")
Popup:CloseAll()
Popup:Enqueue(A); Popup:Enqueue(B); Popup:Enqueue(C)
local closedAll = Popup:CloseAll()
check("11. CloseAll vacía la cola y cierra: true, ventana cerrada, nada pendiente y no se muestra nada más",
    closedAll == true and Popup:IsVisible() == false and Popup:GetQueueSize() == 0 and Popup:GetContent() == nil)
check("11b. tras CloseAll la ventana vuelve a funcionar con normalidad", select(2, Popup:Enqueue(D)) == "shown" and deepEqual(Popup:GetContent(), D))
Popup:CloseAll()
-- La cola se avanza también por Escape y por la X
Popup:Enqueue(A); Popup:Enqueue(B); Popup:Enqueue(C)
closeButton():Click()
check("12. cerrar con la X también avanza la cola", deepEqual(Popup:GetContent(), B) and Popup:GetQueueSize() == 1)
for _, name in ipairs(UISpecialFrames) do local f = _G[name]; if f and f:IsShown() then f:Hide() end end
check("12b. cerrar con Escape también avanza la cola", deepEqual(Popup:GetContent(), C) and Popup:GetQueueSize() == 0)
Popup:CloseAll()
-- Límite de la cola
Popup:Enqueue(A)
local accepted, rejectedAt = 0, nil
for i = 1, 60 do
    local okEnq, why = Popup:Enqueue({ title = "T" .. i, body = "cuerpo " .. i })
    if okEnq then accepted = accepted + 1 elseif not rejectedAt then rejectedAt = { i, why } end
end
check("13. la cola tiene un límite de 50: las 50 primeras se aceptan y la 51.ª se rechaza con 'queue_full' (sin perder las anteriores)",
    accepted == 50 and rejectedAt and rejectedAt[1] == 51 and rejectedAt[2] == "queue_full" and Popup:GetQueueSize() == 50)
local order, count = {}, 0
while Popup:IsVisible() and count < 200 do -- acotado: una cola que no se vacía no debe colgar las pruebas
    count = count + 1
    order[#order + 1] = titleNow()
    Popup:Close()
end
check("13b. al vaciarla se muestran las 51 entradas aceptadas (la primera y las 50 de la cola), en orden, sin duplicados ni pérdidas",
    count == 51 and order[1] == "Dun Morogh" and order[2] == "T1" and order[51] == "T50" and Popup:GetQueueSize() == 0)
check("13c. y después sigue aceptando contenido", select(2, Popup:Enqueue(A)) == "shown")
Popup:CloseAll()

-- ===================== Posición y tamaño =====================
check("14. GetPosition devuelve la posición por defecto: TOP/TOP, 0, -160",
    deepEqual(Popup:GetPosition(), { point = "TOP", relativePoint = "TOP", x = 0, y = -160 }))
check("14b. SetPosition mueve la ventana y GetPosition lo refleja",
    Popup:SetPosition("CENTER", "CENTER", 25, -40) == true and deepEqual(Popup:GetPosition(), { point = "CENTER", relativePoint = "CENTER", x = 25, y = -40 })
        and windowOf():GetNumPoints() == 1)
check("14c. ResetPosition devuelve la ventana a su sitio por defecto",
    Popup:ResetPosition() == true and deepEqual(Popup:GetPosition(), { point = "TOP", relativePoint = "TOP", x = 0, y = -160 }))
for _, case in ipairs({
    { "punto inválido", { "MIDDLE", "TOP", 0, 0 } }, { "punto relativo inválido", { "TOP", "NOWHERE", 0, 0 } },
    { "puntos nil", { nil, nil, 0, 0 } }, { "x NaN", { "TOP", "TOP", 0 / 0, 0 } }, { "y infinita", { "TOP", "TOP", 0, 1 / 0 } },
    { "x cadena", { "TOP", "TOP", "10", 0 } }, { "y nil", { "TOP", "TOP", 0, nil } },
}) do
    local okPos, why = Popup:SetPosition(case[2][1], case[2][2], case[2][3], case[2][4])
    check("14d. SetPosition con " .. case[1] .. ": false + 'invalid_position' y la ventana no se mueve",
        okPos == false and why == "invalid_position" and deepEqual(Popup:GetPosition(), { point = "TOP", relativePoint = "TOP", x = 0, y = -160 }))
end
check("14e. el tamaño no se puede fijar: no existe SetSize (el ancho es el de Theme y el alto sigue al texto)", Popup.SetSize == nil)

-- Arrastre
do
    local moves = {}
    Chronicle.Events:Register(EVENT_MOVED, function(...) moves[#moves + 1] = { n = select("#", ...), ... } end)
    local win = windowOf()
    win.__scripts.OnDragStart(win)
    local startedMoving = win.moving
    Popup:SetPosition("BOTTOMLEFT", "BOTTOMLEFT", 30, 50) -- lo que el cliente dejaría tras arrastrar
    win.__scripts.OnDragStop(win)
    check("15. arrastrar: empieza a mover la ventana al iniciar y la suelta al terminar",
        startedMoving == true and win.moving == false)
    check("15b. al soltar se emite UN evento Chronicle.Popup.Moved con (point, relativePoint, x, y) para que otro módulo lo persista si procede",
        #moves == 1 and moves[1].n == 4 and moves[1][1] == "BOTTOMLEFT" and moves[1][2] == "BOTTOMLEFT" and moves[1][3] == 30 and moves[1][4] == 50
            and Popup.EVENT_MOVED == EVENT_MOVED)
    Chronicle.Events = nil
    local okDrag = pcall(win.__scripts.OnDragStop, win)
    Chronicle.Events = nil
    check("15c. sin bus de eventos soltar tras arrastrar no produce error", okDrag == true)
    Popup:ResetPosition()
end

-- ===================== Fallos de inicialización =====================
Boot()
do
    local theme = Chronicle.Theme
    local failing = Make({ createFrame = function() error("CreateFrame roto") end })
    local ok1, e1 = pcall(failing.popup.Init, failing.popup)
    local ok2, e2 = pcall(failing.popup.Init, failing.popup)
    check("16. si CreateFrame falla, Init lanza un error descriptivo y el Popup no queda listo",
        ok1 == false and tostring(e1):find("no se pudo crear la ventana", 1, true) ~= nil and failing.popup:IsReady() == false)
    check("16b. un Init fallido es definitivo: repetirlo da el mismo error SIN intentar crear otra ventana (sin ventanas huérfanas)",
        ok2 == false and e1 == e2 and failing.factoryCalls == 1)
    check("16c. tras un Init fallido todo devuelve 'not_ready' y nada lanza error",
        select(2, failing.popup:Show(A)) == "not_ready" and failing.popup:Close() == false and failing.popup:IsVisible() == false)

    local noTheme = Make({ theme = Chronicle.Theme.New({}) })
    check("16d. Theme no listo: Init lanza error y NO crea nada; no deja un fallo definitivo (se puede reintentar)",
        not pcall(noTheme.popup.Init, noTheme.popup) and #noTheme.frames == 0 and noTheme.popup:IsReady() == false)
    local missing = Make({ theme = false })
    check("16e. sin Theme (nil) Init falla y no crea ventana", not pcall(missing.popup.Init, missing.popup) and #missing.frames == 0)
    local noFactory = Make({ noCreateFrame = true })
    check("16f. sin CreateFrame Init falla con un error descriptivo",
        (function() local ok, err = pcall(noFactory.popup.Init, noFactory.popup); return ok == false and tostring(err):find("CreateFrame", 1, true) ~= nil end)())
    local noParent = Make({ uiParent = false })
    check("16g. sin UIParent Init falla", not pcall(noParent.popup.Init, noParent.popup) and #noParent.frames == 0)
    local noSpecial = Make({ special = false })
    check("16h. sin UISpecialFrames Init falla (Escape no podría cerrarla) y no crea ventana",
        not pcall(noSpecial.popup.Init, noSpecial.popup) and #noSpecial.frames == 0)

    -- un método de interfaz que falla a mitad de construcción
    local halfBuilt = Make({ createFrame = function(real, kind, name, parent, template)
        local f = real(kind, name, parent, template)
        if kind == "Frame" then
            f.CreateFontString = function() error("sin fuentes") end
        end
        return f
    end })
    local okHalf, errHalf = pcall(halfBuilt.popup.Init, halfBuilt.popup)
    check("17. si la construcción falla a mitad (CreateFontString), Init falla, no se registra en Escape y el Popup no queda a medias",
        okHalf == false and halfBuilt.popup:IsReady() == false and #halfBuilt.special == 0 and select(2, halfBuilt.popup:Show(A)) == "not_ready")
    local badBackdrop = Make({ createFrame = function(real, kind, name, parent, template)
        local f = real(kind, name, parent, template)
        if kind == "Frame" then f.SetBackdrop = function() error("sin backdrop") end end
        return f
    end })
    check("17b. si Theme no puede aplicar el backdrop (ui_error), Init falla con el motivo",
        (function() local ok, err = pcall(badBackdrop.popup.Init, badBackdrop.popup); return ok == false and tostring(err):find("ApplyBackdrop", 1, true) ~= nil end)())

    -- ---- Limpieza del frame parcial ----
    -- En el cliente real un frame recién creado es VISIBLE (el mock los crea ocultos y enmascararía el defecto), así que
    -- estas fábricas lo crean visible. `setup(frame, log)` sabotea el frame; `log` registra el orden de las llamadas.
    local function Visible(setup)
        local state = { log = {} }
        state.ctx = Make({ createFrame = function(real, kind, name, parent, template)
            local f = real(kind, name, parent, template)
            if kind == "Frame" then
                f.shown = true
                state.frame = f
                local realHide, realSetSize = f.Hide, f.SetSize
                f.Hide = function(self, ...) state.log[#state.log + 1] = "Hide"; return realHide(self, ...) end
                f.SetSize = function(self, ...) state.log[#state.log + 1] = "SetSize"; return realSetSize(self, ...) end
                if setup then setup(f, state) end
            end
            return f
        end })
        return state
    end
    local function Run(state)
        local ok, err = pcall(state.ctx.popup.Init, state.ctx.popup)
        return ok, tostring(err)
    end
    local function Clean(state)
        local f = state.frame
        return f ~= nil and f:IsShown() == false and state.ctx.popup:IsReady() == false
            and countIn(state.ctx.special, FRAME_NAME) == 0 and #state.ctx.special == 0
    end

    local fontFail = Visible(function(f) f.CreateFontString = function() error("sin fuentes") end end)
    local okF, errF = Run(fontFail)
    check("17c. CreateFontString falla con el frame visible: Init falla, el frame parcial queda OCULTO, sin Escape y no listo",
        okF == false and errF:find("sin fuentes", 1, true) ~= nil and Clean(fontFail))

    local backdropFail = Visible(function(f) f.SetBackdrop = function() error("sin backdrop") end end)
    local okB, errB = Run(backdropFail)
    check("17d. el backdrop falla con el frame visible: el frame parcial queda oculto, sin Escape y no listo",
        okB == false and errB:find("ApplyBackdrop", 1, true) ~= nil and Clean(backdropFail))

    local pointFail = Visible(function(f) f.SetPoint = function() error("sin anclaje") end end)
    local okP, errP = Run(pointFail)
    check("17e. otra operación de configuración falla (SetPoint): el frame parcial queda oculto, sin Escape y no listo",
        okP == false and errP:find("sin anclaje", 1, true) ~= nil and Clean(pointFail))

    -- el frame se oculta INMEDIATAMENTE tras crearlo, antes de configurar nada: no depende de la limpieza posterior
    local order = Visible(function(f) f.SetPoint = function() error("sin anclaje") end end)
    Run(order)
    check("17f. el frame se oculta lo primero tras crearlo, antes de SetSize y del resto de configuración",
        order.log[1] == "Hide" and order.log[2] == "SetSize")
    local seenShown
    local atFailure = Visible(function(f) f.SetPoint = function(self) seenShown = self.shown; error("sin anclaje") end end)
    Run(atFailure)
    check("17g. en el momento exacto del fallo de configuración el frame ya estaba oculto (no solo después de limpiar)", seenShown == false)

    -- un fallo posterior a haber puesto los scripts (el registro de Escape): la limpieza los quita y oculta el frame
    local lateFail = { log = {} }
    local poisoned = setmetatable({}, { __index = function() error("sin registro de Escape") end })
    local late = Make({ special = poisoned, createFrame = function(real, kind, name, parent, template)
        local f = real(kind, name, parent, template)
        if kind == "Frame" then f.shown = true; lateFail.frame = f end
        return f
    end })
    lateFail.ctx = late
    local okL, errL = Run(lateFail)
    local scripts = lateFail.frame and lateFail.frame.__scripts or {}
    check("17h. fallo al final (registro de Escape): Init falla con ese motivo, el frame parcial queda oculto y SIN scripts",
        okL == false and errL:find("sin registro de Escape", 1, true) ~= nil and lateFail.frame:IsShown() == false
            and scripts.OnHide == nil and scripts.OnDragStart == nil and scripts.OnDragStop == nil and late.popup:IsReady() == false)

    -- un error en la propia limpieza no sustituye ni esconde el error original
    local hides = 0
    local dirty = Visible(function(f)
        f.SetPoint = function() error("fallo original de configuración") end
        local first = f.Hide
        f.Hide = function(self, ...)
            hides = hides + 1
            if hides >= 2 then error("Hide roto en la limpieza") end
            return first(self, ...)
        end
        f.SetScript = function() error("SetScript roto en la limpieza") end
    end)
    local okD, errD = Run(dirty)
    check("17i. si la limpieza también falla, el error original sigue siendo el principal y el de la limpieza se añade como nota",
        okD == false and errD:find("fallo original de configuración", 1, true) ~= nil
            and errD:find("fallo original de configuración", 1, true) < (errD:find("limpieza", 1, true) or 0)
            and errD:find("Hide roto en la limpieza", 1, true) ~= nil and errD:find("SetScript roto en la limpieza", 1, true) ~= nil
            and dirty.ctx.popup:IsReady() == false and #dirty.ctx.special == 0)
    local okD2, errD2 = Run(dirty)
    check("17j. tras una limpieza fallida el fallo sigue siendo definitivo y no se crea otro frame",
        okD2 == false and errD2 == errD and dirty.ctx.factoryCalls == 1 and #dirty.ctx.frames == 1)

    -- repetir Init tras un fallo no crea más frames y nada lanza error
    local again = Visible(function(f) f.SetPoint = function() error("sin anclaje") end end)
    local _, first = Run(again); local _, second = Run(again); local _, third = Run(again)
    check("17k. repetir Init tras un fallo da el mismo error y no crea más frames que el parcial (1 ventana; sin Escape)",
        first == second and second == third and again.ctx.factoryCalls == 1 and #again.ctx.frames == 1 and Clean(again))
    check("17l. tras el fallo el Popup es inerte: Show/Enqueue/Close/CloseAll no lanzan error ni muestran el frame parcial",
        select(2, again.ctx.popup:Show(A)) == "not_ready" and select(2, again.ctx.popup:Enqueue(A)) == "not_ready"
            and again.ctx.popup:Close() == false and (pcall(again.ctx.popup.CloseAll, again.ctx.popup))
            and again.ctx.popup:GetQueueSize() == 0 and again.ctx.popup:IsVisible() == false and again.frame:IsShown() == false)

    -- el camino correcto no cambia: una ventana, oculta, registrada una vez, con la limpieza sin tocar nada
    local good = Visible()
    local okG = Run(good)
    check("17m. Init correcto (aunque el frame nazca visible): una sola ventana, oculta, lista y registrada en Escape una vez",
        okG == true and good.ctx.popup:IsReady() and good.frame:IsShown() == false and #good.ctx.frames == 2
            and countIn(good.ctx.special, FRAME_NAME) == 1 and good.frame.__scripts.OnHide ~= nil and good.log[1] == "Hide")
    check("17n. tras un Init correcto el Popup funciona con normalidad", good.ctx.popup:Show(A) == true and good.ctx.popup:IsVisible()
        and good.ctx.popup:GetContent().title == A.title)
end

-- ===================== Fallos de la interfaz en uso =====================
-- (el fallo de cada caso ocurre a mitad de la actualización, cuando el título ya ha cambiado)
local function Ready(over)
    local ctx = Make(over)
    ctx.popup:Init()
    ctx.window = ctx.frames[1]
    return ctx
end
do
    local ctx = Ready()
    ctx.popup:Show(A)
    ctx.window.children[1].SetText = function() error("SetText roto") end
    ReportedErrors = {}
    local okCall, r1, r2 = pcall(ctx.popup.Show, ctx.popup, B)
    check("18. si la interfaz falla al actualizar una ventana abierta: false, 'ui_error', sin propagar, y se comunica por el mecanismo de errores",
        okCall and r1 == false and r2 == "ui_error" and (function() for _, m in ipairs(ReportedErrors) do if m:find("SetText roto", 1, true) then return true end end end)())
    check("18b. y la ventana sigue abierta con el contenido ANTERIOR (no a medias): GetContent es A", ctx.popup:IsVisible() and deepEqual(ctx.popup:GetContent(), A))
end
do
    local ctx = Ready()
    ctx.popup:Show(A)
    local realBodySetText = ctx.window.children[3].SetText
    ctx.window.children[3].SetText = function(self, text)
        if text == B.body then error("SetText del cuerpo roto") end
        return realBodySetText(self, text)
    end
    local okMid, midR1, midR2 = pcall(ctx.popup.Show, ctx.popup, B)
    check("18d. si el fallo ocurre a mitad de la actualización (el título ya cambió y el cuerpo falla), se RESTAURA el contenido anterior en la ventana real: ni título nuevo con cuerpo viejo ni al revés",
        okMid and midR1 == false and midR2 == "ui_error" and ctx.window.children[1].text == A.title
            and ctx.window.children[3].text == A.body and deepEqual(ctx.popup:GetContent(), A) and ctx.popup:IsVisible())
end
do
    local ctx = Ready()
    ctx.window.children[3].SetText = function() error("SetText cuerpo roto") end
    local okCall, r1, r2 = pcall(ctx.popup.Show, ctx.popup, A)
    check("18c. con la ventana cerrada, un fallo al rellenarla deja la ventana cerrada y sin contenido",
        okCall and r1 == false and r2 == "ui_error" and ctx.popup:IsVisible() == false and ctx.popup:GetContent() == nil)
end
do
    local ctx = Ready()
    ctx.window.Show = function() error("Show roto") end
    local okCall, r1, r2 = pcall(ctx.popup.Show, ctx.popup, A)
    check("19. si mostrar la ventana falla: false, 'ui_error', no queda contenido ni se afirma que está visible",
        okCall and r1 == false and r2 == "ui_error" and ctx.popup:IsVisible() == false and ctx.popup:GetContent() == nil)
    local okQ, q1, q2 = pcall(ctx.popup.Enqueue, ctx.popup, A)
    check("19b. Enqueue con el mismo fallo devuelve el motivo y NO deja la entrada perdida en una cola fantasma",
        okQ and q1 == false and q2 == "ui_error" and ctx.popup:GetQueueSize() == 0)
end
do
    local ctx = Ready()
    ctx.window.IsShown = function() return false end -- el frame dice que no está visible aunque se haya pedido
    local r1, r2 = ctx.popup:Show(A)
    check("19c. si tras Show el frame no está realmente visible, no se afirma éxito", r1 == false and r2 == "ui_error" and ctx.popup:GetContent() == nil)
end
do
    local ctx = Ready()
    ctx.popup:Show(A)
    ctx.window.Hide = function() error("Hide roto") end
    ReportedErrors = {}
    local okCall, r1, r2 = pcall(ctx.popup.Close, ctx.popup)
    check("20. si cerrar falla: false, 'ui_error', sin propagar y comunicado; el estado sigue siendo el del frame real",
        okCall and r1 == false and r2 == "ui_error" and ctx.popup:IsVisible() == true and #ReportedErrors > 0)
end
do
    local ctx = Ready()
    ctx.window.SetPoint = function() error("SetPoint roto") end
    local before = ctx.popup:GetPosition()
    local okPos, why = ctx.popup:SetPosition("CENTER", "CENTER", 5, 5)
    check("21. si mover la ventana falla: false, 'ui_error' y se intenta restaurar la posición anterior sin lanzar error",
        okPos == false and why == "ui_error" and before ~= nil)
    ctx.window.IsShown = function() error("IsShown roto") end
    check("21b. si consultar la visibilidad falla, IsVisible responde false en vez de lanzar error",
        pcall(ctx.popup.IsVisible, ctx.popup) and ctx.popup:IsVisible() == false)
end
do
    -- un contenido de la cola que no se puede mostrar se descarta y no atasca el resto
    local ctx = Ready()
    ctx.popup:Show(A)
    ctx.popup:Enqueue(B); ctx.popup:Enqueue(C); ctx.popup:Enqueue(D)
    local realSetText = ctx.window.children[1].SetText
    ctx.window.children[1].SetText = function(self, text)
        if text == B.title then error("B no se puede mostrar") end
        return realSetText(self, text)
    end
    ReportedErrors = {}
    ctx.popup:Close()
    check("22. si un pendiente de la cola no se puede mostrar se descarta (comunicado) y se pasa al siguiente: la cola no se atasca",
        deepEqual(ctx.popup:GetContent(), C) and ctx.popup:GetQueueSize() == 1 and #ReportedErrors > 0)
end

-- ===================== Aislamiento: nada de State, Discovery ni ChronicleCharDB =====================
local function codeOf(name)
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
check("23. Popup no referencia ChronicleCharDB, State, Discovery, Registry, Localization, Resolver, Proximity ni ZoneDiscovery en su código",
    (function()
        for _, line in ipairs(codeOf("UI/Popup.lua")) do
            for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", "Chronicle.Discovery", "Chronicle.Registry", "Chronicle.Localization",
                "Chronicle.Resolver", "Chronicle.Proximity", "Chronicle.ZoneDiscovery", "Chronicle.MapPosition" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("23b. Popup solo depende de Theme y de Events (para el aviso de movimiento), y de los globales de interfaz inyectados",
    (function()
        local deps = {}
        for _, line in ipairs(codeOf("UI/Popup.lua")) do
            for name in line:gmatch("Chronicle%.(%w+)") do deps[name] = true end
        end
        deps.Popup = nil; deps.Utils = nil
        local list = {}
        for name in pairs(deps) do list[#list + 1] = name end
        table.sort(list)
        return table.concat(list, ",") == "Events,Theme"
    end)(), "")
check("23c. usar el Popup no escribe nada en ChronicleCharDB: queda exactamente el estado inicial del Core",
    deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} } }))
check("23d. mostrar, poner en cola y cerrar no descubre nada ni emite eventos de Discovery",
    (function()
        local discovered = 0
        Chronicle.Events:Register("Chronicle.Discovery.Discovered", function() discovered = discovered + 1 end)
        Popup:Show(A); Popup:Enqueue(B); Popup:Close(); Popup:CloseAll()
        return discovered == 0 and Chronicle.Discovery:Count() == 0
    end)())
check("24. Popup no usa temporizadores, animaciones, sonidos ni el evento OnUpdate",
    (function()
        for _, line in ipairs(codeOf("UI/Popup.lua")) do
            for _, word in ipairs({ "C_Timer", "OnUpdate", "UIFrameFade", "PlaySound", "CreateAnimationGroup", "NewTicker", ".After(", "GetTime" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("24b. Popup no escucha eventos del cliente (RegisterEvent) ni reacciona a zonas, NPC o descubrimientos",
    (function()
        for _, line in ipairs(codeOf("UI/Popup.lua")) do
            for _, word in ipairs({ "RegisterEvent", "ZONE_CHANGED", "PLAYER_", "QUEST_", "GetRealZoneText", "UnitGUID", "Chronicle.Events:Register" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("24c. el único frame con nombre es el del Popup y el único manejador de OnHide/OnDrag* es el suyo (sin ventanas ni scripts duplicados)",
    named(FRAME_NAME) == 1 and (function()
        local w2 = windowOf()
        local count = 0
        for key in pairs(w2.__scripts) do count = count + 1 end
        return count == 3 and w2.__scripts.OnHide and w2.__scripts.OnDragStart and w2.__scripts.OnDragStop and w2.__scripts.OnUpdate == nil
    end)())

-- ===================== Integración con el arranque =====================
announced = Boot(function() Chronicle.Popup.Init = function() error("popup roto") end end)
check("25. un fallo de Popup.Init se diagnostica en Init.failed y por el mecanismo de errores",
    Chronicle.Init.failed.Popup ~= nil and Chronicle.Init.failed.Popup:find("popup roto", 1, true) ~= nil
        and (function() for _, m in ipairs(ReportedErrors) do if m:find("Popup", 1, true) then return true end end end)())
check("25b. Popup es OPCIONAL: su fallo no impide anunciar el arranque ni afecta a Discovery y los servicios del Core",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Discovery:IsReady() and Chronicle.ZoneDiscovery:IsReady()
        and Chronicle.Resolver:IsReady() and Chronicle.Proximity:IsReady() and Chronicle.Popup:IsReady() == false)
check("25c. y quien lo use puede comprobarlo: con el Popup fallido Show devuelve 'not_ready'", select(2, Chronicle.Popup:Show(A)) == "not_ready")
announced = Boot(function() Chronicle.Popup = nil end)
check("25d. Popup ausente: se diagnostica como no cargado y el arranque se anuncia igual",
    Chronicle.Init.failed.Popup:find("no está cargado", 1, true) ~= nil and Chronicle.Init.ready == true and announced == 1)
announced = Boot(function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
check("25e. un fallo de un módulo REQUERIDO sigue impidiendo anunciar el arranque, y Popup (independiente de Discovery) se inicializa igual",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Discovery ~= nil and Chronicle.Popup:IsReady() == true
        and Chronicle.Init.skipped.Popup == nil)
announced = Boot(function() Chronicle.State.Init = function() error("estado roto") end end)
check("25f. con State fallido el Popup funciona igual (no depende de State)", Chronicle.Init.ready == false and Chronicle.Popup:IsReady() == true
    and Chronicle.Popup:Show(A) == true)
Boot()
check("25g. arranque normal restablecido y sin frames sobrantes del Popup", Chronicle.Popup:IsReady() and named(FRAME_NAME) == 1)

-- ===================== API pública =====================
local keys = {}
for key in pairs(Chronicle.Popup) do keys[#keys + 1] = key end
table.sort(keys)
check("26. la API pública del Popup es la documentada (y New en la instancia por defecto)",
    table.concat(keys, ",") == "Close,CloseAll,EVENT_MOVED,Enqueue,GetContent,GetPosition,GetQueueSize,GetSize,Init,IsReady,IsVisible,New,ResetPosition,SetPosition,Show",
    table.concat(keys, ","))
check("26b. Popup.New exige una tabla de dependencias", not pcall(Chronicle.Popup.New, nil) and not pcall(Chronicle.Popup.New, "x"))
check("26c. la ventana del Popup se crea una sola vez en toda la sesión de pruebas de arranque (sin acumulación)", named(FRAME_NAME) == 1)
CreateFrame = realCreateFrame
