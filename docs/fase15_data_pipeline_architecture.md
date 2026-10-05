# Fase 15 — Auditoría arquitectónica y propuesta del pipeline de datos

> **Nota (Fase 15.1):** este documento fue **revisado** en [`fase15_1_architecture_review.md`](fase15_1_architecture_review.md). Esa revisión **sustituye o corrige** D5, D6, D8, D9, D10, D11, D13, D14 y D15 (y la recomendación de licencia de D8), añade el principio **IDENTIFICATION ≠ DISCOVERY ≠ EDITORIAL INCLUSION**, los cuatro niveles de datos y la sección `ClientAdapter`. Donde ambos documentos discrepan, **prevalece la Fase 15.1**. El resto de este documento se conserva como análisis original.

**Rama:** `fase15-data-pipeline-architecture`, creada desde `fase14-npc-discovery` (`b7f5d739558f5c6c5c623a254a60fe84a5e8dcb1`).
**Fecha de la investigación externa:** 2026-10-05. Todo lo externo es información pública a esa fecha y puede cambiar (Forever está en beta).
**Alcance:** este documento es **solo análisis y propuesta**. No se ha modificado el addon, ni los datos, ni los tests, ni `main`. No hay generador, no hay importación, no hay soporte Forever.

## 0. Leyenda de etiquetas

| Etiqueta | Significado |
|---|---|
| **[HECHO]** | Comprobado en el repositorio real (código, datos, tests) o ejecutado. |
| **[INVESTIGADO]** | Leído en una fuente externa. Se indica la fiabilidad: *primaria* (documentación técnica, repositorio, wiki de API) o *secundaria* (prensa, webs de guías). |
| **[PROPUESTA]** | Diseño que recomiendo. No es un hecho ni una decisión tomada. |
| **[INFERENCIA]** | Conclusión mía a partir de lo anterior, sin verificar directamente. |
| **[PENDIENTE EN CLIENTE]** | Solo se puede confirmar con el cliente real (Classic Era o Forever). |

Regla de lectura: si algo no lleva etiqueta explícita en una tabla, hereda la de su columna o encabezado. Nada marcado [INFERENCIA] o [PROPUESTA] debe leerse como un hecho.

---

## 1. Resumen ejecutivo

1. **Chronicle no es una base de datos de NPC.** Es un Codex editorial. La arquitectura debe separar de forma absoluta **qué existe en el mundo (World Data, por versión del juego)** de **qué queremos contar (Chronicle Data, editorial, compartido entre versiones)**. [PROPUESTA]
2. **Lo bueno de partida [HECHO]:** el ID canónico ya es un *slug* estable e independiente del NPC ID del cliente (`npc:grelin_whitebeard`, no `npc:786`); `npcID` es un campo opcional; los textos viven aparte en `Localization`; `Discovery` es independiente de cómo se identifica algo; el descubrimiento de NPC ya se hace por identidad (GUID), no por coordenadas.
3. **Lo que hay que separar [HECHO]:** hoy cada entidad mezcla en un mismo registro identidad editorial, jerarquía geográfica y datos técnicos del cliente (`npcID`, `displayID`); los nombres de zona/subzona que reconoce el cliente se mantienen a mano como alias por idioma; `NpcTargets.lua` es una lista manual por versión de cliente. Nada de eso escala a cientos de entidades ni a dos versiones del juego.
4. **Arquitectura propuesta:** un pipeline offline y reproducible, **fuera del ZIP del addon**: *fuentes → importadores → registros normalizados con procedencia → reconciliación (conflictos explícitos) → World Data por versión → análisis de candidatos → revisión editorial → Chronicle Data → generador determinista → data packs Lua por versión → addon*. El addon solo carga el pack generado y valida su cabecera. [PROPUESTA]
5. **Tres ideas que sostienen todo el diseño [PROPUESTA]:**
   - **Entidad Chronicle ≠ presencia en el mundo.** Una entidad editorial tiene 0..N *presencias* (una por versión), cada una con su identidad técnica, su estado de verificación y su procedencia.
   - **La decisión editorial nunca la toma un algoritmo.** El *score* solo ordena candidatos (`SCORE ≠ DECISIÓN EDITORIAL`); lo editorial sobrevive a cualquier actualización técnica porque se referencia por ID de Chronicle y vive en ficheros distintos.
   - **Los conflictos nunca se resuelven en silencio.** Se detectan, clasifican, registran y solo se resuelven con un *override* explícito, con motivo, que reaparece si la fuente cambia.
6. **Hallazgos que obligan a decisiones tempranas:**
   - **Forever hereda las restricciones de addons de Midnight («valores secretos»)** [INVESTIGADO, secundaria + wiki primaria]. `UnitGUID`/`UnitName` pueden devolver valores secretos en combate o en mapas restringidos, y no se pueden analizar como cadena. El parser de GUID de la Fase 14 no está preparado para eso [HECHO]. Encaja bien con la regla de producto «descubrir al hablar» (fuera de combate), pero hay que diseñarlo expresamente.
   - **La regla de producto cambia** respecto a la Fase 14: *ver / ratón / objetivo / placa de nombre no descubren; hablar con el NPC en un contexto válido, sí.* Eso exige cambiar `NpcDiscovery` en una fase futura (§12).
   - **Licencias:** el contenido de WoW es de Blizzard; QuestieDB y Questie no declaran licencia (no se puede reutilizar su código ni sus datos); CMaNGOS/VMaNGOS son GPL pero su propio aviso reconoce que el contenido del juego no es suyo. El repositorio de Chronicle **no tiene fichero de licencia** [HECHO]. Hay que decidir la política antes de importar nada (§11).
   - **El `Interface` del `.toc` es 11507**, mientras que Classic Era figura hoy en 11509 (1.15.9) [INVESTIGADO]. No bloquea nada, pero hay que decidirlo (§13, D11).

---

## 2. Auditoría del repositorio real [HECHO]

Se leyeron `Data/Schema.lua`, `Data/Registry.lua`, `Data/Entities/*`, `Data/NpcTargets.lua`, `Services/{NpcDiscovery,Discovery,Resolver,ZoneDiscovery,MapPosition,Proximity}.lua`, `Core/{State,Events,Init}.lua`, `Chronicle.toc`, `Localization/*`, `tests/*` y la documentación de la Fase 14.

### 2.1 Inventario
- **39 ficheros Lua + `.toc`** en `Chronicle/` (≈4 600 líneas en Core/Data/Localization/Services). Capas: Core → Data → Localization → Services → UI; `Core/Init.lua` carga el último.
- **53 entidades canónicas:** 1 continente, 2 zonas, 1 ciudad, 40 subzonas, 9 NPC. Textos solo en `esES` (los nombres propios están en inglés dentro de `esES`; no existe `enUS`).
- **Tests:** harness Node + fengari (Lua 5.3) con un mock estricto de la API del cliente; 1632 pruebas superadas, 0 fallidas en el último estado de la Fase 14. No hay intérprete Lua 5.1 real (el cliente usa 5.1): la compatibilidad se comprueba por análisis estático.
- **No hay LICENSE en la raíz del repositorio.**

### 2.2 Qué ya está bien alineado con el objetivo
| Aspecto | Evidencia en el código |
|---|---|
| ID canónico independiente del NPC ID, del nombre visible y del padre | `Schema.lua`: «El ID NO se deriva del nombre visible ni del padre: es una etiqueta estable». `npcID` es un campo **opcional** del tipo `npc`. |
| Contenido canónico separado de presentación | Las entidades no tienen texto visible; `Localization` guarda `name, description, hint, race, role` indexados por ID. |
| Relaciones con una sola fuente de verdad | `parent` (jerarquía), `located_in` (colocación), `related_to` (libre); `contains` es derivado (`Registry:GetContained`). |
| Descubrimiento desacoplado de la identificación | `Discovery:Discover(id)` solo recibe un ID; `ZoneDiscovery` y `NpcDiscovery` solo *piden* el descubrimiento. `DiscoveryNotice` y el Codex reaccionan al mismo evento `Chronicle.Discovery.Discovered`. |
| Único dueño de la persistencia | Solo `Core/State.lua` toca `ChronicleCharDB`. `schemaVersion = 1` con tabla de migraciones vacía lista para usarse. |
| Procedencia incipiente | `Aliases.lua` marca cada alias con `[C]` (confirmado en cliente), `[J]`, `[W]`, `[O]`; `NpcTargets.lua` lleva `confidence` y `sources`. Son precursores informales del modelo de procedencia propuesto. |
| Datos verificados vs no verificados | `Proximity` exige `verified = true` en cada objetivo y hoy no tiene ninguno; las coordenadas no verificadas del addon original **no se migraron**. |

### 2.3 Qué impide escalar tal como está
| # | Hallazgo | Consecuencia |
|---|---|---|
| H1 | Una entidad (`Data/Entities/Npcs.lua`) mezcla identidad editorial, ubicación (`located_in`) y técnicos del cliente (`npcID`, `displayID`). | No se puede tener la misma entidad en dos versiones con distintos `npcID`, ni una entidad sin datos de cliente verificados, sin duplicarla. |
| H2 | `NpcTargets.lua` es una lista manual de NPC habilitados con su `npcID` y confianza. | Escala linealmente con el esfuerzo manual; está atada a una versión del cliente. |
| H3 | Los nombres que el cliente devuelve para zona/subzona (`GetRealZoneText`, `GetSubZoneText`) se resuelven por **nombre localizado** vía `Resolver`; los alias del cliente se mantienen a mano (`Aliases.lua`, 24 alias, 2 añadidos tras observar el cliente real). | Dependiente del idioma **y** de la versión del juego. Forever puede renombrar o añadir zonas. |
| H4 | `NpcDiscovery` descubre al **ver** (objetivo, ratón, placa, conversación). | Contradice la regla de producto definitiva (§9). |
| H5 | `Discovery` guarda `entries[id] = {}` (tabla vacía, sin metadatos). | No registra *cómo* ni *cuándo* se descubrió algo. No hay estado de pistas. |
| H6 | `Localization` tiene un conjunto cerrado de campos (`name, description, hint, race, role`). `hint` existe pero **no se muestra**: pertenece a «la integración con Discovery, que no existe aún» (comentario en `CodexModel.lua`). | La pista es un texto suelto por entidad; no hay modelo de pistas (requisitos, dependencias, progresión). |
| H7 | `ParseGuid`/`Observe` de `NpcDiscovery` asumen que `UnitGUID` devuelve una cadena analizable. | Con valores secretos (§5.4) un `guid == ""` o `guid:sub()` lanzaría error. Hoy lo atrapa un `pcall` externo y se informa como error. |
| H8 | `Interface: 11507` en el `.toc`; un único `.toc` sin variantes por versión del juego. | Sin mecanismo de empaquetado por versión. |
| H9 | `Resolver` indexa nombres + alias de todas las entidades en memoria al arrancar. | Con cientos de entidades y varios idiomas sigue siendo viable, pero el índice debería generarse, no escribirse a mano. |
| H10 | `Proximity` (motor genérico) sin objetivos y sin llamadas a `Evaluate()`. | Es un punto de extensión futuro, no una dependencia del catálogo. |

### 2.4 Qué no debe tocarse (resumen; detalle en §12)
La API y la persistencia de `Discovery`, el bus `Events`, `State` como único dueño de `ChronicleCharDB`, el Popup/`DiscoveryNotice`, la política de privacidad de entidades bloqueadas (`???`), los IDs canónicos existentes y la filosofía del harness de tests.

---

## 3. Investigación externa

### 3.1 QuestieDB — la referencia de arquitectura más cercana
Fuente: [github.com/Questie/QuestieDB](https://github.com/Questie/QuestieDB) (documentos `README`, `DESIGN.md`, `PROVENANCE.md`, `docs/forever.md`, `docs/forever-data.md`, `docs/toc-flavor-selection.md`, `docs/client-metadata-probes.md`, `src/meta/npcMeta.lua`, lista de ADR). Fiabilidad: **primaria** (leídos directamente). **Licencia: GitHub no declara ninguna y no hay fichero LICENSE en la raíz** [INVESTIGADO]. Se estudian las decisiones; **no se copia código ni datos**.

| Decisión de QuestieDB | Qué es | ¿Nos sirve? |
|---|---|---|
| **«The seam»**: «QuestieDB owns what is true about game entities. Questie owns what to do with that truth.» | Separación explícita entre datos del mundo y política del consumidor. | **Sí, es el mismo principio** que World Data / Chronicle Data. |
| **Capas de lectura:** base → correcciones dinámicas → capa del consumidor → terceros; las correcciones no modifican la base. | Un solapamiento (*overlay*) en lectura; base «intacta». | **Sí, el concepto.** En Chronicle la superposición ocurre en *generación*, no en el addon. Limitación documentada: un overlay «puede añadir y cambiar, pero no quitar». |
| **Correcciones estáticas vs dinámicas**: las estáticas se pliegan al generar; las dinámicas se aplican en consulta y son por *propietario*. | Dos mecanismos para parches. | **Parcial:** las estáticas = nuestros *overrides*; las dinámicas no hacen falta (el addon no compone en runtime). |
| **Procedencia por propietario:** `GetProvenance(datatype, id, key)` dice qué propietario aportó el valor ganador. | Procedencia consultable por campo. | **Sí, el concepto;** nosotros la haremos por campo y también en el pipeline, no en runtime. |
| **Generación determinista y verificada:** `generate.lua`, `verify.lua`, `equivalence.lua`, `reconstruct.lua`; «cada regeneración produce artefactos idénticos, así las versiones son revisables y los checksums significativos». | Pipeline reproducible con validación de ida y vuelta. | **Sí, es el modelo a seguir** (generador determinista + comprobación en CI/test de que lo generado = lo versionado). |
| **Schema como autoridad** (`src/meta/*Meta.lua`, rechaza campos no declarados). | Un único lugar define campos y semántica de `nil`. | **Sí.** Nuestro `Schema.lua` ya es así; habrá que ampliarlo por capas. |
| **Validadores** entre entidades (`validators/`). | Invariantes entre tablas. | **Sí.** |
| **Modo *Source* vs *Baked*** (tablas Lua crudas vs CBOR en metadatos de `.toc`). | Optimización de tamaño/arranque para miles de misiones. | **No.** Nuestro volumen es de órdenes de magnitud menor. Además sus propias mediciones muestran trampas de los metadatos de TOC (el cliente recorta espacios en los extremos, trunca líneas a 1 023 bytes, claves sin distinguir mayúsculas). **No guardaremos datos en metadatos de TOC.** |
| **Un flavor por TOC con sufijo** (`QuestieDB_Vanilla.toc`, …; Forever con alias `_Camelot.toc`). | Selección de datos por cliente. | **Parcial;** ver §8 (varias alternativas, con incertidumbre sobre Forever). |
| **Forever como flavor independiente**, con sus propios datos, correcciones, localización y soporte (`data/Forever`, `src/corrections/Forever`, …); «datos mantenidos de forma independiente, no una dependencia en runtime de Era». | No es un delta de Era. | **Sí, la dirección:** World Data **por versión**, no una capa de parches sobre Classic Era. |
| **Conversión de coordenadas Era → Forever** (porcentajes de mapa → posiciones de mundo; cuatro mapas con cambios de marco: Mulgore, Eastern Plaguelands, Redridge, Stormwind City; 13 691 pares convertidos y 123 819 sin cambios). | Evidencia de que parte de la geometría del mundo cambia. | **Informa el diseño:** no asumir que mapas ni coordenadas coinciden. |
| **Datos capturados de jugadores:** `tools/trace-analyzer` regenera correcciones «derivadas de máquina» desde datos agregados; prohibido editarlas a mano. | Herramienta de captura + análisis con salida no editable. | **Sí, el concepto** (§10). |
| **Sondas en cliente real:** `tools/probe-addon/` con TOC sintéticos para medir comportamiento del cliente. | Medir en vez de suponer. | **Sí:** exactamente la filosofía de nuestras pruebas manuales; un *probe*/captura dev está justificado. |
| **Esquema de NPC** (`npcMeta.lua`): 15 campos (`name, minLevel, maxLevel, rank, spawns, waypoints, zoneID, questStarts, questEnds, factionID, friendlyToFaction, subName, npcFlags`, más campos obsoletos). | Un NPC «de mundo» típico. | **Referencia útil** de qué señales objetivas existen (`questStarts/questEnds`, `npcFlags`, `rank`, `subName`). **No tiene capa editorial**: confirma que lo editorial es nuestro valor propio. |
| **Procedencia histórica** (`PROVENANCE.md`): datos migrados desde Questie en un commit concreto, «no un input de build». | Registro del origen. | **Sí, el hábito:** conservar commit/versión de cada fuente. |

Lo que **no** resuelve QuestieDB para nosotros: lore, importancia, pistas, descubrimiento contextual, relaciones narrativas. Eso es 100 % Chronicle.

### 3.2 VMaNGOS y CMaNGOS (bases de servidor para 1.12)
**VMaNGOS** — [vmangos/wiki](https://github.com/vmangos/wiki) (documentación; sin licencia declarada en los metadatos de GitHub) y [vmangos/core](https://github.com/vmangos/core) (GPL-2.0; la base de datos mundial se distribuye aparte como instantánea MySQL). Fiabilidad: **primaria** para la estructura documentada; [INVESTIGADO].
- `creature_template`: propiedades base por *entry* (estadísticas, modelo, facción, IA, botín). `creature`: apariciones (colocación, reaparición, movimiento). `creature_addon`: sobrescrituras por aparición.
- `creature_questrelation` / `creature_involvedrelation`: misiones que el NPC **ofrece** / **termina**. `gossip_menu`, `gossip_menu_option`, `npc_text`, `npc_gossip`: diálogo (con `UNIT_NPC_FLAG_GOSSIP`, vendedor `0x4`, etc.). `locales_creature`: nombres localizados.
- La documentación leída **no especifica el sistema de coordenadas** de `creature` (mundo vs % de mapa) [DESCONOCIDO en lo leído; las bases de servidor suelen usar coordenadas del mundo — INFERENCIA]. Sin esquema de versión explícito en lo leído.
- Destinado a **1.12.x**, no a Classic Era 1.15.x ni a Forever.

**CMaNGOS classic-db** — [cmangos/classic-db](https://github.com/cmangos/classic-db). **GPL-3.0** (verificado en la API de GitHub), ≈414 MB, última actualización 2026-09-23; «contenido para mangos-classic y cliente 1.12» [INVESTIGADO, primaria].
- Su `COPYRIGHT.md` dice, resumiendo: el contenido de WoW es copyright de Blizzard; el proyecto afirma un uso legítimo (*fair use*) no comercial como «demo» y «testimonio» de contenido que ya no está disponible; el contenido protegido «no puede modificarse, alterarse, venderse ni usarse comercialmente sin autorización de Blizzard»; reconoce que el *fair use* varía según países; **no concede una licencia explícita de redistribución del contenido**. No trata específicamente la licencia de la base de datos.
- Aceptan correcciones SQL y recomiendan contrastar con fuentes fiables.

**Valor técnico para Chronicle:** `creature_template` (nombre, subname, nivel, rank, `npc_flags`, facción), relaciones de misiones (señales de importancia) y `locales_creature`. **Limitaciones:** versión 1.12 (el contenido de Classic Era 1.15.x y de Forever difiere); datos reconstruidos por la comunidad; posibles errores; coordenadas en otro sistema que el que usa el cliente moderno para sus mapas. **No** son fuente de verdad para Forever (el mundo cambió).

### 3.3 Warcraft Wiki (warcraft.wiki.gg)
- Texto bajo **CC BY-SA 4.0** (atribución + compartir igual); la propiedad intelectual de Warcraft sigue siendo de Blizzard [INVESTIGADO, primaria: `Warcraft_Wiki:Copyrights`].
- Contiene páginas de NPC con ID, zona, a veces coordenadas (en % de mapa), editadas a mano y que mezclan versiones del juego. En la Fase 14 se leyeron dos páginas puntuales (Grelin Whitebeard: 786; Sten Stoutarm: 658).
- La política de acceso automatizado (API/robots) **no se ha verificado** [DESCONOCIDO].
- También es la fuente de **documentación de API** (§5): página de sufijos de TOC, `issecretvalue`, valores secretos, etc.

### 3.4 Wowhead
- **No se ha encontrado una API pública** [INVESTIGADO, secundaria: varias referencias de la comunidad]. Sus páginas de condiciones (`/terms-of-use`, `/terms`) devolvieron 404 al leerlas: **términos no verificados**.
- Su `robots.txt` **bloquea expresamente a rastreadores de IA** (entre ellos `ClaudeBot` y `anthropic-ai`) [INVESTIGADO, primaria: leído el fichero].
- Los datos los aportan jugadores con un addon («Looter») [INVESTIGADO, secundaria].
- **Conclusión [PROPUESTA]:** no usar Wowhead como fuente automatizable; como mucho, consulta manual por una persona para contrastar. El `npcID` original de la Fase 3 cita Wowhead como origen, pero eso ya está contrastado en cliente (Fase 14).

### 3.5 Otras fuentes (no verificadas)
- **API de datos de juego de Blizzard (Classic):** requiere credenciales OAuth; la documentación no fue legible desde aquí; **no se sabe si hay endpoint de criaturas ni si cubre Classic Era/Forever** [DESCONOCIDO].
- **wago.tools / exportaciones DB2:** existe la tabla «Creature» (`wago.tools/db2/Creature`); términos y cobertura de versiones **no verificados**. Las DB2 describen datos que el cliente lleva (nombres, modelos, áreas), no *dónde aparece cada NPC* [INFERENCIA]. Sí podrían servir para mapas/áreas/zonas (`AreaTable`, `UiMap`) y para nombres localizados.
- **Captura propia desde el cliente** (§10): la única fuente de verdad sobre lo que el cliente real entrega.

### 3.6 World of Warcraft: Forever — lo público a fecha 2026-10-05

**Hechos anunciados** [INVESTIGADO; prensa y wiki; fiabilidad secundaria/mixta]:
- Lanzamiento **4 de noviembre de 2026**; beta del 17 de septiembre al 22 de octubre; reserva de nombres del 27 de octubre al 3 de noviembre ([Warcraft Wiki: Forever](https://warcraft.wiki.gg/wiki/Forever), [Warcraft Tavern](https://www.warcrafttavern.com/forever/news/warcraft-forever-classic-announced-at-blizzcon-2026/), [Shacknews](https://www.shacknews.com/article/150712/world-of-warcraft-forever-classic-release-date-beta-sign-up)). Alguna fuente da el 16 de septiembre como inicio de la beta: **discrepancia menor, sin resolver**.
- Rama independiente («standalone branch»), **no** en la continuidad del WoW retail; nivel máximo 60 permanente; más de 1 000 misiones nuevas, 9 mazmorras nuevas y 2 bandas; nueva raza (Skyborne); nuevas zonas (Mount Hyjal, Riverglades/«Riverlands», Shen'dralas, Zephyras Isle — **grafías distintas según la fuente**); Dalaran en Alterac Mountains; zonas existentes «ampliadas y con mejoras visuales».
- **Cambios concretos en zonas y NPC existentes: no especificados** en lo leído [DESCONOCIDO].

**Cliente y API** [INVESTIGADO]:
| Dato | Valor encontrado | Fuente / fiabilidad |
|---|---|---|
| Versión de cliente | 1.60.1 | PR de un addon de la comunidad ([fooxytv/AdventureGuideClassic#47](https://github.com/fooxytv/AdventureGuideClassic/pull/47)), vía `GetBuildInfo()` — secundaria |
| `Interface` | **16001** | El mismo PR y guías de terceros — secundaria. La tabla de TOC de la wiki **no** lista aún un número para Forever (celdas vacías). |
| Tipo de juego interno | `camelot` (no `standard`/`classic`/…) | PR + `docs/toc-flavor-selection.md` de QuestieDB — secundaria/primaria de dev |
| `WOW_PROJECT_ID` | **`WOW_PROJECT_MAINLINE`** (igual que retail). El par (`WOW_PROJECT_ID`, `Interface`) es lo que lo distingue. | PR + guías — secundaria |
| Sufijo de TOC | `_Camelot.toc` (provisional: «el sufijo puede cambiar antes del lanzamiento») | [Warcraft Wiki: TOC format](https://warcraft.wiki.gg/wiki/TOC_format) — primaria. El PR **no pudo confirmar** en el juego cuál se respeta. |
| Arquitectura de UI | Comparte la arquitectura de UI de Mainline («la gran mayoría de las API de 12.1.5») | Cita atribuida en prensa; **no pude localizar la cita original**. Secundaria. |
| Restricciones de addons | Las mismas que Midnight (valores secretos, etc.); Blizzard prometió sincronizar restricciones entre ambos juegos | Prensa citando entrevistas (Game Informer, Warcraft Tavern, 14-sep-2026) — secundaria |
| API ausentes/cambiadas | `C_Seasons` ausente; `GetSpellInfo` global retirado (usar `C_Spell.GetSpellInfo`); `COMBAT_LOG_EVENT_UNFILTERED` protegido | PR — secundaria; puntual |
| `issecretvalue` | Existe en Mainline 12.1.5, **Forever 1.60.1**, y también en Classic Era 1.15.9, MoP 5.5.4, TBC 2.5.6 | Warcraft Wiki — primaria |
| Questie | Soporta Forever desde la 12.0.1 (2026-09-25) | Guías de terceros — secundaria |

**No verificado en lo leído (todo [PENDIENTE EN CLIENTE])**: comportamiento de `UnitGUID`/`UnitName`/`GetRealZoneText`/`GetSubZoneText`/`C_Map` en Forever; si el formato del GUID de criaturas es el mismo; si los eventos `GOSSIP_SHOW`, `ZONE_CHANGED*`, `PLAYER_TARGET_CHANGED` existen y con qué semántica; los NPC ID y las ubicaciones de los NPC concretos; los nombres (idioma) de zonas y subzonas; los `uiMapID`.

### 3.7 Estado de la plataforma Classic Era [INVESTIGADO]
Classic Era figura hoy en **1.15.9, `Interface` 11509** (build 69109 en las mediciones de QuestieDB, agosto de 2026; wiki de TOC: 11509). El `.toc` de Chronicle declara **11507** [HECHO]. [INFERENCIA, por el comportamiento general de WoW: no verificada aquí] con un cliente más nuevo el addon podría aparecer como «desactualizado» salvo que el jugador permita addons desactualizados. Que el `.toc` admite varios valores de `Interface` separados por comas sí figura en la wiki [INVESTIGADO]. La prueba manual de la Fase 14 sí funcionó; **el efecto exacto en un cliente 11509 no se ha comprobado aquí**.

---

## 4. Principios de la arquitectura [PROPUESTA]

1. **Dos mundos separados:** *World Data* («qué existe») y *Chronicle Data* («qué contamos»). Ninguna entidad editorial contiene datos técnicos del cliente; ningún dato de mundo contiene lore.
2. **La identidad de Chronicle es un slug estable** (`npc:grelin_whitebeard`), nunca el `npcID`. El `npcID` es un atributo de una *presencia* en una versión.
3. **Todo dato técnico lleva procedencia** (fuente, versión de fuente, fecha, campo, confianza, estado de verificación).
4. **Nada se resuelve en silencio:** conflictos → registro → clasificación → override explícito.
5. **El generador es determinista y puro:** mismas entradas → mismos bytes. Los artefactos generados no se editan a mano y su coherencia con las fuentes se comprueba en tests.
6. **El addon no sabe de fuentes ni de importaciones.** Solo carga un *data pack* generado para su versión y valida su cabecera. Sin dependencias externas.
7. **Las coordenadas no son requisito de nada.** Catálogo, selección editorial, lore y descubrimiento por interacción funcionan sin ellas. Son un dato opcional posterior (mapas, pistas, `Proximity`).
8. **El addon de runtime y la herramienta de captura de datos de desarrollo son productos distintos.**
9. **Lo que no se puede verificar se queda como «desconocido» y se genera como tal**, nunca como un valor inventado.
10. **Diseñar para años:** varias versiones, varios idiomas, cientos de entidades editoriales, miles de candidatos, fuentes que cambian.

---

## 5. Compatibilidad con el cliente: lo que condiciona el diseño

### 5.1 Qué no se puede asumir [PROPUESTA basada en §3]
- Que un NPC de Classic Era tenga el mismo `npcID`, nombre, ubicación o existencia en Forever.
- Que zonas, subzonas, misiones, mapas (`uiMapID`) y nombres localizados coincidan.
- Que Forever sea «Classic Era con otro nombre»: su cliente es de la familia Mainline (comparte arquitectura de UI, `WOW_PROJECT_ID == MAINLINE`, restricciones de Midnight) con un `Interface` de apariencia clásica (16001) [INVESTIGADO].
- Que `WOW_PROJECT_ID` identifique la versión: **no lo hace** en Forever.

### 5.2 Detección de versión [PROPUESTA]
La identidad de la versión debe salir de un **par o conjunto de señales** (`GetBuildInfo()` → versión/build/`Interface`, `WOW_PROJECT_ID`, y la cabecera del propio data pack), no de una sola. Si el pack cargado declara un `flavor` y las señales del cliente no encajan, el addon **no activa el descubrimiento** y lo comunica (`Init.failed`), en vez de funcionar con datos de otro mundo. [PENDIENTE EN CLIENTE: confirmar los valores reales de `GetBuildInfo()` en Forever]

### 5.3 Capa de adaptación del cliente [PROPUESTA]
Hoy las llamadas al cliente están repartidas (`MapPosition`, `NpcDiscovery`, `ZoneDiscovery`, `FreshCharacterCheck`, `Trivia`…). Se propone concentrar las que dependen de la versión en una **interfaz de cliente** («ClientAdapter») con una implementación por versión:
- `GetZoneName()`, `GetSubzoneName()`, `GetMapPosition()`
- `ReadUnitIdentity(unitToken)` → `{ kind, npcID, name }` **o** un motivo (`secret`, `unavailable`, `not_creature`)
- eventos de interacción disponibles (`GOSSIP_SHOW`, etc.) y qué unidad usar
- `GetFlavorInfo()`

Ventaja: `NpcDiscovery`, `ZoneDiscovery` y `MapPosition` dejan de conocer qué cliente hay debajo. **No se implementa ahora.**

### 5.4 Valores secretos y la identificación por GUID [INVESTIGADO + INFERENCIA]
- Según la wiki de API, a partir de 12.0 `UnitName()`/`UnitGUID()` devuelven **valores secretos**: en combate para unidades que no son jugador/grupo; en mapas restringidos (mazmorras, bandas); en PvP; con ciertos *tokens* compuestos. Sobre un valor secreto el addon puede almacenarlo, pasarlo y concatenarlo/formatearlo, pero **no** compararlo, medir su longitud, usarlo como clave ni **analizarlo como cadena** [INVESTIGADO, primaria: `Secret_Values`].
- Forever aplicaría las mismas restricciones [INVESTIGADO, secundaria]. Si las restricciones están activas o no en Classic Era 1.15.x: [DESCONOCIDO] (`issecretvalue` existe en 1.15.9, pero eso no implica restricciones activas).
- **Implicaciones para Chronicle [INFERENCIA]:** (1) el descubrimiento por **conversación** ocurre normalmente **fuera de combate**, así que es compatible con la restricción; (2) el descubrimiento por **ratón/objetivo en combate** podría recibir valores secretos; (3) el lector de identidad debe comprobar `issecretvalue` (o equivalente) **antes** de comparar o analizar, y tratar «secreto» como «no identificable ahora», nunca como error; (4) esto refuerza la decisión de producto de no descubrir por ratón/objetivo.
- **[PENDIENTE EN CLIENTE]:** qué devuelve `UnitGUID("npc")` durante una conversación en Forever, y si es secreto en algún caso.

---

## 6. Arquitectura del pipeline [PROPUESTA]

### 6.1 Flujo conceptual

```
 FUENTES EXTERNAS (solo lectura, versionadas por manifiesto)
   · capturas de cliente real (máxima confianza)   · DB2/exports del cliente (si la licencia/términos lo permiten)
   · bases comunitarias (CMaNGOS/VMaNGOS…) como investigación/validación   · wiki   · otras
        │
        ▼
 IMPORTADORES  (uno por fuente; no deciden nada; emiten registros "tal cual lo dijo la fuente")
        │
        ▼
 NORMALIZACIÓN  → registros de fuente normalizados: { entidad-del-mundo, campo, valor, procedencia }
        │
        ▼
 RECONCILIACIÓN → detecta, clasifica y registra conflictos; aplica jerarquía de confianza + overrides
        │
        ▼
 WORLD DATA  (una vista por versión: classic_era, forever…)   «qué existe en el mundo»
        │
        ├──────────────► ANÁLISIS DE CANDIDATOS  (señales objetivas + score) → informe priorizado
        │                                  │
        │                                  ▼
        │                      REVISIÓN EDITORIAL (humana)  — aceptar / rechazar / posponer
        │                                  │
        ▼                                  ▼
 BINDINGS (entidad Chronicle ↔ identidad técnica, por versión)      CHRONICLE DATA  «qué contamos»
        │                                                                (entidades, lore, pistas, reglas, relaciones)
        └─────────────────────────────┬─────────────────────────────────────────┘
                                      ▼
                              GENERADOR (determinista, puro)
                                      │
                                      ▼
                 DATA PACK Classic Era   /   DATA PACK Forever   (Lua generado, no editable)
                                      │
                                      ▼
                                   ADDON
```
No es obligatorio usar estos nombres; sí preservar la separación conceptual. Los *bindings* son la pieza que une los dos mundos y **son una decisión editorial revisada**, no un resultado automático.

### 6.2 Distribución en el repositorio [PROPUESTA]
```
Chronicle/                      ← lo único que va en el ZIP del addon (hoy)
  Data/Generated/<flavor>/…     ← packs Lua generados (versionados; con cabecera y checksum)
pipeline/                       ← NO va en el ZIP
  sources/<fuente>/manifest.json   ← qué fuente, versión/commit/hash, URL, fecha, licencia, método de obtención
  importers/<fuente>/…
  schemas/…                        ← esquemas de los registros normalizados, bindings, editorial
  reconcile/… analyze/… generate/… validate/…
world/<flavor>/                 ← registros normalizados y vista de World Data (mínimos; ver 6.4)
editorial/
  entities/…                    ← entidades Chronicle (identidad, categoría, importancia, relaciones, descubrimiento, pistas)
  localization/<idioma>/…       ← textos (título, resumen, lore, pistas)
  bindings/<flavor>/…           ← entidad ↔ identidad técnica + estado de verificación
  overrides/…                   ← resoluciones explícitas de conflictos
  rejected/…                    ← candidatos rechazados (para que no reaparezcan)
reports/                        ← informes de candidatos y conflictos (generados; no versionados o en un artefacto de CI)
tests/                          ← existente + pruebas del pipeline
```
La ubicación y el formato concretos son una **decisión pendiente** (D1–D3, §13).

### 6.3 Comandos del pipeline [PROPUESTA]
Conceptuales; los nombres son orientativos:

| Comando | Qué hace |
|---|---|
| `data:import <fuente>` | Ejecuta un importador contra una copia **local** de la fuente fijada en su manifiesto; produce registros crudos con procedencia. |
| `data:normalize` | Registros crudos → registros normalizados (esquema común). |
| `data:reconcile` | Detecta y clasifica conflictos; aplica overrides; produce World Data por versión + informe de conflictos. |
| `data:candidates` | Calcula señales y *score*; genera el informe priorizado de candidatos (no decide nada). |
| `data:validate` | Valida esquemas, bindings, referencias, hints, reglas de descubrimiento, y que no haya conflictos sin resolver en entidades publicadas. |
| `data:generate` | Genera los data packs por versión desde World Data + Chronicle Data. Determinista. |
| `data:check` | Regenera en memoria y verifica que coincide **byte a byte** con lo versionado (como `verify.lua`/`equivalence.lua` de QuestieDB). |
| `test` | Suite actual (harness) + pruebas del pipeline + carga del pack generado en el mock. |
| `build` | Empaqueta el addon por versión (ver §8), sin pruebas ni pipeline. |

### 6.4 Reproducibilidad y tamaño del repositorio [PROPUESTA]
- Cada fuente se fija por **manifiesto** (versión/commit/hash). Las copias completas de bases externas **no se versionan**: viven fuera del repositorio o en caché ignorada.
- Se versionan solo los **hechos mínimos extraídos** (por ejemplo `npcID`, nombre, subname, `npc_flags` de las entidades candidatas), cada uno con su procedencia. Esto minimiza el riesgo de licencia y el tamaño.
- El resultado de cada comando depende solo de entradas fijadas: sin red en `generate`/`validate`/`check`.

---

## 7. Modelo de datos [PROPUESTA]

### 7.1 Entidad Chronicle (editorial; compartida entre versiones)
Contiene lo que **es** y lo que **se cuenta**, sin ningún dato técnico del cliente:
```yaml
id: npc:grelin_whitebeard          # slug estable; nunca cambia (ver D15)
type: npc
status: published                  # candidate | accepted | drafting | review | published | retired
category: [survivor, gnomeregan]   # etiquetas editoriales (no técnicas)
importance: major                  # editorial, no el score
place: subzone:coldridge_valley    # ubicación narrativa (entidad Chronicle)
related_to: [npc:senir_whitebeard]
appliesTo: [classic_era]           # en qué versiones debe existir (editorial)
discovery: { ... }                 # §9
hints:     [ ... ]                 # §9.3
texts: ref → editorial/localization/<idioma>/…   # título, resumen, biografía, pistas
```
- Nombres, resumen, biografía y pistas **no** viven aquí: viven en `localization` (por idioma). El nombre «oficial» del cliente es **dato de mundo**, no editorial.
- `appliesTo` es editorial («esta historia aplica a Forever»); que **exista de verdad** en una versión lo dicen las *presencias*.

### 7.2 Presencia en el mundo (World Presence; por versión)
Lo que sabemos de esa entidad en **una** versión concreta, sin lore:
```yaml
entity: npc:grelin_whitebeard
flavor: classic_era
identity:
  kind: creature
  npcID: { value: 786, source: wow_client, source_version: "1.15.x", confidence: client_verified, verified_at: 2026-10-04 }
  name:  { value: "Grelin Whitebeard", locale: enUS, source: …, confidence: … }
  subname: …
world:
  zone/subzone: [ref a presencias de lugares]          # si se conocen
  coordinates: unknown                                  # permitido; nunca bloquea nada
status: verified | source_confirmed | unverified | conflicted | unavailable
```
Casos soportados explícitamente:
| Caso | Representación |
|---|---|
| Entidad en ambas versiones | Una entidad editorial + dos presencias (`classic_era`, `forever`). |
| Solo en una versión | Una sola presencia; el generador no la incluye en el pack de la otra. |
| Distintos `npcID` por versión | Cada presencia con su `npcID`; la entidad no cambia. |
| Distintas ubicaciones | Cada presencia con sus lugares; la entidad editorial usa su `place` narrativo. |
| Sin datos verificados en Forever | Presencia ausente o `unverified`; `data:validate` impide **publicar** esa entidad en Forever hasta que lo esté (o permite publicarla sin descubrimiento por GUID, según D6). |

### 7.3 Lugares (zonas/subzonas/ciudades)
Hoy son entidades con `parent` y nombres reconocidos por alias a mano. Con el mismo modelo: entidad editorial `zone:dun_morogh` + presencia por versión con los **nombres exactos que devuelve el cliente por idioma** (hoy `Resolver` y `Aliases.lua`) y, cuando se conozcan, identificadores técnicos (`areaID`, `uiMapID`). Los alias de `Aliases.lua` pasan a ser **observaciones de cliente con procedencia** (ya llevan `[C]/[J]/[W]/[O]` como precursor). [INFERENCIA: es el punto con más riesgo en Forever, porque `GetRealZoneText`/`GetSubZoneText` dependen del idioma y de la versión.]

### 7.4 Bindings (la unión editorial entre mundos)
`entity ↔ identity` por versión: «la entidad `npc:grelin_whitebeard` **es** la criatura 786 en `classic_era`». Es una decisión **revisada por una persona** (la crea la aceptación de un candidato) y **no la sobrescribe ninguna importación**. Si una fuente cambia el nombre de la criatura 786, el binding persiste y se **levanta un conflicto** (§7.6) para revisión. Esto es lo que garantiza que lore, pistas y decisión editorial sobrevivan.

### 7.5 Procedencia por campo
Registro conceptual (cada dato técnico):
```yaml
field: npcID
value: 786
source: vmangos                    # id de la fuente (manifiesto)
source_version: "<commit/hash>"
source_url: …
retrieved_at: 2026-…
confidence: high | medium | low | client_verified
verification_status: unverified | source_confirmed | client_verified | conflicted | overridden
notes: …
```
Para lo editorial: `source: chronicle_editorial`, `reviewed: true|false`, `reviewer`, `date`. El `confidence`/`verification_status` ya existe en forma embrionaria (`NpcTargets`: `source_confirmed` / `client_verified`).

### 7.6 Jerarquía de confianza y conflictos
**Jerarquía por campo y por versión** (de mayor a menor), [PROPUESTA]:
1. **Override editorial explícito** (con motivo, autor, fecha y referencia a la evidencia).
2. **Observación en cliente real** de esa versión (`client_verified`), con su build.
3. **Datos extraídos del propio cliente** (DB2/exports) para esa versión, si la licencia y términos lo permiten.
4. **Base comunitaria curada para esa versión** (p. ej. QuestieDB, **solo si** su licencia permitiera usarla; hoy no declara ninguna).
5. **Bases de servidor** (CMaNGOS/VMaNGOS) — versión 1.12; válidas como fuente de investigación/validación de Classic Era, **no** de Forever.
6. **Wiki / contribuciones manuales.**
7. **Fuentes secundarias** (prensa, guías) — solo contexto, nunca dato.
Reglas: un nivel más bajo **nunca pisa** a uno más alto; que dos fuentes del mismo nivel discrepen es un conflicto; un dato observado en el cliente real solo se invalida con otra observación en cliente real o con un override.

**Tipos de conflicto** (se detectan, se registran y se clasifican; ninguno se resuelve en silencio):
| Clase | Ejemplo | Gravedad por defecto |
|---|---|---|
| Identidad | Fuente A: ID 786 → «Grelin Whitebeard»; fuente B: ID 786 → otro nombre | **Bloqueante** si la entidad está habilitada para descubrir. |
| Existencia | Una fuente dice que existe en Forever; otra que no | Alta |
| Ubicación | Fuente: subzona X; cliente: subzona Y | Media (no bloquea el descubrimiento por GUID; sí las pistas con ancla) |
| Nombre/idioma | El cliente devuelve un nombre distinto del esperado en esa locale | Media (afecta a `Resolver`; no al descubrimiento por GUID) |
| Duplicidad | Dos entidades con el mismo `npcID` (ya detectado hoy como `ambiguous_entity`) | **Bloqueante** |
| Deriva de fuente | Una fuente cambia un valor que ya estaba aceptado | Media: informe de cambios; no toca lo editorial |

**Registro de conflicto:** `{ id, clase, entidad/presencia, campo, valores en disputa (con procedencia), gravedad, estado: open | accepted_a | accepted_b | overridden | wontfix, resolución, motivo, revisor, fecha, huella de las fuentes }`. Un **override** queda atado a la huella de las fuentes: si las fuentes cambian, el override **vuelve a levantar** un aviso en vez de quedar ciego para siempre.

**Qué hace el generador [PROPUESTA]:** falla si hay conflictos `open` bloqueantes en entidades que se van a publicar; los demás se listan en el informe. Un conflicto abierto **nunca** se «elige» solo.

### 7.7 Cambios de fuente que no rompen lo editorial
- Las importaciones solo escriben en la capa de **World Data**.
- Lo editorial (entidades, lore, pistas, decisiones, bindings, overrides, rechazados) vive en `editorial/` y se referencia **por ID de Chronicle**: ninguna importación lo toca.
- Una actualización produce un **informe de cambios** (nuevo/cambiado/desaparecido por presencia) y, si procede, conflictos nuevos. Ejemplo: «NPC 786 → nueva ubicación» solo cambia la presencia; el lore, las pistas, las relaciones y la decisión de incluir a Grelin no se alteran.
- Si una presencia **desaparece** de la fuente: el binding queda `unavailable`, la entidad editorial se conserva, y la validación impide publicar un descubrimiento sin presencia verificada.

---

## 8. Varias versiones del juego desde el mismo proyecto [PROPUESTA]

### 8.1 Definición de versión («flavor»)
```yaml
flavor: classic_era | forever
interface: [11507, 11509] | [16001]          # valores soportados (comprobar en cliente)
detect: { … }                                 # señales: GetBuildInfo(), WOW_PROJECT_ID, cabecera del pack
features: { gossipDiscovery: unverified|verified, secretValues: yes|no|unknown, … }
locales: [esES, …]
```
Lo compartido (identidad editorial, lore, textos, pistas, relaciones, categorías, reglas de alto nivel) existe **una sola vez**. Lo específico (presencias, nombres de cliente, mapas, lugares, adaptador de API) existe **una vez por versión**.

### 8.2 Empaquetado por versión: opciones
| Opción | Cómo | A favor | En contra / incertidumbre |
|---|---|---|---|
| **A. ZIP por versión** (recomendada) | El `build` genera un ZIP distinto por versión; cada uno con un `.toc` estándar y solo su pack. | No depende de cómo el cliente elija el `.toc`; sin cargar datos ajenos; tamaño mínimo. | Dos artefactos a distribuir y probar. |
| B. `.toc` con sufijo por versión | `Chronicle_Vanilla.toc`, `Chronicle_Camelot.toc`… | Una sola carpeta. | El sufijo de Forever es **provisional** y el PR no pudo confirmar cuál respeta el cliente [INVESTIGADO]. |
| C. Condiciones en un solo `.toc` (`[AllowLoadGameType …]`) | Líneas del `.toc` filtradas por tipo de juego. | Una sola carpeta y un solo `.toc`. | QuestieDB indica que **no se debe asumir** que `forever`/`camelot` sea seguro sin probar el cliente actual [INVESTIGADO]. |
**Recomendación [PROPUESTA]:** A mientras Forever no esté verificado; B/C se reevalúan cuando haya cliente. Esto no obliga a la arquitectura de datos: los packs son los mismos en las tres.

### 8.3 Cabecera del data pack (validada por el addon al arrancar) [PROPUESTA]
`{ packSchema, flavor, interface, generatedFrom (huella de fuentes + commit), generatedAt, entityCount, checksum }`. `Init` rechaza un pack con esquema desconocido o con `flavor` incompatible con el cliente (queda en `Init.failed`; el resto del addon sigue).

### 8.4 Ejemplos de situaciones
- **Entidad en ambas versiones con distinto `npcID`:** una entidad, dos presencias.
- **Entidad solo en Forever** (p. ej. un NPC de una zona nueva): entidad con `appliesTo: [forever]`; no existe en el pack de Classic Era.
- **Entidad editorial que aún no tiene datos verificados para Forever:** se queda en editorial; `data:validate` impide publicarla en Forever hasta tener presencia verificada.

---

## 9. Descubrimiento y pistas

### 9.1 Regla de producto definitiva (decisión del supervisor) [HECHO como requisito; PROPUESTA como diseño]
- **Lugar descubierto:** el jugador llega a la zona/subzona correspondiente (sistema actual: `ZoneDiscovery` → `Discovery`; **no cambia**).
- **NPC descubierto:** el jugador **cumple el contexto** y **habla/interactúa** con el NPC. **Ver, mouseover, objetivo y placa de nombre no descubren.**
- La Fase 14 validó el **circuito técnico de identificación por GUID** (formato real del GUID, `npcID`, eventos). Esa validación se **reutiliza** (identificar *quién* es), pero la regla de *cuándo* descubrir **cambia** (§12): `NpcDiscovery` pasaría a escuchar solo eventos de interacción y a exigir contexto.

### 9.2 Representación de la regla de descubrimiento en los datos [PROPUESTA]
```yaml
discovery:
  method: interaction              # interaction | proximity (futuro) | event (futuro)
  interaction: [gossip]            # eventos de cliente aceptados; por versión (§8.1 features)
  requires:                        # TODAS deben cumplirse
    - { kind: place_discovered, entity: subzone:coldridge_valley }    # o zona; configurable por entidad
    - { kind: entity_discovered, entity: npc:senir_whitebeard }       # opcional (dependencia narrativa)
    - { kind: hint_seen, hint: hint:grelin_whitebeard_1 }              # opcional (solo si se quiere que la pista sea necesaria)
```
Mínimo exigido por producto: **zona descubierta + interacción**. Los demás requisitos son opcionales y por entidad.

**Coexistencia con `Discovery` [PROPUESTA]:** `Discovery:Discover(id)` y su persistencia **no cambian**. Un servicio nuevo de reglas (`DiscoveryRules`, nombre orientativo) decide *si* se llama a `Discover(id)`: `NpcDiscovery` sigue siendo «identificador» (quién es este NPC) y el servicio de reglas es «autorizador» (¿se cumplen los requisitos?). `DiscoveryNotice`, Codex y el bus de eventos no cambian. No se sustituye el sistema actual.

**Estado de pistas:** «pista vista/leída» necesitaría persistir progreso nuevo. Cualquier persistencia nueva debe pasar por `State` con **migración de esquema** (`schemaVersion` 1 → 2). Es una **decisión** (D6): empezar sin pistas persistidas (las pistas se muestran según lugares/entidades ya descubiertos, derivable del estado actual) evita migrar de entrada.

### 9.3 Modelo de pistas [PROPUESTA]
El objetivo del producto: *explorar → leer → relacionar pistas → investigar → encontrar → hablar → desbloquear → leer la historia.* Las pistas **no son coordenadas**.
```yaml
hint:
  id: hint:grelin_whitebeard_1
  for: npc:grelin_whitebeard           # entidad a la que ayuda a encontrar
  kind: narrative | contextual         # narrativa (lore) o contextual (entorno)
  necessity: required | optional
  tier: 1                              # aparición progresiva (1, 2, 3…)
  reveals_when:                        # cuándo se muestra la pista
    - { kind: place_discovered, entity: zone:dun_morogh }
    - { kind: entity_discovered, entity: npc:sten_stoutarm }
  depends_on: [hint:grelin_whitebeard_0]     # orden dentro de la cadena
  related_to: [subzone:coldridge_valley, npc:sten_stoutarm]   # relación narrativa (no coordenadas)
  text: ref → editorial/localization/<idioma>/hints/…         # nunca inline
  anchors: [subzone:coldridge_valley]  # opcional, interno: para validar que la pista no contradice el lugar
```
Reglas de validación [PROPUESTA]: sin ciclos en `depends_on`; toda pista apunta a una entidad existente; cada entidad con descubrimiento por interacción tiene ≥1 pista **necesaria** o una justificación editorial explícita; **lint** de textos: rechazar patrones de coordenadas («x, y», «/way», pares numéricos); las pistas de una entidad bloqueada no deben revelar su nombre. Qué muestra el Codex y cuándo (UI) **queda fuera de esta fase**.

---

## 10. Detección de candidatos (sin decidir) [PROPUESTA]

### 10.1 Principio
```
miles de NPC → análisis → candidatos priorizados → revisión editorial → Chronicle Entity
```
**SCORE ≠ DECISIÓN EDITORIAL.** El score solo ordena la cola de revisión. Ningún NPC entra o sale de Chronicle por su score.

### 10.2 Señales objetivas
| Señal | Origen típico | Observación |
|---|---|---|
| Nº de misiones que ofrece / completa (`questStarts` / `questEnds`) | Bases de servidor, QuestieDB-like | Lo más informativo sobre relevancia narrativa; depende de la versión. |
| Longitud de cadenas de misiones en las que participa | Relaciones de misión | Requiere datos de cadenas (`PreviousQuestId`…). |
| Menciones en textos de misiones de otros NPC/zonas | Texto de misiones | Señal de relevancia narrativa; requiere acceso al texto (licencia). |
| Relaciones con otros NPC (mismo apellido, misma cadena) | Datos + texto | Alimenta `related_to`. |
| Tipo y banderas (`npc_flags`: vendedor, instructor, posadero, maestro de vuelo…; `rank`: élite/raro) | Plantilla de criatura | **Penaliza**, no excluye: p. ej. el posadero de una aldea puede ser relevante. |
| Nombre genérico/plantilla («Guardia», «Niño», «Vendedor…») | Nombre | **Penalización** fuerte; lista editorial de patrones. |
| Subnombre (título) | `subname` | Indicador de rol (p. ej. «Superviviente de Gnomeregan»). |
| Facción/raza y unicidad | Facción, spawns | Un único spawn con nombre propio suele indicar personaje único. |
| Participación en eventos / escenarios | `game_event_creature` etc. | Opcional. |
| Profundidad de diálogo (gossip) | `gossip_menu`/`npc_text` | Requiere texto. |
| Referencias externas (wiki, novelas, otras fuentes) | Manual | Alimenta la revisión, no el cálculo automático. |
| Relevancia en la zona (rol en el arco de misiones de la zona) | Derivada | Ver cadenas. |

### 10.3 Posible puntuación (orientativa)
`score = Σ wᵢ · señalᵢ − Σ penalizaciones`, con pesos **configurables y versionados**; se calcula **por versión**. Los pesos concretos y los umbrales son una **decisión editorial** (D16). El informe explica el desglose de cada candidato (por qué sube) para que el revisor no dependa de una caja negra.

### 10.4 Flujo editorial y memoria
Estados: `candidate → shortlisted → accepted → drafting → review → published` (+ `rejected`, `deferred`, `retired`). Los rechazados se guardan (`editorial/rejected/`) para que **no reaparezcan** en cada ejecución salvo que cambie su evidencia. Al aceptar un candidato se crea la entidad Chronicle (ID nuevo; ver D15) y su **binding** a la identidad técnica.

---

## 11. Fuentes, fuente de verdad y licencias

### 11.1 Fuente de verdad por tipo de dato [PROPUESTA]
| Dato | Classic Era | Forever |
|---|---|---|
| Identidad técnica del NPC (`npcID`, nombre en cliente) | **Observación en cliente real** (captura/GUID); contraste con bases de servidor/wiki | **Solo cliente real y datos extraídos de ese cliente**; ninguna base 1.12 es autoridad |
| Existencia en la versión | Cliente real | Cliente real |
| Zonas/subzonas (nombres por idioma) | Cliente real (`GetRealZoneText`/`GetSubZoneText`); DB2/exports si procede | Cliente real |
| Mapas / `uiMapID` / `areaID` | Cliente real / DB2 | Cliente real / DB2 (Forever cambia marcos de varios mapas según QuestieDB) |
| Coordenadas de NPC | **Desconocidas hasta nueva decisión** (no bloquean nada); capturadas o de bases con conversión explícita | Desconocidas; **no heredar de Classic Era** |
| Misiones y sus relaciones | Bases de servidor/wiki/cliente | Cliente real (las 1 000+ misiones nuevas no están en bases antiguas) |
| `displayID` / modelo | Cliente real | Cliente real |
| Lore, textos, pistas, importancia, categorías, relaciones narrativas, decisión de inclusión | **Chronicle editorial** | **Chronicle editorial** (con adaptación si cambia la continuidad) |
| Reglas de descubrimiento de alto nivel | Chronicle editorial | Chronicle editorial (+ qué eventos de cliente existen) |

### 11.2 Fuentes por versión
| Fuente | Classic Era | Forever |
|---|---|---|
| Captura propia desde el cliente | **Principal** | **Principal** (imprescindible) |
| CMaNGOS classic-db / VMaNGOS | Investigación/validación (1.12; desfase con 1.15.x) | **No válida** como verdad |
| QuestieDB / Questie | Referencia de ideas; **sin licencia declarada → no reutilizar** | Ídem; además su Forever está en evolución |
| Warcraft Wiki | Contraste manual de IDs/zonas (CC BY-SA) | Contraste manual |
| DB2/exports del cliente (wago.tools u otros) | Candidata para áreas/mapas/nombres (términos sin verificar) | Ídem |
| Wowhead | **No automatizar**; consulta manual como mucho | Ídem |
| API Blizzard | Sin verificar | Sin verificar |

### 11.3 Licencias, atribución y qué NO incorporar
**Aviso:** esto no es asesoramiento legal ni afirma nada de forma absoluta. Donde hay incertidumbre se indica. Recomiendo una revisión legal antes de **redistribuir** cualquier dato derivado de fuentes externas.

| Fuente | Licencia / condiciones conocidas | ¿Descarga automática? | ¿Transformar? | ¿Redistribuir resultados? | Atribución probable | NO incorporar |
|---|---|---|---|---|---|---|
| **CMaNGOS classic-db** | Código/BD bajo **GPL-3.0**; su `COPYRIGHT.md` indica que el contenido de WoW es de Blizzard, que el proyecto se ampara en *fair use* y que no cede derechos sobre ese contenido; sin licencia de redistribución del contenido [INVESTIGADO] | Técnicamente sí (repositorio público de ≈414 MB); **conviene limitarlo a uso local** | Extraer hechos mínimos para uso interno: **incierto** (derivados de una BD GPL y de contenido ajeno) | **Incierto**; no redistribuir tablas; los hechos sueltos (p. ej. un ID) son un caso discutible | Citar el repositorio y su versión | La base completa, tablas completas, textos de misiones/diálogos, coordenadas en masa |
| **VMaNGOS** | `core` **GPL-2.0**; BD distribuida aparte; wiki sin licencia declarada en GitHub [INVESTIGADO] | Idem | Idem | Idem (incierto; las versiones de la GPL pueden ser incompatibles entre sí según se declaren «solo» o «o posterior», y mezclar con el código de Chronicle exigiría analizar la licencia de este) | Citar repo y versión | Idem |
| **QuestieDB / Questie** | GitHub **no declara licencia**; no hay LICENSE en la raíz de QuestieDB [INVESTIGADO]. Sin licencia, por defecto los derechos están reservados | No automatizar | **No** transformar sus datos ni copiar su código | **No** | — (solo citar ideas arquitectónicas, ya documentado) | Todo código y datos |
| **Warcraft Wiki** | Texto **CC BY-SA 4.0**; IP de Blizzard aparte [INVESTIGADO] | Política de acceso automatizado **no verificada** | Hechos sueltos (IDs, nombres): riesgo bajo pero no cero; textos largos: **no** | CC BY-SA impone atribución y compartir igual **a las adaptaciones del texto**; para datos factuales mínimos, incierto | «Warcraft Wiki (CC BY-SA 4.0)» + página y fecha | Párrafos de texto, descripciones de lore copiadas |
| **Wowhead** | Términos **no verificados**; `robots.txt` bloquea rastreadores de IA [INVESTIGADO] | **No** | No | No | — | Todo lo extraído de forma automatizada |
| **Blizzard (API / DB2 / contenido)** | Contenido y marcas de Blizzard; términos de la API **no verificados** | Sin verificar | Sin verificar | Sin verificar | Según términos | Nada hasta verificar |
| **Capturas propias del cliente** | Observaciones de nuestro propio cliente; el contenido sigue siendo de Blizzard; condiciones de la política de addons de Blizzard **no revisadas aquí** | Sí (es nuestro) | Sí | Hechos mínimos con procedencia: bajo riesgo esperado, **sin garantía** | «Observado en el cliente <versión>» | Volcados masivos de textos del juego |

**Lo propio de Chronicle:** el repositorio **no tiene LICENSE** [HECHO]. Antes de incorporar contenido con licencia de reciprocidad (CC BY-SA, GPL) hay que decidir la licencia de Chronicle (D8), porque determina si es viable.

**Política recomendada [PROPUESTA]:** (1) mínimos datos necesarios; (2) cada hecho con procedencia; (3) las bases comunitarias solo como investigación/validación local, sin versionar sus datos; (4) **nada de textos de misiones ni diálogos** de fuentes externas: el lore es **escrito por Chronicle**; (5) revisión legal antes de la primera publicación que contenga datos derivados.

---

## 12. Herramienta de captura de datos (concepto) [PROPUESTA]

**Pregunta:** ¿merece la pena una herramienta auxiliar para observar y exportar datos del cliente real? **Recomendación: sí, pero como producto separado del addon de runtime**, y no ahora.

| | Addon de runtime (Chronicle) | Herramienta de captura (desarrollo) |
|---|---|---|
| Usuarios | Jugadores | Desarrolladores/editores |
| Qué hace | Codex, descubrimiento, avisos | Observa unidades y lugares; exporta registros de observación |
| Datos | Solo lo necesario para jugar | GUID, `npcID`, nombre (por idioma), `subname`, zona, subzona, `uiMapID`, posición **del jugador** (`UnitPosition` solo funciona con el jugador/grupo [INVESTIGADO]), versión/build/`Interface`, fecha |
| Persistencia | `ChronicleCharDB` vía `State` | Su propio fichero de SavedVariables; exportable a JSON |
| Distribución | Pública | Interna; **no** en el ZIP de Chronicle |
| Riesgos | — | Valores secretos (no capturar en combate/instancias); no guardar nombres de jugadores; no volcar textos |

- La Fase 14 ya hizo una captura *manual* (`/chronicle npc` mostró GUID crudo, `npcID`, nombre, evento y unidad). Gracias a ella se verificó en el cliente real el formato del GUID y que los eventos de ratón y de placa de nombre entregan identidad, y se vio una pega de diagnóstico (el nombre aparecía como `nil` para NPC no habilitados). Es un argumento a favor de una herramienta mínima. QuestieDB sigue el mismo patrón (sondas en cliente real + `trace-analyzer`).
- Los registros capturados entran al pipeline como fuente `wow_client`, con **la máxima confianza** (`client_verified`) y su build.
- **Pendiente de decidir (D12):** alcance, formato de exportación, política de privacidad y de uso aceptable. Para Forever es la **única** vía fiable de datos mientras las bases externas no existan o no sean de fiar (en lo leído, QuestieDB documenta que parte de los datos heredados de Forever «aún necesita revisión»; que las bases antiguas puedan quedarse desactualizadas es una [INFERENCIA] razonable, no algo que ese documento afirme así).

---

## 13. Qué cambia en el addon, qué no, y decisiones previas

### 13.1 Partes del addon que cambiarían (en fases futuras, nunca ahora)
| Módulo | Cambio previsto | Motivo |
|---|---|---|
| `Data/Schema.lua` | Separar el esquema de **entidad Chronicle** del de **presencia**; `npcID`/`displayID` salen de la entidad y entran en el pack de mundo; admitir entidades sin presencia en una versión | H1 |
| `Data/Registry.lua` | Cargar entidades desde el pack generado (editorial + presencia de la versión activa) | H1 |
| `Data/NpcTargets.lua` | **Sustituido** por un índice generado `npcID → entidad` por versión (nunca mantenido a mano) | H2 |
| `Services/NpcDiscovery.lua` | De «ver» a «interactuar con contexto»; lectura de identidad a prueba de valores secretos; usar el índice generado | H4, H7 |
| `Services/Discovery.lua` | **API sin cambios.** Posible metadato por entrada (cómo/cuándo) solo si se decide y con migración de `State` | H5 |
| Nuevo servicio de reglas (`DiscoveryRules`) | Decide si se cumple el contexto antes de llamar a `Discover` | §9.2 |
| `Services/ZoneDiscovery.lua` + `Resolver.lua` | Índice de nombres/alias **generado** por versión e idioma; aliases con procedencia | H3, H9 |
| `Services/MapPosition.lua` | Detrás de la interfaz de cliente (§5.3) | §5.3 |
| `Core/State.lua` | Migración 1→2 **solo si** se persiste progreso nuevo (pistas) | §9.2 |
| `Core/Init.lua` | Validar cabecera del pack y versión del cliente; módulos opcionales nuevos | §8.3 |
| `Chronicle.toc` + `build` | Empaquetado por versión; `Interface` revisado | H8 |
| `Localization` | Textos generados desde editorial; más idiomas; base `enUS` | H6 |
| UI (Codex) | Mostrar pistas y estados de desbloqueo; **fuera de esta propuesta técnica de datos** | H6 |

### 13.2 Partes que NO deben tocarse
`Discovery` (API y persistencia) · `Core/Events` · `State` como único dueño de `ChronicleCharDB` · `Popup` y `DiscoveryNotice` · la política de privacidad del Codex (`???`) · los IDs canónicos existentes · el harness y la regla «no debilitar pruebas» · `Proximity` (se deja como punto de extensión) · la capa `Core`.

### 13.3 Decisiones necesarias antes de implementar
| # | Decisión | Recomendación [PROPUESTA] |
|---|---|---|
| D1 | Lenguaje/herramientas del generador y dónde vive | **Node.js** (ya está en el proyecto), carpeta `pipeline/` fuera del ZIP; sin dependencias nuevas en el addon |
| D2 | Formato de los datos editoriales y de texto | YAML/JSON con esquema validado (más cómodo para revisar que Lua); los textos largos en ficheros por idioma |
| D3 | ¿Versionar los packs generados? | **Sí**, con `data:check` en los tests (reproducibilidad y revisión) |
| D4 | Empaquetado por versión | **ZIP por versión** hasta verificar Forever; reevaluar sufijos/condiciones de `.toc` |
| D5 | Regla de detección de versión | Par/conjunto de señales + cabecera del pack; nunca `WOW_PROJECT_ID` solo |
| D6 | Semántica exacta del descubrimiento de NPC: ¿zona o subzona?; ¿qué eventos de interacción valen?; ¿pistas persistidas? | Empezar con **zona descubierta + `GOSSIP_SHOW`** (validado en cliente) y sin pistas persistidas |
| D7 | Qué significa «zona descubierta» para NPC en subzonas | Cadena `parent` hasta la zona; definir en el dato de cada entidad |
| D8 | Licencia del repositorio y política de fuentes externas | Decidir licencia de Chronicle **antes** de importar nada; revisión legal; solo hechos mínimos |
| D9 | Flujo y responsables editoriales | Estados de §10.4; una persona revisora por entidad |
| D10 | Política de pistas (spoilers, lint) | Lint automático + revisión editorial |
| D11 | `Interface` del `.toc` (11507 vs 11509 vs ambos) | Probar en cliente actual; admitir lista de valores |
| D12 | Alcance de la herramienta de captura | Minimalista, separada; decidir tras aprobar esta arquitectura |
| D13 | Idiomas y base `enUS` | Definir idioma base de los nombres «oficiales» y cuántos idiomas |
| D14 | Política de valores secretos | Tratar como «no identificable ahora»; nunca error; probar en ambos clientes |
| D15 | Política de IDs (renombres, retiradas, alias de ID) | IDs inmutables; renombres vía alias; `retired` en vez de borrar |
| D16 | Pesos y umbrales del *score* | Decisión editorial, versionada |

---

## 14. Hoja de ruta propuesta [PROPUESTA; no es un compromiso]
1. **Fase 16 — Separación sin cambio de comportamiento:** dividir el esquema (entidad / presencia) y cargar las **mismas 53 entidades** desde un pack; el addon se comporta igual (tests existentes sin modificar).
2. **Fase 17 — Generador mínimo y pack Classic Era:** reproducir los datos actuales de forma determinista; `data:check` en los tests.
3. **Fase 18 — Captura (herramienta de desarrollo):** observaciones del cliente real → registros con procedencia.
4. **Fase 19 — Importadores + candidatos** (Dun Morogh como piloto), con el informe de conflictos y el flujo editorial.
5. **Fase 20 — Reglas de descubrimiento y pistas** (interacción + contexto) sobre `Discovery` sin cambios.
6. **Fase 21 — Adaptador y pack Forever**, **cuando haya cliente verificable**.
Cada fase termina con revisión del supervisor, como hasta ahora.

---

## 15. Qué queda pendiente hasta poder probar Forever [PENDIENTE EN CLIENTE]
1. `GetBuildInfo()` real (versión, build, `Interface`) y qué señales identifican de forma fiable el cliente.
2. Qué `.toc` carga el cliente (`_Camelot.toc`, `_Mainline.toc`, `.toc` estándar, condiciones de tipo de juego) y si el sufijo cambia antes del lanzamiento.
3. Comportamiento de `UnitGUID`/`UnitName` en `target`, `mouseover`, `npc` (durante conversación) y nameplates; formato del GUID de criaturas; casos de valor secreto.
4. Existencia y semántica de `GOSSIP_SHOW`, `ZONE_CHANGED*`, `PLAYER_ENTERING_WORLD`, `PLAYER_TARGET_CHANGED` y `UPDATE_MOUSEOVER_UNIT`.
5. Nombres exactos (por idioma) de zonas y subzonas; `uiMapID`; zonas nuevas; cambios de marco de mapas (Mulgore, Eastern Plaguelands, Redridge, Stormwind según QuestieDB).
6. Qué NPC existen, con qué `npcID`, nombre y ubicación; cuáles de los NPC de Classic Era ya validados siguen existiendo.
7. Si las restricciones de «valores secretos» están activas para lo que Chronicle lee, y en qué contextos.
8. Efecto de `Interface 11507` en el cliente Classic Era actual (11509).
9. Que no se hayan renombrado la rama, el sufijo ni el `WOW_PROJECT_ID` en la versión de lanzamiento.

---

## 16. Respuestas a las 20 preguntas

| # | Pregunta | Dónde / resumen |
|---|---|---|
| 1 | Arquitectura definitiva del pipeline | §6.1: fuentes → importadores → normalización → reconciliación → World Data → candidatos → revisión editorial → Chronicle Data → generador → packs → addon |
| 2 | Fuentes para Classic Era | §11.2: captura de cliente (principal); bases de servidor/wiki como validación; DB2 si procede |
| 3 | Fuentes para Forever | §11.2: solo cliente real y datos extraídos del mismo; el resto, contexto |
| 4 | Fuente de verdad por tipo de dato | §11.1 |
| 5 | Separar World Data y Chronicle Data | §4, §6.1, §7.1–7.4 |
| 6 | Entidad en varias versiones | §7.2, §8 (presencias por versión + `appliesTo`) |
| 7 | Detectar candidatos | §10 (señales, score orientativo, estados editoriales) |
| 8 | Conservar decisiones editoriales | §7.4, §7.7 (editorial por ID, bindings revisados, rechazados persistentes) |
| 9 | Manejar conflictos | §7.6 (detectar, clasificar, registrar, override ligado a huella de fuentes) |
| 10 | Manejar procedencia | §7.5 y §3.1 |
| 11 | Incorporar datos del cliente real | §12 (herramienta de captura y fuente `wow_client`) |
| 12 | Generar los datos Lua del addon | §6.1–6.4, §8.3 (generador determinista, packs con cabecera y checksum) |
| 13 | Mantener el sistema de Discovery | §9.2, §13.2 (API y persistencia intactas; el servicio de reglas autoriza, `Discovery` registra) |
| 14 | Representar pistas | §9.3 |
| 15 | Evitar que actualizar fuentes rompa Chronicle | §7.7 |
| 16 | Classic Era y Forever desde el mismo proyecto | §8 |
| 17 | Qué partes del addon cambian | §13.1 |
| 18 | Qué partes NO se tocan | §13.2 |
| 19 | Decisiones antes de implementar | §13.3 (D1–D16) |
| 20 | Qué queda pendiente hasta probar Forever | §15 |

---

## 17. Verificación de esta fase
- **Contenido:** este documento es el **único fichero** de la rama respecto a `fase14-npc-discovery`; no cambia nada de `Chronicle/`, `tests/` ni `docs/` previos.
- **Tests:** los existentes se ejecutan sin modificar; el resultado figura en el informe de entrega.
- **ZIP:** no se genera ninguno en esta fase.
- **Nada de esto está probado en WoW:** el documento solo analiza código existente y fuentes externas.

## Anexo A — Fuentes consultadas (2026-10-05)
**Repositorios y documentación técnica (primarias):**
- [Questie/QuestieDB](https://github.com/Questie/QuestieDB) — `README`, `DESIGN.md`, `PROVENANCE.md`, `docs/forever.md`, `docs/forever-data.md`, `docs/toc-flavor-selection.md`, `docs/client-metadata-probes.md`, `src/meta/npcMeta.lua`; metadatos de licencia por la API de GitHub.
- [cmangos/classic-db](https://github.com/cmangos/classic-db) y su `COPYRIGHT.md`; [vmangos/core](https://github.com/vmangos/core); [vmangos/wiki](https://github.com/vmangos/wiki) (`World-Database.md`, `Gossip-System.md`).
- Warcraft Wiki: [Forever](https://warcraft.wiki.gg/wiki/Forever), [TOC format](https://warcraft.wiki.gg/wiki/TOC_format), [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values), [API_issecretvalue](https://warcraft.wiki.gg/wiki/API_issecretvalue), [API_UnitGUID](https://warcraft.wiki.gg/wiki/API_UnitGUID), [Copyrights](https://warcraft.wiki.gg/wiki/Warcraft_Wiki:Copyrights).
- [Wowhead robots.txt](https://www.wowhead.com/robots.txt).

**Secundarias (prensa, guías, PR de terceros):**
- [fooxytv/AdventureGuideClassic PR #47](https://github.com/fooxytv/AdventureGuideClassic/pull/47) (cliente Forever 1.60.1, `Interface` 16001, `camelot`, `WOW_PROJECT_MAINLINE`).
- [Warcraft Tavern](https://www.warcrafttavern.com/forever/news/warcraft-forever-classic-announced-at-blizzcon-2026/), [Shacknews](https://www.shacknews.com/article/150712/world-of-warcraft-forever-classic-release-date-beta-sign-up), [kami-labs.fr](https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/) (restricciones de addons en Forever).
- Guías de terceros sobre addons de Forever (Questie 12.0.1): resultados de búsqueda, sin verificar su exactitud más allá de lo indicado.

**No accesibles o no verificados:** términos de uso de Wowhead (404), publicación oficial original de Blizzard sobre la arquitectura de UI de Forever, términos de wago.tools y de la API de Blizzard, cualquier comportamiento de Forever que requiera su cliente.
