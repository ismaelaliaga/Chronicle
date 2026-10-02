-- GENERADO por tests/fixtures/extract_legacy_reference.js -- NO EDITAR A MANO.
-- Copia literal de los datos del addon original (Data/Zones, Data/NPCs, Data/Cities y
-- Data/Continents), obtenida ejecutando sus ficheros .lua. Es la referencia con la que las
-- pruebas de la Fase 3 comparan los datos migrados, sin normalizar ni alterar el contenido.
-- Estructura: continents[nombre], zones[nombre], cities[nombre]; cada zona/ciudad trae sus
-- subzones[nombre], y cada subzona su lista npcs.

LegacyReference = {
    cities = {
        Ironforge = {
            key = "Ironforge",
            relatedPlaces = {
                "Dun Morogh",
            },
            subzones = {
                ["Hall of Explorers"] = {
                    hint = "Más allá de la Great Forge.",
                    key = "Ironforge:HallOfExplorers",
                    text = "El Hall of Explorers, más allá de la Great Forge, es sede de la Liga de Exploradores y de su biblioteca y museo: aquí se guardan los hallazgos de las expediciones arqueológicas enanas por todo Azeroth.",
                },
                ["The Commons"] = {
                    hint = "Nada más entrar por las puertas de Forjaz.",
                    key = "Ironforge:TheCommons",
                    text = "The Commons es lo primero que se ve nada más cruzar las puertas de Forjaz: mercaderes, viajeros recién llegados y la Vault of Ironforge, el banco de la ciudad. Es el punto de encuentro natural de todo el que pasa por aquí.",
                },
                ["The Forlorn Cavern"] = {
                    hint = "Un camino discreto junto al lago subterráneo de Forjaz.",
                    key = "Ironforge:TheForlornCavern",
                    text = "The Forlorn Cavern es un camino sinuoso construido alrededor del lago subterráneo de Forjaz, entre The Mystic Ward y el Hall of Explorers. Su discreción lo ha convertido en el rincón elegido por pícaros y brujos para formarse lejos de miradas indiscretas.",
                },
                ["The Great Forge"] = {
                    hint = "El corazón fundido de la ciudad; no tiene pérdida.",
                    key = "Ironforge:TheGreatForge",
                    npcs = {
                        {
                            displayID = 3597,
                            hint = "En el High Seat, sobre la Great Forge.",
                            key = "Ironforge:KingMagniBronzebeard",
                            name = "King Magni Bronzebeard",
                            npcID = 2784,
                            race = "Enano",
                            role = "Rey de Forjaz",
                            text = "King Magni Bronzebeard gobierna Forjaz desde el High Seat, en lo alto de la Great Forge. En esta época sigue siendo un rey de carne y hueso, muy antes de convertirse en la figura de diamante que recordarán tiempos venideros: aquí es, sencillamente, el líder que ha guiado a su pueblo a través de guerras y desastres.",
                        },
                    },
                    text = "The Great Forge es el corazón fundido de la ciudad, la fragua que le da nombre. En el High Seat, sobre ella, gobierna el rey Magni Bronzebeard: es el centro político y simbólico de todo el pueblo enano.",
                },
                ["The Military Ward"] = {
                    hint = "Al este de The Commons.",
                    key = "Ironforge:TheMilitaryWard",
                    text = "The Military Ward, al este de The Commons, es el barrio castrense de Forjaz: el Hall of Arms forma aquí a guerreros y cazadores para la defensa del reino.",
                },
                ["The Mystic Ward"] = {
                    hint = "Al norte de The Commons.",
                    key = "Ironforge:TheMysticWard",
                    text = "The Mystic Ward, al norte de The Commons, alberga el Hall of Mysteries, donde magos, sacerdotes y paladines enanos aprenden y perfeccionan su oficio.",
                },
                ["Tinker Town"] = {
                    hint = "El barrio gnomo de Forjaz.",
                    key = "Ironforge:TinkerTown",
                    npcs = {
                        {
                            displayID = 7006,
                            hint = "En Tinker Town, sede del gobierno gnomo en el exilio.",
                            key = "Ironforge:HighTinkerMekkatorque",
                            name = "High Tinker Mekkatorque",
                            npcID = 7937,
                            race = "Gnomo",
                            role = "Alto Manitas (líder del gobierno gnomo en el exilio)",
                            text = "High Tinker Gelbin Mekkatorque dirige desde Tinker Town al pueblo gnomo exiliado tras la caída de Gnomeregan. Entre inventos a medio terminar y planes de reconquista, sigue soñando con el día en que su gente pueda volver a casa.",
                        },
                    },
                    text = "Tinker Town es el barrio gnomo de Forjaz, y desde la caída de Gnomeregan también la sede provisional de su gobierno en el exilio bajo el Alto Ingeniero Gelbin Mekkatorque. Desde aquí parte también el Deeprun Tram hacia Ventormenta.",
                },
            },
            text = "Forjaz es la gran ciudad-fortaleza de los enanos, excavada en el corazón de las montañas de Dun Morogh alrededor de la Great Forge. Aquí gobierna el rey Magni Bronzebeard, y aquí también encontraron refugio miles de gnomos cuando Gnomeregan cayó. Es, para cualquier enano o gnomo, la primera gran ciudad de su vida.",
        },
    },
    continents = {
        Kalimdor = {
            key = "Kalimdor",
            places = {
                "Cima del Trueno",
                "Orgrimmar",
                "Darnassus",
            },
            text = "Kalimdor es el continente occidental de Azeroth, tierra ancestral de los elfos de la noche y los tauren, y refugio de los orcos y trolls tras la Tercera Guerra. Sus paisajes van de la sabana de Mulgore a los bosques ancestrales de Teldrassil.",
        },
        ["Reinos del Este"] = {
            key = "EasternKingdoms",
            places = {
                "Dun Morogh",
                "Loch Modan",
                "Ironforge",
                "Ventormenta",
                "Entrañas",
            },
            text = "Los Reinos del Este son la cuna de las razas humana y enana, un continente de reinos antiguos, montañas y bosques que ha visto guerras entre humanos, orcos, enanos y no-muertos. Aquí se alzan Forjaz, hogar del clan Bronzebeard, y Ventormenta, capital del reino humano.",
        },
    },
    zones = {
        ["Dun Morogh"] = {
            key = "DunMorogh",
            nestedCities = {
                "Ironforge",
            },
            relatedPlaces = {
                "Ironforge",
                "Loch Modan",
            },
            subzones = {
                ["Amberstill Ranch"] = {
                    hint = "Un rancho de carneros en Dun Morogh; sigue el sonido de los balidos.",
                    key = "DunMorogh:AmberstillRanch",
                    text = "Amberstill Ranch es el rancho donde los enanos crían los carneros que sirven de montura y de sustento a todo Dun Morogh. Es un lugar tranquilo comparado con el resto de la zona, pero fundamental para mantener a Forjaz abastecida.",
                },
                ["Brewnall Village"] = {
                    hint = "Escondida en Chill Breeze Valley, cerca de la entrada a Gnomeregan.",
                    key = "DunMorogh:BrewnallVillage",
                    text = "Brewnall Village es una aldea diminuta escondida en Chill Breeze Valley, cerca de Gnomeregan. Toda la vida del lugar gira en torno a una única y obsesiva búsqueda: dar con la receta perfecta de cerveza enana.",
                },
                ["Coldridge Pass"] = {
                    hint = "El túnel infestado de troggs que sale de Coldridge Valley hacia el resto de la zona.",
                    key = "DunMorogh:ColdridgePass",
                    text = "Coldridge Pass es el túnel de montaña que conecta Coldridge Valley con el resto de Dun Morogh, y durante años ha sido el camino obligado de los jóvenes reclutas que parten hacia Kharanos. Los troggs lo han infestado, así que cruzarlo es ya la primera pequeña prueba de valor de cualquier enano o gnomo novato.",
                },
                ["Coldridge Valley"] = {
                    hint = "El valle donde empieza todo, nada más salir de Anvilmar.",
                    key = "DunMorogh:ColdridgeValley",
                    npcs = {
                        {
                            displayID = 1354,
                            hint = "Un gnomo superviviente que se quedó cerca de la entrada a Gnomeregan, en Coldridge Valley.",
                            key = "DunMorogh:GrelinWhitebeard",
                            name = "Grelin Whitebeard",
                            npcID = 786,
                            race = "Gnomo",
                            radius = 0.03,
                            role = "Superviviente de Gnomeregan",
                            text = "Grelin Whitebeard es uno de los pocos gnomos que sobrevivió a la catástrofe de Gnomeregan y decidió quedarse cerca de la entrada, cuidando de los refugiados y de los jóvenes gnomos que llegan a Coldridge Valley. Habla con reverencia y tristeza de la ciudad perdida, y suele ser el primer contacto de un gnomo novato con la historia real de su pueblo.",
                            x = 0.42,
                            y = 0.62,
                        },
                        {
                            displayID = 1362,
                            hint = "Reparte el correo por Coldridge Valley; búscalo cerca de Anvilmar.",
                            key = "DunMorogh:StenStoutarm",
                            name = "Sten Stoutarm",
                            npcID = 658,
                            race = "Enano",
                            radius = 0.03,
                            role = "Cartero de Anvilmar",
                            text = "Sten Stoutarm hace de cartero de facto en Coldridge Valley: reparte el correo llegado a Anvilmar a través del peligroso Coldridge Pass y transmite los primeros encargos y noticias a quien acaba de empezar su camino. Para muchos enanos y gnomos, es la primera cara amable que ven al salir de su hogar.",
                            x = 0.366,
                            y = 0.702,
                        },
                    },
                    text = "Coldridge Valley es un valle resguardado entre montañas, el lugar donde tanto los enanos como los gnomos dan sus primeros pasos. Aquí se encuentra Anvilmar, refugio de los enanos jóvenes, y el campamento de refugiados gnomos que huyeron de Gnomeregan. Es un lugar pequeño pero cargado de historia reciente: aquí empieza, literalmente, el camino de un pueblo entero.",
                },
                ["Frostmane Hold"] = {
                    hint = "Al oeste de la zona, en territorio troll. No vayas sin estar preparado.",
                    key = "DunMorogh:FrostmaneHold",
                    text = "Frostmane Hold es el antiguo bastión de los trolls de hielo Frostmane en el oeste de Dun Morogh. Es territorio disputado: los enanos llevan tiempo tratando de romper el dominio troll sobre la zona, y cada patrulla que entra aquí sabe que puede no ser bien recibida.",
                },
                ["Gates of Ironforge"] = {
                    hint = "Donde Dun Morogh termina y empieza Forjaz; no tiene pérdida.",
                    key = "DunMorogh:GatesOfIronforge",
                    text = "Las Gates of Ironforge son la gran entrada a la ciudad enana desde Dun Morogh. Una estatua del antiguo Alto Rey Modimus Anvilmar vigila el paso, y las puertas en sí se ven desde buena parte de la zona: son, para muchos, el primer vistazo real a la grandeza de Forjaz.",
                },
                Gnomeregan = {
                    hint = "La entrada a la ciudad perdida de los gnomos, en algún punto de la zona.",
                    key = "DunMorogh:Gnomeregan",
                    text = "La entrada a Gnomeregan es, en realidad, una herida abierta en la historia gnoma. Tras el desastre que forzó la evacuación de su ciudad subterránea, este acceso quedó custodiado y en cuarentena, infestado de trogg y radiación. Para cualquier gnomo, acercarse aquí es enfrentarse cara a cara con la tragedia que definió a su pueblo.",
                },
                ["Gol'Bolar Quarry"] = {
                    hint = "Una cantera al sureste de la zona, tomada por troggs.",
                    key = "DunMorogh:GolBolarQuarry",
                    text = "Gol'Bolar Quarry es una gran cantera al sureste de Dun Morogh, invadida por troggs que han hecho suyas las obras de excavación enanas. Pese al peligro, sigue siendo un punto de apoyo con vendedores y maestros de oficio para quien empieza su aventura en la zona.",
                },
                ["Helm's Bed Lake"] = {
                    hint = "Otro lago helado, este al sureste de la zona.",
                    key = "DunMorogh:HelmsBedLake",
                    text = "Helm's Bed Lake es otro lago helado, este en el sureste de Dun Morogh, mantenido artificialmente libre de hielo para garantizar agua fresca. Troggs, fauna hostil y algún que otro enano Dark Iron merodean por sus orillas, así que no es lugar para bajar la guardia.",
                },
                ["Iceflow Lake"] = {
                    hint = "Un lago helado al oeste, con islas en el centro. Cuidado con lo que aúlla por la noche.",
                    key = "DunMorogh:IceflowLake",
                    text = "Iceflow Lake es un lago helado en el oeste de Dun Morogh. Los enanos de Brewnall Village mantienen un hueco libre de hielo para poder pescar y abastecerse de agua, pero las islas del centro del lago están dominadas por una jauría de lobos hambrientos liderada por el huargo Timber.",
                },
                ["Ironforge Airfield"] = {
                    hint = "Muy al norte, donde las montañas se allanan; escucha los motores.",
                    key = "DunMorogh:IronforgeAirfield",
                    text = "El Ironforge Airfield es el campo de pruebas gnomo-enano para las primeras máquinas voladoras, a las puertas de Forjaz. Entre motores rugientes y despegues no siempre exitosos, este lugar resume el espíritu inventivo -y algo temerario- de ambos pueblos.",
                },
                Kharanos = {
                    hint = "Sigue el camino al norte, más allá de Coldridge Pass.",
                    key = "DunMorogh:Kharanos",
                    npcs = {
                        {
                            displayID = 1376,
                            hint = "En Kharanos, coordinando la lucha contra los trolls Frostmane.",
                            key = "DunMorogh:SenirWhitebeard",
                            name = "Senir Whitebeard",
                            npcID = 1252,
                            race = "Gnomo",
                            radius = 0.03,
                            role = "Coordinador militar",
                            text = "Senir Whitebeard trabaja desde Kharanos para acabar con la presencia troll Frostmane en la zona, coordinando patrullas y encargos contra Frostmane Hold. Su apellido no es casualidad: es familia de Grelin Whitebeard, el gnomo de Coldridge Valley, y ambos comparten la misma determinación silenciosa.",
                            x = 0.46,
                            y = 0.53,
                        },
                    },
                    text = "Kharanos es el primer asentamiento enano de cierta entidad que encuentran los viajeros al salir de Coldridge Valley. Sus posadas y establos sirven de punto de apoyo frente a la amenaza constante de los trolls Frostmane, que acechan desde Iceflow Lake y los bosques cercanos.",
                },
                ["North Gate Outpost"] = {
                    hint = "El puesto enano más al noreste de la zona, camino de Loch Modan.",
                    key = "DunMorogh:NorthGateOutpost",
                    text = "North Gate Outpost es el asentamiento enano más al noreste de Dun Morogh, en el paso que conecta la zona con Loch Modan. Los mountaineers apostados aquí llevan la peor parte de la fauna hostil de la zona, defendiendo la ruta para quienes viajan hacia el este.",
                },
                ["North Gate Pass"] = {
                    hint = "El paso de montaña que sale de North Gate Outpost.",
                    key = "DunMorogh:NorthGatePass",
                    text = "North Gate Pass es el paso de montaña que une Dun Morogh con Loch Modan por el noreste, con North Gate Outpost vigilando la entrada. Es la ruta más directa para quien sigue viaje hacia los Wetlands.",
                },
                ["Shimmer Ridge"] = {
                    hint = "Al norte, cerca de las puertas de Forjaz, entre trolls Frostmane.",
                    key = "DunMorogh:ShimmerRidge",
                    text = "Shimmer Ridge es un asentamiento trol Frostmane al norte de Dun Morogh, al oeste de las puertas de Forjaz. Los jóvenes aventureros suelen acercarse aquí para recolectar la hierba brillante que da nombre al lugar, ingrediente de una receta de cerveza especialmente sabrosa.",
                },
                ["South Gate Outpost"] = {
                    hint = "El puesto enano más al sureste de la zona, camino de Thelsamar.",
                    key = "DunMorogh:SouthGateOutpost",
                    text = "South Gate Outpost es el asentamiento enano más al sureste de Dun Morogh, en mitad del South Gate Pass hacia Loch Modan. Los mountaineers de aquí lo tienen algo más fácil que sus compañeros del norte: la fauna de los alrededores ya está bastante controlada.",
                },
                ["South Gate Pass"] = {
                    hint = "El paso de montaña que sale de South Gate Outpost.",
                    key = "DunMorogh:SouthGatePass",
                    text = "South Gate Pass es el paso de montaña que une Dun Morogh con Loch Modan por el sureste, con South Gate Outpost a medio camino. Es la ruta que toman la mayoría de los viajeros enanos y gnomos que se dirigen hacia Thelsamar.",
                },
                ["Steelgrill's Depot"] = {
                    hint = "Al este de Kharanos, donde se oyen martillazos todo el día.",
                    key = "DunMorogh:SteelgrillsDepot",
                    text = "Steelgrill's Depot es un pequeño enclave de mineros e ingenieros al este de Kharanos, dirigido por el gnomo Beldin Steelgrill. Es punto de encuentro habitual de veteranos pilotos de máquinas de asedio, y un buen lugar para entender cuánto se apoyan enanos y gnomos en su día a día.",
                },
                ["The Grizzled Den"] = {
                    hint = "Unas cuevas al suroeste de Kharanos, hogar de wendigos.",
                    key = "DunMorogh:TheGrizzledDen",
                    text = "The Grizzled Den es un sistema de cuevas al suroeste de Kharanos, hogar de wendigos. Es, para muchos enanos y gnomos jóvenes, la primera vez que se aventuran en grupo contra una amenaza que ninguno podría afrontar en solitario.",
                },
                ["The Tundrid Hills"] = {
                    hint = "Un atajo peligroso entre Coldridge Valley y el resto de la zona.",
                    key = "DunMorogh:TheTundridHills",
                    text = "The Tundrid Hills es un atajo peligroso en el centro-sur de Dun Morogh, entre Coldridge Valley y el resto de la zona. La mayoría de los viajeros prefiere el camino largo y seguro por Kharanos antes que cruzar estas colinas, plagadas de fauna hostil y trolls Frostmane.",
                },
                ["Thunderbrew Distillery"] = {
                    hint = "La posada de Kharanos; huele a cerveza desde la puerta.",
                    key = "DunMorogh:ThunderbrewDistillery",
                    npcs = {
                        {
                            displayID = 3438,
                            hint = "En el sótano de la posada de Kharanos, vigilando unos barriles de ale.",
                            key = "DunMorogh:JarvenThunderbrew",
                            name = "Jarven Thunderbrew",
                            npcID = 1373,
                            race = "Enano",
                            radius = 0.02,
                            role = "Guardián de los barriles",
                            text = "Jarven Thunderbrew custodia los barriles de Thunder Ale en el sótano de la destilería de Kharanos, y es tan aficionado a su propio producto que basta distraerlo con una jarra para que baje la guardia. Su rivalidad con el resto del clan Thunderbrew por la receta perfecta es uno de los secretos peor guardados de la aldea.",
                            x = 0.4765,
                            y = 0.5266,
                        },
                        {
                            displayID = 3434,
                            hint = "La posadera de la destilería de Kharanos.",
                            key = "DunMorogh:InnkeeperBelm",
                            name = "Innkeeper Belm",
                            npcID = 1247,
                            race = "Enano",
                            radius = 0.02,
                            role = "Posadera",
                            text = "Innkeeper Belm regenta la posada de la Thunderbrew Distillery, sirviendo Thunder Ale a partes iguales a viajeros y a Jarven Thunderbrew, que rara vez rechaza una ronda. Es la cara amable de Kharanos para quien busca descanso, reparar su equipo o simplemente escuchar los cotilleos del pueblo.",
                            x = 0.4765,
                            y = 0.5266,
                        },
                    },
                    text = "La Thunderbrew Distillery es la posada y destilería de Kharanos, célebre por su Thunder Ale. Entre sus barriles se cuece algo más que cerveza: rivalidades familiares, secretos de receta y más de una excusa para no volver al trabajo.",
                },
            },
            text = "Dun Morogh es la tierra ancestral del clan Bronzebeard, un reino de montañas nevadas y túneles excavados bajo el hielo. Aquí se alza Forjaz (Ironforge), la gran ciudad-fortaleza de los enanos, y en sus valles se refugiaron también los gnomos tras la caída de Gnomeregan. Es, para muchos, el primer paisaje que ven quienes empiezan su viaje como enano o gnomo.",
        },
        ["Loch Modan"] = {
            key = "LochModan",
            relatedPlaces = {
                "Dun Morogh",
            },
            subzones = {
                ["Algaz Station"] = {
                    hint = "Un puesto avanzado al este del North Gate Pass.",
                    key = "LochModan:AlgazStation",
                    text = "Algaz Station es un puesto avanzado enano al este del North Gate Pass, guarnición y punto de intercambio para los mountaineers que patrullan la frontera con Dun Morogh.",
                },
                ["Dun Algaz"] = {
                    hint = "El paso hacia los Wetlands, ocupado por orcos Dragonmaw.",
                    key = "LochModan:DunAlgaz",
                    text = "Dun Algaz es el paso de montaña excavado entre Loch Modan y los Wetlands, antigua fortaleza enana hoy ocupada por orcos del clan Dragonmaw. Cruzarlo hacia Menethil Harbor ya no es el trámite seguro que fue en su día.",
                },
                ["Grizzlepaw Ridge"] = {
                    hint = "Al sur de Thelsamar, territorio de osos.",
                    key = "LochModan:GrizzlepawRidge",
                    text = "Grizzlepaw Ridge, al sur de Thelsamar, es territorio de osos: entre ellos, Ol' Sooty, un oso pardo de leyenda que lleva años burlándose de los cazadores que salen a por él desde el Farstrider Lodge.",
                },
                ["Ironband's Excavation Site"] = {
                    hint = "Una excavación arqueológica en algún punto de la zona.",
                    key = "LochModan:IronbandsExcavationSite",
                    text = "En su yacimiento de excavación, el Prospector Ironband recluta aventureros algo más curtidos para investigar las ruinas de Uldaman, una de las expediciones arqueológicas más ambiciosas de todo el pueblo enano.",
                },
                ["Mo'grosh Stronghold"] = {
                    hint = "Cuevas de ogros al noreste de la zona.",
                    key = "LochModan:MograshStronghold",
                    text = "Mo'grosh Stronghold, al noreste de Loch Modan, es una red de cuevas tomadas por ogros liderados por el cacique Chok'sul. Los aventureros más ambiciosos llegan hasta aquí buscando poner fin a su amenaza de una vez por todas.",
                },
                ["Silver Stream Mine"] = {
                    hint = "Una mina abandonada, ahora tomada por kobolds.",
                    key = "LochModan:SilverStreamMine",
                    text = "Silver Stream Mine fue en su día una mina de plata próspera para Forjaz. Agotada la veta, la Liga de Mineros la convirtió en depósito, pero los kobolds Tunnel Rat la han tomado por completo, y ahora nadie entra ahí sin esperar pelea.",
                },
                ["Stonesplinter Valley"] = {
                    hint = "Al suroeste de la zona, infestado de troggs Stonesplinter.",
                    key = "LochModan:StonesplinterValley",
                    text = "Stonesplinter Valley, al suroeste de Loch Modan, está infestado de troggs Stonesplinter liderados por Grawmug. Es otro más de los muchos frentes abiertos por las excavaciones enanas en la región.",
                },
                ["Stonewrought Dam"] = {
                    hint = "La presa que contiene el lago; búscala en un extremo de Loch Modan.",
                    key = "LochModan:StonewroughtDam",
                    npcs = {
                        {
                            displayID = 1685,
                            hint = "Vigilando la Stonewrought Dam.",
                            key = "LochModan:ChiefEngineerHinderweir",
                            name = "Chief Engineer Hinderweir VII",
                            npcID = 1093,
                            race = "Enano",
                            radius = 0.03,
                            role = "Ingeniero jefe",
                            text = "Chief Engineer Hinderweir VII supervisa el mantenimiento de la Stonewrought Dam, la presa que contiene todo Loch Modan, y vigila de cerca cualquier señal de actividad de los enanos Dark Iron. Su título -el séptimo de su linaje en el cargo- dice mucho de cuánto le importa a su familia esta presa.",
                            x = 0.46,
                            y = 0.13,
                        },
                    },
                    text = "La Stonewrought Dam es una maravilla de la ingeniería enana sin igual en Azeroth, la presa que contiene todo el lago. El Chief Engineer Hinderweir VII vela por su mantenimiento, mientras vigila la amenaza de los enanos Dark Iron.",
                },
                ["The Farstrider Lodge"] = {
                    hint = "Un refugio de cazadores al sureste de Loch Modan.",
                    key = "LochModan:TheFarstriderLodge",
                    text = "The Farstrider Lodge, al sureste de Loch Modan, es un refugio de cazadores que se dice fundado a semejanza de los Farstriders élficos de Alleria Windrunner. Aquí se forman cazadores y se organizan expediciones contra la fauna más peligrosa de la zona.",
                },
                ["The Loch"] = {
                    hint = "El lago que da nombre a toda la región.",
                    key = "LochModan:TheLoch",
                    text = "The Loch es el propio lago, contenido por la Stonewrought Dam. Sus aguas tranquilas contrastan con las montañas infestadas de troggs que lo rodean por todos lados.",
                },
                Thelsamar = {
                    hint = "El pueblo principal de Loch Modan; no tiene pérdida.",
                    key = "LochModan:Thelsamar",
                    text = "Thelsamar es el corazón de Loch Modan: posada, maestros de oficio y ruta de vuelo reunidos en un único pueblo. Para quien llega desde Dun Morogh, es la primera señal clara de que el viaje va en serio.",
                },
                ["Valley of Kings"] = {
                    hint = "Un frente militar contra los troggs, en algún punto de la zona.",
                    key = "LochModan:ValleyOfKings",
                    npcs = {
                        {
                            displayID = 1630,
                            hint = "En Valley of Kings, liderando la lucha contra los troggs.",
                            key = "LochModan:CaptainRugelfuss",
                            name = "Captain Rugelfuss",
                            npcID = 1092,
                            race = "Enano",
                            radius = 0.03,
                            role = "Capitán militar",
                            text = "Captain Rugelfuss dirige desde Valley of Kings la campaña contra los troggs que infestan Loch Modan, enviando a jóvenes enanos prometedores a ganarse su lugar en el ejército. Su fama de mano dura no le impide recordar el nombre de cada recluta que consigue volver con vida.",
                            x = 0.23,
                            y = 0.73,
                        },
                    },
                    text = "En Valley of Kings, el Captain Rugelfuss envía a jóvenes enanos prometedores a erradicar los troggs que infestan la región. Es uno de los primeros puntos de apoyo militar fuera de Thelsamar.",
                },
            },
            text = "Loch Modan es el gran lago que da nombre a la región, al este de Dun Morogh, contenido por la colosal Stonewrought Dam. Es el destino natural de cualquier enano o gnomo que ya ha dejado atrás su tierra natal: aquí las excavaciones enanas han desenterrado troggs por toda la zona, y el pueblo de Thelsamar sirve de refugio y punto de partida para quien sigue explorando hacia el sur.",
        },
    },
}
