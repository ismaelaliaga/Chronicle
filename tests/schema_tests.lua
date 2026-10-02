-- Escenarios de prueba del Schema de entidades (Fase 2). Usan entidades de ejemplo con
-- IDs ilustrativos: no son datos del addon (los datos reales llegan en la Fase 3).

LoadAddon()
local Schema = Chronicle.Schema

local function copy(t) return Chronicle.Utils.DeepCopy(t) end
local function with(base, changes)
    local e = copy(base)
    for k, v in pairs(changes) do e[k] = v end
    return e
end
local function without(base, field)
    local e = copy(base)
    e[field] = nil
    return e
end

local continent = { id = "continent:eastern_kingdoms", type = "continent" }
local zone = { id = "zone:dun_morogh", type = "zone", parent = "continent:eastern_kingdoms" }
local city = { id = "city:ironforge", type = "city", parent = "continent:eastern_kingdoms", located_in = "zone:dun_morogh" }
local subzone = { id = "subzone:coldridge_valley", type = "subzone", parent = "zone:dun_morogh" }
local npc = { id = "npc:grelin_whitebeard", type = "npc", located_in = "subzone:coldridge_valley",
    npcID = 786, displayID = 1354, related_to = { "npc:senir_whitebeard" } }
local lore = { id = "lore:the_frostmane_trolls", type = "lore", located_in = "zone:dun_morogh",
    textKey = "lore.the_frostmane_trolls.body", related_to = { "zone:dun_morogh" } }

local function errorsOf(entity) return Schema:Validate(entity).errors end

-- ===================== Tipos =====================
check("el Schema admite los 6 tipos mínimos, ordenados",
    table.concat(Schema:GetTypes(), ",") == "city,continent,lore,npc,subzone,zone")
check("IsValidType acepta los tipos admitidos",
    Schema:IsValidType("continent") and Schema:IsValidType("zone") and Schema:IsValidType("subzone")
        and Schema:IsValidType("city") and Schema:IsValidType("npc") and Schema:IsValidType("lore"))
check("IsValidType rechaza tipos desconocidos y valores que no son cadenas",
    not Schema:IsValidType("faction") and not Schema:IsValidType("") and not Schema:IsValidType(nil)
        and not Schema:IsValidType(5) and not Schema:IsValidType({}) and not Schema:IsValidType("Zone"))
local typesCopy = Schema:GetTypes()
typesCopy[1] = "roto"
check("GetTypes devuelve una copia: modificarla no altera el esquema",
    Schema:GetTypes()[1] == "city")

-- ===================== IDs =====================
local validIds = {
    "zone:dun_morogh", "continent:eastern_kingdoms", "subzone:coldridge_valley", "city:ironforge",
    "npc:grelin_whitebeard", "lore:the_frostmane_trolls", "npc:a", "zone:z1", "lore:5_crowns",
    "npc:" .. string.rep("a", 64),
}
for _, id in ipairs(validIds) do
    check("ID válido: " .. id:sub(1, 30), Schema:IsValidId(id) == true)
end

local invalidIds = {
    { "zone:Dun_Morogh", "mayúsculas" },
    { "zone:dun-morogh", "guion" },
    { "zone:dun morogh", "espacio" },
    { "zone:dun__morogh", "doble guion bajo" },
    { "zone:_dun_morogh", "empieza por _" },
    { "zone:dun_morogh_", "acaba en _" },
    { "zone:", "slug vacío" },
    { ":dun_morogh", "tipo vacío" },
    { "dun_morogh", "sin tipo" },
    { "zone:dun:morogh", "dos separadores" },
    { "faction:alliance", "tipo desconocido" },
    { "Zone:dun_morogh", "tipo en mayúsculas" },
    { "zone:dün_morogh", "carácter no ASCII" },
    { "zone:" .. string.rep("a", 65), "slug demasiado largo" },
    { "", "cadena vacía" },
}
for _, case in ipairs(invalidIds) do
    local ok, err = Schema:IsValidId(case[1])
    check("ID inválido (" .. case[2] .. ")", ok == false and type(err) == "string" and err ~= "", tostring(err))
end
check("IsValidId rechaza valores que no son cadenas",
    Schema:IsValidId(nil) == false and Schema:IsValidId(42) == false and Schema:IsValidId({}) == false)
check("IsValidId comprueba el tipo esperado cuando se indica",
    Schema:IsValidId("zone:dun_morogh", "zone") == true and Schema:IsValidId("zone:dun_morogh", "city") == false)
local pType, pSlug = Schema:ParseId("subzone:coldridge_valley")
check("ParseId devuelve tipo y slug", pType == "subzone" and pSlug == "coldridge_valley")
check("ParseId de un ID inválido devuelve nil y el motivo",
    select(1, Schema:ParseId("zone:Mal")) == nil and type(select(2, Schema:ParseId("zone:Mal"))) == "string")
check("el mensaje de un slug inválido explica la regla",
    contains({ select(2, Schema:ParseId("zone:Mal")) }, "snake_case"))

-- ===================== Entidades válidas de cada tipo =====================
for _, case in ipairs({
    { "continent", continent }, { "zone", zone }, { "city", city },
    { "subzone", subzone }, { "npc", npc }, { "lore", lore },
}) do
    local r = Schema:Validate(case[2])
    check("entidad válida: " .. case[1], r.ok == true and #r.errors == 0 and #r.warnings == 0,
        table.concat(r.errors, " | "))
end
check("un NPC sin displayID ni npcID es válido (son opcionales)",
    Schema:Validate({ id = "npc:sten_stoutarm", type = "npc" }).ok == true)
check("un NPC no necesita lore propio y una entrada de lore no necesita displayID",
    Schema:Validate({ id = "npc:sten_stoutarm", type = "npc", located_in = "city:ironforge" }).ok
        and Schema:Validate({ id = "lore:x", type = "lore" }).ok)
check("una ciudad sin located_in es válida (es opcional)", Schema:Validate(without(city, "located_in")).ok == true)
check("nameKey y descriptionKey son opcionales y se aceptan como cadenas",
    Schema:Validate(with(zone, { nameKey = "names.dun_morogh", descriptionKey = "desc.dun_morogh" })).ok == true)
check("un NPC puede estar colocado en una zona, una ciudad o una subzona",
    Schema:Validate(with(npc, { located_in = "zone:dun_morogh" })).ok
        and Schema:Validate(with(npc, { located_in = "city:ironforge" })).ok
        and Schema:Validate(npc).ok)
check("una subzona puede tener como padre una zona o una ciudad",
    Schema:Validate(subzone).ok and Schema:Validate(with(subzone, { parent = "city:ironforge" })).ok)

-- ===================== Estructura inválida =====================
check("rechaza lo que no es una tabla",
    Schema:Validate(nil).ok == false and Schema:Validate("zone:x").ok == false and Schema:Validate(5).ok == false)
check("id es obligatorio", Schema:Validate(without(zone, "id")).ok == false
    and contains(errorsOf(without(zone, "id")), "id: es obligatorio"))
check("type es obligatorio", Schema:Validate(without(zone, "type")).ok == false
    and contains(errorsOf(without(zone, "type")), "type: es obligatorio"))
check("rechaza un tipo declarado desconocido", contains(errorsOf(with(zone, { type = "faction" })), "tipo desconocido"))
check("rechaza un tipo declarado que no es cadena", Schema:Validate(with(zone, { type = 7 })).ok == false)
check("rechaza un tipo declarado que no coincide con el prefijo del ID",
    contains(errorsOf(with(zone, { type = "city" })), "no coincide con el prefijo"))
check("rechaza un ID con formato inválido", contains(errorsOf(with(zone, { id = "zone:Dun Morogh" })), "id:"))
check("rechaza un ID que no es cadena", Schema:Validate(with(zone, { id = 12 })).ok == false)

-- parent
check("parent es obligatorio en zone, city y subzone",
    Schema:Validate(without(zone, "parent")).ok == false
        and Schema:Validate(without(city, "parent")).ok == false
        and Schema:Validate(without(subzone, "parent")).ok == false
        and contains(errorsOf(without(zone, "parent")), "parent: es obligatorio"))
check("continent, npc y lore no admiten parent",
    Schema:Validate(with(continent, { parent = "continent:kalimdor" })).ok == false
        and Schema:Validate(with(npc, { parent = "zone:dun_morogh" })).ok == false
        and Schema:Validate(with(lore, { parent = "zone:dun_morogh" })).ok == false
        and contains(errorsOf(with(npc, { parent = "zone:dun_morogh" })), "no admite parent"))
check("parent debe ser de un tipo permitido (una zona no cuelga de otra zona ni de una subzona)",
    Schema:Validate(with(zone, { parent = "zone:loch_modan" })).ok == false
        and Schema:Validate(with(zone, { parent = "subzone:coldridge_valley" })).ok == false
        and Schema:Validate(with(subzone, { parent = "continent:kalimdor" })).ok == false
        and Schema:Validate(with(city, { parent = "zone:dun_morogh" })).ok == false
        and contains(errorsOf(with(zone, { parent = "zone:loch_modan" })), "debe ser de tipo continent"))
check("parent debe ser un ID válido (no un nombre visible)",
    Schema:Validate(with(zone, { parent = "Eastern Kingdoms" })).ok == false
        and Schema:Validate(with(zone, { parent = 3 })).ok == false)
check("una entidad no puede ser su propio parent",
    Schema:Validate(with(subzone, { parent = "subzone:coldridge_valley" })).ok == false)

-- located_in
check("located_in debe ser de un tipo permitido (un NPC no está 'en' un continente ni en otro NPC)",
    Schema:Validate(with(npc, { located_in = "continent:eastern_kingdoms" })).ok == false
        and Schema:Validate(with(npc, { located_in = "npc:senir_whitebeard" })).ok == false
        and Schema:Validate(with(city, { located_in = "subzone:coldridge_valley" })).ok == false)
check("zone, subzone y continent no admiten located_in",
    Schema:Validate(with(zone, { located_in = "zone:loch_modan" })).ok == false
        and Schema:Validate(with(subzone, { located_in = "zone:dun_morogh" })).ok == false
        and Schema:Validate(with(continent, { located_in = "zone:dun_morogh" })).ok == false)

-- related_to
check("related_to debe ser una lista", Schema:Validate(with(zone, { related_to = "zone:loch_modan" })).ok == false
    and Schema:Validate(with(zone, { related_to = { a = "zone:loch_modan" } })).ok == false)
check("related_to rechaza elementos que no son IDs válidos, indicando la posición",
    contains(errorsOf(with(zone, { related_to = { "zone:loch_modan", "Loch Modan" } })), "related_to[2]"))
check("related_to admite IDs de cualquier tipo",
    Schema:Validate(with(zone, { related_to = { "npc:x", "lore:y", "city:z", "continent:k" } })).ok == true)
check("related_to no puede apuntar a la propia entidad",
    Schema:Validate(with(zone, { related_to = { "zone:dun_morogh" } })).ok == false)
local dup = Schema:Validate(with(zone, { related_to = { "zone:loch_modan", "zone:loch_modan" } }))
check("un ID repetido en related_to es una advertencia, no un error",
    dup.ok == true and #dup.errors == 0 and #dup.warnings == 1 and contains(dup.warnings, "repetido"))
check("related_to vacío es válido", Schema:Validate(with(zone, { related_to = {} })).ok == true)

-- contains
check("contains no se declara: es una relación derivada",
    contains(errorsOf(with(zone, { contains = { "subzone:coldridge_valley" } })), "contains: no se declara"))

-- claves de presentación
check("nameKey y descriptionKey deben ser cadenas no vacías",
    Schema:Validate(with(zone, { nameKey = "" })).ok == false
        and Schema:Validate(with(zone, { nameKey = 3 })).ok == false
        and Schema:Validate(with(zone, { descriptionKey = {} })).ok == false)

-- ===================== Campos específicos de NPC y lore =====================
check("npcID y displayID deben ser enteros positivos",
    Schema:Validate(with(npc, { displayID = 0 })).ok == false
        and Schema:Validate(with(npc, { displayID = -3 })).ok == false
        and Schema:Validate(with(npc, { displayID = 1.5 })).ok == false
        and Schema:Validate(with(npc, { displayID = "1354" })).ok == false
        and Schema:Validate(with(npc, { displayID = 1 / 0 })).ok == false
        and Schema:Validate(with(npc, { npcID = 0 })).ok == false
        and Schema:Validate(with(npc, { npcID = "786" })).ok == false)
check("displayID numérico positivo es válido; el error indica el campo y el valor",
    Schema:Validate(with(npc, { displayID = 99999 })).ok == true
        and contains(errorsOf(with(npc, { displayID = -3 })), "displayID: debe ser un entero positivo")
        and contains(errorsOf(with(npc, { displayID = -3 })), "-3"))
check("textKey de lore debe ser una cadena no vacía",
    Schema:Validate(with(lore, { textKey = "" })).ok == false
        and Schema:Validate(with(lore, { textKey = 5 })).ok == false)
check("un campo de NPC en otro tipo es un error (displayID en una zona, npcID en lore)",
    contains(errorsOf(with(zone, { displayID = 5 })), "displayID: pertenece a npc")
        and Schema:Validate(with(lore, { npcID = 5 })).ok == false)
check("textKey en un NPC es un error (es un campo de lore)", Schema:Validate(with(npc, { textKey = "x" })).ok == false)

-- ===================== Errores frente a advertencias =====================
local withUnknown = Schema:Validate(with(zone, { colour = "azul" }))
check("un campo desconocido es una advertencia que no invalida la entidad",
    withUnknown.ok == true and #withUnknown.errors == 0 and contains(withUnknown.warnings, "colour")
        and contains(withUnknown.warnings, "campo desconocido"))
check("los errores indican entidad y campo para localizar el problema",
    contains(errorsOf(with(zone, { parent = "x" })), "entidad 'zone:dun_morogh': parent:"))
check("sin ID válido el mensaje lo dice", contains(errorsOf({ type = "zone" }), "entidad sin ID válido"))
local many = Schema:Validate({ id = "zone:Mal", type = "zone", parent = 5, nameKey = "", displayID = 3 })
check("se acumulan todos los errores de una entidad, no solo el primero", #many.errors >= 4)

-- ===================== Determinismo y no mutación =====================
local messy = { id = "zone:dun_morogh", type = "zone", parent = 5, zeta = 1, alfa = 2, nameKey = "",
    related_to = { "x", "zone:ok" } }
local before = copy(messy)
local first, second = Schema:Validate(messy), Schema:Validate(messy)
check("la validación no modifica la entidad recibida (válida ni inválida)",
    deepEqual(messy, before) and deepEqual(zone, copy(zone)))
check("la validación es determinista: misma entrada, mismos errores y advertencias, en el mismo orden",
    deepEqual(first, second) and #first.errors > 0)
check("las advertencias de campos desconocidos salen en orden alfabético",
    first.warnings[1]:find("alfa", 1, true) and first.warnings[2]:find("zeta", 1, true))

-- ===================== Reglas y extensibilidad =====================
local rules = Schema:GetRelationRules("subzone")
check("GetRelationRules devuelve las reglas de relación del tipo",
    rules.parent.required == true and table.concat(rules.parent.types, ",") == "zone,city" and rules.located_in == nil)
rules.parent.types[1] = "roto"
check("GetRelationRules devuelve una copia", Schema:GetRelationRules("subzone").parent.types[1] == "zone")
check("GetRelationRules de un tipo desconocido es nil", Schema:GetRelationRules("faction") == nil)

local custom = Schema.New({
    region = { parent = { types = { "region", "world" } } },
    world = {},
    faction = { fields = { colour = "string" } },
})
check("Schema.New crea esquemas con otros tipos sin tocar el Validate",
    table.concat(custom:GetTypes(), ",") == "faction,region,world" and custom:IsValidId("faction:alliance"))
check("un esquema nuevo valida con sus propias reglas",
    custom:Validate({ id = "faction:alliance", type = "faction", colour = "azul" }).ok == true
        and custom:Validate({ id = "faction:alliance", type = "faction", colour = 5 }).ok == false
        and custom:Validate({ id = "region:north", type = "region", parent = "world:azeroth" }).ok == true)
check("el esquema por defecto no cambia al crear otro",
    not Schema:IsValidType("faction") and table.concat(Schema:GetTypes(), ",") == "city,continent,lore,npc,subzone,zone")
check("Schema.New rechaza definiciones incoherentes",
    not pcall(Schema.New, {}) and not pcall(Schema.New, "x")
        and not pcall(Schema.New, { Zone = {} })
        and not pcall(Schema.New, { zone = { parent = { types = { "nope" } } } })
        and not pcall(Schema.New, { zone = { parent = { types = {} } } })
        and not pcall(Schema.New, { zone = { fields = { id = "string" } } })
        and not pcall(Schema.New, { zone = { fields = { x = "magic" } } }))
