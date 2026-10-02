Chronicle = Chronicle or {}

-- Subzonas de Dun Morogh, Loch Modan y Forjaz (Fase 3). Solo contenido CANÓNICO; nombres,
-- descripciones y pistas viven en Data/Text/. Migradas de los `subzones` de
-- Data/Zones/DunMorogh.lua, Data/Zones/LochModan.lua y Data/Cities/Ironforge.lua del addon
-- original, en su mismo orden. Cada subzona declara `parent` (la zona o ciudad donde la
-- fuente la lista); sus NPC se colocan con `located_in` en Data/Entities/Npcs.lua.
--
-- El slug del ID es el nombre original en inglés en minúsculas, sin apóstrofos y con "_"
-- entre palabras. Una vez publicado, el ID NO cambia aunque cambie el nombre visible.
--
-- Notas de la fuente: "North Gate Pass" y "South Gate Pass" cuelgan de Dun Morogh, no de
-- Loch Modan (la fuente lo confirma como vanilla); "Gates of Ironforge" también es una
-- subzona de Dun Morogh, no de la ciudad.

local Registry = Chronicle.Registry

-- Dun Morogh (21)
Registry:Register({ id = "subzone:coldridge_valley", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:coldridge_pass", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:kharanos", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:thunderbrew_distillery", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:steelgrills_depot", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:brewnall_village", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:amberstill_ranch", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:frostmane_hold", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:iceflow_lake", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:golbolar_quarry", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:shimmer_ridge", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:helms_bed_lake", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:north_gate_outpost", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:north_gate_pass", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:south_gate_outpost", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:south_gate_pass", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:gates_of_ironforge", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:the_grizzled_den", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:the_tundrid_hills", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:gnomeregan", type = "subzone", parent = "zone:dun_morogh" })
Registry:Register({ id = "subzone:ironforge_airfield", type = "subzone", parent = "zone:dun_morogh" })

-- Loch Modan (12)
Registry:Register({ id = "subzone:thelsamar", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:the_loch", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:stonewrought_dam", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:valley_of_kings", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:grizzlepaw_ridge", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:stonesplinter_valley", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:the_farstrider_lodge", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:ironbands_excavation_site", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:silver_stream_mine", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:mogrosh_stronghold", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:algaz_station", type = "subzone", parent = "zone:loch_modan" })
Registry:Register({ id = "subzone:dun_algaz", type = "subzone", parent = "zone:loch_modan" })

-- Ironforge (7)
Registry:Register({ id = "subzone:the_commons", type = "subzone", parent = "city:ironforge" })
Registry:Register({ id = "subzone:the_great_forge", type = "subzone", parent = "city:ironforge" })
Registry:Register({ id = "subzone:the_mystic_ward", type = "subzone", parent = "city:ironforge" })
Registry:Register({ id = "subzone:the_military_ward", type = "subzone", parent = "city:ironforge" })
Registry:Register({ id = "subzone:the_forlorn_cavern", type = "subzone", parent = "city:ironforge" })
Registry:Register({ id = "subzone:hall_of_explorers", type = "subzone", parent = "city:ironforge" })
Registry:Register({ id = "subzone:tinker_town", type = "subzone", parent = "city:ironforge" })
