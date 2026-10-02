Chronicle = Chronicle or {}

-- NPC de Dun Morogh, Loch Modan y Forjaz (Fase 3). Solo contenido CANÓNICO; nombres, textos,
-- pistas, raza y rol viven en Data/Text/. Migrados de Data/NPCs/*.lua del addon original, en
-- su mismo orden.
--
-- located_in  subzona en la que la fuente cuelga al NPC.
-- npcID       ID del NPC en el juego, tal cual figura en la fuente (que declara Wowhead
--             Classic como origen). displayID: ID del modelo; es OTRO dato distinto de npcID.
--             Ambos son opcionales en el esquema; aquí están todos porque la fuente los trae.
-- related_to  solo Senir -> Grelin: el texto original dice explícitamente que son familia.
--             No se declara ninguna otra relación entre personajes.
--
-- NO migrado (el esquema no tiene dónde ponerlo; ver docs/fase3_migracion.md): x, y y
-- radius de cada NPC, que la fuente marca además como "sin verificar en cliente real".

local Registry = Chronicle.Registry

Registry:Register({
    id = "npc:grelin_whitebeard",
    type = "npc",
    located_in = "subzone:coldridge_valley",
    npcID = 786,
    displayID = 1354,
})

Registry:Register({
    id = "npc:sten_stoutarm",
    type = "npc",
    located_in = "subzone:coldridge_valley",
    npcID = 658,
    displayID = 1362,
})

Registry:Register({
    id = "npc:senir_whitebeard",
    type = "npc",
    located_in = "subzone:kharanos",
    npcID = 1252,
    displayID = 1376,
    related_to = { "npc:grelin_whitebeard" },
})

Registry:Register({
    id = "npc:jarven_thunderbrew",
    type = "npc",
    located_in = "subzone:thunderbrew_distillery",
    npcID = 1373,
    displayID = 3438,
})

Registry:Register({
    id = "npc:innkeeper_belm",
    type = "npc",
    located_in = "subzone:thunderbrew_distillery",
    npcID = 1247,
    displayID = 3434,
})

Registry:Register({
    id = "npc:chief_engineer_hinderweir_vii",
    type = "npc",
    located_in = "subzone:stonewrought_dam",
    npcID = 1093,
    displayID = 1685,
})

Registry:Register({
    id = "npc:captain_rugelfuss",
    type = "npc",
    located_in = "subzone:valley_of_kings",
    npcID = 1092,
    displayID = 1630,
})

Registry:Register({
    id = "npc:king_magni_bronzebeard",
    type = "npc",
    located_in = "subzone:the_great_forge",
    npcID = 2784,
    displayID = 3597,
})

Registry:Register({
    id = "npc:high_tinker_mekkatorque",
    type = "npc",
    located_in = "subzone:tinker_town",
    npcID = 7937,
    displayID = 7006,
})
