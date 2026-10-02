Chronicle = Chronicle or {}
Chronicle.LegacyText = Chronicle.LegacyText or {}

-- Textos de Dun Morogh: zona, subzonas y NPC.
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

text["zone:dun_morogh"] = {
    name = "Dun Morogh",
    description = "Dun Morogh es la tierra ancestral del clan Bronzebeard, un reino de "
        .. "montañas nevadas y túneles excavados bajo el hielo. Aquí se alza "
        .. "Forjaz (Ironforge), la gran ciudad-fortaleza de los enanos, y en "
        .. "sus valles se refugiaron también los gnomos tras la caída de "
        .. "Gnomeregan. Es, para muchos, el primer paisaje que ven quienes "
        .. "empiezan su viaje como enano o gnomo.",
}

text["subzone:coldridge_valley"] = {
    name = "Coldridge Valley",
    description = "Coldridge Valley es un valle resguardado entre montañas, el lugar "
        .. "donde tanto los enanos como los gnomos dan sus primeros pasos. "
        .. "Aquí se encuentra Anvilmar, refugio de los enanos jóvenes, y el "
        .. "campamento de refugiados gnomos que huyeron de Gnomeregan. Es un "
        .. "lugar pequeño pero cargado de historia reciente: aquí empieza, "
        .. "literalmente, el camino de un pueblo entero.",
    hint = "El valle donde empieza todo, nada más salir de Anvilmar.",
}

text["subzone:coldridge_pass"] = {
    name = "Coldridge Pass",
    description = "Coldridge Pass es el túnel de montaña que conecta Coldridge "
        .. "Valley con el resto de Dun Morogh, y durante años ha sido el "
        .. "camino obligado de los jóvenes reclutas que parten hacia Kharanos. "
        .. "Los troggs lo han infestado, así que cruzarlo es ya la primera "
        .. "pequeña prueba de valor de cualquier enano o gnomo novato.",
    hint = "El túnel infestado de troggs que sale de Coldridge Valley hacia el "
        .. "resto de la zona.",
}

text["subzone:kharanos"] = {
    name = "Kharanos",
    description = "Kharanos es el primer asentamiento enano de cierta entidad que "
        .. "encuentran los viajeros al salir de Coldridge Valley. Sus posadas y "
        .. "establos sirven de punto de apoyo frente a la amenaza constante de "
        .. "los trolls Frostmane, que acechan desde Iceflow Lake y los bosques "
        .. "cercanos.",
    hint = "Sigue el camino al norte, más allá de Coldridge Pass.",
}

text["subzone:thunderbrew_distillery"] = {
    name = "Thunderbrew Distillery",
    description = "La Thunderbrew Distillery es la posada y destilería de Kharanos, "
        .. "célebre por su Thunder Ale. Entre sus barriles se cuece algo más "
        .. "que cerveza: rivalidades familiares, secretos de receta y más de "
        .. "una excusa para no volver al trabajo.",
    hint = "La posada de Kharanos; huele a cerveza desde la puerta.",
}

text["subzone:steelgrills_depot"] = {
    name = "Steelgrill's Depot",
    description = "Steelgrill's Depot es un pequeño enclave de mineros e ingenieros "
        .. "al este de Kharanos, dirigido por el gnomo Beldin Steelgrill. Es "
        .. "punto de encuentro habitual de veteranos pilotos de máquinas de "
        .. "asedio, y un buen lugar para entender cuánto se apoyan enanos y "
        .. "gnomos en su día a día.",
    hint = "Al este de Kharanos, donde se oyen martillazos todo el día.",
}

text["subzone:brewnall_village"] = {
    name = "Brewnall Village",
    description = "Brewnall Village es una aldea diminuta escondida en Chill Breeze "
        .. "Valley, cerca de Gnomeregan. Toda la vida del lugar gira en torno a "
        .. "una única y obsesiva búsqueda: dar con la receta perfecta de "
        .. "cerveza enana.",
    hint = "Escondida en Chill Breeze Valley, cerca de la entrada a Gnomeregan.",
}

text["subzone:amberstill_ranch"] = {
    name = "Amberstill Ranch",
    description = "Amberstill Ranch es el rancho donde los enanos crían los carneros "
        .. "que sirven de montura y de sustento a todo Dun Morogh. Es un lugar "
        .. "tranquilo comparado con el resto de la zona, pero fundamental para "
        .. "mantener a Forjaz abastecida.",
    hint = "Un rancho de carneros en Dun Morogh; sigue el sonido de los balidos.",
}

text["subzone:frostmane_hold"] = {
    name = "Frostmane Hold",
    description = "Frostmane Hold es el antiguo bastión de los trolls de hielo "
        .. "Frostmane en el oeste de Dun Morogh. Es territorio disputado: los "
        .. "enanos llevan tiempo tratando de romper el dominio troll sobre la "
        .. "zona, y cada patrulla que entra aquí sabe que puede no ser bien "
        .. "recibida.",
    hint = "Al oeste de la zona, en territorio troll. No vayas sin estar "
        .. "preparado.",
}

text["subzone:iceflow_lake"] = {
    name = "Iceflow Lake",
    description = "Iceflow Lake es un lago helado en el oeste de Dun Morogh. Los "
        .. "enanos de Brewnall Village mantienen un hueco libre de hielo para "
        .. "poder pescar y abastecerse de agua, pero las islas del centro del "
        .. "lago están dominadas por una jauría de lobos hambrientos liderada "
        .. "por el huargo Timber.",
    hint = "Un lago helado al oeste, con islas en el centro. Cuidado con lo que "
        .. "aúlla por la noche.",
}

text["subzone:golbolar_quarry"] = {
    name = "Gol'Bolar Quarry",
    description = "Gol'Bolar Quarry es una gran cantera al sureste de Dun Morogh, "
        .. "invadida por troggs que han hecho suyas las obras de excavación "
        .. "enanas. Pese al peligro, sigue siendo un punto de apoyo con "
        .. "vendedores y maestros de oficio para quien empieza su aventura en "
        .. "la zona.",
    hint = "Una cantera al sureste de la zona, tomada por troggs.",
}

text["subzone:shimmer_ridge"] = {
    name = "Shimmer Ridge",
    description = "Shimmer Ridge es un asentamiento trol Frostmane al norte de Dun "
        .. "Morogh, al oeste de las puertas de Forjaz. Los jóvenes aventureros "
        .. "suelen acercarse aquí para recolectar la hierba brillante que da "
        .. "nombre al lugar, ingrediente de una receta de cerveza especialmente "
        .. "sabrosa.",
    hint = "Al norte, cerca de las puertas de Forjaz, entre trolls Frostmane.",
}

text["subzone:helms_bed_lake"] = {
    name = "Helm's Bed Lake",
    description = "Helm's Bed Lake es otro lago helado, este en el sureste de Dun "
        .. "Morogh, mantenido artificialmente libre de hielo para garantizar "
        .. "agua fresca. Troggs, fauna hostil y algún que otro enano Dark Iron "
        .. "merodean por sus orillas, así que no es lugar para bajar la "
        .. "guardia.",
    hint = "Otro lago helado, este al sureste de la zona.",
}

text["subzone:north_gate_outpost"] = {
    name = "North Gate Outpost",
    description = "North Gate Outpost es el asentamiento enano más al noreste de Dun "
        .. "Morogh, en el paso que conecta la zona con Loch Modan. Los "
        .. "mountaineers apostados aquí llevan la peor parte de la fauna "
        .. "hostil de la zona, defendiendo la ruta para quienes viajan hacia el "
        .. "este.",
    hint = "El puesto enano más al noreste de la zona, camino de Loch Modan.",
}

text["subzone:north_gate_pass"] = {
    name = "North Gate Pass",
    description = "North Gate Pass es el paso de montaña que une Dun Morogh con Loch "
        .. "Modan por el noreste, con North Gate Outpost vigilando la entrada. "
        .. "Es la ruta más directa para quien sigue viaje hacia los Wetlands.",
    hint = "El paso de montaña que sale de North Gate Outpost.",
}

text["subzone:south_gate_outpost"] = {
    name = "South Gate Outpost",
    description = "South Gate Outpost es el asentamiento enano más al sureste de Dun "
        .. "Morogh, en mitad del South Gate Pass hacia Loch Modan. Los "
        .. "mountaineers de aquí lo tienen algo más fácil que sus "
        .. "compañeros del norte: la fauna de los alrededores ya está "
        .. "bastante controlada.",
    hint = "El puesto enano más al sureste de la zona, camino de Thelsamar.",
}

text["subzone:south_gate_pass"] = {
    name = "South Gate Pass",
    description = "South Gate Pass es el paso de montaña que une Dun Morogh con Loch "
        .. "Modan por el sureste, con South Gate Outpost a medio camino. Es la "
        .. "ruta que toman la mayoría de los viajeros enanos y gnomos que se "
        .. "dirigen hacia Thelsamar.",
    hint = "El paso de montaña que sale de South Gate Outpost.",
}

text["subzone:gates_of_ironforge"] = {
    name = "Gates of Ironforge",
    description = "Las Gates of Ironforge son la gran entrada a la ciudad enana desde "
        .. "Dun Morogh. Una estatua del antiguo Alto Rey Modimus Anvilmar "
        .. "vigila el paso, y las puertas en sí se ven desde buena parte de la "
        .. "zona: son, para muchos, el primer vistazo real a la grandeza de "
        .. "Forjaz.",
    hint = "Donde Dun Morogh termina y empieza Forjaz; no tiene pérdida.",
}

text["subzone:the_grizzled_den"] = {
    name = "The Grizzled Den",
    description = "The Grizzled Den es un sistema de cuevas al suroeste de Kharanos, "
        .. "hogar de wendigos. Es, para muchos enanos y gnomos jóvenes, la "
        .. "primera vez que se aventuran en grupo contra una amenaza que "
        .. "ninguno podría afrontar en solitario.",
    hint = "Unas cuevas al suroeste de Kharanos, hogar de wendigos.",
}

text["subzone:the_tundrid_hills"] = {
    name = "The Tundrid Hills",
    description = "The Tundrid Hills es un atajo peligroso en el centro-sur de Dun "
        .. "Morogh, entre Coldridge Valley y el resto de la zona. La mayoría "
        .. "de los viajeros prefiere el camino largo y seguro por Kharanos "
        .. "antes que cruzar estas colinas, plagadas de fauna hostil y trolls "
        .. "Frostmane.",
    hint = "Un atajo peligroso entre Coldridge Valley y el resto de la zona.",
}

text["subzone:gnomeregan"] = {
    name = "Gnomeregan",
    description = "La entrada a Gnomeregan es, en realidad, una herida abierta en la "
        .. "historia gnoma. Tras el desastre que forzó la evacuación de su "
        .. "ciudad subterránea, este acceso quedó custodiado y en cuarentena, "
        .. "infestado de trogg y radiación. Para cualquier gnomo, acercarse "
        .. "aquí es enfrentarse cara a cara con la tragedia que definió a su "
        .. "pueblo.",
    hint = "La entrada a la ciudad perdida de los gnomos, en algún punto de la "
        .. "zona.",
}

text["subzone:ironforge_airfield"] = {
    name = "Ironforge Airfield",
    description = "El Ironforge Airfield es el campo de pruebas gnomo-enano para las "
        .. "primeras máquinas voladoras, a las puertas de Forjaz. Entre "
        .. "motores rugientes y despegues no siempre exitosos, este lugar "
        .. "resume el espíritu inventivo -y algo temerario- de ambos pueblos.",
    hint = "Muy al norte, donde las montañas se allanan; escucha los motores.",
}

text["npc:grelin_whitebeard"] = {
    name = "Grelin Whitebeard",
    description = "Grelin Whitebeard es uno de los pocos gnomos que sobrevivió a la "
        .. "catástrofe de Gnomeregan y decidió quedarse cerca de la entrada, "
        .. "cuidando de los refugiados y de los jóvenes gnomos que llegan a "
        .. "Coldridge Valley. Habla con reverencia y tristeza de la ciudad "
        .. "perdida, y suele ser el primer contacto de un gnomo novato con la "
        .. "historia real de su pueblo.",
    hint = "Un gnomo superviviente que se quedó cerca de la entrada a "
        .. "Gnomeregan, en Coldridge Valley.",
    race = "Gnomo",
    role = "Superviviente de Gnomeregan",
}

text["npc:sten_stoutarm"] = {
    name = "Sten Stoutarm",
    description = "Sten Stoutarm hace de cartero de facto en Coldridge Valley: reparte "
        .. "el correo llegado a Anvilmar a través del peligroso Coldridge Pass "
        .. "y transmite los primeros encargos y noticias a quien acaba de "
        .. "empezar su camino. Para muchos enanos y gnomos, es la primera cara "
        .. "amable que ven al salir de su hogar.",
    hint = "Reparte el correo por Coldridge Valley; búscalo cerca de Anvilmar.",
    race = "Enano",
    role = "Cartero de Anvilmar",
}

text["npc:senir_whitebeard"] = {
    name = "Senir Whitebeard",
    description = "Senir Whitebeard trabaja desde Kharanos para acabar con la "
        .. "presencia troll Frostmane en la zona, coordinando patrullas y "
        .. "encargos contra Frostmane Hold. Su apellido no es casualidad: es "
        .. "familia de Grelin Whitebeard, el gnomo de Coldridge Valley, y ambos "
        .. "comparten la misma determinación silenciosa.",
    hint = "En Kharanos, coordinando la lucha contra los trolls Frostmane.",
    race = "Gnomo",
    role = "Coordinador militar",
}

text["npc:jarven_thunderbrew"] = {
    name = "Jarven Thunderbrew",
    description = "Jarven Thunderbrew custodia los barriles de Thunder Ale en el "
        .. "sótano de la destilería de Kharanos, y es tan aficionado a su "
        .. "propio producto que basta distraerlo con una jarra para que baje la "
        .. "guardia. Su rivalidad con el resto del clan Thunderbrew por la "
        .. "receta perfecta es uno de los secretos peor guardados de la aldea.",
    hint = "En el sótano de la posada de Kharanos, vigilando unos barriles de "
        .. "ale.",
    race = "Enano",
    role = "Guardián de los barriles",
}

text["npc:innkeeper_belm"] = {
    name = "Innkeeper Belm",
    description = "Innkeeper Belm regenta la posada de la Thunderbrew Distillery, "
        .. "sirviendo Thunder Ale a partes iguales a viajeros y a Jarven "
        .. "Thunderbrew, que rara vez rechaza una ronda. Es la cara amable de "
        .. "Kharanos para quien busca descanso, reparar su equipo o simplemente "
        .. "escuchar los cotilleos del pueblo.",
    hint = "La posadera de la destilería de Kharanos.",
    race = "Enano",
    role = "Posadera",
}
