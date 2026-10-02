# Fase 6: MapPosition + Proximity (y detección de zonas)

Tres servicios con responsabilidades separadas, todos sin estado persistente propio y sin interfaz:

| Servicio | Responsabilidad |
|---|---|
| `Chronicle.MapPosition` | Leer y **validar** la ubicación del jugador según el cliente: posición en el mapa, nombre de zona y nombre de subzona |
| `Chronicle.Proximity` | **Motor genérico** de proximidad: dada una posición y una lista de objetivos espaciales, pide el descubrimiento a Discovery |
| `Chronicle.ZoneDiscovery` | Descubre la zona/ciudad y la subzona actuales **por nombre**, resueltos con el Resolver. No usa coordenadas |

> **Estado real, dicho sin rodeos:** hoy **no existe ningún dato espacial verificado**. Proximity está
> terminado y probado como motor, pero con los datos actuales **no puede descubrir ningún NPC por distancia**.
> La detección de zonas y subzonas por nombre sí funciona (cuando el nombre se reconoce).

## APIs de WoW utilizadas y qué se ha verificado

**Ningún cliente de WoW se ha ejecutado durante esta fase.** «Verificado» aquí significa solo lo que se indica en
cada columna; ninguna API está demostrada en un cliente real por este desarrollo.

| API | Uso | Documentación pública (Warcraft Wiki, consultada) | Anotado como confirmado jugando por el addon original | Verificada en cliente real aquí |
|---|---|---|---|---|
| `C_Map.GetBestMapForUnit("player")` | mapID del jugador | **No indica disponibilidad en Classic**; solo «Patch 8.0.1: Added» | La usaba; anotó que las funciones antiguas ya no existen y que `C_Map` sí | **No** |
| `C_Map.GetPlayerMapPosition(mapID, "player")` | objeto con `:GetXY()` | Lista disponibilidad en vanilla; devuelve un `vector2` con `GetXY()`; **nil en contenido instanciado** | La usaba | **No** |
| `GetRealZoneText()` | nombre de zona/ciudad | Disponible en vanilla; «nombre de la instancia de mapa», localizado; distinto de `GetZoneText()` | Confirmó que devuelve p. ej. «Ciudad de Forjaz» | **No** |
| `GetSubZoneText()` | nombre de subzona | Disponible en vanilla; devuelve `""` si no hay subzona | Confirmó «El Trono» y «Ciudad Manitas» | **No** |
| Eventos `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD` | disparar ZoneDiscovery | `ZONE_CHANGED` listado en vanilla («al entrar en una subzona exterior»); los otros dos se mencionan como relacionados; `PLAYER_ENTERING_WORLD` no se consultó | Los registraba su detector de zonas | **No** |

Qué significa cada columna: la documentación se consultó y se resume tal como figura; el original dejó esas
notas en sus comentarios y **no se han reverificado**. En particular, la disponibilidad de
`C_Map.GetBestMapForUnit` en Classic Era descansa solo en lo anotado por el addon original, porque la página
pública no la confirma ni la desmiente.

**Salvaguardas:** todo acceso va con comprobación de existencia y dentro de `pcall`. `RegisterEvent` con un
nombre desconocido lanza error en el cliente: se protege y se comunica sin impedir el resto.

**No se usan** `SetMapToCurrentZone()` ni el `GetPlayerMapPosition` global (el original anotó que no existen),
ni `UnitPosition`, `C_Map.GetMapInfo`, `C_Map.GetWorldPosFromMapPos` o `C_Map.GetMapWorldSize`: no se ha podido
comprobar que existan o sirvan en Classic Era.

## MapPosition

Zona, subzona y posición son **tres conceptos distintos**: ninguno se deduce de otro.

```lua
local MP = Chronicle.MapPosition
MP:GetPosition()     --> "available", { mapID, x, y } | "unavailable", motivo | "unknown", motivo
MP:GetZoneName()     --> "available", "Dun Morogh"    | "unavailable", "empty" | "unknown", motivo
MP:GetSubzoneName()  --> "available", "Kharanos"      | "unavailable", "empty" | "unknown", motivo
```

| Estado | Significa | Motivos |
|---|---|---|
| `available` | dato fiable | — |
| `unavailable` | el cliente no lo tiene **ahora** (tras cargar, en instancias…): reintentar tiene sentido | `no_map`, `no_position`, `incomplete`, `no_data`, `empty` |
| `unknown` | no se puede saber o no es creíble: falta una API, falló, o devolvió algo imposible | `api_missing`, `api_error`, `invalid_map`, `invalid_coordinates`, `invalid_value` |

- `mapID`: entero positivo. `x`, `y`: números **finitos** en **[0, 1]**: coordenadas normalizadas de ese mapa.
- **`(0, 0)` exacto se trata como «sin datos»** (`unavailable`/`no_data`), nunca como posición. Una posición con
  `x = 0` o `y = 0` pero no ambas es válida (borde del mapa).
- No convierte coordenadas entre mapas ni compara posiciones. No crea frames ni temporizadores y no tiene `Init`.
- La posición devuelta es una tabla nueva en cada llamada.

**Inyección:** `Chronicle.MapPosition.New(api)`, con `api = { C_Map = { GetBestMapForUnit, GetPlayerMapPosition },
GetRealZoneText, GetSubZoneText }` (o una función que la devuelva). La instancia por defecto lee los globales del
cliente **en cada llamada**.

## Proximity

```lua
local P = Chronicle.Proximity
P:SetTargetProvider(function() return { target1, target2 } end)   --> true | false
local r = P:Evaluate()
-- r = { status, reason, discovered = {ids}, rejected = { {id, reason} }, targets, invalid,
--       alreadyDiscovered, otherMap, outside, inside }
```

**Objetivo espacial** (la interfaz mínima de quien los proporcione; **no** es el Schema):

```lua
{ id = "npc:...", mapID = <entero>, x = <0..1>, y = <0..1>, radius = <0 < r <= 1>, verified = true }
```

`verified` debe ser exactamente `true`: quien proporcione el objetivo declara que `x`, `y` y `radius` se
comprobaron en el cliente real. Sin eso se rechaza y nunca se activa.

| `status` de `Evaluate()` | Cuándo |
|---|---|
| `not_ready` | no inicializado, o falta MapPosition/Discovery |
| `provider_error` | el proveedor lanzó error o no devolvió una lista |
| `no_targets` | no hay objetivos (no se consulta la posición) |
| `position_unavailable` / `position_unknown` | MapPosition no da una posición fiable; `reason` = su motivo |
| `evaluated` | se evaluaron los objetivos |

- **Rechazos** (`rejected`): `invalid_target`, `invalid_id`, `unverified`, `invalid_map`, `invalid_coordinates`,
  `invalid_radius` (objetivo mal formado) o el motivo de Discovery (`unknown_entity`, `persist_failed`,
  `read_only`, `not_ready`, `discovery_error`). **Un rechazo nunca se cuenta como descubrimiento.**
- **Idempotente:** un objetivo ya descubierto se salta sin calcular distancia ni llamar a `Discover`.
- Un objetivo de **otro mapa** no se compara (`otherMap`). Un ID desconocido solo se rechaza al intentar
  descubrirlo (dentro del radio).
- Una consulta de posición y una de proveedor por `Evaluate()`. No busca NPC en el mundo.
- Escribe solo a través de `Discovery:Discover(id)`; no toca `State` ni `ChronicleCharDB`.

### Cómo se calcula la distancia, y sus límites

Distancia **euclídea en unidades de mapa normalizadas**, dentro de un mismo `mapID`. Se compara al cuadrado
(`dx² + dy² <= radius²`, sin raíz), así que **estar exactamente en el radio cuenta como dentro** y no hay error de
redondeo por la raíz.

**No es una distancia física del mundo.** Los mapas no son cuadrados ni tienen el mismo tamaño real: una unidad
en `x` no equivale a una en `y`, y un mismo radio abarca más o menos terreno según el mapa. Por eso el radio de
cada objetivo debe haberse ajustado a **su** mapa. No se ha encontrado una API verificada para convertir a yardas,
y no se ha supuesto ninguna. Si el cliente no da un `mapID` y unas coordenadas fiables, no se calcula nada.

### Quién llama a `Evaluate()`

**Nadie, todavía.** Hacerlo periódicamente exige un temporizador (p. ej. `OnUpdate` con intervalo), que se ha
dejado fuera a propósito: no tiene sentido hasta que haya objetivos verificados y es una decisión de diseño
pendiente (ver más abajo).

## ZoneDiscovery

```lua
local Z = Chronicle.ZoneDiscovery
Z:Check()  --> { status = "checked", zone = salida, subzone = salida } | { status = "not_ready" }
-- salida = { name, status, id, reason, candidates }
```

| `status` de una salida | Significado |
|---|---|
| `discovered` | descubrimiento nuevo guardado |
| `already` | ya estaba descubierto: no se repite nada |
| `unavailable` | MapPosition no entrega el nombre (nil, `""`, error, API ausente); `reason` = su motivo |
| `unrecognized` | el Resolver no conoce ese nombre con ese tipo |
| `ambiguous` | varias entidades; `candidates` ordenados; **no se descubre ninguna** |
| `resolver_not_ready` | el índice del Resolver no está listo |
| `failed` | Discovery lo rechazó (`reason` = su motivo): nunca es un éxito |

Reglas: la zona se resuelve solo como `zone` o `city` (si el nombre vale para ambas es ambiguo) y la subzona solo
como `subzone`, **nunca al revés**. Solo se llama a `Discover` con una resolución inequívoca. Cada nombre se trata
de forma independiente. No usa coordenadas, mapas ni distancias, y no escribe en el estado.

**Cuándo se comprueba:** `Init()` crea **un único frame sin interfaz** que escucha `PLAYER_ENTERING_WORLD`,
`ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` y `ZONE_CHANGED_INDOORS` (los mismos que usaba el addon original) y
llama a `Check()`. No usa temporizadores. Un error dentro de `Check` o al registrar un evento se comunica por
`geterrorhandler` y no se propaga. Es lo único que hace falta para que funcione solo.

## Qué se puede descubrir ya y qué queda pendiente

| Tipo | ¿Se activa ya? | Cómo |
|---|---|---|
| Zonas y ciudades | **Sí**, si el nombre se reconoce | ZoneDiscovery, por nombre |
| Subzonas | **Sí**, si el nombre se reconoce | ZoneDiscovery, por nombre |
| NPC por distancia | **No** | Proximity no tiene objetivos verificados |
| NPC por apuntarlos, continentes, lore | **No** | fuera de esta fase |

### Alias que faltan (documentados, **no añadidos**)

El Resolver tiene 22 alias en español heredados de la fuente (todos de la Fase 4). En un cliente en español, las
subzonas cuyo nombre difiera del inglés **solo se reconocerán si tienen alias**. Hoy **18 de las 40 subzonas**
tienen alias; **22 no**. Para algunas el nombre en español puede ser idéntico al inglés (nombres propios) y no
necesitar alias, pero **no se ha verificado cuáles**:

- **Dun Morogh (7):** Coldridge Valley, Kharanos, Brewnall Village, Shimmer Ridge, South Gate Outpost, South Gate Pass, Gnomeregan.
- **Loch Modan (12):** todas: Thelsamar, The Loch, Stonewrought Dam, Valley of Kings, Grizzlepaw Ridge, Stonesplinter Valley, The Farstrider Lodge, Ironband's Excavation Site, Silver Stream Mine, Mo'grosh Stronghold, Algaz Station, Dun Algaz.
- **Forjaz (3):** The Mystic Ward, The Forlorn Cavern, Hall of Explorers.

Pendiente de verificación en un cliente en español (con el nombre exacto que devuelve `GetSubZoneText()`); no se
han añadido por intuición. Los alias existentes conservan la procedencia anotada en `Aliases.lua`.

## Estado de los datos espaciales de los NPC

- El addon original tenía `x`, `y` y `radius` en **7 de los 9 NPC**; Magni y Mekkatorque no tenían. La propia
  fuente los marca como **no verificados en el cliente real**. Tampoco registraba el `mapID` de ninguna zona.
- **No se han migrado ni inventado**: ni coordenadas, ni radios, ni mapIDs. El Schema no tiene dónde ponerlos y
  no se ha tocado.
- Por eso la instancia por defecto de Proximity **no tiene proveedor de objetivos**.

### Decisión pendiente (no se ha tomado): cómo guardar los datos espaciales

Proximity no necesita el Schema (recibe los objetivos por un proveedor), así que esta fase no cambia nada. Antes
de poder usar Proximity en el juego hay que decidir dónde viven los datos. Dos opciones, sin implementar:

- **A. Fichero de datos espaciales aparte** (p. ej. `Data/Spatial/…`), indexado por ID de entidad, que registre
  los objetivos con `verified = true` solo cuando estén comprobados, y un proveedor que los entregue a Proximity.
  *Ventajas:* no toca el Schema ni las entidades, separa lo canónico de lo medido y se puede ir verificando
  objetivo a objetivo. *Implicación:* una segunda fuente de datos por ID que hay que validar contra el Registry.
- **B. Ampliar el Schema** con un campo espacial opcional en los NPC. *Ventajas:* un único sitio por entidad.
  *Implicaciones:* cambio de diseño aprobado, mezcla lo canónico con datos medidos y falibles, y obliga a
  decidir el formato (mapID incluido) antes de tener ninguna medida.

Recomendación: **A**, pero la decisión es del responsable. En cualquier caso hace falta **medir en el cliente
real** (mapID, `x`, `y` y radio útil de cada objetivo); sin eso no hay datos verificables.

## Pruebas

```
cd tests
npm test
```

Resultado de la ejecución final: **767 superadas, 0 fallidas, código de salida 0** (561 de las fases 1 a 5 y
206 nuevas: 35 de MapPosition en `mapposition_tests.lua`, 95 de Proximity en `proximity_tests.lua` y
76 de ZoneDiscovery en `zonediscovery_tests.lua`).

### Cómo se inyectan las dependencias

- **MapPosition:** `MapPosition.New(api)` con una API simulada que devuelve cualquier respuesta del cliente
  (posiciones válidas o inválidas, `nil`, errores, funciones ausentes, coordenadas fuera de rango…).
- **Proximity:** `Proximity.New({ mapPosition, discovery, targets })`: una posición simulada, un proveedor de
  objetivos inyectado y un **Discovery real** (`Discovery.New`) sobre un `State` simulado que permite probar
  guardado correcto, `Set` que falla o que miente, solo lectura y estado no listo. Los casos de distancia usan
  valores exactos en binario (radio 0,625 = distancia exacta) para que la igualdad sea rigurosa.
- **ZoneDiscovery:** `ZoneDiscovery.New({ mapPosition, resolver, discovery, createFrame })` con el Resolver y los
  datos migrados reales, nombres simulados y una fábrica de frames simulada. El cableado con la instancia por
  defecto se prueba con el `FireEvent` del arnés y `GetRealZoneText`/`GetSubZoneText` definidos temporalmente.

### Cobertura de lo pedido

Dependencias ausentes o no listas; posición desconocida, nil, incompleta e inválida; coordenadas dentro y fuera
de rango (incluidos los límites 0 y 1 y `(0, 0)`); mapas incompatibles; distancia exactamente igual al radio,
dentro y fuera; radios negativos, nulos, no numéricos, infinitos y mayores que 1; objetivos desconocidos o mal
configurados; descubrimiento nuevo guardado; objetivo ya descubierto sin nuevo descubrimiento; fallos de
persistencia y solo lectura; zona/subzona correcta, ambigua, vacía, desconocida y de tipo equivocado; APIs que no
existen, fallan o devuelven resultados incompletos; inicialización y dependencias en `Core/Init`; ausencia de
escritura directa en `ChronicleCharDB`; ausencia de interfaz, sonidos y temporizadores; y regresión de las fases
anteriores.

### Mutaciones probadas (restauradas después)

Se introdujo cada defecto de forma aislada y se comprobó que `npm test` fallaba; tras cada una se restauró el
fichero y al final se verificó que todos quedaron idénticos a la versión correcta. **31 mutaciones, las 31 detectadas.**

- **MapPosition (7):** devolver `(0, 0)` como válida; no validar el rango; no comprobar que el mapID sea finito;
  llamar a las APIs sin `pcall`; aceptar un mapID que no es un entero positivo; tratar un nombre vacío como
  disponible; no detectar un resultado incompleto.
- **Proximity (12):** `<` en vez de `<=` (el radio exacto); comparar mapas distintos; aceptar radios nulos o
  negativos; ignorar `verified`; contar un rechazo de Discovery como descubrimiento; no saltar lo ya descubierto;
  evaluar sin estar inicializado; distancia Manhattan; añadir un temporizador; no validar las coordenadas del
  objetivo; ignorar en silencio un proveedor que falla; contar `already` como descubrimiento nuevo.
- **ZoneDiscovery (8):** resolver sin filtrar por tipo; elegir el primer candidato si es ambiguo; dar un rechazo de
  Discovery por descubrimiento; no registrar los eventos; no aislar los errores del manejador; no tratar las
  ciudades como zona; usar la posición; no comprobar el Resolver en `Init`.
- **Core/Init (4):** Proximity sin `requires`; ZoneDiscovery sin depender del Resolver; Proximity o ZoneDiscovery
  como módulos no requeridos.

**Qué pasó con cuatro de ellas (transparencia):** en una primera pasada cuatro se marcaron como «no detectadas».
Tres (MapPosition sin `pcall`, Proximity que cuenta un rechazo como descubrimiento y ZoneDiscovery sin dependencia
del Resolver) sí hacían fallar el arnés, pero con una excepción de Lua dentro de una prueba y no con una aserción
limpia; se endurecieron las pruebas para que fallen con un `[FAIL]` claro. La cuarta (Proximity que cuenta `already`
como descubrimiento nuevo) **no estaba cubierta de verdad**: se añadieron las pruebas que faltaban. Las cuatro se
volvieron a ejecutar y se detectan.

### Cambio en una prueba anterior

Ninguna prueba se eliminó ni se debilitó. **Un único ajuste, justificado**: la prueba 17f de la Fase 5 exigía
`next(Init.skipped) == nil` cuando falla el Resolver. Ahora `ZoneDiscovery` depende del Resolver y es correcto
que se omita en ese caso, así que la aserción se acotó a lo que la prueba declara: que **Discovery** no se omite
(`Init.skipped.Discovery == nil`).

### Límites del entorno

- Mock de la API de WoW sobre Lua 5.3, no el cliente real (Lua 5.1). El código no usa nada propio de Lua 5.2 o
  posterior.
- **No se ha probado** que las APIs de mapa y zona existan ni devuelvan lo esperado en Classic Era 1.15, ni que los
  eventos de zona se disparen como se documenta, ni el guardado real en SavedVariables.
- Los datos espaciales no existen, así que el motor de proximidad **no se ha podido probar con datos reales**.

## Decisiones que conviene revisar antes de la Fase 7

1. **Datos espaciales** (opciones A/B arriba) y el procedimiento para medirlos en el cliente.
2. **Quién llama a `Proximity:Evaluate()`**: un temporizador con intervalo, otro disparador, o nada hasta que haya
   datos. No se ha implementado ningún temporizador.
3. **Modelo de distancia**: unidades normalizadas por mapa (no físicas). Si se quiere distancia real, hace falta
   una API verificada.
4. **Cableado de eventos de zona en esta fase**: ZoneDiscovery crea un frame invisible que escucha eventos del
   cliente (necesario para que funcione solo). Confirmar que entra en el alcance.
5. **Alias de subzonas pendientes** (22) y verificación en un cliente en español.
6. **ZoneDiscovery no comprueba que la subzona pertenezca a la zona actual** (`parent`). Un nombre repetido entre
   zonas ya sería ambiguo para el Resolver. Se podría endurecer más adelante.
7. **Los tres módulos son requeridos**: si fallan, no se anuncia el arranque. Se podría relajar para ZoneDiscovery
   o Proximity.

## Archivos

**Creados:** `Chronicle/Services/MapPosition.lua`, `Chronicle/Services/Proximity.lua`,
`Chronicle/Services/ZoneDiscovery.lua`, `tests/mapposition_tests.lua`, `tests/proximity_tests.lua`,
`tests/zonediscovery_tests.lua`, `docs/fase6_mapposition_proximity.md`.

**Modificados:** `Chronicle/Chronicle.toc` (tres líneas), `Chronicle/Core/Init.lua` (tres módulos con sus `requires`),
`tests/harness.js` (tres líneas) y `tests/discovery_tests.lua` (el ajuste descrito arriba).

`State`, `Events`, `Schema`, `Registry`, `Localization`, `Resolver` y `Discovery` no se han tocado, ni los datos,
textos, IDs o alias migrados. No hay SavedVariables nuevas ni cambios de `schemaVersion`.
