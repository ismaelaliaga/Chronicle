Chronicle = Chronicle or {}

-- Texto del continente Reinos del Este.
--
-- TEXTO MIGRADO TAL CUAL del addon original (Fase 3) y registrado en Localization (Fase 4)
-- en el idioma "esES": descripciones y pistas en el español en que se redactaron, nombres tal
-- como aparecen en la fuente (los de zonas, subzonas y NPC son nombres propios ingleses).
-- Nada de esto está reescrito, resumido, corregido ni traducido. No existe ningún texto
-- "enUS": no hay traducción al inglés que lo respalde.
--
-- Campos de cada entrada, todos opcionales: name, description, hint; y race, role (solo NPC).
-- El nombre del continente es "Reinos del Este": en la fuente es el único nombre y está en
-- español (los nombres de zonas, subzonas y NPC de la fuente están en inglés).
-- La fuente indica que el texto es lore general de Azeroth, sin la verificación contra
-- Classic Era que sí tienen las subzonas y los NPC.

local Localization = Chronicle.Localization

Localization:Add("esES", "continent:eastern_kingdoms", {
    name = "Reinos del Este",
    description = "Los Reinos del Este son la cuna de las razas humana y enana, un "
        .. "continente de reinos antiguos, montañas y bosques que ha visto "
        .. "guerras entre humanos, orcos, enanos y no-muertos. Aquí se alzan "
        .. "Forjaz, hogar del clan Bronzebeard, y Ventormenta, capital del "
        .. "reino humano.",
})
