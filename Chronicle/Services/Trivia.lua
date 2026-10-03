Chronicle = Chronicle or {}

-- Trivia: curiosidades sueltas («¿Sabías que...?») que se muestran en momentos de inactividad del jugador. Reconstruye Core/Trivia.lua
-- del addon original SIN su arquitectura: es un servicio aislado que no sabe nada del Codex, no toca Discovery y no guarda nada.
--
-- QUÉ ES (y qué no). El contenido original son OCHO CURIOSIDADES, no preguntas con respuesta: no hay respuestas que comprobar. Por eso
-- aquí no hay ni preguntas ni respuestas ni puntuación. El contenido es Chronicle.TriviaEntries (Data/Trivia.lua), migrado literalmente;
-- este módulo no inventa ni añade ninguna.
--
-- CUÁNDO SE MUESTRA (comportamiento del original; aquí SIN VERIFICAR en un cliente real)
--   · PLAYER_DEAD: al morir.
--   · PLAYER_CONTROL_LOST + UnitOnTaxi("player"): al subir a un vuelo. El original esperaba 0,1 s antes de comprobar el vuelo porque
--     el evento llega antes de que el cliente lo refleje; aquí se usa un ÚNICO temporizador de un disparo (C_Timer.After), imprescindible
--     por ese motivo, solo si existe C_Timer. Sin él, este disparador no se activa.
--   · Show(true): bajo demanda (/chronicle trivia), ignorando el enfriamiento.
--   Enfriamiento entre avisos automáticos: 600 s (el original); medido con GetTime.
--   Se pone en la cola del Popup (Popup:Enqueue), que nunca pisa un aviso visible.
--
-- POLÍTICA DE DISCOVERY. Las curiosidades nombran lugares y personajes. Antes de mostrar una, el guardián (`guard`) comprueba que NINGUNA
-- entidad del catálogo que aparezca nombrada en el texto (por nombre o alias, vía Resolver) esté sin descubrir: si hay una bloqueada, o no se
-- puede confirmar (Resolver o Discovery no listos), esa curiosidad NO sale. Es lo conservador y significa que, con poco descubierto,
-- puede no haber ninguna disponible. Nunca descubre nada: solo consulta.
--
-- VALIDACIÓN. Una entrada es válida si es una tabla con `text` cadena no vacía (más de espacios). Las inválidas se ignoran al elegir, no
-- rompen nada, y se pueden contar con Trivia:Validate(). Para no repetir al instante, se evita la misma entrada dos veces seguidas si
-- hay otra disponible.
--
-- CONTRATO
--   Trivia:Show([ignoreCooldown]) -> true | false, motivo
--       "not_ready" (sin Init)   "disabled" (la preferencia triviaEnabled está desactivada)   "cooldown"   "no_content" (no hay entradas
--       válidas)   "guarded" (todas las válidas nombran algo bloqueado o no confirmable)   "no_popup" (no hay Popup)   "ui_error" (el Popup lo rechazó)
--   Trivia:Validate()  -> { valid = n, invalid = n, errors = { ... } }
--   Trivia:Init() / IsReady()   Init es idempotente: crea UN frame y registra los eventos una sola vez. Lanza error si falta lo imprescindible.
--   Trivia.New({ options, popup, entries, guard, createFrame, now, random, after, onTaxi }) crea otra instancia (pruebas). Cada dependencia puede
--   ser el objeto o una función que lo devuelve; la instancia por defecto usa los globales del cliente y Chronicle.*.
--   Trivia.NameGuard(resolver, discovery) -> guardián por defecto (ver arriba).

local TITLE = "¿Sabías que...?"
local COOLDOWN_SECONDS = 600
local TAXI_DELAY = 0.1
local MAX_PHRASE_WORDS = 4

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

local function ValidText(entry)
    return type(entry) == "table" and type(entry.text) == "string" and entry.text:match("%S") ~= nil
end

-- Palabras del texto sin la puntuación de los extremos. Se separa solo por espacios (y se quitan signos ASCII y los españoles ¿ ¡ « »).
local function Words(text)
    local words = {}
    for token in text:gmatch("%S+") do
        token = token:gsub("^[%p]+", ""):gsub("[%p]+$", "")
        token = token:gsub("^¿", ""):gsub("^¡", ""):gsub("^«", ""):gsub("»$", "")
        if token ~= "" then words[#words + 1] = token end
    end
    return words
end

-- Guardián por defecto: un texto se puede mostrar solo si toda entidad nombrada en él (frases de 1 a 4 palabras resueltas por el Resolver,
-- por nombre o alias) está descubierta. Ambiguo = se miran todos los candidatos. Cualquier duda (servicio ausente, no listo o que falla)
-- significa «no se puede mostrar».
local function NameGuard(resolverSource, discoverySource)
    local function Resolve(source)
        local value = source
        if type(value) == "function" then
            local ok, resolved = pcall(value)
            value = ok and resolved or nil
        end
        return value
    end
    return function(text)
        local resolver, discovery = Resolve(resolverSource), Resolve(discoverySource)
        if not IsObject(resolver) or not IsObject(discovery) or type(resolver.Resolve) ~= "function"
            or type(discovery.IsDiscovered) ~= "function" then
            return false
        end
        local okReady = pcall(function()
            if resolver:IsReady() ~= true or discovery:IsReady() ~= true then error("no listo") end
        end)
        if not okReady then
            return false
        end
        local words = Words(text)
        for first = 1, #words do
            for count = 1, math.min(MAX_PHRASE_WORDS, #words - first + 1) do
                local phrase = table.concat(words, " ", first, first + count - 1)
                local ok, id, reason, candidates = pcall(resolver.Resolve, resolver, phrase)
                if not ok then
                    return false
                end
                local ids = {}
                if id then
                    ids[1] = id
                elseif reason == "ambiguous" and type(candidates) == "table" then
                    ids = candidates
                elseif reason == "not_ready" then
                    return false
                end
                for _, candidate in ipairs(ids) do
                    local okDiscovered, discovered = pcall(discovery.IsDiscovered, discovery, candidate)
                    if not okDiscovered or discovered ~= true then
                        return false
                    end
                end
            end
        end
        return true
    end
end

local function NewTrivia(deps)
    if type(deps) ~= "table" then
        error("Chronicle.Trivia.New: se esperaba una tabla de dependencias", 2)
    end
    local function Dep(name)
        local dep = deps[name]
        if type(dep) == "function" and name ~= "createFrame" and name ~= "now" and name ~= "random" and name ~= "after"
            and name ~= "onTaxi" and name ~= "guard" then
            return dep()
        end
        return dep
    end

    local self = {}
    local ready = false
    local frame
    local lastShownAt = -COOLDOWN_SECONDS
    local lastIndex

    local function Entries()
        local entries = Dep("entries")
        if type(entries) == "function" then entries = entries() end
        return type(entries) == "table" and entries or {}
    end

    function self:Validate()
        local report = { valid = 0, invalid = 0, errors = {} }
        for i, entry in ipairs(Entries()) do
            if ValidText(entry) then
                report.valid = report.valid + 1
            else
                report.invalid = report.invalid + 1
                report.errors[#report.errors + 1] = "la entrada " .. i .. " no es válida (se esperaba { text = <cadena no vacía> })"
            end
        end
        return report
    end

    local function Enabled()
        local options = Dep("options")
        if not IsObject(options) or type(options.Get) ~= "function" then
            return false
        end
        local ok, value = pcall(options.Get, options, "triviaEnabled")
        return ok and value == true
    end

    function self:Show(ignoreCooldown)
        if not ready then
            return false, "not_ready"
        end
        if not Enabled() then
            return false, "disabled"
        end
        local clock = deps.now
        local now = type(clock) == "function" and clock() or nil
        if not ignoreCooldown and type(now) == "number" and (now - lastShownAt) < COOLDOWN_SECONDS then
            return false, "cooldown"
        end
        local candidates = {}
        for i, entry in ipairs(Entries()) do
            if ValidText(entry) then candidates[#candidates + 1] = i end
        end
        if #candidates == 0 then
            return false, "no_content"
        end
        local allowed = {}
        local guard = deps.guard
        for _, index in ipairs(candidates) do
            local entries = Entries()
            local okGuard, pass = true, true
            if type(guard) == "function" then
                okGuard, pass = pcall(guard, entries[index].text)
            end
            if okGuard and pass == true then allowed[#allowed + 1] = index end
        end
        if #allowed == 0 then
            return false, "guarded"
        end
        if #allowed > 1 and lastIndex then
            local others = {}
            for _, index in ipairs(allowed) do
                if index ~= lastIndex then others[#others + 1] = index end
            end
            allowed = others
        end
        local random = deps.random
        local pick = type(random) == "function" and random(1, #allowed) or 1
        if type(pick) ~= "number" or pick < 1 or pick > #allowed then pick = 1 end
        local index = allowed[math.floor(pick)]
        local popup = Dep("popup")
        if not IsObject(popup) or type(popup.Enqueue) ~= "function" then
            return false, "no_popup"
        end
        local okShow, shown = pcall(popup.Enqueue, popup, { title = TITLE, body = Entries()[index].text })
        if not okShow or shown ~= true then
            return false, "ui_error"
        end
        lastIndex = index
        if type(now) == "number" then lastShownAt = now end
        return true
    end

    local function OnEvent(_, event)
        if event == "PLAYER_DEAD" then
            self:Show(false)
        elseif event == "PLAYER_CONTROL_LOST" then
            local after, onTaxi = deps.after, deps.onTaxi
            if type(after) == "function" and type(onTaxi) == "function" then
                after(TAXI_DELAY, function()
                    local ok, taxi = pcall(onTaxi, "player")
                    if ok and taxi then self:Show(false) end
                end)
            end
        end
    end

    function self:Init()
        if ready then
            return
        end
        local options = Dep("options")
        if not IsObject(options) or type(options.Get) ~= "function" then
            error("Trivia: Options no está disponible (Trivia se inicializa después de Options)", 0)
        end
        if type(deps.createFrame) ~= "function" then
            error("Trivia: CreateFrame no está disponible", 0)
        end
        if not frame then
            local created = deps.createFrame("Frame")
            if not IsObject(created) then
                error("Trivia: CreateFrame no devolvió un frame", 0)
            end
            frame = created
            created:RegisterEvent("PLAYER_DEAD")
            created:RegisterEvent("PLAYER_CONTROL_LOST")
            created:SetScript("OnEvent", OnEvent)
        end
        ready = true
    end

    function self:IsReady()
        return ready
    end

    return self
end

Chronicle.Trivia = NewTrivia({
    options = function() return Chronicle.Options end,
    popup = function() return Chronicle.Popup end,
    entries = function() return Chronicle.TriviaEntries end,
    guard = NameGuard(function() return Chronicle.Resolver end, function() return Chronicle.Discovery end),
    createFrame = function(...) return CreateFrame(...) end,
    now = function() return GetTime and GetTime() or nil end,
    random = function(a, b) return math.random(a, b) end,
    after = function(...) if C_Timer and C_Timer.After then return C_Timer.After(...) end end,
    onTaxi = function(...) if UnitOnTaxi then return UnitOnTaxi(...) end end,
})
Chronicle.Trivia.New = NewTrivia
Chronicle.Trivia.NameGuard = NameGuard
