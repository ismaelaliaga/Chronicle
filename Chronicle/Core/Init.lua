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
--   * Cada módulo se intenta inicializar en su turno, aunque otro haya fallado: los
--     módulos actuales son independientes entre sí.
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
-- que viene después puede emitir/escuchar eventos al arrancar. Los futuros Services y
-- UI se añaden al final, en este orden de capas: Core -> Services -> UI.
local MODULES = {
    { name = "Events", required = true },
    { name = "State", required = true },
    { name = "Slash", required = false }, -- solo el comando /chronicle: el Core funciona sin él
}

Init.initialized = false -- ya se ha hecho el (único) intento de arranque
Init.ready = false -- los módulos requeridos están inicializados
Init.failed = {} -- nombre de módulo -> texto del error

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
    for _, spec in ipairs(MODULES) do
        if not InitModule(spec.name) and spec.required then
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
