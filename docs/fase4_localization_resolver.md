# Fase 4: Localization y Resolver

Dos componentes independientes, con responsabilidades separadas:

- **`Chronicle.Localization`**: texto de presentación de una entidad, a partir de su ID canónico,
  un campo y un idioma.
- **`Chronicle.Resolver`**: nombre o alias conocido → ID canónico.

Ninguno duplica entidades (el `Chronicle.Registry` sigue siendo la única fuente de verdad), ninguno
toca `ChronicleCharDB` y ninguno está conectado todavía a Discovery, comandos ni interfaz.

## Idiomas disponibles de verdad

Solo **`esES`**. Son los textos de la Fase 3, migrados sin cambios: descripciones, pistas, raza y rol
en el español en que se redactaron, y nombres tal como venían en la fuente (los de zonas, subzonas
y NPC son nombres propios ingleses; solo el del continente, «Reinos del Este», está en español).

**No existe `enUS`.** Un nombre propio inglés dentro de `esES` no es una traducción al inglés, y no
hay textos traducidos que la respalden. Pedir `enUS` hoy cae al fallback (ver más abajo).

## API de Localization

```lua
local L = Chronicle.Localization

L:Get("subzone:coldridge_valley", "name")            --> "Coldridge Valley", "esES"
L:Get("npc:grelin_whitebeard", "race")               --> "Gnomo", "esES"
L:Get("zone:dun_morogh", "description", "enUS")      --> (texto esES), "esES"   -- fallback por campo
L:GetExact("zone:dun_morogh", "name", "enUS")        --> nil                    -- sin fallback
L:GetLanguages()                                     --> { "esES" }             -- ordenados
L:GetIds("esES")                                     --> { ...53 IDs ordenados }
L:GetDefaultLanguage()  /  L:SetDefaultLanguage("esES")   --> true | false, motivo
L:Add("esES", "zone:dun_morogh", { name = "...", description = "..." })  --> true | false, motivo
L:Validate()  --> { ok, errors, warnings }     L:GetRejected()     L:Init()     L:IsReady()
```

`Chronicle.Localization.New(registry)` crea instancias independientes (así se prueba).

### Estructura de los datos

Por idioma y por ID, una entrada con campos opcionales de un conjunto cerrado:
`name`, `description`, `hint`, `race`, `role`. Ninguna entidad tiene que tener todos. Los ficheros
`Localization/<idioma>/*.lua` los registran con `Localization:Add(idioma, id, {...})`; los textos son
cadenas Lua idénticas a las de la Fase 3. Los códigos de idioma son `xxXX` (`esES`, `enUS`, `deDE`...).
`Add` guarda una copia privada: desde fuera solo se leen cadenas.

### Contrato de `Get(id, field, lang)` → `valor, idiomaUsado`

| Situación | Resultado |
|---|---|
| `lang` omitido | usa el idioma predeterminado |
| Idioma pedido **no registrado** | se comporta como un idioma sin entradas: cae al predeterminado (no es error) |
| Idioma registrado, **campo ausente** | cae al predeterminado; si tampoco está ahí, `nil` |
| **ID inexistente** (no está en el Registry) | `nil` |
| **Campo inexistente** (no es de los cinco) | `nil`, sin error: los datos se validan en `Add`/`Validate`, no al consultar |
| Campo **ausente en todos los idiomas** | `nil`; nunca se inventa ni se compone un texto |
| Cadena vacía `""` | es un **valor**: se devuelve `""`, **no** activa el fallback; `Validate` la avisa como advertencia |
| `id`, `field` o `lang` de tipo equivocado | `nil` |

El segundo valor devuelto indica de qué idioma salió el texto, para saber si hubo fallback.

### Política de fallback

- **Por campo**, no por entrada: si falta `description` en `enUS` pero hay `name`, el nombre sale de
  `enUS` y la descripción del predeterminado.
- **Solo hacia el idioma predeterminado**: idioma pedido → idioma predeterminado. No hay cadenas de
  fallback, así que no puede haber ciclos. Si el predeterminado es el idioma pedido y falta el campo,
  el resultado es `nil` (no se vuelve a ningún otro idioma).
- `GetExact` consulta solo el idioma indicado.

### Validación (`Validate` / `Init`)

Errores: entradas rechazadas por `Add` (código de idioma mal formado, campo desconocido, valor que no
es cadena, entrada vacía, `(idioma, ID)` duplicado: **nunca se sobrescribe**), textos de IDs que no
están en el Registry, e idioma predeterminado sin textos habiendo otros idiomas. Advertencias: valores
vacíos. Sin ningún idioma registrado es válido. `Init` falla con un mensaje descriptivo si hay errores.

## API del Resolver

```lua
local R = Chronicle.Resolver

R:Resolve("Forjaz")                      --> "city:ironforge"
R:Resolve("ciudad   de FORJAZ")          --> "city:ironforge"
R:Resolve("Ironforge", { type = "city" })--> "city:ironforge"
R:Resolve("Stormwind")                   --> nil, "not_found"
R:Resolve("Valle")                       --> nil, "ambiguous", { "subzone:s1", "zone:z1" }
R:AddAlias("esES", "city:ironforge", "Forjaz")   --> true | false, motivo
R:Validate()  --> { ok, errors, warnings }   R:Rebuild()   R:Init()   R:IsReady()
R:CountAliases()   R:GetRejected()
```

`Chronicle.Resolver.New(registry, localization)` crea instancias independientes.

### Contrato de `Resolve(text [, opts])`

Devuelve el ID, o `nil, razón[, candidatos]`:

| Razón | Cuándo |
|---|---|
| `not_ready` | el índice aún no está construido (antes de `Init`, o tras añadir alias) |
| `empty` | `text` no es cadena o queda vacío al normalizar |
| `not_found` | ningún nombre ni alias coincide |
| `ambiguous` | varias entidades comparten ese nombre/alias; el tercer valor son los IDs candidatos, ordenados. **Nunca se elige una al azar** |

`opts.type` limita los candidatos a un tipo (`"zone"`, `"city"`...), lo que puede deshacer una
ambigüedad. Un tipo que el Registry no conoce lanza error (es una errata).

Un ID canónico (`zone:dun_morogh`) **no es un nombre**: `Resolve` no lo acepta ni lo confunde con un
alias (`not_found`). Quien ya tiene un ID usa `Registry:Has()`.

### Qué se resuelve

1. El campo `name` de cada entidad en **todos** los idiomas registrados.
2. Los alias añadidos con `AddAlias` (un nombre alternativo de una entidad en un idioma).

El índice se construye en `Init` (o con `Rebuild`) y las consultas solo lo leen. Un nombre o alias de
un ID que no está en el Registry no se indexa (y es error en `Validate`).

### Normalización

Solo para **comparar**; nunca altera lo que se muestra:

1. Se recortan los espacios de los extremos y se reducen los internos repetidos (espacio, tabulador,
   saltos de línea) a uno.
2. Se pasa a minúsculas: ASCII, más las siete mayúsculas acentuadas del español (Á É Í Ó Ú Ñ Ü),
   porque `string.lower` del cliente no toca los bytes UTF-8.

**No** se quitan acentos (`Destilería` ≠ `Destileria`), ni se unifican apóstrofos o guiones. **No hay**
coincidencias parciales, por prefijo ni aproximadas: la cadena normalizada es exactamente un nombre o
alias conocido, o no se resuelve.

### Origen de los alias y ambigüedades

Los 22 alias salen de `ZONE_ALIASES` (2) y `SUBZONE_ALIASES` (20) del `Core/Localization.lua` del addon
original, sin añadir ninguna equivalencia nueva. Los 22 apuntan a entidades ya migradas, así que **no
queda ninguno fuera de alcance**. Están en `Localization/esES/Aliases.lua`, con su procedencia anotada.

**Procedencia, heredada de los comentarios de la fuente. No se ha reverificado aquí:**

| Marca | Qué dice la fuente | Alias |
|---|---|---|
| [C] | confirmado jugando con `/chronicle where` | `Ciudad de Forjaz`, `El Trono`, `Ciudad Manitas` |
| [J] | visto en un mensaje del propio juego, sin confirmar como `GetRealZoneText()` | `Forjaz` |
| [O] | nombre alternativo visto en otra fuente | `Gran Fundición` |
| [W] | de la Wowpedia en español; la fuente avisa de que **no está verificado jugando** | los otros 16 |

La fuente descarta a propósito dos nombres de Cataclysm (`Frente de Peloescarcha`, `Nueva Ciudad
Manitas`); tampoco están aquí.

Una ambigüedad (dos entidades con el mismo nombre normalizado, o un alias que coincide con el nombre de
otra) **no se resuelve por orden de carga**: `Resolve` devuelve `ambiguous` con los candidatos, y
`Validate` la avisa como advertencia (no hace fallar el arranque porque `Resolve` ya la trata de forma
segura). En los datos reales hay 0. El mismo nombre en varios idiomas (o como alias) de una **misma**
entidad no es ambigüedad. Los resultados no dependen del orden de inserción.

### Validación (`Validate` / `Init`)

Errores: alias rechazados por `AddAlias` (idioma o ID que no son cadenas, alias vacío, duplicado del
mismo `(idioma, ID, alias normalizado)`), alias de un ID que no está en el Registry y alias en un idioma
sin textos en Localization. Advertencias: nombres o alias ambiguos.

## Integración con el arranque

`Core/Init.lua` inicializa, en este orden: `Events`, `State`, `Registry`, **`Localization`**,
**`Resolver`**, `Slash`. Localization y Resolver son **módulos requeridos**: si fallan, `Init.ready` es
`false`, el error queda en `Init.failed` y **no** se anuncia `Chronicle.Initialized`. Cada módulo se sigue
intentando aunque otro falle. No hay nuevas SavedVariables y no se escribe nada en `ChronicleCharDB`.

Orden de carga (`Chronicle.toc`): `Data/Registry.lua`, `Data/Entities/*`, `Localization/Localization.lua`,
`Services/Resolver.lua`, `Localization/esES/*` (textos y alias) y, el último, `Core/Init.lua`.

## Archivos

**Creados:**
- `Chronicle/Localization/Localization.lua`
- `Chronicle/Services/Resolver.lua`
- `Chronicle/Localization/esES/Aliases.lua`
- `tests/localization_tests.lua`, `tests/resolver_tests.lua`
- `docs/fase4_localization_resolver.md`

**Movidos y convertidos** (con `git mv`; las cadenas no cambian, solo el contenedor):
`Chronicle/Data/Text/{EasternKingdoms,DunMorogh,LochModan,Ironforge}.lua` →
`Chronicle/Localization/esES/`. Pasan de asignar a `Chronicle.LegacyText[id]` a llamar a
`Localization:Add("esES", id, {...})`. El contenedor provisional `LegacyText` desaparece.

**Modificados:**
- `Chronicle/Chronicle.toc`: nuevos ficheros y nuevo orden.
- `Chronicle/Core/Init.lua`: solo las dos líneas que añaden `Localization` y `Resolver` a la lista de módulos.
- `tests/harness.js`: ejecuta los dos ficheros de pruebas nuevos.
- `tests/data_tests.lua`: sigue haciendo exactamente las mismas comparaciones con la referencia original,
  pero leyendo los textos de `Localization:GetExact(id, campo, "esES")` en vez de `LegacyText`.
- `tests/registry_tests.lua`: la lista de ficheros que excluye `NO_DATA` apunta a `Localization/esES/`.
- `docs/fase3_migracion.md`: nota de actualización.

`Schema.lua`, `Registry.lua` y `State.lua` no se han tocado.

## Pruebas

```
cd tests
npm test
```

Resultado de la ejecución final: **465 superadas, 0 fallidas, código de salida 0** (78 de la Fase 1, 167 de la
Fase 2, 68 de la Fase 3 y 152 nuevas de la Fase 4). La batería cubre las fases 1 a 4. Se
comprobó además que las pruebas nuevas detectan defectos reales (elegir el primer candidato de una
ambigüedad, coincidencia por prefijo, tratar `""` como ausente, fallback por entrada entera, alterar un
carácter de un texto, quitar un alias, quitar el Resolver de los módulos requeridos, no pasar a minúsculas).

### Qué se ha verificado y qué no

**Verificado por las pruebas** (contra un mock de la API de WoW sobre Lua 5.3): el contrato de ambos
módulos, la preservación literal de los textos frente a una copia obtenida ejecutando los ficheros del
addon original, el fallback, la normalización, las ambigüedades, la independencia del orden de carga y
que un fallo de un módulo requerido impide anunciar el arranque.

**No verificado:**
- **El cliente real de Classic Era (Lua 5.1).** Falta probar el addon dentro del juego. En particular, que
  las mayúsculas acentuadas se normalizan como se espera con los textos reales del cliente.
- **Que los alias coincidan con lo que devuelve el juego.** Solo se heredaron de la fuente; la propia
  fuente marca como verificados jugando solo tres, y no se ha podido confirmar ninguno aquí.
- **Los nombres y textos son los de la fuente**, no se ha contrastado su corrección con ninguna otra.

## Limitaciones y decisiones aplazadas

- **No hay `enUS`** ni ningún otro idioma. Cuando exista, bastará con añadir ficheros en
  `Localization/<idioma>/`; no hace falta tocar el módulo.
- **No hay selección de idioma por el cliente ni por el jugador.** El predeterminado es `esES` y se puede
  cambiar con `SetDefaultLanguage`, pero nada lo hace todavía ni se guarda en ninguna parte. Persistir la
  elección (si procede) será decisión de otra fase.
- **El índice del Resolver no se actualiza solo**: tras añadir textos o alias después de `Init`, hay que
  llamar a `Rebuild()`/`Init()`. Mientras tanto, `AddAlias` hace que `Resolve` devuelva `not_ready`.
- **Sin resolución por contexto**: no hay filtro por padre (p. ej. «la subzona que se llama X dentro de
  esta zona»); solo por tipo. Hoy no hace falta (no hay ambigüedades), y queda para cuando Discovery lo pida.
- **Los nombres inglés/español de una misma entidad conviven en `esES`**: el nombre de la ciudad es
  `Ironforge` y `Forjaz` es solo un alias, porque eso es lo que dice la fuente. Decidir si «Forjaz» debe
  ser su `name` en `esES` queda aplazado: cambiaría un texto migrado.
- **`hint`, `race` y `role`** siguen siendo campos de presentación, tal como se migraron. Si `race` o `role`
  deberían pasar a ser datos canónicos sigue pendiente (ver `docs/fase3_migracion.md`).
- **Sin comando `/chronicle` ni integración con Discovery o interfaz**, como pedía el alcance.
