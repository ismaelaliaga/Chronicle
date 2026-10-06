Chronicle = Chronicle or {}

-- ClientAdapter: selector del adaptador de cliente (Fase 17, abstracción INICIAL; aún NO está conectado al runtime). Decide en qué cliente estamos a
-- partir de varias señales independientes (Fase 15.1, D5: nunca solo WOW_PROJECT_ID ni solo Interface) y comprueba que un pack generado corresponde a
-- ese cliente. El contrato de cada adaptador está en Services/EraAdapter.lua.
--
--   ClientFlavor: "ERA" | "FOREVER" | "UNKNOWN"      (UNKNOWN es un estado del RUNTIME, nunca un valor de datos)
--   selector:Detect()          -> flavor, adaptador | nil, motivo     UNKNOWN si ningún adaptador reconoce el cliente o si lo reconocen varios (no se adivina)
--   selector:CheckPack(header) -> true | false, motivo                 motivos: no_header, pack_schema_unsupported, unknown_client, flavor_mismatch
--                                 Un fallo aquí lleva al MODO SEGURO: no se activan descubrimiento ni datos del pack y se informa (Init.failed). Qué cubre
--                                 exactamente el modo seguro es una decisión pendiente (Fase 15.1, R11): este módulo solo da el veredicto.
--
-- FOREVER: NO hay soporte. ForeverAdapter es un marcador explícito: no reconoce ningún cliente y todas sus operaciones devuelven «not_implemented». Los
-- valores observados en la beta (Interface, tipo de juego...) son provisionales y NO se asumen: se implementará con un cliente real (Fase 15.1, 5.3).

local FLAVOR = { ERA = "ERA", FOREVER = "FOREVER", UNKNOWN = "UNKNOWN" }

-- Identificador de versión del pack (cabecera generada) para cada ClientFlavor.
local PACK_FLAVOR = { ERA = "era", FOREVER = "forever" }

-- Versiones del esquema de pack que este addon sabe cargar.
local SUPPORTED_PACK_SCHEMAS = { [1] = true }

local function NewForeverAdapter()
    local self = {}
    function self:GetFlavor() return FLAVOR.FOREVER end
    function self:Matches() return false, "not_implemented" end
    function self:IsSecretValue() return false end
    function self:GetUnitGUID() return nil, "not_implemented" end
    function self:GetUnitName() return nil, "not_implemented" end
    function self:IdentifyUnit() return { status = "unavailable", reason = "not_implemented" } end
    function self:GetCurrentPlace() return nil, "not_implemented" end
    function self:GetInteractionContext() return nil, "not_implemented" end
    function self:GetCapabilities() return {} end
    return self
end

-- Señales por defecto: se leen de los globales del cliente EN EL MOMENTO de detectar (pueden no existir).
local function DefaultSignals()
    local signals = { projectId = _G.WOW_PROJECT_ID, classicProjectId = _G.WOW_PROJECT_CLASSIC }
    if type(_G.GetBuildInfo) == "function" then
        local ok, _, _, _, interface = pcall(_G.GetBuildInfo)
        if ok then
            signals.interface = interface
        end
    end
    return signals
end

local function NewSelector(deps)
    deps = type(deps) == "table" and deps or {}
    local adapters = deps.adapters
    local getSignals = deps.signals or DefaultSignals
    local self = {}

    function self:Detect()
        local list = type(adapters) == "function" and adapters() or adapters or {}
        local ok, signals = pcall(getSignals)
        if not ok or type(signals) ~= "table" then
            return FLAVOR.UNKNOWN, nil, "no_signals"
        end
        local matches = {}
        for _, adapter in ipairs(list) do
            local okMatch, matched = pcall(adapter.Matches, adapter, signals)
            if okMatch and matched == true then
                matches[#matches + 1] = adapter
            end
        end
        if #matches == 1 then
            return matches[1]:GetFlavor(), matches[1]
        elseif #matches == 0 then
            return FLAVOR.UNKNOWN, nil, "no_adapter_matches"
        end
        return FLAVOR.UNKNOWN, nil, "ambiguous" -- varios reconocen el cliente: no se adivina
    end

    function self:CheckPack(header)
        if type(header) ~= "table" then
            return false, "no_header"
        end
        if type(header.pack_schema) ~= "number" or not SUPPORTED_PACK_SCHEMAS[header.pack_schema] then
            return false, "pack_schema_unsupported"
        end
        local flavor = self:Detect()
        if flavor == FLAVOR.UNKNOWN then
            return false, "unknown_client"
        end
        if PACK_FLAVOR[flavor] ~= header.flavor then
            return false, "flavor_mismatch"
        end
        return true
    end

    return self
end

Chronicle.ClientAdapter = {
    FLAVOR = FLAVOR,
    New = NewSelector,
    NewForeverAdapter = NewForeverAdapter,
    DefaultSignals = DefaultSignals,
}

-- Instancia por defecto (Era + el marcador de Forever). No la usa ningún módulo todavía.
Chronicle.ClientAdapter.Default = NewSelector({
    adapters = function()
        return { Chronicle.EraAdapter.New(), NewForeverAdapter() }
    end,
})
