Chronicle = Chronicle or {}

-- Alias en español (esES) de nombres de entidades ya migradas. Origen: Core/Localization.lua
-- del addon original (tablas ZONE_ALIASES y SUBZONE_ALIASES); aquí no se ha añadido ninguna
-- equivalencia nueva. Cada alias apunta al ID de la entidad que en la fuente era el nombre
-- inglés al que traducía. Los 22 alias de la fuente corresponden a entidades migradas, así que
-- no queda ninguno fuera de alcance.
--
-- PROCEDENCIA (heredada de los comentarios de la fuente; NO se ha reverificado aquí):
--   [C]  la fuente lo marca como CONFIRMADO jugando con "/chronicle where".
--   [J]  la fuente dice que es lo que se veía en un mensaje del propio juego, sin confirmarlo
--        como GetRealZoneText().
--   [W]  investigado en la Wowpedia en español; la fuente avisa de que NO está verificado
--        jugando.
--   [O]  nombre alternativo visto en otra fuente, sin más detalle.
--
-- Excluidos a propósito (la fuente los descarta por ser de Cataclysm, no de Classic Era):
-- "Frente de Peloescarcha" y "Nueva Ciudad Manitas".
--
-- Es contenido para el Resolver, no texto que se muestre: los nombres visibles siguen en los
-- demás ficheros de esta carpeta.

local Resolver = Chronicle.Resolver

-- Forjaz (ciudad)
Resolver:AddAlias("esES", "city:ironforge", "Ciudad de Forjaz") -- [C]
Resolver:AddAlias("esES", "city:ironforge", "Forjaz") -- [J]

-- Dun Morogh
Resolver:AddAlias("esES", "subzone:coldridge_pass", "Desfiladero de Crestanevada") -- [W]
Resolver:AddAlias("esES", "subzone:thunderbrew_distillery", "Destilería Cebatruenos") -- [W]
Resolver:AddAlias("esES", "subzone:steelgrills_depot", "Almacén de Brasacerada") -- [W]
Resolver:AddAlias("esES", "subzone:amberstill_ranch", "Granja de Semperámbar") -- [W]
Resolver:AddAlias("esES", "subzone:frostmane_hold", "Refugio Peloescarcha") -- [W]
Resolver:AddAlias("esES", "subzone:iceflow_lake", "Lago Glacial") -- [W]
Resolver:AddAlias("esES", "subzone:golbolar_quarry", "Cantera de Gol'Bolar") -- [W]
Resolver:AddAlias("esES", "subzone:helms_bed_lake", "Lago de Helm") -- [W]
Resolver:AddAlias("esES", "subzone:north_gate_outpost", "Avanzada de la Puerta Norte") -- [W]
Resolver:AddAlias("esES", "subzone:north_gate_pass", "Paso de la Puerta Norte") -- [W]
Resolver:AddAlias("esES", "subzone:gates_of_ironforge", "Puertas de Forjaz") -- [W]
Resolver:AddAlias("esES", "subzone:the_grizzled_den", "Cubil Pardo") -- [W]
Resolver:AddAlias("esES", "subzone:the_tundrid_hills", "Colinas Tundra") -- [W]
Resolver:AddAlias("esES", "subzone:ironforge_airfield", "Base aérea de Forjaz") -- [W]

-- Forjaz (subzonas). "La Gran Forja", "Gran Fundición" y "El Trono" son tres nombres de la
-- misma subzona en la fuente; "El Trono" es lo que devuelve el juego junto al rey Magni.
Resolver:AddAlias("esES", "subzone:the_commons", "La Plaza") -- [W]
Resolver:AddAlias("esES", "subzone:the_great_forge", "La Gran Forja") -- [W]
Resolver:AddAlias("esES", "subzone:the_great_forge", "Gran Fundición") -- [O]
Resolver:AddAlias("esES", "subzone:the_great_forge", "El Trono") -- [C]
Resolver:AddAlias("esES", "subzone:the_military_ward", "La Sala Militar") -- [W]
Resolver:AddAlias("esES", "subzone:tinker_town", "Ciudad Manitas") -- [C]
