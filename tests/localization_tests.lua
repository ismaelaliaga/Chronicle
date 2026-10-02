-- Escenarios de prueba de Localization (Fase 4): textos migrados con los datos reales, y el
-- contrato de la API (fallback, errores, aislamiento) con instancias propias y datos de ejemplo.
-- La referencia de los textos es LegacyReference (tests/fixtures/legacy_reference.lua), una copia
-- literal de los datos del addon original; se compara con == sin normalizar nada.

local Ref = LegacyReference
local FIELDS = { "name", "description", "hint", "race", "role" }

local function snapshotRegistry(registry) return registry:GetAll() end

-- Arranca el addon completo con los datos reales.
local function Boot(prepare)
    LoadAddon()
    ChronicleCharDB = nil
    if prepare then prepare() end
    local announced = 0
    Chronicle.Events:Register("Chronicle.Initialized", function() announced = announced + 1 end)
    FireEvent("ADDON_LOADED", "Chronicle")
    return announced
end

-- ===================== Datos reales (esES) =====================
local announced = Boot()
local Loc = Chronicle.Localization
local Registry = Chronicle.Registry

check("Localization está inicializada y el arranque se anuncia con los módulos requeridos listos",
    Loc:IsReady() == true and Chronicle.Init.ready == true and announced == 1 and next(Chronicle.Init.failed) == nil)
check("el único idioma disponible es esES (no hay traducciones inventadas a otros)",
    table.concat(Loc:GetLanguages(), ",") == "esES" and Loc:HasLanguage("esES") and not Loc:HasLanguage("enUS"))
check("el idioma predeterminado es esES", Loc:GetDefaultLanguage() == "esES")
check("hay entradas de esES para las 53 entidades registradas, y ninguna para un ID que no exista",
    #Loc:GetIds("esES") == 53 and (function()
        for _, id in ipairs(Loc:GetIds("esES")) do if not Registry:Has(id) then return false end end
        return true
    end)())

local report = Loc:Validate()
check("Localization:Validate() del conjunto real: sin errores ni advertencias",
    report.ok == true and #report.errors == 0 and #report.warnings == 0, table.concat(report.errors, " | "))

-- Recuperación de nombre, descripción y pista de varias entidades
local sub = Ref.zones["Dun Morogh"].subzones["Coldridge Valley"]
check("subzona: nombre, descripción y pista de Coldridge Valley, idénticos a la fuente",
    Loc:Get("subzone:coldridge_valley", "name") == "Coldridge Valley"
        and Loc:Get("subzone:coldridge_valley", "description") == sub.text
        and Loc:Get("subzone:coldridge_valley", "hint") == sub.hint)
check("zona: nombre y descripción de Loch Modan idénticos a la fuente; una zona no tiene pista ni raza ni rol",
    Loc:Get("zone:loch_modan", "name") == "Loch Modan"
        and Loc:Get("zone:loch_modan", "description") == Ref.zones["Loch Modan"].text
        and Loc:Get("zone:loch_modan", "hint") == nil and Loc:Get("zone:loch_modan", "race") == nil
        and Loc:Get("zone:loch_modan", "role") == nil)
check("ciudad: el nombre es 'Ironforge' (tal como en la fuente) y la descripción menciona 'Forjaz'",
    Loc:Get("city:ironforge", "name") == "Ironforge"
        and Loc:Get("city:ironforge", "description") == Ref.cities["Ironforge"].text
        and Loc:Get("city:ironforge", "description"):find("Forjaz", 1, true) ~= nil)
check("continente: el nombre está en español, como en la fuente",
    Loc:Get("continent:eastern_kingdoms", "name") == "Reinos del Este"
        and Loc:Get("continent:eastern_kingdoms", "description") == Ref.continents["Reinos del Este"].text)

-- race y role de los NPC
local npcExpect = {
    ["npc:grelin_whitebeard"] = { "Gnomo", "Superviviente de Gnomeregan" },
    ["npc:sten_stoutarm"] = { "Enano", "Cartero de Anvilmar" },
    ["npc:king_magni_bronzebeard"] = { "Enano", "Rey de Forjaz" },
    ["npc:high_tinker_mekkatorque"] = { "Gnomo", "Alto Manitas (líder del gobierno gnomo en el exilio)" },
}
check("race y role de NPC concretos, escritos a mano a partir de la fuente",
    (function()
        for id, want in pairs(npcExpect) do
            if Loc:Get(id, "race") ~= want[1] or Loc:Get(id, "role") ~= want[2] then return false, id end
        end
        return true
    end)())
check("race y role de los 9 NPC idénticos a la fuente; sus nombres, descripciones y pistas también",
    (function()
        local n = 0
        for _, area in pairs({ Ref.zones["Dun Morogh"], Ref.zones["Loch Modan"], Ref.cities["Ironforge"] }) do
            for _, s in pairs(area.subzones) do
                for _, npc in ipairs(s.npcs or {}) do
                    local id = "npc:" .. npc.name:lower():gsub("[^a-z0-9]+", "_")
                    if Loc:Get(id, "name") ~= npc.name or Loc:Get(id, "description") ~= npc.text
                        or Loc:Get(id, "hint") ~= npc.hint or Loc:Get(id, "race") ~= npc.race
                        or Loc:Get(id, "role") ~= npc.role then
                        return false, npc.name
                    end
                    n = n + 1
                end
            end
        end
        return n == 9
    end)())
check("race y role solo existen en los NPC (ninguna otra entidad los tiene)",
    (function()
        for _, id in ipairs(Registry:GetIds()) do
            if Registry:Get(id).type ~= "npc" and (Loc:Get(id, "race") ~= nil or Loc:Get(id, "role") ~= nil) then
                return false
            end
        end
        return true
    end)())

-- Preservación exacta de textos representativos
check("preservación exacta: apóstrofos, tildes, guiones, paréntesis y puntuación originales",
    Loc:Get("subzone:golbolar_quarry", "name") == "Gol'Bolar Quarry"
        and Loc:Get("subzone:ironbands_excavation_site", "name") == "Ironband's Excavation Site"
        and Loc:Get("subzone:mogrosh_stronghold", "name") == "Mo'grosh Stronghold"
        and Loc:Get("subzone:steelgrills_depot", "name") == "Steelgrill's Depot"
        and Loc:Get("subzone:helms_bed_lake", "name") == "Helm's Bed Lake"
        and Loc:Get("npc:chief_engineer_hinderweir_vii", "name") == "Chief Engineer Hinderweir VII"
        and Loc:Get("npc:high_tinker_mekkatorque", "role") == "Alto Manitas (líder del gobierno gnomo en el exilio)"
        and Loc:Get("subzone:the_tundrid_hills", "description"):find("centro-sur de Dun Morogh", 1, true) ~= nil
        and Loc:Get("subzone:ironforge_airfield", "description"):find("inventivo -y algo temerario- de", 1, true) ~= nil
        and Loc:Get("subzone:coldridge_valley", "description"):find("Es un lugar pequeño pero cargado de historia", 1, true) ~= nil)
check("preservación exacta: los 53 conjuntos de campos coinciden carácter a carácter con la referencia",
    (function()
        local checked = 0
        local function same(id, entry)
            if Loc:Get(id, "name") ~= entry.name then return false end
            if Loc:Get(id, "description") ~= entry.text then return false end
            if Loc:Get(id, "hint") ~= entry.hint then return false end
            checked = checked + 1
            return true
        end
        if not same("continent:eastern_kingdoms", { name = "Reinos del Este", text = Ref.continents["Reinos del Este"].text }) then return false end
        local placeIds = { ["Dun Morogh"] = "zone:dun_morogh", ["Loch Modan"] = "zone:loch_modan", ["Ironforge"] = "city:ironforge" }
        for name, id in pairs(placeIds) do
            local place = Ref.zones[name] or Ref.cities[name]
            if not same(id, { name = name, text = place.text }) then return false end
        end
        return checked == 4
    end)())
check("preservación exacta con la referencia directa: ninguna descripción de subzona cambia (40 comprobaciones)",
    (function()
        local n = 0
        local ids = {}
        for _, id in ipairs(Registry:GetIds("subzone")) do ids[id] = true end
        for _, area in pairs({ Ref.zones["Dun Morogh"], Ref.zones["Loch Modan"], Ref.cities["Ironforge"] }) do
            for subName, s in pairs(area.subzones) do
                local id = "subzone:" .. subName:lower():gsub("'", ""):gsub("[^a-z0-9]+", "_")
                if not ids[id] or Loc:Get(id, "name") ~= subName or Loc:Get(id, "description") ~= s.text
                    or Loc:Get(id, "hint") ~= s.hint then
                    return false, subName
                end
                n = n + 1
            end
        end
        return n == 40
    end)())

-- Fallback y ausencia de traducciones inventadas con los datos reales
local text, used = Loc:Get("zone:dun_morogh", "name", "enUS")
check("pedir un idioma sin datos (enUS) cae al predeterminado y lo indica; no se inventa una traducción",
    text == "Dun Morogh" and used == "esES" and Loc:GetExact("zone:dun_morogh", "name", "enUS") == nil
        and Loc:GetExact("zone:dun_morogh", "description", "enUS") == nil
        and Loc:Get("zone:dun_morogh", "description", "enUS") == Ref.zones["Dun Morogh"].text)
check("un idioma desconocido o mal formado se comporta como uno sin entradas (no es un error)",
    Loc:Get("zone:dun_morogh", "name", "xxXX") == "Dun Morogh" and Loc:Get("zone:dun_morogh", "name", "klingon") == "Dun Morogh"
        and Loc:GetExact("zone:dun_morogh", "name", "xxXX") == nil)
check("Get devuelve el idioma del que salió el texto",
    select(2, Loc:Get("zone:dun_morogh", "name")) == "esES" and select(2, Loc:Get("zone:dun_morogh", "name", "esES")) == "esES")

-- ID inexistente, campo inexistente, campo ausente
check("ID inexistente -> nil (con y sin idioma)", Loc:Get("zone:no_existe", "name") == nil
    and Loc:Get("zone:no_existe", "name", "esES") == nil and Loc:Get("npc:grelin", "name") == nil)
check("un ID con formato inválido o que no es cadena -> nil, sin error",
    Loc:Get("Dun Morogh", "name") == nil and Loc:Get(nil, "name") == nil and Loc:Get(42, "name") == nil and Loc:Get({}, "name") == nil)
check("campo inexistente (no está entre los de presentación) -> nil, sin error",
    Loc:Get("zone:dun_morogh", "title") == nil and Loc:Get("zone:dun_morogh", "npcID") == nil
        and Loc:Get("zone:dun_morogh", "") == nil and Loc:Get("zone:dun_morogh", nil) == nil and Loc:Get("zone:dun_morogh", 1) == nil)
check("campo que existe pero la entidad no tiene en ningún idioma -> nil (hint de una zona)",
    Loc:Get("zone:dun_morogh", "hint") == nil and Loc:Get("zone:dun_morogh", "hint", "enUS") == nil)
check("un idioma que no es cadena -> nil", Loc:Get("zone:dun_morogh", "name", 5) == nil and Loc:Get("zone:dun_morogh", "name", {}) == nil)

-- Idioma predeterminado configurable
check("no se puede fijar como predeterminado un idioma sin textos, y el predeterminado no cambia",
    (function()
        local ok, err = Loc:SetDefaultLanguage("enUS")
        return ok == false and type(err) == "string" and Loc:GetDefaultLanguage() == "esES"
            and Loc:SetDefaultLanguage(nil) == false and Loc:SetDefaultLanguage("") == false
    end)())
check("se puede fijar un idioma con textos como predeterminado (esES)", Loc:SetDefaultLanguage("esES") == true)

-- Aislamiento: consultar no modifica el Registry ni a Localization
Boot()
Loc, Registry = Chronicle.Localization, Chronicle.Registry
local beforeEntities = snapshotRegistry(Registry)
local beforeIds = Registry:GetIds()
local beforeText = {}
for _, id in ipairs(Loc:GetIds("esES")) do
    beforeText[id] = {}
    for _, f in ipairs(FIELDS) do beforeText[id][f] = Loc:Get(id, f) end
end
for _, id in ipairs(Registry:GetIds()) do
    for _, f in ipairs(FIELDS) do Loc:Get(id, f); Loc:Get(id, f, "enUS"); Loc:GetExact(id, f, "esES") end
end
Loc:Get("zone:no_existe", "name"); Loc:Get("zone:dun_morogh", "title"); Loc:GetLanguages(); Loc:GetIds("esES")
local mutated = Loc:GetIds("esES"); mutated[1] = "roto"; table.insert(mutated, "otro")
local mutatedLangs = Loc:GetLanguages(); mutatedLangs[1] = "roto"
local afterText = {}
for _, id in ipairs(Loc:GetIds("esES")) do
    afterText[id] = {}
    for _, f in ipairs(FIELDS) do afterText[id][f] = Loc:Get(id, f) end
end
check("consultar textos no modifica el Registry (entidades ni listados)",
    deepEqual(beforeEntities, snapshotRegistry(Registry)) and deepEqual(beforeIds, Registry:GetIds())
        and Registry:Count() == 53 and #Registry:GetRejected() == 0)
check("consultar y manipular lo devuelto no altera los textos guardados",
    deepEqual(beforeText, afterText) and Loc:GetLanguages()[1] == "esES" and #Loc:GetIds("esES") == 53)
check("las entidades canónicas no contienen ningún texto de presentación (ni name, description, hint, race, role)",
    (function()
        for _, e in ipairs(Registry:GetAll()) do
            for _, f in ipairs(FIELDS) do if e[f] ~= nil then return false end end
        end
        return true
    end)())
check("ningún dato de presentación se escribe en ChronicleCharDB",
    deepEqual(ChronicleCharDB, { schemaVersion = 1, discovery = { entries = {} } }))

-- ===================== Contrato de la API (instancias propias) =====================
local function NewWorld()
    local reg = Chronicle.Registry.New(Chronicle.Schema)
    for _, id in ipairs({ "alpha", "beta", "gamma" }) do
        assert(reg:Register({ id = "continent:" .. id, type = "continent" }))
    end
    return reg, Chronicle.Localization.New(reg)
end

local reg, loc = NewWorld()
local entryEs = { name = "Alfa", description = "Descripción en español.", hint = "Pista en español." }
local entryEn = { name = "Alpha" }
check("Add acepta entradas válidas", loc:Add("esES", "continent:alpha", entryEs) == true
    and loc:Add("enUS", "continent:alpha", entryEn) == true and loc:Add("esES", "continent:beta", { name = "Beta" }) == true)
check("Add no modifica la entrada recibida, y cambiarla después no altera lo guardado",
    (function()
        local copyEs = Chronicle.Utils.DeepCopy(entryEs)
        local ok = deepEqual(entryEs, copyEs)
        entryEs.name = "CAMBIADO"
        local same = loc:Get("continent:alpha", "name", "esES") == "Alfa"
        entryEs.name = "Alfa"
        return ok and same
    end)())
check("los idiomas con entradas salen ordenados", table.concat(loc:GetLanguages(), ",") == "enUS,esES")
check("GetIds(idioma) lista solo los IDs de ese idioma, ordenados",
    table.concat(loc:GetIds("esES"), ",") == "continent:alpha,continent:beta"
        and table.concat(loc:GetIds("enUS"), ",") == "continent:alpha" and #loc:GetIds("deDE") == 0 and #loc:GetIds(nil) == 0)

-- Fallback por campo
local v, l = loc:Get("continent:alpha", "name", "enUS")
check("fallback por campo: el campo presente en el idioma pedido se usa tal cual", v == "Alpha" and l == "enUS")
v, l = loc:Get("continent:alpha", "description", "enUS")
check("fallback por campo: el campo que falta en enUS sale del idioma predeterminado", v == "Descripción en español." and l == "esES")
v, l = loc:Get("continent:alpha", "hint", "enUS")
check("el fallback es por campo y no sustituye la entrada entera: el nombre sigue siendo el de enUS",
    v == "Pista en español." and l == "esES" and loc:Get("continent:alpha", "name", "enUS") == "Alpha")
v, l = loc:Get("continent:beta", "name", "enUS")
check("una entidad sin entrada en el idioma pedido cae al predeterminado", v == "Beta" and l == "esES")
check("un campo que no está en ningún idioma devuelve nil, no una cadena inventada",
    loc:Get("continent:alpha", "race", "enUS") == nil and loc:Get("continent:beta", "role") == nil
        and loc:Get("continent:beta", "description", "enUS") == nil)
check("GetExact no hace fallback", loc:GetExact("continent:alpha", "description", "enUS") == nil
    and loc:GetExact("continent:alpha", "description", "esES") == "Descripción en español."
    and loc:GetExact("continent:alpha", "name", "deDE") == nil and loc:GetExact("continent:alpha", "name", nil) == nil)
check("sin idioma se usa el predeterminado", loc:Get("continent:alpha", "name") == "Alfa")

-- El fallback solo va al idioma predeterminado, sin cadenas ni ciclos
check("se puede cambiar el idioma predeterminado a otro con textos", loc:SetDefaultLanguage("enUS") == true
    and loc:GetDefaultLanguage() == "enUS" and loc:Get("continent:alpha", "name") == "Alpha")
check("el fallback solo apunta al predeterminado: con enUS como predeterminado, un campo que falta ahí es nil (no vuelve a esES)",
    loc:Get("continent:alpha", "description") == nil and loc:Get("continent:alpha", "description", "esES") == "Descripción en español."
        and loc:Get("continent:alpha", "description", "enUS") == nil and loc:Get("continent:beta", "name", "esES") == "Beta"
        and loc:Get("continent:beta", "name") == nil)
loc:SetDefaultLanguage("esES")

-- Cadena vacía frente a campo ausente
loc:Add("esES", "continent:gamma", { name = "Gamma", hint = "Pista" })
loc:Add("enUS", "continent:gamma", { name = "", description = "" })
v, l = loc:Get("continent:gamma", "name", "enUS")
check("una cadena vacía es un valor, no una ausencia: se devuelve '' y NO cae al predeterminado", v == "" and l == "enUS")
check("un campo ausente en cambio sí cae al predeterminado", loc:Get("continent:gamma", "hint", "enUS") == "Pista")
local gammaReport = loc:Validate()
check("Validate avisa de los valores vacíos como advertencias (no los oculta) y no los trata como error",
    gammaReport.ok == true and #gammaReport.warnings == 2 and contains(gammaReport.warnings, "name es una cadena vacía")
        and contains(gammaReport.warnings, "description es una cadena vacía"))

-- Rechazos de Add
local rejectedBefore = #loc:GetRejected()
local cases = {
    { "código de idioma sin formato xxXX", { "es", "continent:alpha", { name = "x" } } },
    { "código de idioma en mayúsculas", { "ESES", "continent:alpha", { name = "x" } } },
    { "código de idioma con la región en minúsculas", { "esEs", "continent:alpha", { name = "x" } } },
    { "idioma que no es cadena", { 5, "continent:alpha", { name = "x" } } },
    { "ID que no es cadena", { "deDE", nil, { name = "x" } } },
    { "ID vacío", { "deDE", "", { name = "x" } } },
    { "entrada que no es tabla", { "deDE", "continent:alpha", "texto" } },
    { "entrada vacía", { "deDE", "continent:alpha", {} } },
    { "campo desconocido", { "deDE", "continent:alpha", { name = "x", title = "y" } } },
    { "campo con clave que no es cadena", { "deDE", "continent:alpha", { "x" } } },
    { "valor que no es cadena", { "deDE", "continent:alpha", { name = 5 } } },
    { "valor tabla", { "deDE", "continent:alpha", { name = { "x" } } } },
}
for _, case in ipairs(cases) do
    local ok, err = loc:Add(unpack(case[2], 1, 3))
    check("Add rechaza: " .. case[1], ok == false and type(err) == "string" and err ~= "", tostring(err))
end
check("lo rechazado no crea ningún idioma ni entrada", not loc:HasLanguage("deDE") and #loc:GetIds("deDE") == 0)
check("cada rechazo queda anotado en GetRejected", #loc:GetRejected() - rejectedBefore == #cases)
local dupOk, dupErr = loc:Add("esES", "continent:alpha", { name = "Intruso" })
check("un (idioma, ID) repetido se rechaza y NO sobrescribe la entrada original",
    dupOk == false and dupErr:find("duplicada", 1, true) ~= nil and loc:Get("continent:alpha", "name", "esES") == "Alfa")
check("el mensaje de campo desconocido indica los campos admitidos",
    contains({ select(2, loc:Add("deDE", "continent:alpha", { title = "x" })) }, "admitidos: description, hint, name, race, role"))

-- Validate / Init
check("los rechazos de Add son errores de Validate, y Init falla con un mensaje descriptivo",
    loc:Validate().ok == false and #loc:Validate().errors == #loc:GetRejected()
        and not pcall(loc.Init, loc) and loc:IsReady() == false)
local okInit, errInit = pcall(loc.Init, loc)
check("el error de Init nombra el problema", okInit == false and tostring(errInit):find("Localization: validación fallida", 1, true) ~= nil
    and tostring(errInit):find("problema(s)", 1, true) ~= nil)

local reg2, loc2 = NewWorld()
loc2:Add("esES", "continent:alpha", { name = "Alfa" })
loc2:Add("esES", "continent:fantasma", { name = "Huérfano" })
check("un texto de un ID que no está en el Registry es un error de Validate y no se puede consultar",
    loc2:Validate().ok == false and contains(loc2:Validate().errors, "continent:fantasma")
        and loc2:Get("continent:fantasma", "name") == nil and loc2:GetExact("continent:fantasma", "name", "esES") == nil)

local reg3, loc3 = NewWorld()
loc3:Add("enUS", "continent:alpha", { name = "Alpha" })
check("con textos registrados pero ninguno en el idioma predeterminado, Validate lo señala",
    loc3:Validate().ok == false and contains(loc3:Validate().errors, "idioma predeterminado esES no tiene textos"))
check("... y Get no inventa nada: sin entrada en el predeterminado ni en el pedido, nil",
    loc3:Get("continent:beta", "name", "enUS") == nil and loc3:Get("continent:alpha", "name", "esES") == nil)
loc3:SetDefaultLanguage("enUS")
check("fijar el predeterminado a un idioma que sí tiene textos resuelve ese error", loc3:Validate().ok == true)

local reg4, loc4 = NewWorld()
check("sin ningún idioma registrado Localization es válida y se inicializa", loc4:Validate().ok == true
    and pcall(loc4.Init, loc4) and loc4:IsReady() == true and loc4:Get("continent:alpha", "name") == nil
    and #loc4:GetLanguages() == 0)
loc4:Add("esES", "continent:alpha", { name = "Alfa" })
check("añadir una entrada invalida el estado 'listo' hasta la siguiente inicialización", loc4:IsReady() == false)
check("Localization.New exige un Registry", not pcall(Chronicle.Localization.New, nil) and not pcall(Chronicle.Localization.New, {}))

-- Determinismo: el orden de inserción no cambia los resultados
local regA, locA = NewWorld()
local regB, locB = NewWorld()
local items = {
    { "esES", "continent:alpha", { name = "Alfa", hint = "h" } }, { "enUS", "continent:alpha", { name = "Alpha" } },
    { "esES", "continent:beta", { name = "Beta" } }, { "deDE", "continent:gamma", { name = "Gamma" } },
}
for i = 1, #items do locA:Add(unpack(items[i], 1, 3)) end
for i = #items, 1, -1 do locB:Add(unpack(items[i], 1, 3)) end
check("el orden de carga no cambia los idiomas, los IDs ni los textos",
    table.concat(locA:GetLanguages(), ",") == table.concat(locB:GetLanguages(), ",")
        and table.concat(locA:GetIds("esES"), ",") == table.concat(locB:GetIds("esES"), ",")
        and locA:Get("continent:alpha", "hint", "enUS") == locB:Get("continent:alpha", "hint", "enUS")
        and locA:Get("continent:beta", "name", "enUS") == locB:Get("continent:beta", "name", "enUS")
        and deepEqual(locA:Validate(), locB:Validate()))

-- Integración con el arranque
announced = Boot(function() Chronicle.Localization:Add("esES", "npc:fantasma", { name = "Sin entidad" }) end)
check("un texto huérfano (ID inexistente) en los datos impide anunciar el arranque y queda diagnosticado",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Localization ~= nil
        and Chronicle.Init.failed.Localization:find("npc:fantasma", 1, true) ~= nil and Chronicle.Localization:IsReady() == false
        and contains(ReportedErrors, "Localization"))
announced = Boot(function() Chronicle.Localization:Add("esES", "zone:dun_morogh", { name = "Otro nombre" }) end)
check("un texto duplicado de un dato migrado impide anunciar el arranque y no sobrescribe el original",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Localization:find("duplicada", 1, true) ~= nil
        and Chronicle.Localization:Get("zone:dun_morogh", "name") == "Dun Morogh")
announced = Boot(function() Chronicle.Localization:Add("klingon", "zone:dun_morogh", { name = "x" }) end)
check("un código de idioma inválido en los datos impide anunciar el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Localization ~= nil)
announced = Boot(function() Chronicle.Localization = nil end)
check("Localization ausente: se diagnostica como no cargada y no se anuncia el arranque",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Localization:find("no está cargado", 1, true) ~= nil)
announced = Boot(function() Chronicle.Localization.Init = function() error("localization rota") end end)
check("un Localization:Init que lanza error deja Init.ready en false",
    Chronicle.Init.ready == false and announced == 0 and Chronicle.Init.failed.Localization:find("localization rota", 1, true) ~= nil)
check("los fallos de Localization no impiden que los módulos independientes se inicialicen",
    Chronicle.State:IsReady() == true and SlashCmdList["CHRONICLE"] ~= nil)

-- Sin datos reales (Fases 2 y 3 cargadas, sin Localization/esES): sigue arrancando
announced = (function()
    LoadAddon({ "^Data/Entities/", "^Localization/esES/" })
    ChronicleCharDB = nil
    local n = 0
    Chronicle.Events:Register("Chronicle.Initialized", function() n = n + 1 end)
    FireEvent("ADDON_LOADED", "Chronicle")
    return n
end)()
check("sin ficheros de datos el addon arranca igualmente (Localization y Resolver vacíos son válidos)",
    Chronicle.Init.ready == true and announced == 1 and Chronicle.Localization:IsReady() and Chronicle.Resolver:IsReady())

-- Orden de carga y aislamiento del estado persistente
local order = {}
for i, file in ipairs(ADDON_FILES) do order[file.name] = i end
check("orden de carga: Registry < Localization < Resolver < ficheros esES < Init (y Init el último)",
    order["Data/Registry.lua"] < order["Localization/Localization.lua"]
        and order["Localization/Localization.lua"] < order["Services/Resolver.lua"]
        and order["Services/Resolver.lua"] < order["Localization/esES/EasternKingdoms.lua"]
        and order["Localization/esES/Aliases.lua"] < order["Core/Init.lua"] and order["Core/Init.lua"] == #ADDON_FILES)
check("todos los ficheros de presentación se cargan antes de Core/Init.lua",
    (function()
        for name, position in pairs(order) do
            if name:find("^Localization/") and position > order["Core/Init.lua"] then return false end
        end
        return true
    end)())
-- Fase 5: Services/Discovery.lua usa Chronicle.State como API de persistencia (es su cometido), así que
-- queda exento de la mitad "Chronicle.State"; la prohibición de ChronicleCharDB sigue valiendo para todos.
check("ningún fichero de Localization ni de Services referencia ChronicleCharDB en su código, ni Chronicle.State salvo Services/Discovery.lua",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name:find("^Localization/") or file.name:find("^Services/") then
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") and (line:find("ChronicleCharDB", 1, true)
                        or (file.name ~= "Services/Discovery.lua" and line:find("Chronicle.State", 1, true))) then
                        return false, file.name
                    end
                end
            end
        end
        return true
    end)())
check("los ficheros de Localization/esES solo registran a través de la API (Localization:Add y Resolver:AddAlias)",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name:find("^Localization/esES/") then
                local inEntry = false
                for line in file.source:gmatch("[^\n]+") do
                    if line:match("^Localization:Add%(") then inEntry = true end
                    if not inEntry and not line:match("^%s*%-%-") and line:find("%S")
                        and not line:match("^Chronicle = Chronicle or {}$")
                        and not line:match("^local Localization = Chronicle%.Localization$")
                        and not line:match("^local Resolver = Chronicle%.Resolver$")
                        and not line:match("^Resolver:AddAlias%(") and not line:match("^Localization:Add%(") then
                        return false, file.name .. ": " .. line
                    end
                    if line == "})" then inEntry = false end
                end
            end
        end
        return true
    end)())
