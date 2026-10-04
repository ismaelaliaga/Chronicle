# Fase 14 — Descubrimiento de NPC (rama `fase14-npc-discovery`)

Base: `candidata-limpia-1` (`e7f9b6064cec608070e4c50535b9a5bf778f07b2`). Fecha de la investigación: 2026-10-04. **Nada de esto está probado en WoW Classic Era 1.15.7.** Lo que se afirma sobre el cliente viene de la documentación de la comunidad y está marcado como NO verificado.

## 1. Fuentes de datos investigadas

| Fuente | Qué ofrece | ¿Estructurada / automatizable? | Licencia y condiciones | Uso en esta fase |
|---|---|---|---|---|
| [Wowhead Classic](https://www.wowhead.com/) | NPC ID, nombre, zona, coordenadas (en % de mapa), facción, nivel... Sus datos los aportan jugadores con un addon («Looter») | **No hay API pública** (según varias fuentes de la comunidad; no he podido confirmarlo en sus condiciones: `/terms-of-use` y `/terms` dan 404). Existen scrapers de terceros | Condiciones **no verificadas**. Su [robots.txt](https://www.wowhead.com/robots.txt) **bloquea explícitamente** a rastreadores de IA (incluidos `ClaudeBot` y `anthropic-ai`) | **No se ha extraído nada.** Solo se leyó su robots.txt. Es el origen declarado de los `npcID` del addon original |
| [Warcraft Wiki](https://warcraft.wiki.gg/) | Páginas de NPC con ID, zona, subzona, a veces coordenadas (en % de mapa), facción | Es un MediaWiki (probablemente con API, **no verificado**). Las coordenadas son editadas a mano y mezclan versiones del juego | Texto bajo [CC BY-SA 4.0](https://warcraft.wiki.gg/wiki/Warcraft_Wiki:Copyrights): atribución y compartir igual. Los derechos de Warcraft son de Blizzard. Su política de acceso automatizado no consta en esa página | Leídas **dos páginas sueltas** como contraste: [Grelin Whitebeard](https://warcraft.wiki.gg/wiki/Grelin_Whitebeard) (ID 786, Coldridge Valley) y [Sten Stoutarm](https://warcraft.wiki.gg/wiki/Sten_Stoutarm) (ID 658, Coldridge Valley). Solo se toman IDs numéricos (hechos), con esta atribución |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | Base de datos SQL de servidor para el cliente **1.12.x**: `creature_template` (id, nombre...) y `creature` (apariciones con mapa y posición en **coordenadas del mundo** x, y, z) | **Sí**: SQL descargable, estructurado | GPL v3 (más `COPYRIGHT.md`). Contenido reconstruido por la comunidad para 1.12, **no** la verdad oficial de 1.15.x | No se ha descargado. Candidata para una herramienta de recopilación offline (ver §2). Redistribuir datos derivados exige revisar la compatibilidad con la licencia del addon |
| [VMaNGOS core](https://github.com/vmangos/core) | Servidor 1.12 con su base de datos aparte (instantánea MySQL) | Sí (descarga aparte) | GPL-2.0 | No usada. Mismas reservas que la anterior |
| [Blizzard Game Data API (Classic)](https://community.developer.battle.net/documentation/world-of-warcraft-classic/game-data-apis) | Datos oficiales de juego | Requiere credenciales OAuth del desarrollador | Términos de la API de Blizzard | **No verificada**: la página de documentación no es legible desde aquí; no sé si hay endpoint de criaturas ni si cubre Classic Era. No usada |
| [wago.tools](https://wago.tools/db2/Creature) (exportaciones DB2) | Tablas DB2 del cliente por versión (existe «Creature - DB2») | Descargas CSV (no verificado para 1.15.x) | Términos **no verificados** | No usada. Las DB2 describen datos del cliente (nombres, modelos), **no** dónde aparece cada NPC (esto último es mi conocimiento, no verificado aquí) |
| El propio cliente (`UnitGUID`) | npcID real de la unidad que ve el jugador | Sí, en tiempo de ejecución | Sin restricciones | **Es la base del descubrimiento** (§3) |

Conclusión: no existe una vía estructurada, abierta y verificada que permita incorporar miles de NPC con coordenadas fiables sin trabajo legal y técnico adicional. Wowhead queda descartado (robots.txt y condiciones sin verificar). Las coordenadas de todas las fuentes públicas son aproximadas y de otro sistema (% de mapa en wiki/Wowhead; coordenadas del mundo en las bases de servidor), y ninguna se ha verificado en 1.15.7: **quedan desconocidas, no se ha guardado ninguna.**

## 2. Estrategia propuesta para recopilar muchos NPC (NO implementada)
1. **Catálogo ≠ lista habilitada.** Un catálogo amplio de NPC (npcID, nombre, subzona, procedencia, confianza) puede prepararse aparte; solo los NPC de `Data/NpcTargets.lua` participan en el descubrimiento.
2. **Recopilación asistida por el propio juego (la más segura).** Un modo opt-in que registre `npcID + nombre + zona/subzona` de lo que el jugador ve (lo mismo que hace el «Looter» de Wowhead), para generar catálogos **verificados por construcción** y sin problemas de licencia. Requeriría guardar datos (SavedVariables nuevas, esquema de State): decisión del supervisor, fuera de esta fase.
3. **Herramienta offline** (fuera del ZIP del addon) que lea una copia local de classic-db y emita candidatos `npcID ↔ nombre ↔ zona`. Necesita convertir coordenadas del mundo a mapas/subzonas (no hay datos de conversión en ese repositorio) y una revisión de licencia (GPL). Sus resultados serían `confidence = "source_confirmed"` como mucho, hasta contrastarlos en el cliente.
4. Cada entrada conserva su procedencia y su nivel de confianza; los IDs canónicos y los textos migrados no se tocan.

## 3. Arquitectura implementada
- **`Data/NpcTargets.lua`**: lista explícita de NPC habilitados (`id`, `npcID`, `confidence`, `sources`). Hoy: Grelin Whitebeard (786) y Sten Stoutarm (658), ambos `source_confirmed` (addon original + Warcraft Wiki; **pendientes de verificar con `UnitGUID` en el cliente**). No hay coordenadas.
- **`Services/NpcDiscovery.lua`**: identifica y pide `Discovery:Discover(id)`. No guarda, no avisa, no escribe en State ni toca el Popup. Discovery persiste y evita duplicados; `DiscoveryNotice` avisa y el Codex se repinta con el mismo evento de siempre.
- **Eventos** (cada uno registrado con `pcall`; reactivo, sin temporizadores): `PLAYER_TARGET_CHANGED` (`target`), `UPDATE_MOUSEOVER_UNIT` (`mouseover`), `NAME_PLATE_UNIT_ADDED` (token del evento), `GOSSIP_SHOW` (`npc`). No se depende de las placas de nombre: objetivo y ratón funcionan sin ellas.
- **Identificación**: GUID `Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID` (7 campos, sin campos vacíos, npcID entero positivo). Jugadores, mascotas, objetos y cualquier otro formato → no descubre nada. Debe estar en la lista; el Registry debe tener **una sola** entidad con ese `npcID`, la declarada; el nombre (`UnitName` → `Resolver`) solo rechaza si resuelve a **otra** entidad (`name_mismatch`); si no se puede comprobar (nombre localizado sin alias, unidad sin cargar) queda «unverified» y se acepta porque el GUID es el dato fiable. Un `Discover` fallido no se da por hecho y puede reintentarse.
- **`/chronicle npc`**: muestra la última unidad observada (evento, unidad, **GUID crudo**, npcID, nombre, resultado). Sirve para verificar en el cliente real qué entrega WoW; no descubre nada y no revela la entidad canónica de algo no descubierto.

## 4. Limitaciones conocidas (NO verificado en el cliente)
- El **formato del GUID en 1.15.7** y que `UnitGUID` devuelva datos para `target`, `mouseover`, `nameplateN` y `npc` se apoya en documentación de la comunidad (que cita Retail y versiones de Classic). Si no coincide, el parser falla en seguro (no descubre nada) y `/chronicle npc` lo mostrará.
- `GOSSIP_SHOW` con la unidad `npc`: la documentación no lo confirma; se ignora si no responde.
- Los `npcID` de la lista están contrastados en dos fuentes, no en el cliente.
- Con cliente en español, el nombre de `UnitName` no está en el catálogo (los nombres migrados están en inglés): la comprobación de nombre será «unverified» salvo que se añadan alias con valores reales.
- No hay coordenadas ni descubrimiento por distancia: `Proximity` sigue sin objetivos y nadie llama a `Evaluate()`.
- Redistribuir datos derivados de classic-db o de Warcraft Wiki exige cumplir sus licencias (GPL / CC BY-SA 4.0); no consultado con un jurista.

## 5. Prueba manual mínima en WoW
1. Instala el ZIP, `/console scriptErrors 1`.
2. Ve a Coldridge Valley y pon a **Grelin Whitebeard** como objetivo (clic izquierdo). Debe salir su aviso de descubrimiento y su entrada en el Codex.
3. Ejecuta `/chronicle npc` y pega la salida (incluye el GUID crudo).
4. Haz lo mismo con **Sten Stoutarm**, esta vez solo pasando el ratón por encima (sin objetivo).
5. Vuelve a ponerlos como objetivo: no debe salir ningún aviso nuevo. Pon como objetivo a un jugador o a otro NPC: no debe descubrirse nada.
6. Si algo falla, `/chronicle npc` y el texto de cualquier error Lua dicen en qué paso se corta.

## 6. Revisión técnica (commit posterior a `d73ca53`)
Defectos encontrados y corregidos, cada uno con su prueba de regresión:
- **`/chronicle npc` podía revelar un ID canónico** no descubierto en el motivo de un rechazo `name_mismatch` (el motivo era el ID de la otra entidad). Ahora el motivo solo se imprime en estados que no pueden contener IDs (`failed`, `not_ready`, `invalid_guid`, `not_creature`). Prueba `C5`.
- **Las observaciones sin unidad borraban la última observación útil** (soltar el objetivo o quitar el ratón de encima dispara los mismos eventos sin unidad), así que `/chronicle npc` dejaba de mostrar el GUID justo cuando había que consultarlo. Ahora se cuentan (`GetStats().ignored_unit`) pero no sobrescriben `GetLast()`. Prueba `C6`.
Pruebas añadidas sin defecto asociado: `E1` (un evento que el cliente rechaza registrar no impide los demás), `E2` (un fallo del módulo no impide Codex, descubrimiento de lugares ni avisos), `E3` (placa de nombre + objetivo = un solo descubrimiento y un solo aviso), `C5b`.

Evidencia sobre el GUID: la Warcraft Wiki ([GUID](https://warcraft.wiki.gg/wiki/GUID), [UnitGUID](https://warcraft.wiki.gg/wiki/API_UnitGUID)) documenta `Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID` con el npcID en la sexta posición y ejemplos de addons de Classic que lo usan. **Sigue sin verificarse en el cliente 1.15.7**; el parser conserva su comportamiento seguro (formato distinto = no descubre nada) y `/chronicle npc` enseña el GUID crudo para comprobarlo.
