Chronicle = Chronicle or {}

-- Textos de Ironforge: ciudad, subzonas y NPC.
--
-- TEXTO MIGRADO TAL CUAL del addon original (Fase 3) y registrado en Localization (Fase 4)
-- en el idioma "esES": descripciones y pistas en el español en que se redactaron, nombres tal
-- como aparecen en la fuente (los de zonas, subzonas y NPC son nombres propios ingleses).
-- Nada de esto está reescrito, resumido, corregido ni traducido. No existe ningún texto
-- "enUS": no hay traducción al inglés que lo respalde.
--
-- Campos de cada entrada, todos opcionales: name, description, hint; y race, role (solo NPC).
-- La fuente nombra la ciudad "Ironforge" (clave de los datos); en los textos aparece como
-- "Forjaz". No se añade ningún otro nombre: los alias en español son de la Fase 4.

local Localization = Chronicle.Localization

Localization:Add("esES", "city:ironforge", {
    name = "Ironforge",
    description = "Forjaz es la gran ciudad-fortaleza de los enanos, excavada en el "
        .. "corazón de las montañas de Dun Morogh alrededor de la Great "
        .. "Forge. Aquí gobierna el rey Magni Bronzebeard, y aquí también "
        .. "encontraron refugio miles de gnomos cuando Gnomeregan cayó. Es, "
        .. "para cualquier enano o gnomo, la primera gran ciudad de su vida.",
})

Localization:Add("esES", "subzone:the_commons", {
    name = "The Commons",
    description = "The Commons es lo primero que se ve nada más cruzar las puertas de "
        .. "Forjaz: mercaderes, viajeros recién llegados y la Vault of "
        .. "Ironforge, el banco de la ciudad. Es el punto de encuentro natural "
        .. "de todo el que pasa por aquí.",
    hint = "Nada más entrar por las puertas de Forjaz.",
})

Localization:Add("esES", "subzone:the_great_forge", {
    name = "The Great Forge",
    description = "The Great Forge es el corazón fundido de la ciudad, la fragua que "
        .. "le da nombre. En el High Seat, sobre ella, gobierna el rey Magni "
        .. "Bronzebeard: es el centro político y simbólico de todo el pueblo "
        .. "enano.",
    hint = "El corazón fundido de la ciudad; no tiene pérdida.",
})

Localization:Add("esES", "subzone:the_mystic_ward", {
    name = "The Mystic Ward",
    description = "The Mystic Ward, al norte de The Commons, alberga el Hall of "
        .. "Mysteries, donde magos, sacerdotes y paladines enanos aprenden y "
        .. "perfeccionan su oficio.",
    hint = "Al norte de The Commons.",
})

Localization:Add("esES", "subzone:the_military_ward", {
    name = "The Military Ward",
    description = "The Military Ward, al este de The Commons, es el barrio castrense "
        .. "de Forjaz: el Hall of Arms forma aquí a guerreros y cazadores para "
        .. "la defensa del reino.",
    hint = "Al este de The Commons.",
})

Localization:Add("esES", "subzone:the_forlorn_cavern", {
    name = "The Forlorn Cavern",
    description = "The Forlorn Cavern es un camino sinuoso construido alrededor del "
        .. "lago subterráneo de Forjaz, entre The Mystic Ward y el Hall of "
        .. "Explorers. Su discreción lo ha convertido en el rincón elegido "
        .. "por pícaros y brujos para formarse lejos de miradas indiscretas.",
    hint = "Un camino discreto junto al lago subterráneo de Forjaz.",
})

Localization:Add("esES", "subzone:hall_of_explorers", {
    name = "Hall of Explorers",
    description = "El Hall of Explorers, más allá de la Great Forge, es sede de la "
        .. "Liga de Exploradores y de su biblioteca y museo: aquí se guardan "
        .. "los hallazgos de las expediciones arqueológicas enanas por todo "
        .. "Azeroth.",
    hint = "Más allá de la Great Forge.",
})

Localization:Add("esES", "subzone:tinker_town", {
    name = "Tinker Town",
    description = "Tinker Town es el barrio gnomo de Forjaz, y desde la caída de "
        .. "Gnomeregan también la sede provisional de su gobierno en el exilio "
        .. "bajo el Alto Ingeniero Gelbin Mekkatorque. Desde aquí parte "
        .. "también el Deeprun Tram hacia Ventormenta.",
    hint = "El barrio gnomo de Forjaz.",
})

Localization:Add("esES", "npc:king_magni_bronzebeard", {
    name = "King Magni Bronzebeard",
    description = "King Magni Bronzebeard gobierna Forjaz desde el High Seat, en lo "
        .. "alto de la Great Forge. En esta época sigue siendo un rey de carne "
        .. "y hueso, muy antes de convertirse en la figura de diamante que "
        .. "recordarán tiempos venideros: aquí es, sencillamente, el líder "
        .. "que ha guiado a su pueblo a través de guerras y desastres.",
    hint = "En el High Seat, sobre la Great Forge.",
    race = "Enano",
    role = "Rey de Forjaz",
})

Localization:Add("esES", "npc:high_tinker_mekkatorque", {
    name = "High Tinker Mekkatorque",
    description = "High Tinker Gelbin Mekkatorque dirige desde Tinker Town al pueblo "
        .. "gnomo exiliado tras la caída de Gnomeregan. Entre inventos a medio "
        .. "terminar y planes de reconquista, sigue soñando con el día en que "
        .. "su gente pueda volver a casa.",
    hint = "En Tinker Town, sede del gobierno gnomo en el exilio.",
    race = "Gnomo",
    role = "Alto Manitas (líder del gobierno gnomo en el exilio)",
})
