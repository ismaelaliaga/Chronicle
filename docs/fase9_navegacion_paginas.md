# Fase 9 — Navegación y páginas del Codex

Estado: implementada y pendiente de revisión del supervisor. Trabaja **solo** con el catálogo de entidades (Registry) y sus textos
(Localization). **No hay integración con Discovery**: todo se ve, descubierto o no.

## Resumen

La zona izquierda del Codex es ahora un **árbol navegable** de todas las entidades registradas, y la derecha muestra la **página** de
la entidad elegida, con **breadcrumbs** (la ruta geográfica) e **historial** Atrás/Adelante. La API pública del Codex **no cambia**
(`Init`, `IsReady`, `IsVisible`, `Show`, `Hide`, `Toggle`): la navegación se hace con la propia interfaz.

## Hallazgos del contrato real (léelos antes de revisar)

Se leyeron las implementaciones, no se dedujeron por los nombres:

1. **Ninguna entidad del catálogo declara `nameKey`, `descriptionKey` ni `textKey`**, y **no existe ninguna entidad de tipo `lore`**.
   Se implementan igualmente (el esquema los admite), pero hoy solo se ejercitan con catálogos sintéticos en las pruebas.
2. **Localization no tiene un campo de artículo.** Sus campos son `name`, `description`, `hint`, `race` y `role`, y solo responde por IDs
   que estén en el Registry (`Get(id, field, lang)`). El esquema define `textKey` como «clave del cuerpo del artículo de lore», pero
   Localization no puede devolver «el cuerpo de la clave X». **Decisión tomada (abierta a revisión):** el único canal que el contrato
   actual permite es `Localization:Get(textKey, "description")`, es decir, que `textKey` sea el ID de una entidad registrada cuya
   descripción es el artículo. Si no responde, la página marca `bodyUnresolved = true` y **no muestra nada**; la descripción corta
   **nunca** se usa como cuerpo ni al revés. Para un artículo largo de verdad hará falta, en una fase posterior, un campo `body` en
   Localization. No se tocó Localization.
3. `hint` (la pista de descubrimiento) existe en Localization pero **no se muestra**: pertenece a la integración con Discovery.

## Arquitectura

| Fichero | Responsabilidad | Depende de |
|---|---|---|
| `UI/CodexModel.lua` | **Lógica sin frames**: árbol, páginas, breadcrumbs, historial, expansión | Registry y Localization (inyectados) |
| `UI/CodexScroll.lua` | Zona con desplazamiento compartida (rueda del ratón + indicador de posición) | Theme |
| `UI/CodexNavigation.lua` | **Vista** del árbol (filas, +/-, selección) | Theme, CodexScroll, modelo |
| `UI/CodexPage.lua` | **Vista** de la página, breadcrumbs y botones Atrás/Adelante | Theme, CodexScroll, modelo |
| `UI/Codex.lua` | Ventana (Fase 8) y **cableado** de lo anterior; sigue siendo pequeño | todos los anteriores |

Orden en el `.toc`: `Theme`, `Popup`, `CodexModel`, `CodexScroll`, `CodexNavigation`, `CodexPage`, `Codex`, y después la localización y
`Core/Init.lua`. En `Core/Init.lua` el Codex sigue siendo **opcional** y ahora declara `requires = { "Theme", "Registry",
"Localization" }`: si cualquiera falla, el Codex se omite (`Init.skipped`) sin intentarse, y si el Codex falla, los servicios arrancan
igual.

Se separó el modelo de las vistas para poder probar la lógica sin frames y mantener `Codex.lua` pequeño. Los tres ficheros de vista son
internos: no forman parte de ninguna API pública y los frames nunca salen del Codex.

## Cómo se obtienen las relaciones y los textos

- **Relaciones:** `Registry:GetContained(id)` (la relación derivada `contains`), `Registry:Get`, `Registry:GetAll` y `Registry:Has`. El
  modelo **no guarda ninguna copia de la jerarquía**: la calcula en cada consulta. Lo único que guarda es estado de interfaz en memoria.
- **Textos:** siempre `Localization:Get(id, campo)` (con su fallback de idioma por campo). Para `name` y `description` se prueba antes
  `nameKey`/`descriptionKey` de la entidad, si la declara, y después su propio ID.

### El árbol

Cada nodo cuelga de su **ancla**: su `parent` si lo tiene y, si no, su `located_in`.

- `parent` es la jerarquía geográfica (continente → zona/ciudad → subzona).
- Un **NPC** o una entrada de **lore** no tienen `parent`; solo *están* en un lugar (`located_in`). Cuelgan de ese lugar, pero ese colgar
  es presentación, no una relación `parent`: no hay un `parent` nuevo ni se modifica ninguna entidad.
- **`located_in` de una entidad que sí tiene `parent` NO la cuelga de ese lugar.** Forjaz está en Dun Morogh (`located_in`) pero es una
  ciudad del continente (`parent`): en el árbol está bajo el continente y su ubicación se muestra como dato contextual en su página
  («Ubicado en: …»). Así no se fabrica una jerarquía falsa.
- `related_to` no crea jerarquía.
- Raíces: las entidades sin ancla, o **cuyo ancla no está registrado** (para que nada desaparezca en silencio).
- **Orden determinista**, independiente del idioma y del orden de registro: por tipo (continente, zona, ciudad, subzona, personaje, lore;
  los tipos futuros al final) y dentro del tipo por ID.
- Expandir y contraer **no cambian la página**. Seleccionar una página sí **expande sus ancestros** para que su fila sea visible, y
  desplaza la lista lo mínimo para mostrarla; expandir/contraer nunca mueve la lista.

### Las páginas

`CodexModel:GetPage(id)` y la vista muestran **solo lo que existe**, de arriba abajo: nombre, tipo («Continente», «Zona», «Ciudad»,
«Subzona», «Personaje», «Lore»; un tipo futuro muestra su identificador de tipo), ubicación contextual, raza y rol (NPC), **descripción**
y, separado por una línea, **cuerpo del artículo**. Lo que falta no deja hueco ni se rellena. Los textos se muestran **enteros**: la
página se mide con el texto puesto y la zona se desplaza con la rueda del ratón. Cada página nueva empieza arriba; repintar la misma
página (por ejemplo al expandir un nodo) conserva el punto de lectura.

**Fallback del nombre:** si no hay nombre localizado (o está vacío), se muestra el **propio ID canónico** (p. ej. `subzone:foo`), atenuado
(color de texto secundario). La entidad nunca se oculta ni se lanza un error.

### Breadcrumbs

La ruta de **`parent`** hasta la página actual (nunca `located_in`). Cada tramo anterior es un botón que navega a esa entidad; el último,
la página actual, es texto. Si no caben en el ancho, se quitan tramos por el principio y se antepone «...» (medido con
`GetStringWidth`). Un NPC no tiene ruta jerárquica: su breadcrumb es solo él, y su ubicación va aparte.

### Historial

Como el de un navegador, **en memoria** y por sesión de la interfaz (nada en SavedVariables): máximo 100 entradas (se descarta la más
antigua).

- Seleccionar la página actual **no hace nada** (sin entradas duplicadas ni repintado).
- Seleccionar otra página añade una entrada tras la posición actual y **descarta todo lo que había «por delante»**.
- Atrás/Adelante mueven la posición sin modificar la lista y **saltan las entradas cuyo ID ya no existe**.
- Los botones `<` y `>` se atenúan si no hay a dónde ir.
- El historial y los breadcrumbs son cosas distintas: el primero son las páginas visitadas en orden; los segundos, la ruta geográfica de
  una página.

## API

### Pública (sin cambios)

`Codex:Init()`, `IsReady()`, `IsVisible()`, `Show()`, `Hide()`, `Toggle()`. `Chronicle.Codex.New({ theme, registry, localization,
createFrame, uiParent, specialFrames })` crea otra instancia (pruebas); la instancia por defecto usa `Chronicle.Theme`, `Registry` y
`Localization`.

### Interna

- `CodexModel.New({ registry, localization, onChange })` → `GetRows`, `GetChildren`, `Select`, `Toggle`, `SetExpanded`, `IsExpanded`,
  `GetCurrent`, `GetPage`, `GetBreadcrumbs`, `GetName`, `Back`, `Forward`, `CanBack`, `CanForward`, `GetHistory`. `Select`/`Toggle`
  devuelven `true` o `false, motivo` (`"invalid_id"`, `"unknown_id"`, `"no_children"`); un fallo de `onChange` se ignora.
- `CodexScroll.New({ theme, createFrame }):Create(parent, left, top, width, height)` → `GetChild`, `GetContentWidth`,
  `SetContentHeight`, `ScrollTo`, `GetOffset`, `GetRange`, `Reveal`.
- `CodexNavigation.New({ theme, createFrame, scroll })` y `CodexPage.New({ ... })` → `Attach(parent, width, height, model)` y `Refresh()`.

## Theme

Todo el estilo sale de Theme (colores, fuentes, medidas, espaciado); las vistas no definen ninguna constante visual. Se **añadieron** (sin
cambiar ninguno existente) los tokens que faltaban: `colors.SELECTION` (fondo de la fila seleccionada) y las medidas `CODEX_ROW_HEIGHT`,
`CODEX_ROW_INDENT`, `CODEX_TOGGLE_WIDTH`, `CODEX_TOOLBAR_HEIGHT`, `CODEX_BUTTON_WIDTH`, `CODEX_SCROLLBAR_WIDTH`,
`CODEX_MIN_THUMB_HEIGHT` y `CODEX_SCROLL_STEP`. Hacían falta porque las filas, la barra de herramientas y el desplazamiento no tenían
medidas. Los únicos literales de las vistas son los símbolos de los botones (`+`, `-`, `<`, `>`, `/`, `...`) y los rótulos
«Ubicado en», «Raza», «Rol» y la indicación sin página; no pasan por Localization (no hay mecanismo para textos de interfaz).

## Desplazamiento

Se decidió usar **solo APIs básicas** de widgets: `ScrollFrame` con `SetScrollChild`/`SetVerticalScroll`, la rueda del ratón
(`EnableMouseWheel` + `OnMouseWheel`) y un `Frame`/textura planos como **indicador** de posición. No se usa `UIPanelScrollFrameTemplate`
ni `Slider`, cuyo comportamiento en Classic Era no se pudo verificar. Consecuencia: la barra es un **indicador, no se arrastra**; se
desplaza con la rueda. El desplazamiento máximo se calcula en el propio código (alto del contenido − alto visible), sin depender del
rango que recalcula el cliente. El mock se amplió con esas APIs (`SetScrollChild`, `SetVerticalScroll`, `GetVerticalScroll`,
`EnableMouseWheel`, `GetStringWidth`); no recorta ni recalcula rangos como el cliente real.

## Fallos de interfaz

Si falla la **construcción** de cualquiera de las vistas, `Init` falla con el motivo, deja el frame principal oculto y sin scripts (como en
la Fase 8) y es definitivo; sus hijos (zonas, botones) quedan bajo la ventana oculta y conservan sus scripts, inofensivos al no ser
visibles. Si falla un **repintado en uso**, el clic no lanza error y el fallo se comunica por `geterrorhandler`; el Codex se recupera en
la siguiente actualización correcta.

## Verificación

`npm test` desde `tests`: **1168 superadas, 0 fallidas, código de salida 0** (998 de las fases 1 a 7, 66 del Codex de la Fase 8 —con
las actualizaciones descritas abajo— y 104 nuevas de `tests/codex_nav_tests.lua`).

Las pruebas de la Fase 9 son de dos niveles que no hay que confundir:

- **Lógica** (`CodexModel`): el árbol contra las relaciones reales del Registry, `parent` frente a `located_in`, nombres de
  Localization, entidades sin textos, selección, expansión que no cambia la página, orden determinista (también independiente del orden de
  registro), breadcrumbs, historial (atrás, adelante, futuro descartado, sin duplicados, acotado, saltando IDs que dejan de existir),
  descripción frente a cuerpo (`textKey`), `nameKey`/`descriptionKey`, textos largos íntegros, IDs inexistentes o inválidos, tipos
  futuros y entidades con ancla inexistente. Sobre el catálogo real y sobre catálogos sintéticos.
- **Interfaz con el mock estricto**: se pulsan los botones reales (`OnClick`) y se comprueban los textos, los colores de Theme, la fila
  seleccionada, los breadcrumbs, los botones Atrás/Adelante, la rueda del ratón (límites y punto de lectura), el indicador de posición,
  las medidas de Theme (con un tema alterado), el desbordamiento de breadcrumbs, las filas reutilizadas y los fallos de repintado.
  **Esto no es una comprobación visual:** el mock no dibuja ni recorta.

**Mutaciones** (criterio estricto: solo cuenta una aserción `[FAIL]` clara, no una excepción de Lua): **64 mutaciones, las 64 detectadas
con aserciones claras.** Tras cada una se restauró el fichero y al final se verificó que todos eran idénticos a la versión final. Cubren
(modelo) el ancla que prefiere `located_in`, los breadcrumbs por `located_in`, el orden sin tipo o invertido, expandir que cambia la
página, no descartar el futuro, duplicar la página actual, no saltar IDs inexistentes, no validar el ID, historial sin límite,
no revelar ancestros, nombres que no vienen de Localization, el fallback vacío, la descripción usada como cuerpo, descripción truncada,
`hint` mostrado, `nameKey` ignorado, entidades con ancla inexistente ocultas, expandir hojas, no notificar, errores de `onChange`
propagados, filas que ignoran la expansión, selección sin marcar, Atrás/Adelante que alteran la lista y tipos futuros sin etiqueta;
(árbol) el botón +/- que selecciona, todas las filas seleccionadas, selección sin oro, sin sangría, filas sobrantes sin ocultar,
desplazamiento por selección ausente o excesivo, alto de fila fuera de Theme, nombre de reserva sin atenuar, símbolos invertidos y
hojas con botón +/-; (desplazamiento) sin límite superior, rueda invertida, paso fuera de Theme, contenido sin altura, indicador
siempre visible o nunca; (página) repintado en cada cambio, descripción que muestra el cuerpo, breadcrumb o Atrás que navegan mal,
texto truncado, breadcrumbs sin acortar, sin indicación vacía, sin ubicación, página que no empieza arriba, sin línea de separación y
botones de historial sin atenuar; (cableado) árbol o página sin pintar al construir, modelo sin aviso a las vistas, fallos de repintado
no comunicados y Registry sin comprobar; (integración) Codex sin depender de Registry o de Localization, Codex requerido; y tokens de
Theme ausentes o alterados.

Nueve de ellas, además de las aserciones `[FAIL]` claras, dejan una excepción de Lua posterior en el resto del script de pruebas
(`MM12`, `MM13`, `MM20`, `MN1`, `MS4`, `MC1`, `MC3`, `MC4` y `MT3`): cuentan como detectadas porque fallan primero por aserciones, y se
declara aquí para que no pase inadvertido. Se endurecieron las pruebas donde fue sencillo (clics y filas tolerantes) pero no se
eliminó del todo.

**Historial (transparencia):** la primera pasada completa de mutaciones se detuvo por un límite de tiempo en la última tanda y **dejó
`Theme.lua` mutado** (sin `CODEX_ROW_HEIGHT`); se detectó al volver a ejecutar las pruebas (22 fallos), se restauró y se repitió toda la
batería con copia de seguridad de los ficheros. Esa pasada también reveló cuatro mutaciones **no detectadas** que llevaron a nuevas
pruebas: una hoja que hereda el botón +/- de una fila reutilizada, repintar la página al expandir un nodo (perdía el punto de
lectura), los botones de historial sin atenuar al empezar y el desplazamiento de la lista al expandir/contraer.

## Cambios en pruebas anteriores

Ninguna se eliminó ni se debilitó. Hubo que **actualizar** pruebas de la Fase 8 que describían la estructura provisional que esta fase
sustituye: el helper `Make` ahora inyecta Registry y Localization; 2d y 2e (ya no existen las etiquetas provisionales «Navegación» y
«Contenido»; ahora se comprueba que no están); 7 (sin la etiqueta); 2i (tres `Init` no crean más frames que el primero, en vez de un
número fijo); 12b (los roles de Theme se registran en vez de buscarse por posición) y 12d (la lista exacta de dependencias del Codex
ahora incluye Registry, Localization y sus módulos internos). La prueba 1f del Popup ya se había acotado en la Fase 8.

## Limitaciones no verificadas en WoW Classic Era real

Todo lo anterior se ha probado con un mock estricto que valida la **lógica**, no el dibujo ni el comportamiento del cliente.
**No se ha ejecutado en el juego.** Pendiente de comprobar en un cliente real:

- El aspecto: sangrías, colores, el fondo de selección, el tamaño y el espaciado de filas y página.
- `ScrollFrame` con `SetScrollChild`/`SetVerticalScroll`, la rueda del ratón y el recorte del contenido; el indicador de posición.
- El comportamiento de los botones sin plantilla (`Button` con un `FontString` propio) y el orden de apilado del botón +/- sobre la fila.
- `GetStringHeight`/`GetStringWidth` con las fuentes de Theme, de las que dependen el alto de la página y el ajuste de los breadcrumbs.
- Nombres muy largos: dentro de una fila de ancho fijo pueden ajustarse a dos líneas (no se usa `SetWordWrap`, no verificado).
- La barra de desplazamiento no se arrastra.
- Con el catálogo actual no hay entradas de lore ni `textKey`; el camino del cuerpo del artículo solo se ha ejercitado con datos sintéticos.
- No hay forma de abrir el Codex salvo `Codex:Show()` desde código (sin `/chronicle` ni botón de minimapa, por alcance).

## Fuera de alcance (no implementado)

Integración con Discovery, estados descubierto/no descubierto, entidades bloqueadas o `???`, avisos de proximidad, enlaces automáticos
dentro de los textos, modelos 3D de NPC, botón del minimapa, panel de opciones, nuevos comandos slash, persistencia de página, expansión o
historial, y nuevos datos de lore o traducciones.

## Archivos

Nuevos: `Chronicle/UI/CodexModel.lua`, `CodexScroll.lua`, `CodexNavigation.lua`, `CodexPage.lua`, `tests/codex_nav_tests.lua`,
`docs/fase9_navegacion_paginas.md`.
Modificados: `Chronicle/Chronicle.toc`, `Chronicle/Core/Init.lua` (dependencias del Codex), `Chronicle/UI/Theme.lua` (tokens),
`Chronicle/UI/Codex.lua` (cableado), `tests/mock.lua` (APIs de desplazamiento), `tests/harness.js`, `tests/codex_tests.lua` (ver arriba).
