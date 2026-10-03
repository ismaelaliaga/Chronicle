# Fase 12 — Minimapa, opciones, comandos, Trivia y FreshCharacterCheck

Estado: implementada y pendiente de revisión del supervisor. Commit base: `133bab78747960e6304a69ac2e8d7ec6e261b5ad` (comprobado al empezar:
`main` en ese commit, árbol limpio salvo `Chronicle.zip`, que ya estaba sin seguimiento). **No se ha empezado la Fase 13 ni se ha retirado código
antiguo.** El addon original y su ZIP **no se han modificado** (el original se ha leído en solo lectura).

Convención de este documento: cada afirmación se marca como **[migrado]** (texto o dato copiado del original), **[verificado en código]**
(se puede comprobar leyendo el repositorio o con las pruebas) o **[sin verificar]** (suposición sobre el cliente real de Classic Era o sobre el
comportamiento del original que no se ha podido comprobar).

## 1. Inspección previa

Se leyeron `Chronicle.toc`, `Core/Init.lua`, `Slash.lua`, `State.lua`, `Events.lua`, `Utils.lua`, `UI/Popup.lua`, `Codex.lua`, `Theme.lua`,
`Services/Discovery.lua`, `MapPosition.lua`, `Resolver.lua`, las pruebas y el harness, y —del original, solo lectura— `Core/Options.lua`,
`Core/Trivia.lua`, `Data/Trivia.lua`, `Core/FreshCharacterCheck.lua`, `Core/Init.lua`, `UI/MinimapButton.lua` y `UI/OptionsPanel.lua`.

| Funcionalidad | Original | En la reconstrucción antes de la fase | Contratos que se reutilizan |
|---|---|---|---|
| Botón del minimapa | `UI/MinimapButton.lua` | no existía | `Codex:Toggle()`, `Theme`, `Options` |
| Panel de opciones | `UI/OptionsPanel.lua` + `Core/Options.lua` | no existía | `Theme:ApplyText`, `Options` |
| Comandos | `Core/Init.lua` (varios subcomandos) | `Slash:Register`, solo `/chronicle` (estado) | `Slash:Register` |
| Trivia | `Core/Trivia.lua` + `Data/Trivia.lua` | no existía | `Popup:Enqueue`, `Resolver`, `Discovery:IsDiscovered` |
| FreshCharacterCheck | `Core/FreshCharacterCheck.lua` | no existía | `Discovery:Count`, `Popup`, `Events` (**ya no `State`**, ver 4.5) |

Hallazgos que condicionan el diseño **[verificado en código]**:
- `State:Set(valor, ruta...)` crea los contenedores intermedios al escribir, así que `("options", nombre)` se guarda
  **sin tocar `schemaVersion`, el estado inicial de State ni Discovery**, y sin escribir nada al arrancar.
- `Discovery` **no tiene operación de reinicio** (`ResetAll` del original no existe) y no debía modificarse en esta fase.
- Las pruebas de arquitectura existentes prohíben que los *Services* referencien `Chronicle.State` (salvo Discovery) y que haya rutas de
  textura fuera de `Theme.lua`: por eso FreshCharacterCheck vive en `Core/` y las texturas del minimapa están en Theme.
- No existe en la reconstrucción ningún aviso automático que dependa del interruptor «avisos automáticos» del original, ni tema pergamino.

## 2. Orden de carga e inicialización

`.toc` (los ficheros nuevos, en su sitio): `Core/Options.lua` y `Core/FreshCharacterCheck.lua` tras `State`; `Data/Trivia.lua` tras los datos de
entidades; `Services/Trivia.lua` tras los servicios; `UI/OptionsPanel.lua`, `UI/MinimapButton.lua` y `UI/Commands.lua` tras el Codex; todos antes
de `Core/Init.lua`.

`Core/Init.lua` — **los seis módulos son opcionales** (`required = false`), así que ninguno puede impedir el arranque ni el anuncio de
`Chronicle.Initialized`. No se cambió el contrato de inicialización global, solo se añadieron entradas:

| Módulo | `requires` | Si falla o su dependencia falla |
|---|---|---|
| `Options` | `State` | `Init.failed` / `Init.skipped`; Trivia y el panel se omiten |
| `Trivia` | `Options` | idem |
| `FreshCharacterCheck` | `Discovery` (ya no `State`) | se omite si Discovery falla; con State de solo lectura funciona igual (no escribe nada) |
| `OptionsPanel` | `Options`, `Theme` | se omite |
| `MinimapButton` | `Theme` | se omite; **no** depende de Options (sin ellas usa la posición predeterminada y no guarda) |
| `Slash` → `Commands` | `Slash` | los comandos se omiten |

## 3. Preferencias disponibles

`Core/Options.lua` **[verificado en código]** guarda por personaje en `("options", nombre)` a través de State; valida al leer (un valor guardado
inválido se ignora y se usa el predeterminado, sin repararlo) y al escribir (`invalid_value`, sin coaccionar); nunca escribe al arrancar.

| Preferencia | Tipo | Predeterminado | Quién la consume | Quién la cambia |
|---|---|---|---|---|
| `triviaEnabled` | booleano | `true` | `Trivia` | casilla del panel de opciones |
| `minimapAngle` | grados finitos, normalizados a [0, 360) | `215` (el del original) | `MinimapButton` | el arrastre del botón (se guarda al soltar) |

**Pospuestas, con su motivo:** «avisos automáticos» (`enabled` del original) y tema pergamino (`loreParchmentTheme`): no hay un consumidor en la
reconstrucción; añadirlas sería poner un control que no hace nada. Se incorporarán con la funcionalidad que las use.

## 4. Módulos

### 4.1 Botón del minimapa (`UI/MinimapButton.lua`)
Un botón de 31×31 hijo de `Minimap`, con el icono y el borde del propio juego (rutas en `Theme`: `MINIMAP_ICON`, `MINIMAP_BORDER`). **Clic
izquierdo → `Codex:Toggle()`** (no hay lógica de ventana en el botón; si el Codex no está disponible lo dice en el chat). Se arrastra con el
botón izquierdo alrededor del minimapa (radio 80, ángulo en grados); **el ángulo se guarda una sola vez, al soltar**, con `Options:Set`.
Tooltip con el título y dos líneas de ayuda. **`OnUpdate` solo existe mientras se arrastra** (necesario para que el botón siga al cursor) y se
retira al soltar y al ocultarse; fuera del arrastre no hay `OnUpdate` ni temporizadores.
API: `Init()` idempotente (un solo botón), `IsReady()`, `GetAngle()`, `SetAngle(a)`, `Toggle()`; `New({...})` para pruebas.
Si falta `Minimap`, el módulo se degrada: no crea nada, lo comunica **una vez** y `Init` no falla. Si la construcción falla a medias, el botón
queda oculto y reintentar da el mismo error sin crear otro botón con el mismo nombre.

### 4.2 Panel de opciones (`UI/OptionsPanel.lua`)
Un panel registrado en las opciones del juego con **un solo control**: la casilla «Curiosidades ocasionales (al morir o al volar)». La casilla
**nunca guarda por su cuenta**: pide `Options:Set` y, si falla, vuelve a mostrar el valor real y lo comunica una vez. Se relee al abrirse el panel.
Estilos de `Theme`; las etiquetas son literales del fichero (Localization solo guarda textos de entidades). `Init` idempotente (un panel, un
registro). Sin ninguna API de registro o sin poder crear la casilla, el módulo no queda listo, lo comunica una vez y no registra nada.
API: `Init()`, `IsReady()`, `Open()` → `true | false, "not_ready"|"unavailable"|"ui_error"`, `Refresh()`.

### 4.3 Comandos (`UI/Commands.lua`, registrados con `Slash:Register`)
`/chronicle` sin argumentos sigue mostrando el estado del Core (Fase 1). Los demás no distinguen mayúsculas **y ninguno admite argumentos**
(con argumentos no se ejecutan y se explica el uso). Un comando desconocido lo contesta `Slash` («comando desconocido: x»).

| Comando | Qué hace |
|---|---|
| `help` | lista los comandos |
| `codex` | abre o cierra el Codex (`Codex:Toggle`) |
| `options` | abre el panel de opciones (`OptionsPanel:Open`) |
| `trivia` | muestra una curiosidad ahora, ignorando el enfriamiento (respeta la preferencia y las reglas de Discovery) |
| `test` | muestra un aviso de ejemplo en el Popup (como el original) |
| `where` | zona, subzona y posición del jugador |

**No se registran** `reset` (necesita un reinicio de Discovery que no existe), el conmutador vacío de «avisos automáticos» (sin consumidor) ni
`codex2` (era del Codex antiguo).

**`/chronicle where`** usa el servicio `MapPosition` y distingue por cada dato (**[verificado en código]** con el servicio real y con dobles):
`disponible` («Zona: X», «Posición: mapa N, x=0.123 y=0.456»), `no disponible (motivo)` (el cliente no lo tiene *ahora*) y `desconocido (motivo)` (no
se puede saber con este cliente). Nunca inventa una ubicación. **Nombres bloqueados:** si el texto del cliente resuelve (por nombre o alias,
con el Resolver) a una entidad que no está descubierta —o no se puede confirmar—, se muestra `???`; un nombre que no es de ninguna entidad se
muestra tal cual. Las coordenadas se muestran siempre (no son nombres). Consultar no descubre nada.

### 4.4 Trivia (`Services/Trivia.lua` + `Data/Trivia.lua`)
**Origen del contenido [migrado]:** los **8 textos** de `Data/Trivia.lua` del original, **literales y en su orden** (una prueba los compara con una
copia literal en `tests/fixtures/legacy_trivia.lua`). No se ha añadido, corregido ni traducido ninguno. El original los describe como redacción propia
que se ciñe a sus datos verificados; **aquí no se han vuelto a contrastar**.

**No son preguntas con respuesta.** El original no tenía quiz: son curiosidades («¿Sabías que...?»). Por eso el módulo no tiene preguntas,
respuestas ni puntuación, y las pruebas de «respuestas» no aplican. *Decisión para el supervisor si se pretendía un quiz.*

Comportamiento **[migrado del original, sin verificar en el cliente]**: se muestra al morir (`PLAYER_DEAD`) y al subir a un vuelo
(`PLAYER_CONTROL_LOST` + `UnitOnTaxi` tras 0,1 s), con enfriamiento de 600 s entre avisos automáticos (`/chronicle trivia` lo ignora). El
único temporizador (`C_Timer.After`, un disparo) es imprescindible porque el evento llega antes de que el cliente refleje el vuelo; sin
`C_Timer` ese disparador no se activa. Se encola con `Popup:Enqueue` (no pisa un aviso visible). Se evita repetir la misma curiosidad dos veces
seguidas si hay otra disponible (el original no lo hacía).

**Política de Discovery (añadida; el original no la tenía):** las curiosidades nombran lugares y personajes. Antes de mostrar una, un guardián
comprueba que **ninguna entidad nombrada** en el texto (frases de 1 a 4 palabras resueltas por el Resolver, por nombre o alias) esté sin
descubrir; cualquier duda (servicio no listo o que falla) la bloquea. Consecuencia: **con poco descubierto puede no salir ninguna**
(`/chronicle trivia` lo explica). Nunca descubre nada. Validación: entradas con `text` cadena no vacía; las demás se ignoran y se cuentan.
API: `Show([ignoreCooldown])` → `true | false, "not_ready"|"disabled"|"cooldown"|"no_content"|"guarded"|"no_popup"|"ui_error"`, `Validate()`, `Init()`
idempotente (un frame, eventos registrados una vez), `IsReady()`.

### 4.5 FreshCharacterCheck (`Core/FreshCharacterCheck.lua`)
**Qué detecta [migrado del original]:** un personaje recién creado (nivel 1, ≤ 30 min jugados) que ya tiene progreso de Chronicle guardado. Causa:
WoW guarda las SavedVariables por nombre+reino, así que borrar un personaje y crear otro con el mismo nombre hereda el progreso del anterior.

**Cuándo se ejecuta:** en `PLAYER_ENTERING_WORLD`, si `UnitLevel("player") == 1`, pide el tiempo jugado (`RequestTimePlayed`, que imprime en el chat
las líneas de «tiempo jugado» del cliente, como el original) **una vez por sesión**; la respuesta llega en `TIME_PLAYED_MSG`.
**Condiciones:** nivel 1, tiempo ≤ 1800 s y `Discovery:Count() > 0` (se pregunta a Discovery; no se lee la SavedVariable).
**Control de repetición: como máximo una vez por SESIÓN, solo en memoria** (corrección posterior a la primera entrega). La petición del tiempo jugado
se hace una sola vez por sesión aunque `PLAYER_ENTERING_WORLD` salte varias veces. Con una respuesta **válida** (tiempo numérico finito ≥ 0 y Discovery
listo) la comprobación queda **completada en esa sesión** —cumpla o no las condiciones— y no se procesa ninguna respuesta más. Con un resultado
**desconocido** (tiempo no válido; Discovery no listo, ausente o que falla) **no** se da por completada, no se avisa y no se escribe nada; tampoco se
reintenta dentro de la misma sesión (la petición es única y su respuesta se consume).

**Por qué NO hay una marca persistente.** La primera versión guardaba `("freshCheck", "done") = true` en State, como el original. Pero esa marca vive en
**las mismas SavedVariables que hereda el personaje nuevo con el nombre de uno borrado**: si el anterior ya la había escrito, el nuevo se saltaba la
comprobación y nunca recibía el aviso. Una marca en esas SavedVariables no garantiza que *este* personaje se haya comprobado, así que no puede usarse
como garantía. Se eliminó: el módulo **no escribe nada** (ni en State ni en las SavedVariables), no necesita State (se quitó de su configuración en
`Init.lua`) y **ignora** cualquier `freshCheck.done` heredado, que además deja intacto. Una sesión nueva siempre puede volver a comprobar.
**Consecuencia aceptada: mientras el personaje siga cumpliendo las condiciones (nivel 1, ≤ 30 min jugados y progreso guardado) el aviso puede volver a
aparecer en otra sesión.** No se evita con ninguna marca persistente.

**Faltan datos / orden de las comprobaciones (`Evaluate`):** primero se valida el tiempo y el nivel (no numéricos, infinitos, NaN o negativos → `unknown`);
**después se exige Discovery SIEMPRE**, antes de mirar nivel o tiempo: ausente, sin métodos, no listo, o que falla al consultar `IsReady()` o `Count()`
→ `unknown`, aunque el tiempo jugado ya superara 1800 s (un «no fresco» tampoco puede afirmarse sin poder consultar el progreso; una respuesta de 4000 s
con Discovery caído NO completa la sesión). Solo entonces: nivel ≠ 1 o tiempo > 1800 s → `not_fresh`; si no, progreso > 0 → `fresh`, sin progreso →
`not_fresh`. (Defecto corregido: la primera versión comprobaba el tiempo antes que Discovery.) **Qué consume el resultado:** emite `Chronicle.FreshCharacter.Detected` (sin argumentos) y, si hay Popup, encola un aviso **informativo**.
**No reinicia, borra ni sobrescribe nada** (hay una prueba y una mutación que lo exigen).
**Desviaciones del original [verificado en código]:** (1) solo atiende la respuesta a su propia petición (el original atendía cualquier
`TIME_PLAYED_MSG`, incluido un `/played` manual en un personaje de otro nivel); (2) **no ofrece «Reiniciar»**, porque Discovery no tiene reinicio:
el aviso lo dice. *Decisión pendiente del supervisor: añadir una operación de reinicio a Discovery en otra fase para restablecer esa opción.*

## 5. APIs de Classic Era pendientes de verificación en un cliente real **[sin verificar]**

Todo se ha probado con un mock estricto; **nada se ha ejecutado en el juego**. Pendientes: el frame global `Minimap` (`GetCenter`,
`GetEffectiveScale`), `GetCursorPosition`, `GameTooltip` y las texturas `Interface\Icons\INV_Misc_Book_09` y `Interface\Minimap\MiniMap-TrackingBorder`;
el radio fijo de 80 (asume el minimapa redondo clásico); `InterfaceOptions_AddCategory`, `InterfaceOptionsFrame_OpenToCategory` y la API moderna
`Settings.*`; la plantilla `InterfaceOptionsCheckButtonTemplate`; los eventos `PLAYER_DEAD`, `PLAYER_CONTROL_LOST`, `PLAYER_ENTERING_WORLD`,
`TIME_PLAYED_MSG` y las funciones `UnitOnTaxi`, `UnitLevel`, `RequestTimePlayed`, `GetTime`, `C_Timer.After`; y el retardo de 0,1 s del vuelo. Las
APIs de posición (`C_Map...`) ya estaban sin verificar desde la Fase 6.

## 6. Pospuesto

| Qué | Por qué |
|---|---|
| `/chronicle reset` y «Reiniciar progreso» (comando, panel y aviso) | requieren un reinicio de Discovery que no existe; Discovery no se modifica en esta fase |
| «Avisos automáticos» y tema pergamino | sin consumidor en la reconstrucción |
| Una opción para ocultar el botón del minimapa | el original no la tenía |
| Preguntas/respuestas de Trivia | el original no tiene quiz; no se inventa contenido |
| Integración de Trivia con Discovery (descubrir al contestar) | no hay respuestas; el original tampoco lo hacía |
| TextLinker, Fase 13 | fuera de alcance |

## 7. Verificación

`npm test` desde `tests`: **1549 superadas, 0 fallidas, código de salida 0** (1356 de las fases 1 a 11 y 193 de `tests/integrations_tests.lua`; ver «Corrección de FreshCharacterCheck» al final de esta sección). Son
pruebas con el **mock estricto** (se añadieron al mock `Minimap`, `GameTooltip`, `GetCursorPosition`, `GetTime`, `C_Timer`, `UnitLevel`, `UnitOnTaxi`,
`RequestTimePlayed`, `InterfaceOptions_*`, `CheckButton`); **no demuestran** que esas APIs existan ni se comporten así en el cliente real.

Cubren: inicialización correcta e idempotente de cada módulo (un solo frame, un solo registro de eventos, un solo registro en las opciones, un solo botón,
sin comandos duplicados); preferencias (predeterminados, escritura solo por State, normalización, rechazo de valores no válidos sin coaccionar, valores
guardados corruptos o editados a mano, State en solo lectura o que no guarda, nada se escribe al arrancar); Trivia (los 8 textos idénticos al original,
contenido válido, vacío y no válido, enfriamiento, preferencia, no repetir seguida, guardián de Discovery, Popup ausente o que rechaza, eventos del
cliente y el temporizador de un disparo, y con los servicios reales Discovery/Resolver/Popup); FreshCharacterCheck (cada condición, cada dato que
falta, una sola vez, nada se toca de Discovery, y con el addon real); minimapa (posición, clic abre el Codex real, arrastre, guardado una sola vez,
ángulo inválido, sin Minimap, sin Options, Codex roto, construcción a medias); panel (un control, guardado, reversión si falla, API clásica y moderna,
sin API, sin plantilla); comandos (válidos, con argumentos, desconocidos, módulos rotos) y `/chronicle where` (disponible, no disponible, desconocido, servicio
que falla, ausente, y **nombres bloqueados que no se filtran** por nombre ni por alias); fallos independientes de cada módulo opcional; y que ningún módulo
nuevo referencia la SavedVariable, llama a `Discover`, usa temporizadores u `OnUpdate` fuera de lo declarado, ni define rutas de textura o colores propios.

**Pruebas anteriores modificadas** (ninguna eliminada ni debilitada): `core_tests` — el aviso de «subcomando aún no implementado» usaba `where`, que ahora
existe; usa `reset`, que sigue sin implementarse; `popup_tests` 1f — los nombres globales permitidos incluyen los del panel y el botón del minimapa.

**Mutaciones** (criterio estricto: solo cuenta una aserción `[FAIL]` clara): **69 mutaciones, las 69 detectadas por aserciones**; tras cada una se restauró
el fichero y al final se verificó que todos eran idénticos a la versión final. **Una** (`T16`, quitar la textura del icono de Theme) deja además una
excepción de Lua posterior, tras 11 aserciones fallidas claras. Cubren las preferencias (sin validar, sin normalizar, sin comprobar lo guardado, solo
lectura, predeterminados, escritura al arrancar), Trivia (enfriamiento, preferencia, entradas inválidas, repetición, guardián, vuelo, rechazo del Popup,
frames duplicados, titulo, temporizador), FreshCharacterCheck (nivel, peticiones repetidas, `/played` ajeno, umbral, progreso, resultado desconocido,
marca de hecha, evento, borrado de Discovery, solo lectura, Discovery no listo, frames duplicados), el minimapa (guardar en cada fotograma, `OnUpdate` al
soltar y al ocultar, clic, duplicados, ángulo inválido, ruta de textura en el módulo, falta de `Minimap`, aviso repetido, visible al crearlo), el panel (no
guardar, no revertir, doble registro, duplicados, registro sin casilla, `IsReady`, releer al abrir), los comandos (nombres bloqueados, Resolver no listo,
argumentos, estados mal etiquetados, ayuda, Codex), las dependencias de `Init.lua` y Theme.

**Historial (transparencia):** la primera pasada completa dio 59 de 69. Había huecos reales de las pruebas (que el ángulo guardado esté normalizado, que
se compruebe lo guardado con un State que miente, que el Resolver no listo oculte el nombre, el botón creado visible, una posición no numérica, y
llamadas sin proteger que hacían caer el script en vez de fallar una aserción) y **dos mutantes equivalentes** por doble guarda (`ready` + frame en
Init de Trivia y de FreshCharacterCheck: cada guarda sola no cambia nada), que se sustituyeron por la mutación de ambas a la vez. La revisión descubrió
además un **defecto real** del botón: si su construcción fallaba a medias, reintentar `Init` creaba otro botón con el mismo nombre; ahora queda
oculto y reintentar da el mismo error. Tras corregirlo se repitió la batería completa desde un estado limpio. No se interrumpió ninguna ejecución.


### Corrección de FreshCharacterCheck (Discovery exigido antes de decidir)

Caso límite detectado en la revisión de `8fda0a7`: `Evaluate()` devolvía `not_fresh` por tiempo > 1800 s **antes** de comprobar Discovery, de modo que una
respuesta válida de tiempo jugado completaba la sesión con Discovery ausente, no listo o fallando. Ahora Discovery se exige siempre antes de decidir
(ver 4.5). Pruebas añadidas (26; bloques `14` y `15`, con `Evaluate()` **y** el flujo integrado por eventos): Discovery no listo, `IsReady()` que lanza
error, `Count()` que lanza error o devuelve algo no numérico, sin métodos y ausente, cada uno con 4000, 1800 y 60 s → `unknown`, sesión sin completar,
sin evento y sin aviso (y con otro nivel); el desconocido no se reintenta aunque Discovery se recupere; Discovery operativo con más de 1800 s → `not_fresh`
completada; ≤ 1800 s sin progreso → `not_fresh` completada; ≤ 1800 s con progreso → `fresh`, aviso único y completada; nivel distinto de 1 → `not_fresh`. La
prueba `10d` pasó a llamadas protegidas. Con el código anterior fallaban 19 de esas aserciones. `npm test`: **1549 superadas, 0 fallidas**. Mutaciones:
**16, las 16 detectadas por aserciones claras** (`V14`, aceptar un tiempo no válido, deja además una excepción posterior); cubren restaurar el defecto, ignorar
Discovery no listo, error de `IsReady`, error o valor no numérico de `Count`, Discovery ausente, los umbrales de tiempo y nivel, el progreso, completar o
no según el resultado, reintentar, y avisar o no. Primera pasada: 15 de 16 (el que faltaba solo producía una excepción por llamadas sin proteger).

### Corrección de FreshCharacterCheck (marca persistente retirada)

Defecto detectado por el supervisor en la entrega `96bec01`: la marca persistente `freshCheck.done` se heredaba con el progreso del personaje anterior y
podía impedir el aviso en el nuevo (ver 4.5). Corrección: el control de repetición pasa a **memoria de la instancia**, por sesión; se eliminan la marca y
la dependencia de State (módulo, `Init.lua` y pruebas). **No cambian** las condiciones de detección, el uso de Discovery por su API pública, la
inicialización idempotente ni la protección contra eventos duplicados.

Pruebas (11 más en esta corrección; ninguna eliminada o debilitada salvo las que afirmaban lo contrario de lo corregido y se reescribieron): una comprobación
válida se procesa una vez por sesión; `PLAYER_ENTERING_WORLD` repetido no duplica peticiones; una respuesta válida no genera una segunda comprobación (ni
tras un resultado negativo); un resultado desconocido (Discovery no listo o que falla, tiempo inválido) **no** cuenta como detección negativa válida ni
completa la sesión; **una instancia nueva comprueba de nuevo aunque las SavedVariables traigan `freshCheck.done = true`** (simulado explícitamente con el
addon completo y con una instancia aislada); no se escribe ninguna marca (`State:Set` no se llama y las SavedVariables, incluida la marca antigua, quedan
idénticas); se conserva la detección de progreso heredado; no hay aviso si no se cumplen las condiciones; y una segunda sesión con las mismas SavedVariables
puede volver a avisar. Pruebas reescritas: las que exigían guardar la marca, que State de solo lectura impidiera inicializar y que `Init` dependiera de State.

Mutaciones de esta corrección: **18, las 18 detectadas por aserciones claras**; una (`R17`, aceptar un tiempo no numérico) deja además una excepción
posterior. Cubren guardar una marca persistente, dejar que una marca antigua bloquee, pedir el tiempo en cada pantalla de carga, atender respuestas sin
petición propia, completar con un resultado desconocido o no completar con uno válido, procesar respuestas tras completar, permitir pedir otra vez, no
comprobar el nivel, el umbral, el progreso, el aviso, el borrado de Discovery, asumir progreso sin Discovery, frames duplicados, la dependencia de Discovery,
tiempos no válidos y el nivel exigido. Primera pasada: 17 de 18; el mutante no detectado (quitar la guarda de «completada») era **equivalente** por doble
guarda (la petición única y la respuesta consumida ya impiden reprocesar) y se sustituyó por quitar ambas. Ficheros restaurados y verificados idénticos.

## 8. Decisiones que requieren al supervisor

1. **Persistencia nueva en `ChronicleCharDB`:** `options` aparece **solo al escribirse**, por `State:Set`, sin cambiar `schemaVersion`
   ni el estado inicial (FreshCharacterCheck ya no escribe nada). Si se considera un cambio de estructura que exige declararlo en `State`/migración, hay que decidirlo.
2. **Trivia sin preguntas:** el original son curiosidades, no un quiz.
3. **Guardián de Discovery en Trivia:** hace que, con poco descubierto, no salga ninguna curiosidad.
4. **Reinicio de progreso:** pospuesto hasta que Discovery tenga esa operación.
5. **`OnUpdate` durante el arrastre del minimapa:** necesario para seguir al cursor; alternativa sin él: mover solo al soltar.
