Chronicle = Chronicle or {}
Chronicle.LegacyText = Chronicle.LegacyText or {}

-- Textos de Loch Modan: zona, subzonas y NPC.
--
-- TEXTO MIGRADO TAL CUAL del addon original (Fase 3): descripciones y pistas en el español
-- en que se redactaron, nombres tal como aparecen en la fuente. Nada de esto está
-- reescrito, resumido, corregido ni traducido.
--
-- Esto NO es el sistema de localización (Fase 4): es un contenedor pasivo, indexado por ID
-- de entidad, que ningún módulo lee todavía. Cada campo es opcional:
--   name, description, hint (todas las entidades), race y role (solo NPC).
-- Cómo se reparte entre idiomas y cómo se resuelve queda para la Fase 4.

local text = Chronicle.LegacyText

text["zone:loch_modan"] = {
    name = "Loch Modan",
    description = "Loch Modan es el gran lago que da nombre a la región, al este de "
        .. "Dun Morogh, contenido por la colosal Stonewrought Dam. Es el "
        .. "destino natural de cualquier enano o gnomo que ya ha dejado atrás "
        .. "su tierra natal: aquí las excavaciones enanas han desenterrado "
        .. "troggs por toda la zona, y el pueblo de Thelsamar sirve de refugio "
        .. "y punto de partida para quien sigue explorando hacia el sur.",
}

text["subzone:thelsamar"] = {
    name = "Thelsamar",
    description = "Thelsamar es el corazón de Loch Modan: posada, maestros de oficio "
        .. "y ruta de vuelo reunidos en un único pueblo. Para quien llega "
        .. "desde Dun Morogh, es la primera señal clara de que el viaje va en "
        .. "serio.",
    hint = "El pueblo principal de Loch Modan; no tiene pérdida.",
}

text["subzone:the_loch"] = {
    name = "The Loch",
    description = "The Loch es el propio lago, contenido por la Stonewrought Dam. Sus "
        .. "aguas tranquilas contrastan con las montañas infestadas de troggs "
        .. "que lo rodean por todos lados.",
    hint = "El lago que da nombre a toda la región.",
}

text["subzone:stonewrought_dam"] = {
    name = "Stonewrought Dam",
    description = "La Stonewrought Dam es una maravilla de la ingeniería enana sin "
        .. "igual en Azeroth, la presa que contiene todo el lago. El Chief "
        .. "Engineer Hinderweir VII vela por su mantenimiento, mientras vigila "
        .. "la amenaza de los enanos Dark Iron.",
    hint = "La presa que contiene el lago; búscala en un extremo de Loch Modan.",
}

text["subzone:valley_of_kings"] = {
    name = "Valley of Kings",
    description = "En Valley of Kings, el Captain Rugelfuss envía a jóvenes enanos "
        .. "prometedores a erradicar los troggs que infestan la región. Es uno "
        .. "de los primeros puntos de apoyo militar fuera de Thelsamar.",
    hint = "Un frente militar contra los troggs, en algún punto de la zona.",
}

text["subzone:grizzlepaw_ridge"] = {
    name = "Grizzlepaw Ridge",
    description = "Grizzlepaw Ridge, al sur de Thelsamar, es territorio de osos: entre "
        .. "ellos, Ol' Sooty, un oso pardo de leyenda que lleva años "
        .. "burlándose de los cazadores que salen a por él desde el "
        .. "Farstrider Lodge.",
    hint = "Al sur de Thelsamar, territorio de osos.",
}

text["subzone:stonesplinter_valley"] = {
    name = "Stonesplinter Valley",
    description = "Stonesplinter Valley, al suroeste de Loch Modan, está infestado de "
        .. "troggs Stonesplinter liderados por Grawmug. Es otro más de los "
        .. "muchos frentes abiertos por las excavaciones enanas en la región.",
    hint = "Al suroeste de la zona, infestado de troggs Stonesplinter.",
}

text["subzone:the_farstrider_lodge"] = {
    name = "The Farstrider Lodge",
    description = "The Farstrider Lodge, al sureste de Loch Modan, es un refugio de "
        .. "cazadores que se dice fundado a semejanza de los Farstriders "
        .. "élficos de Alleria Windrunner. Aquí se forman cazadores y se "
        .. "organizan expediciones contra la fauna más peligrosa de la zona.",
    hint = "Un refugio de cazadores al sureste de Loch Modan.",
}

text["subzone:ironbands_excavation_site"] = {
    name = "Ironband's Excavation Site",
    description = "En su yacimiento de excavación, el Prospector Ironband recluta "
        .. "aventureros algo más curtidos para investigar las ruinas de "
        .. "Uldaman, una de las expediciones arqueológicas más ambiciosas de "
        .. "todo el pueblo enano.",
    hint = "Una excavación arqueológica en algún punto de la zona.",
}

text["subzone:silver_stream_mine"] = {
    name = "Silver Stream Mine",
    description = "Silver Stream Mine fue en su día una mina de plata próspera para "
        .. "Forjaz. Agotada la veta, la Liga de Mineros la convirtió en "
        .. "depósito, pero los kobolds Tunnel Rat la han tomado por completo, "
        .. "y ahora nadie entra ahí sin esperar pelea.",
    hint = "Una mina abandonada, ahora tomada por kobolds.",
}

text["subzone:mogrosh_stronghold"] = {
    name = "Mo'grosh Stronghold",
    description = "Mo'grosh Stronghold, al noreste de Loch Modan, es una red de cuevas "
        .. "tomadas por ogros liderados por el cacique Chok'sul. Los "
        .. "aventureros más ambiciosos llegan hasta aquí buscando poner fin a "
        .. "su amenaza de una vez por todas.",
    hint = "Cuevas de ogros al noreste de la zona.",
}

text["subzone:algaz_station"] = {
    name = "Algaz Station",
    description = "Algaz Station es un puesto avanzado enano al este del North Gate "
        .. "Pass, guarnición y punto de intercambio para los mountaineers que "
        .. "patrullan la frontera con Dun Morogh.",
    hint = "Un puesto avanzado al este del North Gate Pass.",
}

text["subzone:dun_algaz"] = {
    name = "Dun Algaz",
    description = "Dun Algaz es el paso de montaña excavado entre Loch Modan y los "
        .. "Wetlands, antigua fortaleza enana hoy ocupada por orcos del clan "
        .. "Dragonmaw. Cruzarlo hacia Menethil Harbor ya no es el trámite "
        .. "seguro que fue en su día.",
    hint = "El paso hacia los Wetlands, ocupado por orcos Dragonmaw.",
}

text["npc:chief_engineer_hinderweir_vii"] = {
    name = "Chief Engineer Hinderweir VII",
    description = "Chief Engineer Hinderweir VII supervisa el mantenimiento de la "
        .. "Stonewrought Dam, la presa que contiene todo Loch Modan, y vigila "
        .. "de cerca cualquier señal de actividad de los enanos Dark Iron. Su "
        .. "título -el séptimo de su linaje en el cargo- dice mucho de "
        .. "cuánto le importa a su familia esta presa.",
    hint = "Vigilando la Stonewrought Dam.",
    race = "Enano",
    role = "Ingeniero jefe",
}

text["npc:captain_rugelfuss"] = {
    name = "Captain Rugelfuss",
    description = "Captain Rugelfuss dirige desde Valley of Kings la campaña contra "
        .. "los troggs que infestan Loch Modan, enviando a jóvenes enanos "
        .. "prometedores a ganarse su lugar en el ejército. Su fama de mano "
        .. "dura no le impide recordar el nombre de cada recluta que consigue "
        .. "volver con vida.",
    hint = "En Valley of Kings, liderando la lucha contra los troggs.",
    race = "Enano",
    role = "Capitán militar",
}
