Chronicle = Chronicle or {}
Chronicle.LegacyText = Chronicle.LegacyText or {}

-- Texto del continente Reinos del Este.
--
-- TEXTO MIGRADO TAL CUAL del addon original (Fase 3): descripciones y pistas en el español
-- en que se redactaron, nombres tal como aparecen en la fuente. Nada de esto está
-- reescrito, resumido, corregido ni traducido.
--
-- Esto NO es el sistema de localización (Fase 4): es un contenedor pasivo, indexado por ID
-- de entidad, que ningún módulo lee todavía. Cada campo es opcional:
--   name, description, hint (todas las entidades), race y role (solo NPC).
-- Cómo se reparte entre idiomas y cómo se resuelve queda para la Fase 4.
-- El nombre del continente es "Reinos del Este": en la fuente es el único nombre y está en
-- español (los nombres de zonas, subzonas y NPC de la fuente están en inglés).
-- La fuente indica que el texto es lore general de Azeroth, sin la verificación contra
-- Classic Era que sí tienen las subzonas y los NPC.

local text = Chronicle.LegacyText

text["continent:eastern_kingdoms"] = {
    name = "Reinos del Este",
    description = "Los Reinos del Este son la cuna de las razas humana y enana, un "
        .. "continente de reinos antiguos, montañas y bosques que ha visto "
        .. "guerras entre humanos, orcos, enanos y no-muertos. Aquí se alzan "
        .. "Forjaz, hogar del clan Bronzebeard, y Ventormenta, capital del "
        .. "reino humano.",
}
