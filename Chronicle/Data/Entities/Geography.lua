Chronicle = Chronicle or {}

-- Entidades geográficas de nivel superior de la Fase 3: continente, zonas y ciudad. Solo
-- contenido CANÓNICO (IDs y relaciones); los nombres y textos viven en Data/Text/.
-- Migrado de Data/Continents.lua, Data/Zones/*.lua y Data/Cities/Ironforge.lua del addon
-- original. El alcance es solo Dun Morogh, Loch Modan y Forjaz: no se crean otros
-- continentes ni ciudades (Kalimdor, Ventormenta... existen en la fuente pero quedan fuera).
--
-- parent      continente de cada zona y de la ciudad: Continents.lua lista "Dun Morogh",
--             "Loch Modan" e "Ironforge" como lugares de Reinos del Este.
-- located_in  Forjaz -> Dun Morogh: la fuente la declara en `nestedCities` de Dun Morogh y
--             describe la ciudad como excavada en las montañas de Dun Morogh.
-- related_to  `relatedPlaces` de la fuente (Dun Morogh -> Forjaz y Loch Modan; Loch Modan ->
--             Dun Morogh; Forjaz -> Dun Morogh). La relación es simétrica, así que se declara
--             UNA vez por pareja (aquí, del lado de Dun Morogh) y Registry:GetRelated() la ve
--             desde los dos lados; declararla también del otro lado la duplicaría.
--
-- Los datos se registran sin comprobar que existan sus referencias: lo hace
-- Registry:Validate() durante la inicialización.

local Registry = Chronicle.Registry

Registry:Register({
    id = "continent:eastern_kingdoms",
    type = "continent",
})

Registry:Register({
    id = "zone:dun_morogh",
    type = "zone",
    parent = "continent:eastern_kingdoms",
    related_to = { "city:ironforge", "zone:loch_modan" },
})

Registry:Register({
    id = "zone:loch_modan",
    type = "zone",
    parent = "continent:eastern_kingdoms",
})

Registry:Register({
    id = "city:ironforge",
    type = "city",
    parent = "continent:eastern_kingdoms",
    located_in = "zone:dun_morogh",
})
