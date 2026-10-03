# Fase 11 — NPC 3D y contenido relacionado del Codex

Estado: implementada y pendiente de revisión del supervisor. Commit base: `e386bf1e1a5f4df92de497ac569a0577305a0fdd`. **No se ha empezado la
Fase 12.** Dos objetivos: un visor 3D de NPC en sus páginas y enlaces entre entidades relacionadas, ambos bajo la política de visibilidad
de la Fase 10.

## Qué se inspeccionó

Código real de `Codex.lua`, `CodexModel.lua`, `CodexPage.lua`, `CodexNavigation.lua`, `CodexScroll.lua`, `Theme.lua`, `Schema.lua`,
`Registry.lua`, `Discovery.lua`, `Core/Init.lua`, el `.toc`, el harness y el mock, los datos de NPC (`Data/Entities/Npcs.lua`) y, solo en
lectura, el código del addon original que dibujaba el modelo.

- **Schema:** el tipo `npc` admite `located_in` y los campos opcionales `npcID` y `displayID` (enteros positivos). Ningún otro tipo
  admite `displayID`. `related_to` es una lista de IDs; **no se admite que una entidad se relacione consigo misma**.
- **Registry:** `GetContained(id)` devuelve la unión de los hijos por `parent` y por `located_in`; `GetRelated(id)` devuelve `related_to` en
  los **dos** sentidos (puede incluir IDs declarados que no están registrados: Registry no los valida al registrar); `Get` y `Has`.

## NPC con identificador de modelo, y de dónde sale

Los **9 NPC** del catálogo (`npc:grelin_whitebeard`, `npc:sten_stoutarm`, `npc:senir_whitebeard`, `npc:jarven_thunderbrew`,
`npc:innkeeper_belm`, `npc:chief_engineer_hinderweir_vii`, `npc:captain_rugelfuss`, `npc:king_magni_bronzebeard` y
`npc:high_tinker_mekkatorque`) **tienen `displayID` y `npcID`**. Procedencia: los migró la Fase 3 **tal cual** del addon
original, que los declara «de Wowhead Classic»; la prueba `data_tests` los compara con una copia literal del original y la `18` de este
fichero comprueba que los 9 los conservan. **No se han podido contrastar de forma independiente** (ni con Wowhead ni dentro del juego), así
que esta fase los usa como **datos declarados**, no como datos verificados, y no los promueve a «confirmados». No se ha añadido,
modificado ni inventado ningún identificador ni ningún dato canónico.

## Visor 3D

`UI/CodexNpcModel.lua` (módulo interno, opcional) con un único `PlayerModel` **reutilizado** por todas las páginas.

### APIs consultadas y qué se pudo verificar

Se consultó la wiki de la API de WoW (warcraft.wiki.gg):

| API | Resultado |
|---|---|
| `PlayerModel:SetDisplayInfo(displayID [, mountDisplayID])` | documentada, con disponibilidad listada para Vanilla/Classic Era 1.15.x |
| `PlayerModel:SetCreature(creatureID [, displayID])` | documentada con disponibilidad en Vanilla 1.15.x; **el primer argumento es un creature ID, no un display ID** |
| `Model:ClearModel()` | documentada para Classic Era |
| El tipo de frame `PlayerModel` en `CreateFrame` | la wiki documenta sus métodos pero **no indica su disponibilidad por versión**. Sin verificar. |

**No hay forma de ejecutar esto en un cliente real desde aquí**, así que la compatibilidad con la interfaz 11507 **no está verificada**: la
wiki puede describir otra revisión de Classic Era, y no se ha comprobado que el cliente dibuje el modelo ni que el display ID sea el
correcto.

**Hallazgo sobre el addon original:** llamaba a `SetCreature(displayID)`. Según la documentación consultada, esa llamada pasa un display ID
donde se espera un creature ID, y por tanto probablemente mostraría otro NPC o ninguno. **No se ha copiado.** Esta fase usa
`SetDisplayInfo(displayID)`; solo si el frame no la tiene, usa el respaldo `SetCreature(npcID, displayID)` y únicamente con un `npcID`
válido. El original tampoco se ha tocado. (Que esa llamada funcionara o no en el original es una conjetura mía a partir de la
documentación; no lo he comprobado.)

### Comportamiento

- Se muestra **solo** en la página de un **NPC descubierto** cuyo `displayID` sea un entero positivo (`CodexModel` decide `page.model`;
  una entidad que no es NPC nunca lo tiene, aunque otro esquema le deje guardar un `displayID`; una bloqueada tampoco, porque su página es
  solo `???`).
- **Degradación segura:** si el cliente no crea el `PlayerModel`, si el frame no tiene ni `SetDisplayInfo` ni `SetCreature`, si falla
  cualquier llamada, o si el NPC no tiene identificador válido, la página se muestra completa **sin marco ni hueco**; el fallo se
  comunica una sola vez (`geterrorhandler`) y no se propaga. Ningún método del componente lanza errores.
- **Reutilización sin restos:** antes de decidir lo que hay en cada página se oculta y se vacía (`ClearModel`) el visor y se oculta su
  recuadro de fondo; un modelo nuevo se carga solo tras vaciar el anterior; un fallo a medias lo deja vacío y oculto. No se le ponen
  scripts. Se crea **una vez** (una segunda llamada a `Attach` no crea otro).
- **No interfiere:** no activa el ratón ni la rueda (la página sigue desplazándose), sin `OnUpdate` ni temporizadores (el original rotaba
  con `OnUpdate`; aquí no hay rotación, zoom ni animaciones: no se pidieron y las pruebas prohíben `OnUpdate` en el Codex).
- Tamaño de `Theme` (`CODEX_MODEL_WIDTH/HEIGHT`, 150 × 170), limitado al ancho disponible; el recuadro usa `BG_PANEL`. La página reserva su
  espacio y el texto queda por debajo.

## Enlaces entre entidades relacionadas

`CodexModel:GetPage` añade `links` (solo a páginas descubiertas). La vista pinta cada sección con una cabecera y un botón por destino;
pulsar uno llama a `model:Select(id)`, es decir, **la navegación y el historial de siempre** (breadcrumbs, Atrás/Adelante, fila
seleccionada, el futuro se descarta como en cualquier selección).

| Sección | De dónde sale | Notas |
|---|---|---|
| **Situado aquí** | entidades cuyo `located_in` es la actual (la derivada «contiene» por `located_in`) | **no** los hijos por `parent`: esos ya son el árbol |
| **Relacionado con** | `related_to`, visto desde los dos lados (`GetRelated`) | declarada por un solo lado, se ve desde ambos |

- `parent` sigue siendo solo la jerarquía del árbol y de los breadcrumbs. `located_in` sigue siendo el dato contextual «Ubicado en» (texto
  de la Fase 9/10); **no se enlaza** ni se convierte en jerarquía. `related_to` no genera jerarquía. Ninguna relación se modifica.
- **Se descartan** los destinos que el Registry no tiene (no hay enlaces que no se puedan resolver) y no hay ni un enlace repetido ni un
  enlace a la propia entidad: **cada entidad aparece una vez por página**; si es a la vez «situada aquí» y «relacionada», sale en «Situado
  aquí» (por ejemplo Forjaz en la página de Dun Morogh). Se aceptó perder esa segunda etiqueta para no duplicar enlaces.
- Las secciones vacías no existen. Orden: tipo e ID, como el árbol.
- Los datos reales dan: Dun Morogh → Forjaz («Situado aquí») y Loch Modan («Relacionado con»); cada subzona → los NPC situados en ella;
  Senir ↔ Grelin.

## Política de Discovery

- **Una página bloqueada sigue siendo solo `???`:** sin tipo, ubicación, descripción, cuerpo, raza, rol, **modelo ni enlaces** (su
  `GetPage` no los lleva). La vista oculta y vacía el visor y las filas de enlaces en cada repintado antes de decidir.
- **Cada destino se evalúa por sí solo** (`CodexModel:GetName`): un destino bloqueado se enlaza como `???` en el color `LOCKED` (se puede
  abrir y su página es la bloqueada) y su nombre real no aparece en ningún widget. Un destino descubierto bajo un ancestro bloqueado no
  hace visible el nombre de ese ancestro (su ubicación es `???`). **Decisión abierta:** un enlace `???` revela que *existe* una relación con
  algo aún no descubierto; es la misma clase de dato que el árbol ya muestra (Fase 10, punto 5) y que el «Ubicado en: ???». Omitir los
  destinos bloqueados es la alternativa menos reveladora; no se adoptó por coherencia con la Fase 10. Cambiarlo es una línea.
- **Actualización:** al descubrirse una entidad cuya etiqueta aparece en la página abierta (la propia, su ubicación o cualquiera de sus
  enlaces), `AffectsPage` repinta la página (el visor aparece al descubrir el NPC); las demás no mueven el punto de lectura.
- El Codex **no descubre nada**: ni la vista ni el visor nombran `Discover`; las pruebas cuentan las llamadas (0) y comparan
  `ChronicleCharDB` antes y después. No se toca el esquema ni SavedVariables. Discovery sigue siendo una dependencia opcional.

## Archivos

Nuevos: `Chronicle/UI/CodexNpcModel.lua` (el visor; un módulo aparte porque aísla un widget del cliente no verificado y sus fallos),
`tests/codex_content_tests.lua`, este documento.
Modificados:
- `Chronicle/UI/CodexModel.lua`: `page.model`, `page.links`, `BuildLinks` y `AffectsPage` ampliado.
- `Chronicle/UI/CodexPage.lua`: visor y enlaces en la página.
- `Chronicle/UI/Codex.lua`: pasa el módulo del visor a la página y exige los tamaños del visor a Theme.
- `Chronicle/UI/Theme.lua`: `CODEX_MODEL_WIDTH` y `CODEX_MODEL_HEIGHT` (hacían falta: no había medidas para un recuadro de modelo).
- `Chronicle/Chronicle.toc`: `CodexNpcModel.lua` antes de `CodexPage.lua`.
- `tests/mock.lua`: el tipo de frame `PlayerModel` con `SetDisplayInfo`/`SetCreature`/`ClearModel` (solo guardan lo que se les pide; ningún
  otro tipo tiene esos métodos).
- `tests/harness.js`: el fichero de pruebas nuevo.
- `tests/codex_tests.lua`: la lista exacta de dependencias de `Codex.lua` (prueba 12d) incluye el módulo opcional del visor; no se quitó
  ninguna comprobación.
No se tocaron `Discovery`, `State`, `Schema`, `Registry`, `Localization`, `Core/Init.lua` ni los datos.

## Verificación

`npm test` desde `tests`: **1356 superadas, 0 fallidas, código de salida 0** (1270 de las fases 1 a 10 y 86 nuevas de
`tests/codex_content_tests.lua`). Las pruebas son de dos niveles que no hay que confundir: **lógica** (qué datos de modelo y de enlaces da
el modelo, con el catálogo real y con mundos sintéticos) e **interfaz con el mock estricto** (se pulsan los botones reales y se leen los
widgets). **Ninguna valida el comportamiento en el cliente real.**

Cubren, entre otras cosas: un NPC descubierto con identificador usa el visor (cargado con `SetDisplayInfo`, con el tamaño de Theme, sin
ratón ni scripts); un NPC sin identificador, una entidad que no es NPC y un NPC bloqueado no lo muestran ni lo cargan (se cuentan las
llamadas al cliente); los fallos del cliente (no se puede crear el `PlayerModel`, `SetDisplayInfo` o `Show` lanzan error, el frame no tiene
métodos de modelo) dejan la página completa y sin marco, con el fallo comunicado una vez; el respaldo `SetCreature(npcID, displayID)`; el
paso de un NPC con modelo a otro sin él no deja nada del anterior (oculto, vacío y sin recuadro), con **un solo** widget reutilizado; el
componente aislado; los enlaces (válidos, desde los dos lados, sin duplicados, sin destinos inexistentes, sin secciones vacías), que
pulsar uno usa la navegación y el historial existentes (incluido descartar el futuro), que las relaciones canónicas no cambian, y la
política de Discovery (destinos bloqueados como `???`, páginas bloqueadas sin enlaces ni visor, un descendiente descubierto bajo un
ancestro bloqueado sin nombres filtrados en ningún widget, ningún `Discover`, `ChronicleCharDB` idéntico); y con los **datos reales**:
Grelin Whitebeard muestra su modelo con el displayID 1354 y Dun Morogh enlaza con Forjaz y con Loch Modan.

**Mutaciones** (criterio estricto: solo cuenta una aserción `[FAIL]` clara): **37 mutaciones, las 37 detectadas por aserciones, ninguna con
excepción posterior**; tras cada una se restauró el fichero y al final se verificó que todos eran idénticos a la versión final. Cubren el
visor (no vaciarlo ni ocultarlo, usar `SetCreature(displayID)` como el original, el respaldo con el ID equivocado o sin `npcID`, no limpiar
tras un fallo, dejarlo visible al crearlo, repetir el error, aceptar identificadores no válidos, crear un widget por llamada, no aislar la
creación), el modelo (modelo para un no-NPC, `displayID` cero o fraccionario, `npcID` inventado, enlaces por `parent`, enlaces repetidos o
a destinos inexistentes, nombre real de un destino bloqueado, secciones vacías, avisos que no actualizan la página, `related_to` de un solo
lado, `located_in` y `parent` mezclados), la página (visor sin reiniciar, filas o cabeceras de enlaces con restos, enlace que retrocede
en vez de navegar, color de enlace y de bloqueado, espacio del visor sin reservar, visor mostrado sin modelo, botones de historial) y el
cableado (módulo no pasado a la página, tamaños no exigidos a Theme, token de Theme alterado).

**Historial (transparencia):** la primera pasada completa dio 32 de 37 con 5 sin detectar y otras 2 con excepción posterior. Cuatro eran
huecos reales de las pruebas (el visor recién creado visible, el color de los enlaces, restos de texto en filas de enlaces ocultas, y que
la ausencia del visor saliera como excepción) y se añadieron pruebas; **dos mutantes eran equivalentes y se retiraron o se sustituyeron
por una variante real**: «enlazar un destino inexistente» sin quitar a la vez la comprobación del Registry no cambia nada (la entidad
inexistente se descarta al ordenar), y «una entidad se enlaza a sí misma» es imposible con datos válidos porque **Schema prohíbe que una
entidad se relacione consigo misma**. Se repitió la batería completa desde un estado limpio: 37 de 37. No se interrumpió ninguna
ejecución.


## Limitaciones que requieren comprobación en WoW Classic Era

Todo lo anterior se probó con un mock estricto que valida la **lógica**; **no se ha ejecutado en el juego**.

- Que el tipo de frame `PlayerModel` exista en la interfaz 11507 y que `SetDisplayInfo`, `SetCreature` y `ClearModel` se comporten como la
  wiki indica (la wiki no fija versiones exactas para esta build).
- Que los **9 `displayID`** declarados sean los correctos y muestren al NPC esperado: son datos heredados no contrastados.
- Que el modelo se dibuje, con qué encuadre, y que no se vea cortado por el recuadro o por el recorte del `ScrollFrame` al desplazar la
  página (un `PlayerModel` dentro de un `ScrollFrame` podría no recortarse bien); el modelo puede necesitar tiempo para cargar (el original
  repetía la llamada con un temporizador, que aquí se evita a propósito).
- Sin rotación, zoom ni animaciones: no se pidieron.
- El aspecto de los enlaces (`GOLD_DIM`) y su zona de pulsación, y la altura de las páginas con muchos enlaces.
- La decisión abierta sobre los enlaces a destinos bloqueados (arriba).

## Fuera de alcance (no implementado)

Minimapa, comandos slash, panel de opciones, Trivia, FreshCharacterCheck (Fase 12), TextLinker, persistencia de la interfaz o del
historial, y cualquier dato o relación nuevos.
