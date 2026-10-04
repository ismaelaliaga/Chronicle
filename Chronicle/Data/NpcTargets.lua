Chronicle = Chronicle or {}

-- NpcTargets: la lista EXPLÍCITA de NPC cuyo descubrimiento por GUID está habilitado (Fase 14). Es DATOS TÉCNICOS DE JUEGO con procedencia, separados de las entidades
-- canónicas (Data/Entities), de los textos (Localization) y de los alias. Que un NPC exista en el Registry NO lo habilita: solo está activo el que aparece aquí.
-- Ampliar la lista no requiere tocar la lógica de Services/NpcDiscovery.lua: se añade una entrada y su prueba.
--
-- ENTRADA: { id, npcID, confidence, sources }
--   id          ID canónico de Chronicle (debe existir en el Registry con tipo "npc").
--   npcID       ID del NPC en el juego; debe coincidir con el `npcID` de la entidad en el Registry (NpcDiscovery lo comprueba al arrancar y rechaza lo que no cuadre).
--   confidence  "source_confirmed": el npcID coincide en DOS fuentes independientes (addon original, que cita Wowhead Classic, y Warcraft Wiki), pero aún NO se ha
--               comprobado en el cliente 1.15.7 con UnitGUID. Pasa a "client_verified" cuando el supervisor lo confirme en el juego (/chronicle npc).
--   sources     de dónde sale (para atribución y auditoría).
-- NO se guardan coordenadas: el descubrimiento es por identidad (GUID), no por posición, y las coordenadas de las fuentes no están verificadas.
--
-- PROCEDENCIA (consultada el 2026-10-04; ver docs/fase14_npc_discovery.md): el texto de Warcraft Wiki está bajo CC BY-SA 4.0; aquí solo se toman IDs numéricos
-- (hechos), con atribución en la documentación.

Chronicle.NpcTargets = {
    {
        id = "npc:grelin_whitebeard", npcID = 786, confidence = "client_verified",
        sources = { "addon original (Wowhead Classic)", "Warcraft Wiki: Grelin Whitebeard (NPC ID 786, Coldridge Valley)", "prueba manual en WoW Classic Era (ratón y objetivo lo descubrieron por GUID)" },
    },
    {
        id = "npc:sten_stoutarm", npcID = 658, confidence = "client_verified",
        sources = { "addon original (Wowhead Classic)", "Warcraft Wiki: Sten Stoutarm (NPC ID 658, Coldridge Valley)", "prueba manual en WoW Classic Era (ratón y objetivo lo descubrieron por GUID)" },
    },
}
