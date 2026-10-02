# Fase 5: Discovery

`Chronicle.Discovery` registra y consulta **qué entidades ha descubierto el personaje actual**. El
Registry dice qué existe en el mundo; Discovery guarda cuáles de esas ha descubierto este personaje.

## Responsabilidad y límites

- **Hace:** guardar un descubrimiento por ID canónico, consultarlo, listarlo, contarlo, dar el progreso por
  tipo y emitir un evento la primera vez.
- **No hace:** detectar nada. No lee zonas, subzonas ni GUID, no usa eventos del cliente, coordenadas ni
  proximidad, no muestra nada y no conoce nombres (no usa Localization ni el Resolver). Las capas futuras de
  detección lo llamarán con `Discover(id)`.
- **No duplica el catálogo:** solo acepta IDs que existen en el Registry, y nunca crea entidades.
- **No toca `ChronicleCharDB`:** lee y escribe únicamente con `State:Get` / `State:Set`.

## Estructura persistente exacta

Sin segunda SavedVariable, sin cambiar `schemaVersion` (sigue en 1) y sin migración: usa el contenedor
`discovery.entries` que `State` ya crea.

```lua
ChronicleCharDB = {
    schemaVersion = 1,
    discovery = {
        entries = {
            ["zone:dun_morogh"] = {},
            ["npc:grelin_whitebeard"] = {},
        },
    },
}
```

- Un ID está descubierto si y solo si su valor es una **tabla**. La tabla está **vacía a propósito**: es el
  hueco para metadatos futuros, que se añadirán como claves nuevas sin migrar nada. No se guarda ningún
  campo hoy (p. ej. fecha) porque ninguno tiene todavía un uso definido.
- Se prefiere `{}` a `true` precisamente para no necesitar migrar cuando haya metadatos.
- Cualquier otro valor (`true`, `false`, cadenas…) y cualquier ID que ya no esté en el Registry se
  **ignoran** al consultar: no son un error, no cuentan y no se borran.
- Un guardado antiguo o incompleto (sin `discovery`, sin `entries`, o de versiones anteriores sin
  `schemaVersion`) equivale a progreso vacío y no produce errores. Si `State` está en solo lectura (guardado de
  una versión más nueva) y no trae `discovery`, se consulta como vacío.

## API pública

`Chronicle.Discovery.New({ state, registry, events })` crea instancias independientes (cada dependencia puede
ser la tabla del módulo o una función que la devuelve); la instancia por defecto usa los módulos de
`Chronicle.*`. Las consultas devuelven **listas nuevas**: nunca las tablas de `State`.

```lua
local D = Chronicle.Discovery

D:Discover("zone:dun_morogh")      --> true, "new", emitido     -- descubrimiento nuevo, GUARDADO
D:Discover("zone:dun_morogh")      --> true, "already"          -- idempotente: no escribe ni emite
D:Discover("zone:no_existe")       --> false, "unknown_entity"
D:IsDiscovered("zone:dun_morogh")  --> true | false
D:GetIds()                         --> { "city:ironforge", "zone:dun_morogh", ... }   -- ordenados
D:GetIds("subzone")                --> solo las de ese tipo
D:Count()  /  D:Count("npc")       --> número
D:GetProgress("subzone")           --> descubiertas, total        (total = entidades de ese tipo en el Registry)
D:Init()   /   D:IsReady()
```

### `Discover(id)`

| Resultado | Cuándo |
|---|---|
| `true, "new", emitido` | descubrimiento nuevo, **guardado**. `emitido` es `true` si se pudo emitir el evento y `false` si no (ver «Evento»); el guardado no depende de ello |
| `true, "already"` | ya estaba descubierta: no se escribe nada ni se emite nada |
| `false, "invalid_id"` | `id` no es una cadena no vacía |
| `false, "unknown_entity"` | `id` no está en el Registry (un nombre visible o un alias tampoco es un ID) |
| `false, "not_ready"` | Discovery no se ha inicializado, falta el Registry, o `State` no está listo |
| `false, "read_only"` | `State` está en solo lectura (guardado de una versión más nueva) |
| `false, "persist_failed"` | `State:Set` devolvió `false`, o no dejó el valor guardado |

Orden de comprobación: `invalid_id`, `not_ready`/`unknown_entity`, `read_only`, `persist_failed`. En todos los
fallos **no se guarda nada y no se emite nada**; nunca se afirma un éxito que no se haya persistido (tras
`State:Set` se vuelve a leer lo guardado). En solo lectura hasta lo ya guardado devuelve `read_only`: nada se
persiste.

### Consultas

| Función | Contrato |
|---|---|
| `IsDiscovered(id)` | `true`/`false`. `false` para un ID inválido, desconocido, si no hay estado o antes de `Init`. **Nunca** descubre nada ni emite eventos |
| `GetIds([tipo])` | lista nueva, **ordenada**, de IDs descubiertos que existen en el Registry; vacía si no hay estado |
| `Count([tipo])` | `#GetIds(tipo)` |
| `GetProgress([tipo])` | `descubiertas, total`; sin tipo, sobre todas las entidades |

Un `tipo` que el Registry no conoce (o que no es una cadena) **lanza error** en `GetIds`/`Count`/`GetProgress`,
igual que el Registry: es una errata del llamante y devolver 0 la escondería.

### `Init()` e `IsReady()`

`Init()` comprueba que `State` está listo y que existe el Registry; si no, lanza un error descriptivo y el
servicio no queda listo. Con `State` en solo lectura **tiene éxito** (las consultas funcionan; solo se rechazan
las escrituras). El bus de eventos no se exige aquí: `Core/Init` ya lo verifica antes de anunciar el arranque, y
Discovery tolera su ausencia al emitir.

## Evento

`"Chronicle.Discovery.Discovered"` (`Discovery.EVENT_DISCOVERED`), por `Chronicle.Events`, con **un único
argumento**: el ID canónico recién descubierto.

- Se emite **una vez por descubrimiento nuevo y solo después de guardarlo**.
- No se emite en consultas, intentos inválidos, fallos de persistencia ni al repetir un descubrimiento.
- Si el bus no está disponible, o `Emit` lanza un error, el descubrimiento ya guardado **se mantiene**, el fallo
  se comunica por `geterrorhandler` y `Discover` devuelve `emitido = false`: no se finge una emisión. No se
  emite retroactivamente. (Los errores de los listeners los aísla el propio `Events`.)
- Discovery no depende de ningún listener ni de la interfaz.

## Dependencias y orden de inicialización

- **Depende de:** `State` (`Get`/`Set`/`IsReady`/`IsReadOnly`), `Registry` (`Has`, `Count`) y `Events` (`Emit`).
  No depende de `Localization` ni de `Resolver`. Sin dependencias circulares.
- **Carga (`.toc`):** `Services/Discovery.lua`, tras `Services/Resolver.lua` y antes de los datos de
  `Localization/esES` y de `Core/Init.lua`.
- **Inicialización (`Core/Init`):** módulo **requerido**, declarado con `requires = { "State", "Registry" }`.
  `Core/Init` aprende aquí un concepto nuevo y mínimo: si un módulo declara `requires` y alguno de ellos no quedó
  inicializado, ese módulo **no se intenta**. Queda en `Init.skipped[nombre]` (no en `Init.failed`, que solo lista
  las causas) y, si es requerido, `Init.ready` es `false` y no se anuncia el arranque. Los módulos
  independientes se siguen intentando.

## Pruebas

```
cd tests
npm test
```

Resultado de la ejecución final: **561 superadas, 0 fallidas, código de salida 0** (482 de las fases 1 a 4 y 79
nuevas de Discovery en `tests/discovery_tests.lua`).

Cobertura de Discovery: estado inicial vacío; guardado por `State:Set` (con un `State` espía: una sola llamada,
ruta y valor exactos); evento exactamente una vez con un argumento; idempotencia (sin reescribir ni reemitir);
consultas sin efectos; ID inexistente, nombre visible y alias rechazados; argumentos de tipo incorrecto; listas y
recuentos deterministas y copias; filtro por tipo y progreso; estados incompletos, antiguos y con basura; `State`
no listo, en solo lectura, `Set` que falla y `Set` que miente; persistencia entre sesiones y servicio
reconstruido; descubrir las 53 entidades reales; bus de eventos ausente, `Emit` roto y listeners rotos;
diagnóstico del arranque (fallo de `Discovery.Init`, ausencia del módulo, `State` o `Registry` fallidos y
módulos independientes); API mínima sin tablas internas; y que el fichero no usa `ChronicleCharDB`, ni APIs de
detección del juego, ni Localization/Resolver.

### Mutaciones probadas (restauradas después)

Se introdujo cada defecto de forma aislada y se comprobó que `npm test` fallaba: emitir el evento dos veces,
aceptar un ID desconocido, no persistir pero afirmar éxito, emitir al repetir, que consultar descubra, ignorar el
solo lectura, emitir aunque no se guarde, no verificar lo guardado, lista sin ordenar, contar valores que no son
tabla, contar IDs que ya no están en el Registry, filtro por tipo que no filtra, guardar `true` en vez de una
tabla, devolver la tabla interna de `State`, `Core/Init` sin `requires`, Discovery como módulo no requerido y
`Init` que no comprueba `State`. Las 17 se detectaron.

### Cambios en pruebas anteriores

Ninguna prueba se eliminó ni se debilitó. Un único ajuste, justificado: la prueba de la Fase 4 «ningún fichero de
Localization ni de Services referencia `ChronicleCharDB` ni `Chronicle.State`» exime ahora a
`Services/Discovery.lua` de la mitad de `Chronicle.State` (es su cometido usarlo como API de persistencia); la
prohibición de `ChronicleCharDB` sigue valiendo para todos los ficheros.

### Límites del entorno

Las pruebas corren contra un mock de la API de WoW sobre Lua 5.3, no en el cliente real de Classic Era (Lua 5.1).
El código no usa nada propio de Lua 5.2 o posterior. **No se ha probado el guardado real en SavedVariables** (que
el cliente escriba y vuelva a cargar `ChronicleCharDB`): la persistencia se verifica simulando la recarga con la
misma tabla.

## Limitaciones conocidas

- **Sin metadatos**: no se guarda cuándo ni cómo se descubrió algo; la tabla vacía los admite sin migrar.
- **No hay «des-descubrir» ni reinicio**: el servicio solo añade. Reiniciar el progreso, o la pregunta de
  `FreshCheck`, son de otra fase.
- **No propaga descubrimientos**: descubrir un lugar no descubre sus subzonas ni a la inversa; cada ID es
  independiente. Cualquier regla así será de la capa que llame.
- **Los IDs que dejan de existir** en el Registry se conservan en `State` pero se ignoran: no se limpian.
- **`GetIds`/`Count` recorren el estado entero** en cada llamada (sin caché). Con unas decenas o cientos de
  entradas no importa; habría que revisarlo si el catálogo creciera mucho.
- **No hay nada que se muestre**: ni notificación ni popup al descubrir; un listener del evento lo hará.

## Pendiente expresamente para la Fase 6

Detección automática (entrada en zonas y subzonas, apuntar a NPC), proximidad y mapas, y todo lo que consuma el
evento. Esta fase solo deja la API `Discover(id)` y el evento para que esas capas se conecten.

## Archivos

**Creados:** `Chronicle/Services/Discovery.lua`, `tests/discovery_tests.lua`, `docs/fase5_discovery.md`.

**Modificados:** `Chronicle/Chronicle.toc` (una línea), `Chronicle/Core/Init.lua` (el módulo `Discovery` y el
mecanismo `requires`/`Init.skipped`), `tests/harness.js` (una línea) y `tests/localization_tests.lua` (el ajuste
descrito arriba).

`State.lua`, `Events.lua`, `Schema.lua`, `Registry.lua`, `Localization.lua` y `Resolver.lua` no se han tocado, ni
los datos, textos, IDs o alias migrados.
