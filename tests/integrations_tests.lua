-- Escenarios de prueba de la Fase 12: preferencias (Options), Trivia, FreshCharacterCheck, botón del minimapa, panel de opciones y
-- comandos. Se prueban con el mock ESTRICTO de las APIs del cliente (tests/mock.lua: Minimap, GameTooltip, GetCursorPosition, GetTime,
-- C_Timer, UnitLevel, RequestTimePlayed, InterfaceOptions_*). El mock solo guarda lo que se le pide: NO demuestra que esas APIs existan
-- ni se comporten así en el cliente real de Classic Era (ver docs/fase12_integraciones.md).

local function Boot(preset, prepare)
    LoadAddon()
    ChronicleCharDB = preset
    if prepare then prepare() end
    FireEvent("ADDON_LOADED", "Chronicle")
end
local function chat() return table.concat(ChatLog, "\n") end
local function countReports(fragment, from)
    local n = 0
    for i = (from or 0) + 1, #ReportedErrors do
        if ReportedErrors[i]:find(fragment, 1, true) then n = n + 1 end
    end
    return n
end
local function slash(text)
    ChatLog = {}
    SlashCmdList["CHRONICLE"](text)
    return chat()
end

local TEMPLATE = { schemaVersion = 1, discovery = { entries = {} } }
local function noop() end
local DUMMY_BUTTON = { children = { {}, {} }, points = { {} }, __scripts = setmetatable({}, { __index = function() return noop end }) }

-- ===================== Arranque =====================
Boot(nil)
check("0. arranque normal con los módulos de la Fase 12: todo listo, sin fallos ni omitidos y se anuncia",
    Chronicle.Init.ready == true and next(Chronicle.Init.failed) == nil and next(Chronicle.Init.skipped) == nil
        and Chronicle.Options:IsReady() and Chronicle.Trivia:IsReady() and Chronicle.FreshCharacterCheck:IsReady()
        and Chronicle.OptionsPanel:IsReady() and Chronicle.MinimapButton:IsReady() and Chronicle.Commands:IsReady())
check("0b. el arranque no escribe nada nuevo en la SavedVariable: sigue siendo el estado inicial del Core",
    deepEqual(ChronicleCharDB, TEMPLATE))
check("0c. no hay avisos de error en un arranque normal", #ReportedErrors == 0)

-- ===================== Options =====================
do
    local o = Chronicle.Options
    check("1. valores predeterminados: curiosidades activadas y ángulo del minimapa 215 (el del original)",
        o:Get("triviaEnabled") == true and o:Get("minimapAngle") == 215 and o:GetDefault("triviaEnabled") == true and o:GetDefault("minimapAngle") == 215)
    check("1b. solo existen las preferencias con consumidor (no hay «avisos automáticos» ni tema pergamino)",
        table.concat(o:GetNames(), ",") == "minimapAngle,triviaEnabled" and o:Get("enabled") == nil and o:Get("loreParchmentTheme") == nil)
    check("1c. Set guarda a través de State: la preferencia queda en ('options', nombre) y Get la devuelve",
        o:Set("triviaEnabled", false) == true and o:Get("triviaEnabled") == false and Chronicle.State:Get("options", "triviaEnabled") == false
            and ChronicleCharDB.schemaVersion == 1)
    check("1d. el ángulo se normaliza a [0, 360): 725 -> 5, -10 -> 350",
        o:Set("minimapAngle", 725) and o:Get("minimapAngle") == 5 and Chronicle.State:Get("options", "minimapAngle") == 5
            and o:Set("minimapAngle", -10) and o:Get("minimapAngle") == 350 and Chronicle.State:Get("options", "minimapAngle") == 350)
    local bad = {}
    for _, case in ipairs({
        { "triviaEnabled", "yes" }, { "triviaEnabled", 1 }, { "triviaEnabled", nil }, { "minimapAngle", "90" }, { "minimapAngle", 0 / 0 },
        { "minimapAngle", math.huge }, { "minimapAngle", -math.huge }, { "minimapAngle", true }, { "minimapAngle", {} },
    }) do
        local called, ok, reason = pcall(o.Set, o, case[1], case[2])
        if not called or ok ~= false or reason ~= "invalid_value" then bad[#bad + 1] = tostring(case[1]) .. "=" .. tostring(case[2]) end
    end
    check("1e. valores no válidos se rechazan con invalid_value y no se coaccionan " .. table.concat(bad, ", "), #bad == 0)
    local ok, reason = o:Set("noExiste", true)
    check("1f. una preferencia desconocida se rechaza con unknown_option", ok == false and reason == "unknown_option" and o:Get("noExiste") == nil)
    check("1g. un rechazo no cambia lo guardado", o:Get("minimapAngle") == 350 and o:Get("triviaEnabled") == false)
end

do
    -- valores guardados corruptos o editados a mano
    Boot({ schemaVersion = 1, discovery = { entries = {} }, options = { triviaEnabled = "sí", minimapAngle = 0 / 0 } })
    check("2. un valor guardado que no supera la validación se ignora y se usa el predeterminado (sin repararlo ni borrarlo)",
        Chronicle.Options:Get("triviaEnabled") == true and Chronicle.Options:Get("minimapAngle") == 215
            and ChronicleCharDB.options.triviaEnabled == "sí")
    Boot({ schemaVersion = 1, discovery = { entries = {} }, options = { minimapAngle = 450 } })
    check("2b. un ángulo guardado fuera de rango se normaliza al leerlo", Chronicle.Options:Get("minimapAngle") == 90)
    Boot({ schemaVersion = 1, discovery = { entries = {} }, options = "basura" })
    check("2c. un contenedor `options` que no es una tabla equivale a no tener nada: predeterminados y sin errores",
        Chronicle.Options:Get("minimapAngle") == 215 and Chronicle.Options:Get("triviaEnabled") == true and #ReportedErrors == 0)
    Boot({ schemaVersion = 99, discovery = { entries = {} } })
    local ok, reason = Chronicle.Options:Set("triviaEnabled", false)
    check("2d. con State en solo lectura (guardado de una versión más nueva) Set devuelve read_only y no escribe",
        ok == false and reason == "read_only" and ChronicleCharDB.options == nil)
    local o = Chronicle.Options.New({ state = function() return nil end })
    local ok2, reason2 = o:Set("triviaEnabled", true)
    check("2e. sin State: Get devuelve el predeterminado, Set devuelve not_ready y Init lanza un error descriptivo",
        o:Get("triviaEnabled") == true and ok2 == false and reason2 == "not_ready" and not pcall(o.Init, o))
    local failing = Chronicle.Options.New({ state = { Get = function() return nil end, Set = function() return false end, IsReady = function() return true end,
        IsReadOnly = function() return false end } })
    failing:Init()
    local ok3, reason3 = failing:Set("minimapAngle", 10)
    check("2f. si State no llega a guardar, Set devuelve persist_failed (no afirma un éxito que no se guardó)", ok3 == false and reason3 == "persist_failed")
    local lying = Chronicle.Options.New({ state = { Get = function() return nil end, Set = function() return true end, IsReady = function() return true end,
        IsReadOnly = function() return false end } })
    lying:Init()
    local ok4, reason4 = lying:Set("triviaEnabled", false)
    check("2f2. si State dice que guardó pero lo leído no coincide, Set también devuelve persist_failed (se comprueba lo guardado)",
        ok4 == false and reason4 == "persist_failed")
    local before = Chronicle.Utils.DeepCopy(ChronicleCharDB)
    Chronicle.Options:Init(); Chronicle.Options:Init()
    check("2g. Init es idempotente y no escribe", deepEqual(before, ChronicleCharDB))
end

-- ===================== Trivia: contenido migrado =====================
do
    Boot(nil)
    local entries = Chronicle.TriviaEntries
    check("3. los 8 textos de Trivia se migraron literalmente del original, en su orden y sin tocarlos",
        #entries == 8 and #LegacyTrivia == 8 and (function()
            for i = 1, 8 do if entries[i].text ~= LegacyTrivia[i] then return false, i end end
            return true
        end)())
    check("3b. no hay más entradas que las migradas ni campos de pregunta o respuesta (el original no los tenía)",
        (function()
            for _, entry in ipairs(entries) do
                for key in pairs(entry) do if key ~= "text" then return false end end
            end
            return true
        end)())
    check("3c. el contenido migrado es válido para Trivia", Chronicle.Trivia:Validate().valid == 8 and Chronicle.Trivia:Validate().invalid == 0)
end

-- ===================== Trivia: servicio con dependencias controladas =====================
local function MakeTrivia(over)
    over = over or {}
    local ctx = { shown = {}, frames = 0, now = 1000, enabled = over.enabled ~= false, picks = over.picks or {} }
    ctx.options = over.options or { Get = function(_, name) return name == "triviaEnabled" and ctx.enabled or nil end }
    ctx.popup = over.popup == false and nil or over.popup or { Enqueue = function(_, content)
        if ctx.popupResult == false then return false, "queue_full" end
        ctx.shown[#ctx.shown + 1] = content
        return true, "shown"
    end }
    ctx.timers = {}
    ctx.taxi = false
    ctx.trivia = Chronicle.Trivia.New({
        options = ctx.options, popup = ctx.popup,
        entries = over.entries or { { text = "uno" }, { text = "dos" }, { text = "tres" } },
        guard = over.guard,
        createFrame = function(...) ctx.frames = ctx.frames + 1; return CreateFrame(...) end,
        now = function() return ctx.now end,
        random = function(a, b) local v = table.remove(ctx.picks, 1); return v or a end,
        after = (not over.noTimer) and function(seconds, fn) ctx.timers[#ctx.timers + 1] = { seconds = seconds, fn = fn } end or nil,
        onTaxi = function() return ctx.taxi end,
    })
    return ctx
end

do
    Boot(nil)
    local t = MakeTrivia()
    local ok0, why0 = t.trivia:Show(true)
    check("4. antes de Init, Show devuelve false, not_ready y no muestra nada", ok0 == false and why0 == "not_ready" and #t.shown == 0)
    t.trivia:Init(); t.trivia:Init()
    check("4b. Init es idempotente: un único frame", t.frames == 1 and t.trivia:IsReady())
    check("4c. con contenido válido se muestra en el Popup con el título «¿Sabías que...?» y el texto tal cual",
        t.trivia:Show(true) == true and t.shown[1].title == "¿Sabías que...?" and t.shown[1].body == "uno")
    check("4d. el enfriamiento (600 s) frena el aviso automático pero no el pedido a mano",
        (function()
            local ok, why = t.trivia:Show(false)
            local manual = t.trivia:Show(true)
            return ok == false and why == "cooldown" and manual == true
        end)())
    t.now = 1700
    check("4e. pasado el enfriamiento vuelve a mostrarse", t.trivia:Show(false) == true)
    t.enabled = false
    local okD, whyD = t.trivia:Show(true)
    check("4f. con la preferencia desactivada no se muestra (disabled)", okD == false and whyD == "disabled")
    t.enabled = true
    check("4g. los eventos del cliente funcionan: PLAYER_DEAD muestra una curiosidad (si no hay enfriamiento)",
        (function() t.now = 5000; local n = #t.shown; FireEvent("PLAYER_DEAD"); return #t.shown == n + 1 end)())
    check("4h. tras Init repetido un evento no duplica el aviso (el manejador se registró una sola vez)",
        (function() t.now = 9000; local n = #t.shown; FireEvent("PLAYER_DEAD"); return #t.shown == n + 1 end)())
end

do
    local t = MakeTrivia({ picks = { 1 } })
    t.trivia:Init()
    t.trivia:Show(true)
    t.trivia:Show(true)
    t.trivia:Show(true)
    check("5. no repite la misma entrada dos veces seguidas cuando hay otras disponibles", t.shown[1] ~= nil and t.shown[2] ~= nil and t.shown[3] ~= nil and t.shown[1].body ~= t.shown[2].body and t.shown[2].body ~= t.shown[3].body)
    local single = MakeTrivia({ entries = { { text = "solo" } } })
    single.trivia:Init()
    single.trivia:Show(true); single.trivia:Show(true)
    check("5b. con una sola entrada disponible sí puede repetirse", #single.shown == 2 and single.shown[2].body == "solo")
end

do
    local empty = MakeTrivia({ entries = {} })
    empty.trivia:Init()
    local ok, why = empty.trivia:Show(true)
    check("6. sin contenido: no se muestra, devuelve no_content y no lanza error", ok == false and why == "no_content" and #empty.shown == 0)
    local nilEntries = MakeTrivia({ entries = function() return nil end })
    nilEntries.trivia:Init()
    check("6b. si el contenido no es una tabla tampoco falla", select(2, nilEntries.trivia:Show(true)) == "no_content")
    local invalid = MakeTrivia({ entries = { {}, { text = "" }, { text = "   " }, { text = 5 }, "cadena", 42, { text = "bien" }, { texto = "mal" } } })
    invalid.trivia:Init()
    local report = invalid.trivia:Validate()
    check("6c. entradas inválidas (sin texto, vacío, solo espacios, no cadena, no tabla) se ignoran y se cuentan: 1 válida y 7 inválidas",
        report.valid == 1 and report.invalid == 7 and #report.errors == 7)
    invalid.trivia:Show(true); invalid.trivia:Show(true)
    check("6d. solo se muestran las válidas", #invalid.shown == 2 and invalid.shown[1].body == "bien" and invalid.shown[2].body == "bien")
    local onlyBad = MakeTrivia({ entries = { {}, { text = "" } } })
    onlyBad.trivia:Init()
    check("6e. si todas son inválidas equivale a no tener contenido", select(2, onlyBad.trivia:Show(true)) == "no_content")
end

do
    local guarded = MakeTrivia({ guard = function(text) return text == "dos" end })
    guarded.trivia:Init()
    guarded.trivia:Show(true); guarded.trivia:Show(true)
    check("7. el guardián de Discovery filtra: solo sale la curiosidad permitida", #guarded.shown == 2 and guarded.shown[1].body == "dos" and guarded.shown[2].body == "dos")
    local blocked = MakeTrivia({ guard = function() return false end })
    blocked.trivia:Init()
    local ok, why = blocked.trivia:Show(true)
    check("7b. si el guardián bloquea todas, devuelve guarded y no muestra nada", ok == false and why == "guarded" and #blocked.shown == 0)
    local throwing = MakeTrivia({ guard = function() error("guardián roto") end })
    throwing.trivia:Init()
    check("7c. un guardián que falla cuenta como bloqueo (no se muestra nada y no se lanza error)",
        select(2, throwing.trivia:Show(true)) == "guarded" and #throwing.shown == 0)
    local nonTrue = MakeTrivia({ guard = function() return "sí" end })
    nonTrue.trivia:Init()
    check("7d. el guardián debe devolver true exacto", select(2, nonTrue.trivia:Show(true)) == "guarded")
    local noPopup = MakeTrivia({ popup = false })
    noPopup.popup = nil
    local np = Chronicle.Trivia.New({ options = noPopup.options, popup = nil, entries = { { text = "x" } }, createFrame = CreateFrame, now = function() return 1 end })
    np:Init()
    check("7e. sin Popup devuelve no_popup", select(2, np:Show(true)) == "no_popup")
    local rejecting = MakeTrivia()
    rejecting.popupResult = false
    rejecting.trivia:Init()
    check("7f. si el Popup rechaza el aviso devuelve ui_error y no se cuenta como mostrado (no activa el enfriamiento)",
        select(2, rejecting.trivia:Show(false)) == "ui_error" and (function() rejecting.popupResult = true; return rejecting.trivia:Show(false) == true end)())
end

do
    local t = MakeTrivia()
    t.trivia:Init()
    FireEvent("PLAYER_CONTROL_LOST")
    check("8. PLAYER_CONTROL_LOST deja UN temporizador de un disparo (0,1 s) y no muestra nada todavía", #t.timers == 1 and t.timers[1].seconds == 0.1 and #t.shown == 0)
    t.timers[1].fn()
    check("8b. si al vencer el temporizador el jugador no va en vuelo, no se muestra", #t.shown == 0)
    t.taxi = true
    FireEvent("PLAYER_CONTROL_LOST")
    t.timers[2].fn()
    check("8c. si va en vuelo, se muestra", #t.shown == 1)
    local noTimer = MakeTrivia({ noTimer = true })
    noTimer.trivia:Init()
    FireEvent("PLAYER_CONTROL_LOST")
    check("8d. sin C_Timer el disparador de vuelo no hace nada (y no falla)", #noTimer.shown == 0 and #noTimer.timers == 0)
    local notReady = Chronicle.Trivia.New({ options = nil, createFrame = CreateFrame })
    check("8e. Init sin Options lanza un error descriptivo y sin CreateFrame también",
        not pcall(notReady.Init, notReady) and not pcall(Chronicle.Trivia.New({ options = { Get = function() end } }).Init))
end

-- ===================== Trivia: con los servicios reales (Discovery, Resolver, Popup) =====================
do
    Boot(nil)
    local trivia = Chronicle.Trivia
    local ok, why = trivia:Show(true)
    check("9. con nada descubierto ninguna curiosidad se puede mostrar: todas nombran lugares o personajes (guarded) y no se muestra nada",
        ok == false and why == "guarded" and not Chronicle.Popup:IsVisible())
    local count = Chronicle.Discovery:Count()
    local discovers = 0
    local realDiscover = Chronicle.Discovery.Discover
    Chronicle.Discovery.Discover = function(self, ...) discovers = discovers + 1; return realDiscover(self, ...) end
    Chronicle.Discovery:Discover("subzone:coldridge_valley")
    discovers = 0
    Chronicle.Popup:CloseAll() -- el descubrimiento de arriba ya mostró su propio aviso; la curiosidad se comprueba sola
    local ok2 = trivia:Show(true)
    check("9b. al descubrir el único lugar que nombra la primera curiosidad, sale esa y solo esa, con su texto literal",
        ok2 == true and Chronicle.Popup:IsVisible() and Chronicle.Popup:GetContent().body == LegacyTrivia[1])
    check("9c. mostrar curiosidades no descubre nada: Discover no se llamó y Discovery solo tiene lo descubierto a mano",
        discovers == 0 and Chronicle.Discovery:Count() == count + 1)
    Chronicle.Discovery.Discover = realDiscover
    check("9d. las curiosidades que nombran lugares sin descubrir siguen bloqueadas: ninguna otra sale tras varios intentos",
        (function()
            for _ = 1, 10 do
                Chronicle.Popup:CloseAll()
                if not trivia:Show(true) or Chronicle.Popup:GetContent().body ~= LegacyTrivia[1] then return false end
            end
            return true
        end)())
    Chronicle.Options:Set("triviaEnabled", false)
    check("9e. con la preferencia desactivada /chronicle trivia lo dice y no muestra nada",
        (function() Chronicle.Popup:CloseAll(); return select(2, trivia:Show(true)) == "disabled" and not Chronicle.Popup:IsVisible() end)())
end

do
    -- el guardián aislado
    local resolver = { IsReady = function() return true end, Resolve = function(_, text)
        if text == "Aldea" then return "zone:a" end
        if text == "Mixto" then return nil, "ambiguous", { "zone:a", "zone:b" } end
        if text == "Roto" then error("resolver roto") end
        return nil, "not_found"
    end }
    local discovery = { IsReady = function() return true end, IsDiscovered = function(_, id) return id == "zone:a" end }
    local guard = Chronicle.Trivia.NameGuard(resolver, discovery)
    check("9f. guardián: texto sin entidades -> permitido; entidad descubierta -> permitido; ambigua con una bloqueada -> bloqueado",
        guard("nada que ver") == true and guard("Visita la Aldea, amigo.") == true and guard("El Mixto sale") == false)
    check("9g. guardián: un resolver que falla, o no está listo, o un Discovery no listo o ausente bloquea",
        guard("Roto") == false
            and Chronicle.Trivia.NameGuard({ IsReady = function() return false end, Resolve = resolver.Resolve }, discovery)("hola") == false
            and Chronicle.Trivia.NameGuard(resolver, { IsReady = function() return false end, IsDiscovered = function() return true end })("hola") == false
            and Chronicle.Trivia.NameGuard(resolver, nil)("hola") == false)
    check("9h. guardián: reconoce nombres de varias palabras, con signos de puntuación y en medio del texto",
        Chronicle.Trivia.NameGuard({ IsReady = function() return true end, Resolve = function(_, t) if t == "Loch Modan" then return "zone:loch" end return nil, "not_found" end },
            { IsReady = function() return true end, IsDiscovered = function() return false end })("El lago de «Loch Modan», existe.") == false)
end

-- ===================== FreshCharacterCheck =====================
local function QUIET() Chronicle.FreshCharacterCheck.Init = function() end end
local function MakeFresh(over)
    over = over or {}
    local ctx = { frames = 0, requests = 0, level = over.level or 1, emitted = 0, shown = {} }
    ctx.discovery = over.discovery or { IsReady = function() return true end, Count = function() return ctx.count or 3 end }
    ctx.events = { Emit = function(_, name) ctx.emitted = ctx.emitted + 1; ctx.lastEvent = name end }
    ctx.popup = { Enqueue = function(_, content) ctx.shown[#ctx.shown + 1] = content; return true, "shown" end }
    ctx.check = Chronicle.FreshCharacterCheck.New({
        discovery = ctx.discovery, popup = ctx.popup, events = ctx.events,
        createFrame = function(...) ctx.frames = ctx.frames + 1; return CreateFrame(...) end,
        unitLevel = function() return ctx.level end,
        requestTimePlayed = function() ctx.requests = ctx.requests + 1 end,
    })
    return ctx
end

do
    Boot(nil, QUIET)
    local f = MakeFresh()
    check("10. Evaluate: nivel 1, <= 30 min y progreso -> fresh",
        f.check:Evaluate(1, 600) == "fresh" and f.check:Evaluate(1, 1800) == "fresh" and f.check:Evaluate(1, 0) == "fresh")
    check("10b. Evaluate: más de 30 min, o nivel distinto de 1 -> not_fresh",
        f.check:Evaluate(1, 1801) == "not_fresh" and f.check:Evaluate(2, 60) == "not_fresh" and f.check:Evaluate(60, 99999) == "not_fresh")
    f.count = 0
    check("10c. Evaluate: sin progreso guardado -> not_fresh", f.check:Evaluate(1, 60) == "not_fresh")
    local function Ev(...)
        local ok, result = pcall(f.check.Evaluate, f.check, ...)
        return ok and result or "ERROR"
    end
    check("10d. Evaluate: datos que no son números finitos o negativos -> unknown (sin lanzar error)",
        Ev(nil, 60) == "unknown" and Ev(1, nil) == "unknown" and Ev(1, -1) == "unknown"
            and Ev(1, 0 / 0) == "unknown" and Ev("1", 60) == "unknown" and Ev(1, math.huge) == "unknown" and Ev(1, -math.huge) == "unknown"
            and Ev(0 / 0, 60) == "unknown" and Ev(math.huge, 60) == "unknown" and Ev(1, "60") == "unknown")
    f.count = 5
    local notReady = MakeFresh({ discovery = { IsReady = function() return false end, Count = function() return 9 end } })
    local broken = MakeFresh({ discovery = { IsReady = function() error("roto") end, Count = function() return 9 end } })
    local missing = MakeFresh({ discovery = {} })
    check("10e. Evaluate: con Discovery no listo, que falla o ausente -> unknown (nunca se asume progreso)",
        notReady.check:Evaluate(1, 60) == "unknown" and broken.check:Evaluate(1, 60) == "unknown" and missing.check:Evaluate(1, 60) == "unknown")
end

do
    Boot(nil, QUIET)
    local f = MakeFresh()
    f.check:Init(); f.check:Init()
    check("11. Init es idempotente: un único frame y listo", f.frames == 1 and f.check:IsReady())
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("PLAYER_ENTERING_WORLD")
    check("11b. a nivel 1 se pide el tiempo jugado UNA sola vez aunque PLAYER_ENTERING_WORLD salte varias veces en la sesión", f.requests == 1)
    FireEvent("TIME_PLAYED_MSG", 600)
    check("11c. con respuesta fresca se emite el evento una vez, se avisa en el Popup y la comprobación queda completada EN ESTA SESIÓN (solo en memoria)",
        f.emitted == 1 and f.lastEvent == "Chronicle.FreshCharacter.Detected" and #f.shown == 1 and f.check:IsCompleted())
    check("11d. el aviso informa con claridad y NO ofrece reiniciar (Discovery no puede)",
        (f.shown[1] or {}).body ~= nil and f.shown[1].body:find("no puede reiniciar", 1, true) ~= nil)
    FireEvent("TIME_PLAYED_MSG", 600); FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 10)
    check("11e. una respuesta válida no produce una segunda comprobación en la sesión: ni más peticiones, ni eventos, ni avisos",
        f.requests == 1 and f.emitted == 1 and #f.shown == 1)
end

do
    local cases = {
        { "11f. más de 30 min jugados: la comprobación se completa (resultado válido negativo) y no se avisa", 1, 4000, 3 },
        { "11g. sin progreso guardado: la comprobación se completa (resultado válido negativo) y no se avisa", 1, 60, 0 },
    }
    for _, case in ipairs(cases) do
        Boot(nil, QUIET)
        local f = MakeFresh({ level = case[2] })
        f.count = case[4]
        f.check:Init()
        FireEvent("PLAYER_ENTERING_WORLD")
        FireEvent("TIME_PLAYED_MSG", case[3])
        f.count = 5
        FireEvent("TIME_PLAYED_MSG", 60); FireEvent("PLAYER_ENTERING_WORLD")
        check(case[1] .. " (y una respuesta posterior que sí cumpliría no la reabre)",
            f.emitted == 0 and #f.shown == 0 and f.check:IsCompleted() and f.requests == 1)
    end
    Boot(nil, QUIET)
    local f = MakeFresh({ level = 2 })
    f.check:Init()
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 60)
    check("11h. nivel distinto de 1: no se pide el tiempo jugado, y un /played manual posterior no provoca ningún aviso (desviación respecto al original)",
        f.requests == 0 and f.emitted == 0 and #f.shown == 0 and not f.check:IsCompleted())
    Boot(nil, QUIET)
    local g = MakeFresh()
    g.check:Init()
    FireEvent("TIME_PLAYED_MSG", 60)
    check("11i. una respuesta de tiempo jugado sin petición propia se ignora", g.emitted == 0 and not g.check:IsCompleted())
    FireEvent("PLAYER_ENTERING_WORLD")
    local okEvent = pcall(FireEvent, "TIME_PLAYED_MSG", "mucho")
    check("11j. un tiempo que no es un número válido es desconocido: no lanza error, no avisa y NO completa la comprobación", okEvent and g.emitted == 0 and not g.check:IsCompleted())
    FireEvent("TIME_PLAYED_MSG", 60); FireEvent("PLAYER_ENTERING_WORLD")
    check("11j2. y no se reintenta en la misma sesión: la petición es única y la respuesta ya se consumió", g.requests == 1 and g.emitted == 0 and not g.check:IsCompleted())
    Boot(nil, QUIET)
    local h = MakeFresh({ discovery = { IsReady = function() return false end, Count = function() return 9 end } })
    h.check:Init()
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 60)
    check("11k. con Discovery no listo el resultado es DESCONOCIDO: no se avisa, no se trata como una detección negativa válida y NO se completa",
        h.emitted == 0 and #h.shown == 0 and not h.check:IsCompleted() and h.requests == 1)
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 60)
    check("11l. con Discovery que falla ocurre lo mismo y la sesión no se queda marcada como comprobada",
        (function()
            local broken = MakeFresh({ discovery = { IsReady = function() error("roto") end, Count = function() return 9 end } })
            broken.check:Init()
            FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 60)
            return broken.emitted == 0 and not broken.check:IsCompleted()
        end)())
end

do
    -- Regresión: Discovery se exige ANTES de decidir por nivel o tiempo. Cada caso se prueba con Evaluate() y con el flujo integrado (OnEvent).
    local function working(count) return { IsReady = function() return true end, Count = function() return count end } end
    local unavailable = {
        { "Discovery no listo", { IsReady = function() return false end, Count = function() return 5 end } },
        { "IsReady lanza un error", { IsReady = function() error("IsReady roto") end, Count = function() return 5 end } },
        { "Count lanza un error", { IsReady = function() return true end, Count = function() error("Count roto") end } },
        { "Count no devuelve un número", { IsReady = function() return true end, Count = function() return "mucho" end } },
        { "Discovery sin métodos", {} },
        { "Discovery ausente", nil },
    }
    for _, case in ipairs(unavailable) do
        for _, played in ipairs({ 4000, 1800, 60 }) do
            Boot(nil, QUIET)
            local f = MakeFresh({ discovery = case[2] or false })
            if case[2] == nil then f.check = Chronicle.FreshCharacterCheck.New({ discovery = nil, popup = f.popup, events = f.events,
                createFrame = CreateFrame, unitLevel = function() return 1 end, requestTimePlayed = function() f.requests = f.requests + 1 end }) end
            local evaluated = f.check:Evaluate(1, played)
            local evaluatedLevel2 = f.check:Evaluate(2, played)
            f.check:Init()
            FireEvent("PLAYER_ENTERING_WORLD")
            FireEvent("TIME_PLAYED_MSG", played)
            check("14. " .. case[1] .. " + " .. played .. " s: Evaluate es unknown (también con otro nivel) y el flujo NO completa la sesión, no emite el evento y no avisa",
                evaluated == "unknown" and evaluatedLevel2 == "unknown" and f.requests == 1 and f.emitted == 0 and #f.shown == 0 and f.check:IsCompleted() == false)
        end
    end
    -- el resultado desconocido no se reintenta en la sesión, aunque Discovery se recupere después
    Boot(nil, QUIET)
    local flaky = { ready = false }
    local fl = MakeFresh({ discovery = { IsReady = function() return flaky.ready end, Count = function() return 5 end } })
    fl.check:Init()
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 4000)
    flaky.ready = true
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 4000)
    check("14b. un resultado desconocido no se reintenta en la misma sesión aunque Discovery se recupere: una sola petición, sin completar y sin aviso",
        fl.requests == 1 and fl.check:IsCompleted() == false and fl.emitted == 0)

    local operative = {
        { "15. Discovery operativo + más de 1800 s -> not_fresh y comprobación completada, sin aviso", 4000, 5, "not_fresh", false },
        { "15b. Discovery operativo + 1801 s -> not_fresh y completada", 1801, 5, "not_fresh", false },
        { "15c. Discovery operativo + 1800 s sin progreso -> not_fresh y completada, sin aviso", 1800, 0, "not_fresh", false },
        { "15d. Discovery operativo + 0 s sin progreso -> not_fresh y completada, sin aviso", 0, 0, "not_fresh", false },
        { "15e. Discovery operativo + 1800 s con progreso -> fresh, aviso único y completada", 1800, 5, "fresh", true },
        { "15f. Discovery operativo + 600 s con progreso -> fresh, aviso único y completada", 600, 1, "fresh", true },
    }
    for _, case in ipairs(operative) do
        Boot(nil, QUIET)
        local f = MakeFresh({ discovery = working(case[3]) })
        local evaluated = f.check:Evaluate(1, case[2])
        f.check:Init()
        FireEvent("PLAYER_ENTERING_WORLD")
        FireEvent("TIME_PLAYED_MSG", case[2])
        FireEvent("TIME_PLAYED_MSG", case[2]); FireEvent("PLAYER_ENTERING_WORLD")
        local noticed = case[5] and 1 or 0
        check(case[1], evaluated == case[4] and f.check:IsCompleted() == true and f.requests == 1 and f.emitted == noticed and #f.shown == noticed)
    end
    Boot(nil, QUIET)
    local lv = MakeFresh({ discovery = working(5) })
    check("15g. Discovery operativo + nivel distinto de 1 -> not_fresh (con cualquier tiempo)",
        lv.check:Evaluate(2, 60) == "not_fresh" and lv.check:Evaluate(60, 99999) == "not_fresh")
end

do
    -- El control de repetición vive en memoria: una instancia NUEVA (otra sesión) vuelve a comprobar aunque lo persistente traiga la marca antigua.
    local legacy = { schemaVersion = 1, discovery = { entries = { ["zone:dun_morogh"] = {} } }, freshCheck = { done = true } }
    Boot(legacy)
    local setCalls = 0
    local realSet = Chronicle.State.Set
    Chronicle.State.Set = function(self, ...) setCalls = setCalls + 1; return realSet(self, ...) end
    local before = Chronicle.Utils.DeepCopy(ChronicleCharDB)
    FireEvent("PLAYER_ENTERING_WORLD")
    check("12. SavedVariables heredadas con la marca antigua freshCheck.done = true NO bloquean la comprobación: se pide el tiempo jugado",
        MockClient.playedRequests == 1 and ChronicleCharDB.freshCheck.done == true)
    FireEvent("TIME_PLAYED_MSG", 300)
    check("12b. y se detecta el progreso heredado: aviso real en el Popup (con el addon completo)",
        Chronicle.Popup:IsVisible() and Chronicle.Popup:GetContent().title == "Chronicle" and Chronicle.Popup:GetContent().body:find("progreso guardado", 1, true) ~= nil)
    check("12c. el módulo NO escribe ninguna marca: State:Set no se llamó, las SavedVariables son idénticas (también la marca antigua, que no se toca) y el progreso de Discovery está intacto",
        setCalls == 0 and deepEqual(before, ChronicleCharDB) and Chronicle.Discovery:Count() == 1 and Chronicle.Discovery:IsDiscovered("zone:dun_morogh"))
    FireEvent("TIME_PLAYED_MSG", 300); FireEvent("PLAYER_ENTERING_WORLD")
    check("12d. dentro de la sesión no se repite: una sola petición y un solo aviso", MockClient.playedRequests == 1)

    -- otra sesión con las mismas SavedVariables: vuelve a comprobar y, si las condiciones siguen cumpliéndose, el aviso puede repetirse
    local saved = ChronicleCharDB
    Boot(saved)
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 300)
    check("12e. una sesión nueva con las mismas SavedVariables vuelve a comprobar y, mientras se cumplan las condiciones, el aviso PUEDE repetirse (consecuencia aceptada)",
        MockClient.playedRequests == 1 and Chronicle.Popup:IsVisible() and Chronicle.Popup:GetContent().body:find("progreso guardado", 1, true) ~= nil)

    -- una instancia nueva aislada, con State que trae la marca antigua
    Boot({ schemaVersion = 1, discovery = { entries = {} }, freshCheck = { done = true } }, QUIET)
    local f = MakeFresh()
    f.check:Init()
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 600)
    check("12f. una instancia nueva puede comprobarse aunque el estado persistente tenga freshCheck.done = true: pide, detecta y avisa",
        f.requests == 1 and f.emitted == 1 and #f.shown == 1 and f.check:IsCompleted())
    check("12g. y no escribió nada: ninguna clave nueva en las SavedVariables",
        deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} }, freshCheck = { done = true } }))
end

do
    -- sin marca persistente en ningún caso (ni con detección, ni sin ella, ni con resultado desconocido)
    for _, scenario in ipairs({
        { "detección", 300, true }, { "sin detección (mucho tiempo jugado)", 9000, true }, { "resultado desconocido", "x", true },
    }) do
        Boot({ schemaVersion = 1, discovery = { entries = { ["zone:dun_morogh"] = {} } } })
        local initial = Chronicle.Utils.DeepCopy(ChronicleCharDB)
        FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", scenario[2])
        check("13. no se escribe ninguna marca de finalización en State ni en las SavedVariables (" .. scenario[1] .. ")",
            ChronicleCharDB.freshCheck == nil and Chronicle.State:Get("freshCheck") == nil and deepEqual(initial, ChronicleCharDB))
    end
    Boot({ schemaVersion = 99, discovery = { entries = { ["zone:dun_morogh"] = {} } } })
    check("13b. con State en solo lectura el módulo ya no depende de él: se inicializa y funciona sin escribir",
        Chronicle.Init.failed.FreshCharacterCheck == nil and Chronicle.FreshCharacterCheck:IsReady())
    FireEvent("PLAYER_ENTERING_WORLD"); FireEvent("TIME_PLAYED_MSG", 300)
    check("13c. y detecta igualmente el progreso heredado", MockClient.playedRequests == 1 and Chronicle.Popup:IsVisible())
    Boot(nil, function() Chronicle.State.Init = function() error("estado roto") end end)
    check("13d. si State falla, Discovery y FreshCharacterCheck se omiten en cadena (FreshCharacterCheck ya solo depende de Discovery, no de State)",
        Chronicle.Init.skipped.Discovery ~= nil and Chronicle.Init.skipped.FreshCharacterCheck ~= nil)
    Boot(nil, function() Chronicle.Discovery.Init = function() error("discovery roto") end end)
    check("13e. si Discovery falla el módulo se omite (depende de Discovery) sin romper el Codex, el Popup ni el minimapa",
        Chronicle.Init.skipped.FreshCharacterCheck ~= nil and Chronicle.Codex:IsReady() and Chronicle.Popup:IsReady() and Chronicle.MinimapButton:IsReady())
end

-- ===================== Botón del minimapa =====================
do
    Boot(nil)
    local button = _G["ChronicleMinimapButton"] or DUMMY_BUTTON
    local angle = math.rad(215)
    check("13. el botón existe, es hijo del Minimap, está visible y colocado en el borde con el ángulo predeterminado (215°)",
        button ~= nil and button.parent == Minimap and button.shown == true and button.points[1][1] == "CENTER" and button.points[1][2] == Minimap
            and math.abs(button.points[1][4] - 80 * math.cos(angle)) < 1e-9 and math.abs(button.points[1][5] - 80 * math.sin(angle)) < 1e-9)
    check("13b. el icono y el borde salen de Theme (las rutas no están en el módulo)",
        button.children[1].texture == Chronicle.Theme:GetTexture("MINIMAP_ICON") and button.children[2].texture == Chronicle.Theme:GetTexture("MINIMAP_BORDER"))
    local frames = 0
    local original = CreateFrame
    CreateFrame = function(...) frames = frames + 1; return original(...) end
    Chronicle.MinimapButton:Init(); Chronicle.MinimapButton:Init()
    CreateFrame = original
    check("13c. inicializar de nuevo no crea otro botón", frames == 0 and _G["ChronicleMinimapButton"] == button)
    check("13d. sin arrastrar no hay ningún OnUpdate", button.__scripts.OnUpdate == nil)
    check("13e. el clic izquierdo abre el Codex (Codex:Toggle) y otro lo cierra; el botón no tiene lógica de ventana propia",
        (function()
            button.__scripts.OnClick(button, "LeftButton")
            local opened = Chronicle.Codex:IsVisible()
            button.__scripts.OnClick(button, "LeftButton")
            return opened and not Chronicle.Codex:IsVisible()
        end)())
    button.__scripts.OnClick(button, "RightButton")
    check("13f. otros botones del ratón no hacen nada", not Chronicle.Codex:IsVisible())
    button.__scripts.OnEnter(button)
    check("13g. el tooltip muestra el título y las dos líneas de ayuda y se oculta al salir",
        MockClient.tooltipOwner == button and MockClient.tooltipLines[1] == "Chronicle" and #MockClient.tooltipLines == 3 and MockClient.tooltipShown == true
            and (function() button.__scripts.OnLeave(button); return MockClient.tooltipShown == false end)())
end

do
    local sets = 0
    Boot(nil, function()
        local realSet = Chronicle.Options.Set
        Chronicle.Options.Set = function(self, ...) sets = sets + 1; return realSet(self, ...) end
    end)
    local button = _G["ChronicleMinimapButton"] or DUMMY_BUTTON
    button.__scripts.OnDragStart(button)
    check("14. al empezar a arrastrar se instala el OnUpdate (solo durante el arrastre)", button.__scripts.OnUpdate ~= nil)
    MockClient.cursor = { 600, 400 } -- a la derecha del centro (500, 400): ángulo 0
    button.__scripts.OnUpdate(button)
    check("14b. el botón sigue al cursor: ángulo 0, colocado a la derecha del minimapa y sin guardar todavía",
        math.abs(button.points[1][4] - 80) < 1e-9 and math.abs(button.points[1][5]) < 1e-9 and sets == 0 and ChronicleCharDB.options == nil)
    MockClient.cursor = { 500, 500 } -- arriba: ángulo 90
    button.__scripts.OnUpdate(button)
    button.__scripts.OnDragStop(button)
    check("14c. al soltar se retira el OnUpdate y el ángulo (90°) se guarda UNA vez a través de Options y State",
        button.__scripts.OnUpdate == nil and sets == 1 and ChronicleCharDB.options.minimapAngle == 90 and Chronicle.MinimapButton:GetAngle() == 90)
    button.__scripts.OnDragStart(button)
    local onHide = button.__scripts.OnHide
    if onHide then onHide(button) end
    check("14d. si el botón se oculta durante un arrastre el OnUpdate se retira", button.__scripts.OnUpdate == nil)
    MockClient.cursor = { 0 / 0, 1 }
    button.__scripts.OnDragStart(button)
    local ok = pcall(button.__scripts.OnUpdate, button)
    check("14e. un cursor con datos no válidos no rompe nada ni cambia el ángulo", ok and Chronicle.MinimapButton:GetAngle() == 90)
    local good = button.points[1][4]
    check("14f. SetAngle valida: un valor no numérico se rechaza y no altera la posición del botón (sigue siendo un número válido)",
        select(2, pcall(Chronicle.MinimapButton.SetAngle, Chronicle.MinimapButton, "x")) == false
            and select(2, pcall(Chronicle.MinimapButton.SetAngle, Chronicle.MinimapButton, 0 / 0)) == false
            and button.points[1][4] == good and button.points[1][4] == button.points[1][4] and button.points[1][5] == button.points[1][5])
end

do
    Boot({ schemaVersion = 1, discovery = { entries = {} }, options = { minimapAngle = 0 } })
    local button = _G["ChronicleMinimapButton"] or DUMMY_BUTTON
    check("15. el ángulo guardado se restaura al arrancar (0°)", math.abs(button.points[1][4] - 80) < 1e-9)
    Boot({ schemaVersion = 1, discovery = { entries = {} }, options = { minimapAngle = "abc" } })
    local b2 = _G["ChronicleMinimapButton"] or DUMMY_BUTTON
    check("15b. un ángulo guardado inválido se ignora: posición predeterminada", math.abs(b2.points[1][4] - 80 * math.cos(math.rad(215))) < 1e-9)
    local before = #ReportedErrors
    Boot(nil, function() Minimap = nil end)
    check("15c. sin Minimap el módulo se degrada: no crea botón, Init no falla, se comunica una vez y el resto arranca",
        _G["ChronicleMinimapButton"] == nil and Chronicle.Init.failed.MinimapButton == nil and Chronicle.MinimapButton:IsReady() == false
            and Chronicle.Codex:IsReady() and countReports("Minimap") == 1)
    pcall(Chronicle.MinimapButton.Init, Chronicle.MinimapButton); pcall(Chronicle.MinimapButton.Init, Chronicle.MinimapButton)
    check("15d. repetir Init sin Minimap no repite el aviso", countReports("Minimap") == 1)
    Boot(nil, function() Chronicle.Options.Init = function() error("options roto") end end)
    check("15e. sin Options (fallan) el botón funciona igual con la posición predeterminada y no guarda",
        Chronicle.MinimapButton:IsReady() and Chronicle.Init.failed.Options ~= nil and Chronicle.MinimapButton:GetAngle() == 215
            and select(1, Chronicle.MinimapButton:SetAngle(10)) == false and Chronicle.MinimapButton:GetAngle() == 215)
    Boot(nil, function() Chronicle.Codex.Init = function() error("codex roto") end end)
    local button = _G["ChronicleMinimapButton"] or DUMMY_BUTTON
    ChatLog = {}
    button.__scripts.OnClick(button, "LeftButton")
    check("15f. con el Codex fallido el clic lo dice en el chat y no lanza errores",
        contains(ChatLog, "el Codex no está disponible") and Chronicle.MinimapButton:IsReady())
    Boot(nil, function() Chronicle.Theme.Init = function() error("theme roto") end end)
    check("15g. sin Theme el botón se omite (depende de él) sin romper el resto",
        Chronicle.Init.skipped.MinimapButton ~= nil and _G["ChronicleMinimapButton"] == nil and Chronicle.Discovery:IsReady())
end

do
    -- construcción a medias: el botón queda oculto y reintentar no crea otro con el mismo nombre
    Boot(nil)
    local made, last = 0, nil
    local mb = Chronicle.MinimapButton.New({
        createFrame = function(kind, name, parent)
            made = made + 1
            local f = CreateFrame(kind, name, parent)
            f.shown = true -- como en el cliente: un frame recién creado es visible
            f.CreateTexture = function() error("sin texturas") end
            last = f
            return f
        end,
        minimap = Minimap, theme = Chronicle.Theme, options = Chronicle.Options, codex = Chronicle.Codex,
    })
    local ok1, err1 = pcall(mb.Init, mb)
    local ok2, err2 = pcall(mb.Init, mb)
    check("15h. si la construcción del botón falla a medias, Init lo dice, el botón queda OCULTO y no listo",
        ok1 == false and tostring(err1):find("sin texturas", 1, true) ~= nil and last.shown ~= true and mb:IsReady() == false)
    check("15i. reintentar da el mismo error y NO crea otro botón con el mismo nombre", ok2 == false and err2 == err1 and made == 1)
end

-- ===================== Panel de opciones =====================
do
    Boot(nil)
    local panel = _G["ChronicleOptionsPanel"]
    check("16. el panel existe, está oculto, se llama «Chronicle» y se registró UNA vez en las opciones del juego (API clásica)",
        panel ~= nil and panel.shown ~= true and panel.name == "Chronicle" and #MockClient.optionCategories == 1 and MockClient.optionCategories[1] == panel
            and Chronicle.OptionsPanel:IsReady())
    Chronicle.OptionsPanel:Init(); Chronicle.OptionsPanel:Init()
    check("16b. inicializar de nuevo no crea otro panel ni lo registra otra vez", #MockClient.optionCategories == 1 and _G["ChronicleOptionsPanel"] == panel)
end

do
    local boxes, panelFrame = {}, nil
    local original = CreateFrame
    Boot(nil, function()
        CreateFrame = function(kind, name, parent, template)
            local frame = original(kind, name, parent, template)
            if kind == "CheckButton" then boxes[#boxes + 1] = frame end
            if name == "ChronicleOptionsPanel" then panelFrame = frame end
            return frame
        end
    end)
    CreateFrame = original
    local box = boxes[1]
    check("17. el panel tiene exactamente un control, la casilla de curiosidades, que refleja la preferencia (activada por defecto)",
        #boxes == 1 and box.checked == true and box.parent == panelFrame)
    box:SetChecked(false)
    box.__scripts.OnClick(box)
    check("17b. desmarcarla guarda la preferencia a través de Options y State", Chronicle.Options:Get("triviaEnabled") == false and ChronicleCharDB.options.triviaEnabled == false)
    box:SetChecked(true)
    box.__scripts.OnClick(box)
    check("17c. volver a marcarla la guarda", Chronicle.Options:Get("triviaEnabled") == true)
    Chronicle.Options:Set("triviaEnabled", false)
    local onShow = (panelFrame.__scripts or {}).OnShow
    if onShow then onShow(panelFrame) end
    check("17d. al abrir el panel la casilla vuelve a leer la preferencia (cambiada por otro camino)", box.checked == false)
    check("17e. el texto de la casilla y el título usan los roles de Theme (fuente y color)",
        (function()
            for _, child in ipairs(panelFrame.children) do
                if child.text == "Chronicle" then return deepEqual(child.color, Chronicle.Theme:GetColor("GOLD")) end
            end
            return false
        end)())
    check("17f. Open usa la API clásica del juego y devuelve true", Chronicle.OptionsPanel:Open() == true and MockClient.openedCategories[1] == panelFrame)
    local before = #ReportedErrors
    Chronicle.Options.Set = function() return false, "persist_failed" end
    box:SetChecked(true)
    box.__scripts.OnClick(box); box.__scripts.OnClick(box)
    check("17g. si no se puede guardar, la casilla vuelve al valor real y el error se comunica una sola vez",
        box.checked == false and countReports("no se pudo guardar la preferencia", before) == 1)
end

do
    -- API moderna (Settings), sin API, sin plantilla de casilla
    Boot(nil, function()
        InterfaceOptions_AddCategory = nil
        Settings = {
            RegisterCanvasLayoutCategory = function(panel, name) return { ID = "cat:" .. name, panel = panel } end,
            RegisterAddOnCategory = function(category) MockClient.settingsRegistered = (MockClient.settingsRegistered or 0) + 1; MockClient.lastCategory = category end,
            OpenToCategory = function(id) MockClient.openedId = id end,
        }
    end)
    check("18. con la API moderna Settings el panel se registra una vez y se abre con el ID de la categoría",
        Chronicle.OptionsPanel:IsReady() and MockClient.settingsRegistered == 1 and Chronicle.OptionsPanel:Open() == true and MockClient.openedId == "cat:Chronicle")
    local before = #ReportedErrors
    Boot(nil, function() InterfaceOptions_AddCategory = nil; InterfaceOptionsFrame_OpenToCategory = nil; Settings = nil end)
    local ok, why = Chronicle.OptionsPanel:Open()
    check("18b. sin ninguna API de registro el módulo no está listo, no registra nada, lo comunica una vez y Open devuelve unavailable",
        Chronicle.OptionsPanel:IsReady() == false and ok == false and why == "unavailable" and #MockClient.optionCategories == 0
            and Chronicle.Init.failed.OptionsPanel == nil and countReports("ninguna API para registrar") == 1)
    Chronicle.OptionsPanel:Init()
    check("18c. repetir Init no repite el aviso ni crea otro panel", countReports("ninguna API para registrar") == 1)
    local original = CreateFrame
    Boot(nil, function()
        CreateFrame = function(kind, name, parent, template)
            if kind == "CheckButton" then error("plantilla inexistente") end
            return original(kind, name, parent, template)
        end
    end)
    CreateFrame = original
    check("18d. si no se puede crear la casilla no hay panel sin controles: no se registra y se comunica",
        Chronicle.OptionsPanel:IsReady() == false and #MockClient.optionCategories == 0 and countReports("no se pudo crear la casilla") == 1)
    Boot(nil, function() Chronicle.Options.Init = function() error("options roto") end end)
    check("18e. sin Options el panel se omite y no rompe el resto", Chronicle.Init.skipped.OptionsPanel ~= nil and Chronicle.Codex:IsReady())
end

-- ===================== Comandos =====================
do
    Boot(nil)
    local calls = 0
    local slashFn = SlashCmdList["CHRONICLE"]
    Chronicle.Commands:Init(); Chronicle.Commands:Init()
    check("19. registrar los comandos otra vez no cambia el comando de barra ni duplica nada",
        SlashCmdList["CHRONICLE"] == slashFn and table.concat(Chronicle.Commands:GetCommands(), ",") == "codex,help,options,test,trivia,where")
    local out = slash("help")
    check("19b. /chronicle help lista todos los comandos disponibles",
        out:find("/chronicle codex", 1, true) and out:find("/chronicle options", 1, true) and out:find("/chronicle trivia", 1, true)
            and out:find("/chronicle test", 1, true) and out:find("/chronicle where", 1, true) and out:find("/chronicle help", 1, true))
    check("19c. el comando no distingue mayúsculas ni espacios sobrantes", slash("  HELP  "):find("comandos disponibles", 1, true) ~= nil)
    check("19d. un comando desconocido lo contesta Slash y no falla", slash("inventado"):find("comando desconocido: inventado", 1, true) ~= nil)
    check("19e. /chronicle sin argumentos sigue mostrando el estado del Core", slash(""):find("Core activo", 1, true) ~= nil)
    check("19f. reset NO existe (pospuesto: Discovery no tiene reinicio) y se contesta como desconocido",
        slash("reset"):find("comando desconocido: reset", 1, true) ~= nil and Chronicle.Discovery:Count() == 0)
    for _, name in ipairs({ "codex", "options", "trivia", "test", "where", "help" }) do
        local result = slash(name .. " algo extra")
        if not result:find("no admite argumentos", 1, true) or not result:find("/chronicle " .. name, 1, true) then
            check("19g. " .. name .. " con argumentos explica el uso", false)
        end
    end
    check("19g. todos los comandos rechazan los argumentos con una explicación de uso y no se ejecutan",
        not Chronicle.Codex:IsVisible() and not Chronicle.Popup:IsVisible() and #MockClient.openedCategories == 0)
end

do
    Boot(nil)
    slash("codex")
    check("20. /chronicle codex abre el Codex y otro lo cierra", Chronicle.Codex:IsVisible() == true and (function() slash("codex"); return not Chronicle.Codex:IsVisible() end)())
    check("20b. /chronicle options abre el panel de opciones", (function() slash("options"); return MockClient.openedCategories[1] == _G["ChronicleOptionsPanel"] end)())
    slash("test")
    check("20c. /chronicle test muestra el aviso de ejemplo en el Popup",
        Chronicle.Popup:IsVisible() and Chronicle.Popup:GetContent().title == "Chronicle" and Chronicle.Popup:GetContent().body:find("aviso de ejemplo", 1, true) ~= nil)
    Chronicle.Popup:CloseAll()
    local out = slash("trivia")
    check("20d. /chronicle trivia sin nada descubierto lo explica y no muestra nada", out:find("no hay ninguna curiosidad que puedas ver", 1, true) ~= nil and not Chronicle.Popup:IsVisible())
    Chronicle.Discovery:Discover("subzone:coldridge_valley")
    Chronicle.Popup:CloseAll() -- (ver 9b: se descarta el aviso del propio descubrimiento)
    slash("trivia")
    check("20e. con el lugar descubierto /chronicle trivia muestra la curiosidad", Chronicle.Popup:IsVisible() and Chronicle.Popup:GetContent().body == LegacyTrivia[1])
    Chronicle.Popup:CloseAll()
    Chronicle.Options:Set("triviaEnabled", false)
    check("20f. con la preferencia desactivada lo dice", slash("trivia"):find("desactivadas", 1, true) ~= nil and not Chronicle.Popup:IsVisible())
end

do
    Boot(nil, function() Chronicle.Codex.Init = function() error("codex roto") end; Chronicle.OptionsPanel.Open = function() return false, "unavailable" end end)
    check("21. con el Codex roto /chronicle codex lo dice y no lanza errores", slash("codex"):find("el Codex no está disponible", 1, true) ~= nil)
    check("21b. si el panel no se puede abrir lo dice", slash("options"):find("no se ha podido abrir el panel", 1, true) ~= nil)
    Boot(nil, function() Chronicle.Popup.Init = function() error("popup roto") end end)
    check("21c. con el Popup roto /chronicle test lo dice y no lanza errores", slash("test"):find("no se ha podido mostrar", 1, true) ~= nil)
    Boot(nil, function() Chronicle.Slash.Init = function() error("slash roto") end end)
    check("21d. si Slash falla los comandos se omiten (Commands depende de él) y el resto arranca",
        Chronicle.Init.skipped.Commands ~= nil and Chronicle.Init.failed.Commands == nil and Chronicle.Codex:IsReady())
end

-- ===================== /chronicle where =====================
local function WhereWith(map, prepare)
    Boot(nil, prepare)
    local commands = Chronicle.Commands.New({
        slash = { Register = function() end }, mapPosition = map, resolver = Chronicle.Resolver, discovery = Chronicle.Discovery,
        print = function(m) Chronicle.Utils.Print(m) end,
    })
    local handlers = {}
    local fake = Chronicle.Commands.New({
        slash = { Register = function(_, name, fn) handlers[name] = fn end }, mapPosition = map,
        resolver = Chronicle.Resolver, discovery = Chronicle.Discovery, print = function(m) Chronicle.Utils.Print(m) end,
    })
    fake:Init()
    ChatLog = {}
    handlers.where("")
    return chat()
end

do
    local available = {
        GetZoneName = function() return "available", "Zona Inventada" end,
        GetSubzoneName = function() return "available", "Subzona Inventada" end,
        GetPosition = function() return "available", { mapID = 1426, x = 0.123456, y = 0.5 } end,
    }
    local out = WhereWith(available)
    check("22. where con todos los datos disponibles: zona, subzona y posición (mapa y coordenadas con 3 decimales)",
        out:find("Zona: Zona Inventada", 1, true) and out:find("Subzona: Subzona Inventada", 1, true)
            and out:find("Posición: mapa 1426, x=0.123 y=0.500", 1, true))
    local mixed = WhereWith({
        GetZoneName = function() return "available", "Zona Inventada" end,
        GetSubzoneName = function() return "unavailable", "empty" end,
        GetPosition = function() return "unknown", "api_missing" end,
    })
    check("22b. distingue no disponible ahora (con su motivo) de desconocido (con su motivo) y no inventa ninguna ubicación",
        mixed:find("Subzona: no disponible (empty)", 1, true) and mixed:find("Posición: desconocido (api_missing)", 1, true) and not mixed:find("x=", 1, true))
    local failing = WhereWith({
        GetZoneName = function() error("zona rota") end,
        GetSubzoneName = function() return "available", "Y" end,
        GetPosition = function() return "unavailable", "no_map" end,
    })
    check("22c. si una consulta del servicio falla se dice desconocido (api_error) y las demás se muestran",
        failing:find("Zona: desconocido (api_error)", 1, true) and failing:find("Subzona: Y", 1, true) and failing:find("Posición: no disponible (no_map)", 1, true))
    local noService = WhereWith(nil)
    check("22d. sin el servicio de posición lo dice y no falla", noService:find("el servicio de posición no está disponible", 1, true) ~= nil)
    local partial = WhereWith({})
    check("22e. un servicio sin métodos se trata como desconocido (api_missing)", partial:find("Zona: desconocido (api_missing)", 1, true) ~= nil)
end

do
    -- nombres bloqueados
    local map = {
        GetZoneName = function() return "available", "Dun Morogh" end,
        GetSubzoneName = function() return "available", "Kharanos" end,
        GetPosition = function() return "available", { mapID = 1, x = 0.1, y = 0.2 } end,
    }
    local lockedOut = WhereWith(map)
    check("23. where no revela los nombres de lugares sin descubrir: la zona y la subzona salen como «???»",
        lockedOut:find("Zona: ???", 1, true) and lockedOut:find("Subzona: ???", 1, true) and not lockedOut:find("Dun Morogh", 1, true) and not lockedOut:find("Kharanos", 1, true))
    check("23b. pero sí da la posición (las coordenadas no son nombres)", lockedOut:find("Posición: mapa 1, x=0.100 y=0.200", 1, true) ~= nil)
    local discovers = 0
    local out
    Chronicle.Discovery:Discover("zone:dun_morogh")
    local realDiscover = Chronicle.Discovery.Discover
    Chronicle.Discovery.Discover = function(self, ...) discovers = discovers + 1; return realDiscover(self, ...) end
    local handlers = {}
    Chronicle.Commands.New({ slash = { Register = function(_, n, f) handlers[n] = f end }, mapPosition = map, resolver = Chronicle.Resolver,
        discovery = Chronicle.Discovery, print = function(m) Chronicle.Utils.Print(m) end }):Init()
    ChatLog = {}
    handlers.where("")
    out = chat()
    check("23c. con la zona descubierta su nombre se muestra y la subzona sigue en «???» (cada nombre se evalúa por sí solo)",
        out:find("Zona: Dun Morogh", 1, true) and out:find("Subzona: ???", 1, true) and not out:find("Kharanos", 1, true))
    check("23d. consultar la posición no descubre nada", discovers == 0 and Chronicle.Discovery:Count() == 1)
    Chronicle.Discovery.Discover = realDiscover
    local other = WhereWith({
        GetZoneName = function() return "available", "Forjaz" end,
        GetSubzoneName = function() return "available", "Gnomeregan" end,
        GetPosition = function() return "unavailable", "no_map" end,
    })
    check("23e. un alias (Forjaz) o un nombre de subzona del catálogo sin descubrir también salen como «???»",
        other:find("Zona: ???", 1, true) and other:find("Subzona: ???", 1, true) and not other:find("Forjaz", 1, true) and not other:find("Gnomeregan", 1, true))
    local h2 = {}
    local notReadyResolver = { IsReady = function() return false end, Resolve = function() return nil, "not_found" end }
    Chronicle.Commands.New({ slash = { Register = function(_, n, f) h2[n] = f end }, mapPosition = map, resolver = notReadyResolver,
        discovery = Chronicle.Discovery, print = function(m) Chronicle.Utils.Print(m) end }):Init()
    ChatLog = {}
    h2.where("")
    check("23f. si el Resolver no está listo no se puede confirmar nada: los nombres salen como «???»", chat():find("Zona: ???", 1, true) ~= nil and not chat():find("Dun Morogh", 1, true))
end

do
    -- /chronicle where con el addon real y el cliente simulado
    Boot(nil, function()
        function GetRealZoneText() return "Dun Morogh" end
        function GetSubZoneText() return "" end
        C_Map = {
            GetBestMapForUnit = function() return 1426 end,
            GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end,
        }
    end)
    local out = slash("where")
    check("24. /chronicle where por el comando real con el servicio MapPosition real: nombre bloqueado, subzona vacía no disponible y posición",
        out:find("Zona: ???", 1, true) and out:find("Subzona: no disponible", 1, true) and out:find("Posición: mapa 1426, x=0.500 y=0.250", 1, true))
    GetRealZoneText, GetSubZoneText, C_Map = nil, nil, nil -- (la prueba anterior los definió como globales)
    Boot(nil)
    local out2 = slash("where")
    check("24b. sin ninguna API de posición del cliente todo es desconocido y no hay errores de Lua",
        out2:find("Zona: desconocido", 1, true) and out2:find("Posición: desconocido (api_missing)", 1, true))
end

-- ===================== Fallos independientes y aislamiento =====================
do
    local modules = { "Options", "Trivia", "FreshCharacterCheck", "OptionsPanel", "MinimapButton", "Commands" }
    for _, name in ipairs(modules) do
        Boot(nil, function() Chronicle[name].Init = function() error(name .. " roto") end end)
        check("25. si " .. name .. " falla (opcional) queda en Init.failed y el Codex, Discovery y el Popup siguen funcionando y se anuncia el arranque",
            Chronicle.Init.failed[name] ~= nil and Chronicle.Init.ready == true and Chronicle.Codex:IsReady() and Chronicle.Discovery:IsReady()
                and Chronicle.Popup:IsReady())
    end
    Boot(nil, function() Chronicle.State.Init = function() error("estado roto") end end)
    check("25b. si State falla, Options y sus dependientes se omiten (no fallan) y no hay errores de Lua",
        Chronicle.Init.skipped.Options ~= nil and Chronicle.Init.skipped.Trivia ~= nil and Chronicle.Init.skipped.OptionsPanel ~= nil
            and Chronicle.Init.failed.Options == nil)
    Boot(nil, function() Chronicle.Options = nil end)
    check("25c. si el módulo Options no está cargado se diagnostica y las dependientes se omiten", Chronicle.Init.failed.Options ~= nil and Chronicle.Init.skipped.Trivia ~= nil)
end

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
local NEW = { "Core/Options.lua", "Core/FreshCharacterCheck.lua", "Services/Trivia.lua", "UI/OptionsPanel.lua", "UI/MinimapButton.lua", "UI/Commands.lua" }

check("26. ningún módulo nuevo referencia la SavedVariable, y solo Options nombra State (para persistir; FreshCharacterCheck ya no lo necesita), ninguno escribe sus rutas a mano",
    (function()
        for _, name in ipairs(NEW) do
            local lines = codeOf(name)
            if not lines then return false, name .. " no está en el .toc" end
            for _, line in ipairs(lines) do
                if line:find("ChronicleCharDB", 1, true) then return false, name end
                if line:find("Chronicle.State", 1, true) and name ~= "Core/Options.lua" then return false, name .. ": State" end
            end
        end
        return true
    end)())
check("26b. ningún módulo nuevo llama a Discover ni modifica Discovery (solo la consultan)",
    (function()
        for _, name in ipairs(NEW) do
            for _, line in ipairs(codeOf(name)) do
                for _, word in ipairs({ ":Discover(", ".Discover(", "ResetAll", "Discovery.Init", "Discovery:Set" }) do
                    if line:find(word, 1, true) then return false, name .. ": " .. word end
                end
            end
        end
        return true
    end)())
check("26c. los módulos nuevos no usan OnUpdate ni temporizadores salvo lo declarado: OnUpdate solo en el arrastre del minimapa y un único C_Timer.After de un disparo en Trivia",
    (function()
        for _, name in ipairs(NEW) do
            local updates = 0
            for _, line in ipairs(codeOf(name)) do
                if line:find("OnUpdate", 1, true) then updates = updates + 1 end
                if (line:find("C_Timer", 1, true) or line:find("NewTicker", 1, true)) and name ~= "Services/Trivia.lua" then return false, name .. ": temporizador" end
            end
            if name == "UI/MinimapButton.lua" then
                if updates ~= 2 then return false, "MinimapButton: OnUpdate en " .. updates .. " líneas" end
            elseif updates ~= 0 then
                return false, name .. ": OnUpdate"
            end
        end
        return true
    end)())
check("26d. los módulos nuevos no definen rutas de textura, colores ni fuentes propios (todo sale de Theme)",
    (function()
        for _, name in ipairs({ "UI/OptionsPanel.lua", "UI/MinimapButton.lua", "UI/Commands.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                for _, word in ipairs({ "Interface\\\\", "Interface/", "Fonts\\\\", "SetFont(", "SetTextColor", "SetBackdrop(", "SetVertexColor" }) do
                    if line:find(word, 1, true) then return false, name .. ": " .. word end
                end
                if line:find("0%.%d+%s*,%s*0%.%d+") then return false, name .. ": " .. line end
            end
        end
        return true
    end)())
check("26e. el orden de carga del .toc respeta las capas: Options y FreshCharacterCheck tras State; Trivia tras Services; la interfaz tras el Codex; Commands tras todo",
    (function()
        local order = {}
        for i, file in ipairs(ADDON_FILES) do order[file.name] = i end
        return order["Core/Options.lua"] > order["Core/State.lua"] and order["Core/FreshCharacterCheck.lua"] > order["Core/Options.lua"]
            and order["Services/Trivia.lua"] > order["Services/ZoneDiscovery.lua"] and order["Data/Trivia.lua"] ~= nil
            and order["UI/OptionsPanel.lua"] > order["UI/Codex.lua"] and order["UI/MinimapButton.lua"] > order["UI/Codex.lua"]
            and order["UI/Commands.lua"] > order["UI/MinimapButton.lua"] and order["Core/Init.lua"] > order["UI/Commands.lua"]
    end)())
check("26f. los textos de las curiosidades y de los avisos no están duplicados en los módulos de interfaz: Trivia usa Data/Trivia.lua",
    (function()
        for _, name in ipairs({ "Services/Trivia.lua", "UI/Commands.lua" }) do
            for _, line in ipairs(codeOf(name)) do
                if line:find("Coldridge", 1, true) or line:find("Thunderbrew", 1, true) then return false, name end
            end
        end
        return true
    end)())
