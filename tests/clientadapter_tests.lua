-- Fase 17: abstracción inicial de ClientAdapter (EraAdapter + selector + marcador de Forever). Con un cliente SIMULADO: no demuestra nada sobre el cliente real.
-- Lo que se comprueba: identificación del GUID, valores secretos, lugar, capacidades, selección del cliente, comprobación del pack, y que NADA del runtime
-- (ni Core) conoce todavía el adaptador ni sus detalles.

LoadAddon()
local CA = Chronicle.ClientAdapter
local Era = Chronicle.EraAdapter

local GRELIN = "Creature-0-4379-0-2-786-0000045A7B"

-- Un valor «secreto» simulado: cualquier operación sobre él lanza error. Si el adaptador lo toca antes de preguntar a issecretvalue, la prueba falla.
local SECRET = setmetatable({}, {
    __index = function() error("se operó sobre un valor secreto (index)") end,
    __len = function() error("se operó sobre un valor secreto (len)") end,
    __concat = function() error("se operó sobre un valor secreto (concat)") end,
    __lt = function() error("se operó sobre un valor secreto (lt)") end,
    __call = function() error("se operó sobre un valor secreto (call)") end,
})

local function adapter(units, extra)
    local deps = {
        unitGuid = function(unit) local u = units[unit]; if u == "ERROR" then error("api rota") end return u and u.guid end,
        unitName = function(unit) local u = units[unit]; return u and u.name end,
        zoneText = function() return units.zone end,
        subZoneText = function() return units.subzone end,
        issecretvalue = function(v) return v == SECRET end,
    }
    for k, v in pairs(extra or {}) do deps[k] = v end
    return Era.New(deps)
end

-- ===================== constantes y contrato =====================
check("CA1. ClientFlavor tiene exactamente ERA, FOREVER y UNKNOWN",
    CA.FLAVOR.ERA == "ERA" and CA.FLAVOR.FOREVER == "FOREVER" and CA.FLAVOR.UNKNOWN == "UNKNOWN" and (function() local n = 0 for _ in pairs(CA.FLAVOR) do n = n + 1 end return n == 3 end)())
local a0 = adapter({})
check("CA2. EraAdapter cumple el contrato (todos los métodos existen) y es ERA",
    a0:GetFlavor() == "ERA" and (function()
        for _, m in ipairs({ "Matches", "IsSecretValue", "GetUnitGUID", "GetUnitName", "IdentifyUnit", "GetCurrentPlace", "GetInteractionContext", "GetCapabilities" }) do
            if type(a0[m]) ~= "function" then return false, m end
        end
        return true
    end)())

-- ===================== identificación de unidades =====================
local units = { target = { guid = GRELIN, name = "Grelin Whitebeard" } }
local ok1 = adapter(units):IdentifyUnit("target")
check("CA3. un GUID de criatura válido se identifica: tipo creature, npcID 786 y nombre",
    ok1.status == "identified" and ok1.kind == "creature" and ok1.npcID == 786 and ok1.name == "Grelin Whitebeard")
check("CA3b. sin nombre disponible se identifica igualmente por GUID (el nombre es opcional)",
    adapter({ target = { guid = GRELIN } }):IdentifyUnit("target").status == "identified" and adapter({ target = { guid = GRELIN } }):IdentifyUnit("target").name == nil)
check("CA4. jugador, mascota y objeto son «not_creature» y no dan npcID",
    adapter({ a = { guid = "Player-4379-0123ABCD" }, b = { guid = "Pet-0-4379-0-2-786-0000045A7B" }, c = { guid = "GameObject-0-4379-0-2-786-0000045A7B" } }):IdentifyUnit("a").status == "not_creature"
        and adapter({ b = { guid = "Pet-0-4379-0-2-786-0000045A7B" } }):IdentifyUnit("b").status == "not_creature"
        and adapter({ c = { guid = "GameObject-0-4379-0-2-786-0000045A7B" } }):IdentifyUnit("c").npcID == nil)
local function id(guid) return adapter({ u = { guid = guid } }):IdentifyUnit("u") end
check("CA5. un GUID mal formado no identifica nada (falla en seguro): faltan campos, campo vacío, npcID no numérico, cero o sobrante",
    id("Creature-0-4379-0-2-786").status == "unavailable" and id("Creature-0-4379-0-2--5-0000045A7B").status == "unavailable"
        and id("Creature-0-4379-0-2-abc-0000045A7B").status == "unavailable" and id("Creature-0-4379-0-2-0-0000045A7B").status == "unavailable"
        and id("Creature-0-4379-0-2-786-0000045A7B-x").status == "unavailable" and id("Creature-0-4379-0-2-786-0000045A7B").npcID == 786)
check("CA6. unidad inexistente, token no válido o error de API: «unavailable» sin lanzar error",
    adapter({}):IdentifyUnit("target").status == "unavailable" and adapter({}):IdentifyUnit(nil).status == "unavailable"
        and adapter({ target = "ERROR" }):IdentifyUnit("target").status == "unavailable" and adapter({ target = "ERROR" }):IdentifyUnit("target").reason == "api_error")

-- ===================== valores secretos =====================
local secretUnits = { target = { guid = SECRET, name = SECRET } }
local okS, resS = pcall(function() return adapter(secretUnits):IdentifyUnit("target") end)
check("CA7. un GUID SECRETO es «no identificable ahora»: sin error, sin npcID y sin tocar el valor (issecretvalue se pregunta ANTES de operar)",
    okS and resS.status == "not_identifiable_now" and resS.reason == "secret" and resS.npcID == nil)
local okN, nameS, whyS = pcall(function() return adapter(secretUnits):GetUnitName("target") end)
check("CA7b. un nombre SECRETO no se devuelve ni se opera: nil con motivo «secret»", okN and nameS == nil and whyS == "secret")
check("CA7c. IsSecretValue es false sin la API (cliente sin valores secretos) y nunca lanza error",
    adapter({}, { issecretvalue = false }):IsSecretValue(SECRET) == false and adapter({}, { issecretvalue = function() error("x") end }):IsSecretValue(1) == false)
check("CA7d. con issecretvalue ausente un valor que no es cadena se descarta como «unavailable» sin error (la última barrera es pcall, no el mecanismo principal)",
    (function()
        local ok, res = pcall(function() return adapter({ target = { guid = SECRET } }, { issecretvalue = false }):IdentifyUnit("target") end)
        return ok and res.status == "unavailable"
    end)())

-- ===================== lugar =====================
local place = adapter({ zone = "Dun Morogh", subzone = "Valle de Crestanevada" }):GetCurrentPlace()
check("CA8. el lugar actual devuelve zona y subzona tal como las da el cliente", place.zone == "Dun Morogh" and place.subzone == "Valle de Crestanevada")
check("CA8b. una subzona secreta o vacía se omite sin error; sin ningún dato: nil, «unavailable»",
    (function()
        local p = adapter({ zone = "Dun Morogh", subzone = SECRET }):GetCurrentPlace()
        local q, why = adapter({ zone = "", subzone = "" }):GetCurrentPlace()
        return p.zone == "Dun Morogh" and p.subzone == nil and q == nil and why == "unavailable"
    end)())

-- ===================== interacción y capacidades =====================
local ctx, ctxWhy = adapter({}):GetInteractionContext()
check("CA9. el contexto de interacción NO está implementado: no se asume ningún evento del cliente", ctx == nil and ctxWhy == "not_implemented")
local caps = adapter({}):GetCapabilities()
check("CA10. las capacidades declaran lo que el código sabe intentar: identidad y lugar sí; ninguna interacción",
    caps["unit_identity.target"].supported and caps["unit_identity.mouseover"].supported and caps["place.zone_text"].supported
        and not caps["interaction.gossip"].supported and not caps["interaction.quest"].supported and not caps["interaction.merchant"].supported)
check("CA10b. GetCapabilities devuelve una copia: modificarla no cambia el adaptador",
    (function() local c = adapter({}):GetCapabilities(); c["interaction.gossip"].supported = true; return adapter({}):GetCapabilities()["interaction.gossip"].supported == false end)())

-- ===================== selección del cliente =====================
local function selector(signals, adapters)
    return CA.New({ signals = function() return signals end, adapters = adapters or function() return { adapter({}), CA.NewForeverAdapter() } end })
end
local flavorEra, ad = selector({ projectId = 2, classicProjectId = 2, interface = 11507 }):Detect()
check("CA11. con proyecto e Interface de la familia de Era el cliente se detecta como ERA", flavorEra == "ERA" and ad ~= nil and ad:GetFlavor() == "ERA")
check("CA11b. un cambio de Interface dentro de la familia (11507 -> 11509) sigue siendo ERA", (selector({ projectId = 2, classicProjectId = 2, interface = 11509 }):Detect()) == "ERA")
local fUnk, adUnk, whyUnk = selector({ projectId = 1, classicProjectId = 2, interface = 99999 }):Detect()
check("CA12. un cliente que ningún adaptador reconoce es UNKNOWN (sin adaptador, con motivo), no se adivina", fUnk == "UNKNOWN" and adUnk == nil and whyUnk == "no_adapter_matches")
check("CA12b. NUNCA se detecta FOREVER: no hay soporte (el marcador no reconoce ningún cliente, ni por proyecto ni por Interface)",
    (selector({ projectId = 1, classicProjectId = 2, interface = 99999 }):Detect()) == "UNKNOWN"
        and (selector({ projectId = 2, classicProjectId = 2, interface = 99999 }):Detect()) == "UNKNOWN"
        and CA.NewForeverAdapter():Matches({ projectId = 2, classicProjectId = 2, interface = 11507 }) == false)
check("CA12c. una señal sola no basta: sin Interface, sin proyecto o sin señales => UNKNOWN",
    (selector({ projectId = 2, classicProjectId = 2 }):Detect()) == "UNKNOWN" and (selector({ interface = 11507 }):Detect()) == "UNKNOWN"
        and (CA.New({ signals = function() error("sin señales") end, adapters = {} }):Detect()) == "UNKNOWN")
check("CA12d. si varios adaptadores reconocen el cliente es «ambiguous»: UNKNOWN, no se elige uno",
    (function()
        local fl, _, why = selector({ projectId = 2, classicProjectId = 2, interface = 11507 }, function() return { adapter({}), adapter({}) } end):Detect()
        return fl == "UNKNOWN" and why == "ambiguous"
    end)())
local fo = CA.NewForeverAdapter()
check("CA13. el marcador de Forever no implementa nada: todo «not_implemented» y sin capacidades",
    fo:GetFlavor() == "FOREVER" and fo:IdentifyUnit("target").reason == "not_implemented" and select(2, fo:GetCurrentPlace()) == "not_implemented"
        and select(2, fo:GetInteractionContext()) == "not_implemented" and next(fo:GetCapabilities()) == nil)

-- ===================== comprobación del pack =====================
local eraSel = selector({ projectId = 2, classicProjectId = 2, interface = 11507 })
check("CA14. un pack de la versión correcta y de un esquema soportado es válido", eraSel:CheckPack({ pack_schema = 1, flavor = "era" }) == true)
check("CA14b. un pack de otra versión (incluido un flavor ficticio) se rechaza: flavor_mismatch",
    select(2, eraSel:CheckPack({ pack_schema = 1, flavor = "forever" })) == "flavor_mismatch" and select(2, eraSel:CheckPack({ pack_schema = 1, flavor = "fixture_alt" })) == "flavor_mismatch")
check("CA14c. esquema desconocido, sin cabecera o cliente desconocido => modo seguro con su motivo",
    select(2, eraSel:CheckPack({ pack_schema = 2, flavor = "era" })) == "pack_schema_unsupported" and select(2, eraSel:CheckPack(nil)) == "no_header"
        and select(2, eraSel:CheckPack({ flavor = "era" })) == "pack_schema_unsupported"
        and select(2, selector({ projectId = 1, classicProjectId = 2, interface = 99999 }):CheckPack({ pack_schema = 1, flavor = "era" })) == "unknown_client")

-- ===================== aislamiento: el runtime no lo conoce todavía =====================
local function sourceOf(name) for _, f in ipairs(ADDON_FILES) do if f.name == name then return f.source end end end
check("CA15. Core NO conoce nada del cliente que el adaptador encapsula: GUID, npcID, UnitGUID/UnitName, zonas, secretos ni el propio adaptador",
    (function()
        for _, f in ipairs(ADDON_FILES) do
            if f.name:sub(1, 5) == "Core/" then
                for _, word in ipairs({ "Creature-", "npcID", "UnitGUID", "UnitName", "GetRealZoneText", "GetSubZoneText", "issecretvalue", "ClientAdapter", "EraAdapter" }) do
                    if f.source:find(word, 1, true) then return false, f.name .. ": " .. word end
                end
            end
        end
        return true
    end)())
check("CA16. ningún módulo del addon usa todavía el adaptador (abstracción inicial: no está conectada al runtime)",
    (function()
        for _, f in ipairs(ADDON_FILES) do
            if f.name ~= "Services/ClientAdapter.lua" and f.name ~= "Services/EraAdapter.lua" and (f.source:find("ClientAdapter", 1, true) or f.source:find("EraAdapter", 1, true)) then
                return false, f.name
            end
        end
        return true
    end)())
check("CA17. el adaptador no se registra en Init (no hay nada que inicializar) y cargarlo no cambia el arranque",
    (function()
        local ok = pcall(function() FireEvent("ADDON_LOADED", "Chronicle") end)
        return ok and Chronicle.Init.failed.ClientAdapter == nil and Chronicle.Init.failed.EraAdapter == nil and Chronicle.Init.ready == true
    end)())
check("CA18. los ficheros del adaptador no usan construcciones ajenas a Lua 5.1 ni referencian la SavedVariable",
    (function()
        for _, name in ipairs({ "Services/EraAdapter.lua", "Services/ClientAdapter.lua" }) do
            local src = sourceOf(name):gsub("%-%-[^\n]*", "")
            for _, bad in ipairs({ "goto ", "ChronicleCharDB", "\\x", "\\z", "\\u{" }) do
                if src:find(bad, 1, true) then return false, name .. ": " .. bad end
            end
        end
        return true
    end)())
