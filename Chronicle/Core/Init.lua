Chronicle = Chronicle or {}

-- Punto de arranque del Core. Se limita a inicializar los módulos en un orden explícito;
-- no contiene lógica de producto.
--
-- Los ficheros del .toc solo DEFINEN módulos (Chronicle.Events, Chronicle.State...). La
-- inicialización real -- la que necesita las SavedVariables ya cargadas -- se hace aquí,
-- una sola vez, en ADDON_LOADED de este addon, cuando ya se han ejecutado todos los
-- ficheros del .toc.

local Init = {}
Chronicle.Init = Init

local ADDON_NAME = "Chronicle"

-- Orden de inicialización. Cada módulo puede definir Module:Init(); si no, se omite.
-- Events no tiene estado que preparar, pero se lista para que la dependencia sea
-- explícita: todo lo que viene después puede emitir/escuchar eventos al arrancar.
-- Los futuros Services y UI se añaden al final, en este orden de capas:
-- Core -> Services -> UI.
local MODULE_ORDER = { "Events", "State", "Slash" }

Init.initialized = false
Init.failed = {}

local function ReadVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMeta and getMeta(ADDON_NAME, "Version") or nil
end

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

-- Inicializa los módulos en orden. Un módulo que falla se reporta y se marca en
-- Init.failed, pero no impide que arranquen los demás. Idempotente.
function Init:Run()
    if Init.initialized then
        return
    end
    Init.initialized = true
    Chronicle.version = ReadVersion()

    for _, name in ipairs(MODULE_ORDER) do
        local module = Chronicle[name]
        if module == nil then
            ReportFailure(name, "el módulo no está cargado (revisa el orden del .toc)")
        elseif type(module.Init) == "function" then
            local ok, err = pcall(module.Init, module)
            if not ok then
                ReportFailure(name, err)
            end
        end
    end

    Chronicle.Events:Emit("Chronicle.Initialized")
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
