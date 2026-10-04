Chronicle = Chronicle or {}

-- Punto de arranque del Core. Se limita a inicializar los módulos en un orden explícito;
-- no contiene lógica de producto.
--
-- Los ficheros del .toc solo DEFINEN módulos (Chronicle.Events, Chronicle.State...). La
-- inicialización real -- la que necesita las SavedVariables ya cargadas -- se hace aquí,
-- una sola vez, en ADDON_LOADED de este addon, cuando ya se han ejecutado todos los
-- ficheros del .toc.
--
-- POLÍTICA DE INICIALIZACIÓN
--   * Cada módulo se intenta inicializar en su turno, aunque otro haya fallado, salvo que
--     declare `requires` (módulos de los que depende): si alguno de ellos no quedó
--     inicializado, ese módulo NO se intenta. Queda en Init.skipped[nombre] (no en
--     Init.failed, que solo lista las causas: el módulo del que depende ya está ahí) y, si
--     es requerido, Init.ready es false. Así un módulo nunca se inicializa antes de que sus
--     dependencias estén listas.
--   * Todo fallo queda en Init.failed[nombre] (texto del error) y se comunica por
--     geterrorhandler(). Nunca se convierte en un éxito silencioso.
--   * Cada módulo es `required` o no. Init.ready solo es true si TODOS los requeridos se
--     han inicializado bien. Un módulo no requerido que falla queda diagnosticado en
--     Init.failed, pero no impide el arranque.
--   * "Chronicle.Initialized" se emite únicamente si Init.ready es true (lo que implica
--     que el bus de eventos existe y funciona). Si no, no se anuncia ningún arranque.
--   * Init:Run() es idempotente: tras el primer intento, cualquier otra llamada no hace
--     nada (no repite inicializaciones ni vuelve a emitir).

local Init = {}
Chronicle.Init = Init

local ADDON_NAME = "Chronicle"

-- Orden de inicialización. Cada módulo puede definir Module:Init(); si no, basta con que
-- exista. Events no tiene estado que preparar, pero es requerido y va primero: todo lo
-- que viene después puede emitir/escuchar eventos al arrancar. Los Services y la UI van
-- después, en este orden de capas: Core -> Services -> UI.
local MODULES = {
    { name = "Events", required = true },
    { name = "State", required = true },
    { name = "Registry", required = true }, -- no se da por listo si los datos no superan su validación
    { name = "Localization", required = true }, -- tras Registry: valida que sus textos son de entidades que existen
    { name = "Resolver", required = true }, -- tras Localization: construye el índice de nombres y alias
    -- Discovery lee y guarda el progreso con State y valida entidades con el Registry: no se intenta si
    -- alguno de los dos no está listo.
    { name = "Discovery", required = true, requires = { "State", "Registry" } },
    -- MapPosition no tiene estado que inicializar (lee el cliente en cada consulta): basta con que exista.
    { name = "MapPosition", required = true },
    -- Proximity necesita MapPosition y un Discovery listo; sin proveedor de objetivos no descubre nada.
    { name = "Proximity", required = true, requires = { "MapPosition", "Discovery" } },
    -- ZoneDiscovery empieza a escuchar los eventos de zona: necesita nombres, el Resolver y Discovery listos.
    { name = "ZoneDiscovery", required = true, requires = { "MapPosition", "Resolver", "Discovery" } },
    -- Interfaz: OPCIONAL a propósito. Un fallo puramente visual (una fuente, un frame) no debe impedir que Discovery y el
    -- resto de servicios funcionen ni que se anuncie el arranque; queda diagnosticado en Init.failed. Quien use el
    -- Popup debe comprobar Popup:IsReady(). Popup depende de Theme: si Theme falla, Popup no se intenta.
    { name = "Theme", required = false },
    { name = "Popup", required = false, requires = { "Theme" } },
    -- Codex: ventana principal con navegación y páginas (Fases 8-9). Opcional por la misma razón que el Popup. Depende de Theme y,
    -- ahora que muestra el catálogo, de Registry y Localization (requeridos: si fallan, el Codex ni se intenta).
    { name = "Codex", required = false, requires = { "Theme", "Registry", "Localization" } },
    -- Avisos de descubrimiento: une el evento de Discovery con el Popup. Opcional: si falla, Discovery y el Codex siguen funcionando.
    { name = "DiscoveryNotice", required = false, requires = { "Discovery" } },
    -- Descubrimiento de NPC por GUID (Fase 14): opcional; sin él el resto funciona. Solo pide Discovery:Discover; Discovery guarda y DiscoveryNotice avisa.
    { name = "NpcDiscovery", required = false, requires = { "Discovery", "Registry", "Resolver" } },
    -- Fase 12: integraciones OPCIONALES. Ninguna es requerida: si falla, queda en Init.failed y el resto (Discovery, Codex, Popup...) funciona.
    -- `requires` solo nombra lo que el módulo NO puede usar sin esa pieza; el resto de dependencias (Popup, Codex...) se comprueba al usarlas.
    { name = "Options", required = false, requires = { "State" } }, -- preferencias, guardadas con State
    { name = "Trivia", required = false, requires = { "Options" } },
    { name = "FreshCharacterCheck", required = false, requires = { "Discovery" } },
    { name = "OptionsPanel", required = false, requires = { "Options", "Theme" } },
    { name = "MinimapButton", required = false, requires = { "Theme" } }, -- sin Options usa la posición predeterminada y no la guarda
    { name = "Slash", required = false }, -- solo el comando /chronicle: el Core funciona sin él
    { name = "Commands", required = false, requires = { "Slash" } }, -- los subcomandos de /chronicle (Fase 12)
}

Init.initialized = false -- ya se ha hecho el (único) intento de arranque
Init.ready = false -- los módulos requeridos están inicializados
Init.failed = {} -- nombre de módulo -> texto del error
Init.skipped = {} -- nombre de módulo -> por qué no se intentó (una dependencia no está lista)

-- Comunica un fallo sin depender de ningún módulo de Chronicle (ni siquiera de Utils o
-- Events): solo de lo que provee el cliente, y con respaldo si ni eso existe.
local function ReportFailure(name, err)
    Init.failed[name] = tostring(err)
    local message = "Chronicle: falló la inicialización de '" .. name .. "': " .. tostring(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    else
        print(message)
    end
end

local function ReadVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMeta then
        return nil
    end
    local ok, version = pcall(getMeta, ADDON_NAME, "Version")
    return ok and version or nil
end

-- Intenta inicializar un módulo. Devuelve true si queda listo.
local function InitModule(name)
    local module = Chronicle[name]
    if type(module) ~= "table" then
        ReportFailure(name, "el módulo no está cargado (revisa el orden del .toc)")
        return false
    end
    if type(module.Init) ~= "function" then
        return true
    end
    local ok, err = pcall(module.Init, module)
    if not ok then
        ReportFailure(name, err)
        return false
    end
    return true
end

-- Anuncia el arranque. Solo se llama con Init.ready == true; aun así se comprueba que el
-- bus es utilizable, y un fallo del propio Emit se reporta en vez de propagarse.
local function Announce()
    local events = Chronicle.Events
    if type(events) ~= "table" or type(events.Emit) ~= "function" then
        ReportFailure("Events", "el bus de eventos no es utilizable para anunciar el arranque")
        Init.ready = false
        return
    end
    local ok, err = pcall(events.Emit, events, "Chronicle.Initialized")
    if not ok then
        ReportFailure("Events", err)
        Init.ready = false
    end
end

function Init:Run()
    if Init.initialized then
        return
    end
    Init.initialized = true
    Chronicle.version = ReadVersion()

    local ready = true
    local done = {} -- módulos que quedaron inicializados
    for _, spec in ipairs(MODULES) do
        local blockedBy
        for _, dependency in ipairs(spec.requires or {}) do
            if not done[dependency] then
                blockedBy = dependency
                break
            end
        end

        if blockedBy then
            Init.skipped[spec.name] = "no se intentó: depende de '" .. blockedBy .. "', que no está inicializado"
            if spec.required then
                ready = false
            end
        elseif InitModule(spec.name) then
            done[spec.name] = true
        elseif spec.required then
            ready = false
        end
    end

    Init.ready = ready
    if ready then
        Announce()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    Init:Run()
end)
