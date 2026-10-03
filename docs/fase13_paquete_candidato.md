# Fase 13 — Limpieza final y paquete instalable (candidata 1)

Commit base: `d3c2578290418728cc8dcd73daf27d1c33a6016f`. Esta fase **no añade funcionalidades ni refactoriza**: audita la reconstrucción, retira lo que
inequívocamente sobre (resultado: **nada**), verifica el `.toc` y genera y verifica un ZIP instalable. **No es una prueba en WoW Classic Era**: la
validación estructural del ZIP no demuestra que el addon funcione dentro del juego.

## 1. Auditoría

**Inventario** **[verificado]**: `Chronicle/` tiene **37 ficheros**: `Chronicle.toc` y **36 ficheros Lua**, todos declarados en el `.toc`.

| Capa | Ficheros |
|---|---|
| Core (7) | `Utils`, `Events`, `State`, `Options`, `FreshCharacterCheck`, `Slash`, `Init` |
| Data (6) | `Schema`, `Registry`, `Entities/Geography`, `Entities/Subzones`, `Entities/Npcs`, `Trivia` |
| Localization (6) | `Localization` y `esES/` (`EasternKingdoms`, `DunMorogh`, `LochModan`, `Ironforge`, `Aliases`) |
| Services (6) | `Resolver`, `Discovery`, `MapPosition`, `Proximity`, `ZoneDiscovery`, `Trivia` |
| UI (11) | `Theme`, `Popup`, `CodexModel`, `CodexScroll`, `CodexNavigation`, `CodexNpcModel`, `CodexPage`, `Codex`, `OptionsPanel`, `MinimapButton`, `Commands` |

**Comprobaciones realizadas y su resultado:**
- **`.toc`:** las 36 rutas declaradas existen; no hay duplicados; **no hay ningún `.lua` en disco que no esté en el `.toc`**; `Chronicle/Core/Init.lua` va el último; `## Interface: 11507`; `## SavedVariablesPerCharacter: ChronicleCharDB` (la única SavedVariable).
- **Código antiguo:** el repositorio de reconstrucción **no contiene código del addon original** (nunca se copió su arquitectura). Búsqueda de rastros de lo antiguo (`ShowLore`, `ToggleCodex`, `codex2`, `TextLinker`, `Chronicle.Data.*`, `discoveredZones/NPCs/Subzones`, `ResetAll`, `LoreFrame`, `CodexFrame`, el interruptor `Chronicle.enabled`): **ninguna coincidencia en código** (la única «coincidencia», `ChronicleCodexFrame`, es el frame del Codex nuevo). No se carga ninguna funcionalidad por duplicado: hay un Popup, un Codex, un Discovery, un minimapa y un conjunto de comandos.
- **SavedVariable:** `ChronicleCharDB` se menciona **solo en `Core/State.lua`** (comprobado por búsqueda y por una prueba existente). Ningún módulo nuevo la referencia.
- **Compatibilidad Lua 5.1:** un análisis de los 36 ficheros (sin comentarios ni contenido de cadenas) no encuentra `goto`, operadores de bits ni `//`, `\x`/`\z`/`\u{}`, `table.unpack`/`pack`/`move`, `utf8`, `math.type`, `xpcall` con argumentos, `setfenv`/`getfenv`, `os`, `io`, `require`, ni metamétodos de 5.2. (`math.atan2`, que 5.3 no tiene, está protegido en `MinimapButton`.) **No se ha podido ejecutar un intérprete Lua 5.1 real** (solo el de las pruebas, 5.3, con fengari).
- **FreshCharacterCheck** **[verificado]**: sigue con las dos correcciones: control de repetición **solo en memoria** (sin `freshCheck.done` ni ninguna escritura persistente), sin referencia a `State` (`requires = { "Discovery" }` en `Init.lua`), y `Evaluate()` exige Discovery antes de decidir por nivel o tiempo.
- **Eventos del cliente registrados** (cada uno una vez, en su módulo): `ADDON_LOADED` (Init), `PLAYER_DEAD` y `PLAYER_CONTROL_LOST` (Trivia), `PLAYER_ENTERING_WORLD` y `TIME_PLAYED_MSG` (FreshCharacterCheck); `ZoneDiscovery`/`Proximity` registran los suyos por su servicio. Eventos internos: `Chronicle.Initialized`, `Chronicle.Discovery.Discovered`, `Chronicle.FreshCharacter.Detected`.

## 2. Qué se retira

**Nada.** No hay ningún módulo de ejecución obsoleto en este repositorio ni se cargan dos implementaciones de lo mismo, y retirar algo «por intuición» está
prohibido. Conservado expresamente: todos los datos canónicos, los textos migrados y los alias, todos los servicios, el Codex y su visor, y lo que usan las
pruebas y la documentación:
- `tests/fixtures/extract_legacy_reference.js`, `legacy_reference.lua` y `legacy_trivia.lua`: herramienta y referencias de las pruebas de migración (Fases 3 y 12); **no** van en el paquete.
- `docs/`: documentación de cada fase; **no** va en el paquete.

**Único cambio de esta fase en el código: tres comentarios desactualizados** (sin ningún cambio de ejecución): la cabecera del `.toc` decía «(futura UI)», `Core/Slash.lua`
decía que los comandos de producto «llegarán en su fase» y `Core/Init.lua` hablaba de «futuros Services y UI». No se tocó ninguna línea de código ni el orden
de carga.

**Dudas sin resolver (se conservan):** `## Version: 0.2.0-dev` sigue en el `.toc` (no hay una convención de versión de candidata en el repositorio; Init la lee de ahí,
y cambiarla no era necesario). Se deja al supervisor decidir si la candidata debe llevar otra versión.

## 3. Paquete

- **Nombre:** `Chronicle-rebuild-candidate-1.zip`. **Ubicación:** `C:\Users\ialiaga\Documents\Claude\_Apps\Chronicle_V2_dist\` (carpeta hermana del repositorio, fuera de él; el ZIP **no** se
  versiona). No se ha tocado el addon original ni `Chronicle-addon.zip`.
- **Cómo se genera** (para que se corresponda exactamente con un commit): desde la raíz del repositorio, con el árbol limpio:
  `git archive --format=zip --prefix=Chronicle/ -o <destino>/Chronicle-rebuild-candidate-1.zip HEAD:Chronicle`. Contiene solo los ficheros **versionados**
  de `Chronicle/`, con `Chronicle/` como raíz del ZIP. No contiene `tests/`, `docs/`, `.git`, `node_modules`, scripts de mutación, registros ni temporales.
- **Instalación:** copiar la carpeta `Chronicle` del ZIP a `World of Warcraft/_classic_era_/Interface/AddOns/`.
- **Verificación del artefacto** (se hace después de generarlo, abriéndolo con una herramienta real): existe y no está vacío; la estructura interna; el `.toc` en
  `Chronicle/Chronicle.toc`; cada ruta del `.toc` existe dentro del ZIP; no hay carpetas de desarrollo; cada fichero es **idéntico byte a byte** al del commit
  (`git show`); SHA-256. Los resultados concretos están en el informe de entrega.

## 4. Pruebas

`npm test` desde `tests`: ver el informe de entrega (resultado real, número de pruebas superadas y fallidas, y código de salida). No se eliminó, omitió ni debilitó ninguna prueba.

## 5. Limitaciones conocidas que requieren una prueba en WoW Classic Era

Nada de esto se ha ejecutado dentro del juego; todo se probó con un mock estricto de la API. Está detallado en los documentos de cada fase, en particular:
- **Codex y visor 3D (Fases 8, 9, 11):** el aspecto, `BackdropTemplate`, `ScrollFrame`, la rueda del ratón, el tipo de frame `PlayerModel`, `SetDisplayInfo`/`SetCreature`/`ClearModel`, y que los 9 `displayID` heredados (no contrastados) muestren al NPC correcto.
- **Posición y descubrimiento (Fase 6):** `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `GetRealZoneText`, `GetSubZoneText`, y que (0, 0) no signifique «sin dato».
- **Minimapa, opciones y comandos (Fase 12):** `Minimap`, `GetCursorPosition`, `GameTooltip`, las texturas del botón, el radio de 80, `InterfaceOptions_*`/`Settings.*` y la plantilla de la casilla.
- **Trivia y FreshCharacterCheck (Fase 12):** `PLAYER_DEAD`, `PLAYER_CONTROL_LOST`, `UnitOnTaxi`, `C_Timer.After` (retardo de 0,1 s del vuelo), `UnitLevel`, `RequestTimePlayed` y `TIME_PLAYED_MSG`.
- **Comportamiento conocido:** FreshCharacterCheck puede repetir su aviso en sesiones distintas mientras se cumplan las condiciones; el aviso no ofrece «Reiniciar» (Discovery no tiene esa operación); con poco descubierto puede no salir ninguna curiosidad.
- **Sin intérprete Lua 5.1 real** para comprobar la sintaxis (solo análisis estático y el intérprete 5.3 de las pruebas).
- TextLinker sigue fuera de alcance.
