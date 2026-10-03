# Fase 8 — Codex base

Estado: implementada y pendiente de revisión del supervisor. **Solo la estructura visual de la ventana principal.** No hay navegación,
ni artículos, ni conexión con Discovery.

## Qué hay

`Chronicle/UI/Codex.lua` (módulo `Chronicle.Codex`) crea una ventana con:

- un marco con el estilo de Chronicle (backdrop `WINDOW`, fondo y borde de Theme);
- un encabezado: el título «Chronicle» (rol `TITLE`) a la izquierda, el botón de cierre estándar del cliente (`UIPanelCloseButton`)
  a la derecha y una línea de separación debajo;
- una **zona de navegación** a la izquierda: un contenedor vacío (un frame hijo) sobre una superficie de panel (`BG_PANEL`) con la
  etiqueta provisional «Navegación»;
- una **separación vertical** entre ambas zonas (color `DIVIDER`);
- una **zona de contenido** a la derecha: un contenedor vacío (otro frame hijo) con la etiqueta provisional «Contenido».

Las dos etiquetas son provisionales y se retirarán cuando haya contenido real. No hay iconos, datos de lore ni botones que aparenten
funcionar. Los dos contenedores son los frames donde las fases siguientes colgarán el árbol y las páginas; **no se exponen**.

### Dimensiones y proporciones

840 × 560 (3:2, apaisada, la de una ventana de consulta), centrada en pantalla. La navegación mide 240 de ancho (algo menos de un tercio) y
el resto es contenido. El encabezado mide 40 y todo queda 14 por dentro del borde del backdrop (sus insets son 11–12). Son valores
razonables sobre el papel; **no se han comprobado visualmente en un cliente** (ver «Limitaciones»).

## API pública

| Método | Resultado |
|---|---|
| `Codex:Init()` | crea la ventana, oculta, una sola vez. Idempotente. Lanza un error descriptivo si no puede. |
| `Codex:IsReady()` | `true` solo si `Init` terminó con éxito. |
| `Codex:IsVisible()` | `true` si la ventana está visible; se pregunta al **frame real** (no hay una variable de visibilidad). |
| `Codex:Show()` | muestra la ventana → `true` \| `false, motivo` |
| `Codex:Hide()` | la oculta (no la destruye) → `true` \| `false, motivo` |
| `Codex:Toggle()` | alterna → `true` \| `false, motivo` |

`Show`, `Hide` y `Toggle` son **idempotentes**: devuelven `true` si, al terminar, la ventana está en el estado pedido (mostrar algo ya
visible u ocultar algo ya oculto es `true`). Esto difiere de `Popup:Close()`, que devuelve `false` si no había nada que cerrar: el
Popup cierra «algo» (contenido, cola); el Codex solo tiene un estado visible/oculto. El estado se comprueba en el frame real tras
actuar, así que no se afirma un éxito que el cliente no confirmó.

Motivos: `"not_ready"` (antes de un `Init` válido o tras uno fallido; nunca crean la ventana por su cuenta ni lanzan error) y
`"ui_error"` (la interfaz falló; se comunica por `geterrorhandler`).

`Chronicle.Codex.New({ theme, createFrame, uiParent, specialFrames })` crea otra instancia (pruebas). **La API no expone frames**: no
hay `GetFrame` ni nada parecido. Escape cierra la ventana (se registra en `UISpecialFrames` como último paso de la construcción). No hay
`/chronicle`, ni botón de minimapa, ni opciones.

### Arrastre

Se arrastra con el botón izquierdo; si el cliente ofrece `SetClampedToScreen` se usa para que no salga de la pantalla. **La posición no se
guarda**: cada sesión empieza centrada. No hay redimensionado.

## Uso de Theme

El Codex no define ninguna constante visual. Todo sale de Theme:

| Qué | De dónde |
|---|---|
| Fondo, borde, backdrop | `ApplyBackdrop(f, "WINDOW", "BG_WINDOW", "BORDER")` |
| Título | `ApplyText(…, "TITLE")` |
| Etiquetas provisionales | `ApplyText(…, "SECONDARY")` |
| Superficie de navegación / separaciones | `GetColor("BG_PANEL")` / `GetColor("DIVIDER")` sobre `GetTexture("SOLID")` |
| Espaciado | `GetSpacing("SM" / "MD" / "LG")` |
| Posición del botón de cierre | `GetLayout("POPUP_CLOSE_OFFSET")` (el mismo botón estándar sobre el mismo backdrop) |

### Tokens que faltaban y se añadieron a Theme

Theme no tenía medidas de una ventana principal. Se añadieron (sin cambiar ningún valor existente):

- `layout.CODEX_WIDTH = 840`, `CODEX_HEIGHT = 560`, `CODEX_INSET = 14`, `CODEX_HEADER_HEIGHT = 40`, `CODEX_NAV_WIDTH = 240`,
  `CODEX_DIVIDER_THICKNESS = 1`;
- `strata.CODEX = "MEDIUM"`: **por debajo** de la del Popup (`HIGH`), para que un aviso no quede nunca tapado por el Codex.

No se añadieron a la lista de tokens obligatorios de `Theme:Init` (`REQUIRED`): así un tema incompleto no tumba al Popup. El Codex
comprueba él mismo los que usa al inicializar y falla, sin crear nada, diciendo cuál falta.

## Inicialización segura (lecciones de la Fase 7)

1. El frame se **oculta inmediatamente después de crearlo**, antes de `SetSize` y del resto de la configuración. En el cliente un frame
   recién creado es visible.
2. No se registra en `UISpecialFrames` hasta el último paso.
3. Si la construcción falla, `Init` intenta dejar el frame parcial **oculto y sin scripts** con llamadas protegidas (`pcall`). Un error de
   esa limpieza **no sustituye** al error original: se añade al final como nota.
4. El módulo **no se marca listo** hasta que la construcción terminó.
5. Un `Init` fallido por la construcción es **definitivo** en la sesión: repetirlo da el mismo error y no crea otro frame, para no acumular
   ventanas parciales. Un fallo anterior a crear nada (Theme no listo o sin los tokens, falta `CreateFrame`/`UIParent`/`UISpecialFrames`)
   no crea ningún frame y se puede reintentar.
6. **Limitación:** WoW no permite destruir un frame con nombre (`ChronicleCodexFrame`), así que el parcial seguirá existiendo hasta cerrar el
   juego: oculto, sin scripts y sin registrar en Escape; sus hijos (zonas, botón) con él. No se reutiliza ni se intenta crear otro. Si la
   propia llamada a `Hide` fallara no hay otro mecanismo verificado para esconderlo: el error de limpieza se comunica, no se oculta.

No se ha copiado el código del Popup: se reutilizan los principios, y se mantiene su `Cleanup` propio porque cada módulo limpia scripts
distintos (el Popup también tiene `OnHide`). No se creó una abstracción compartida para dos funciones de veinte líneas.

## Integración

- `Chronicle.toc`: `UI/Codex.lua` va después de `UI/Popup.lua` y antes de los ficheros de localización y de `Core/Init.lua`.
- `Core/Init.lua`: `{ name = "Codex", required = false, requires = { "Theme" } }`. **Opcional**: si falla, queda en `Init.failed` y los
  servicios (Discovery, Proximity, ZoneDiscovery…) arrancan igual y se anuncia `Chronicle.Initialized`. Si Theme falla, el Codex no se
  intenta (`Init.skipped`).
- No accede a `ChronicleCharDB`, ni a State, Registry, Localization, Resolver, Discovery, MapPosition, Proximity, ZoneDiscovery ni al
  Popup. Su único módulo de Chronicle es Theme. No usa temporizadores, animaciones, sonidos ni eventos del cliente.

## Pruebas

`tests/codex_tests.lua` (66 comprobaciones, nuevo fichero en `harness.js`). Con el mock estricto, que además crea los frames de la
fábrica de pruebas **visibles** (como el cliente real) para que no oculte el defecto de inicialización. Cubren: inicialización,
idempotencia, ventana oculta al empezar, `Show`/`Hide`/`Toggle` en ambos sentidos, `IsVisible` frente al frame real (incluso si éste
falla), cierre por la X y por Escape, que abrir y cerrar no recrea nada, la estructura (encabezado, zonas, separación, anclajes), la
ausencia de frames en la API, las operaciones previas a `Init`, los fallos de construcción (fuentes, backdrop, anclaje, hijos, registro
de Escape), la limpieza (ocultar, quitar scripts, orden de llamadas, error original conservado si la limpieza falla), que `Init` fallido
es definitivo y no acumula frames, los fallos de la interfaz en uso, el uso de Theme (con otro tema la ventana cambia), el aislamiento y la
integración con el arranque (un fallo del Codex no impide inicializar los servicios; Theme caído omite el Codex).

Cambio en pruebas anteriores: la prueba 1f del Popup contaba **todos** los frames creados al arrancar; ahora que el Codex crea los suyos,
se acotó a los frames del propio Popup (y se permite el nombre de la ventana del Codex). Se sigue comprobando exactamente lo mismo del
Popup. El resto no se tocó.

### Verificación

`npm test` desde `tests`: **1064 superadas, 0 fallidas, código de salida 0** (998 de las fases 1 a 7 más 66 del Codex).

**Mutaciones (criterio estricto: solo cuenta una aserción `[FAIL]` clara, no una excepción de Lua):** 34 sobre `Codex.lua`, `Init.lua` y
`Theme.lua`, todas detectadas con aserciones claras y sin excepciones posteriores; tras cada una se restauró el fichero y al final se
verificó que eran idénticos a la versión final. Cubren: sin ocultación temprana (o tardía, o nacer visible); sin limpieza, limpieza que no
oculta, que no quita scripts, sin `pcall`, o que sustituye al error original; Escape registrado antes de terminar o nunca; `Init` fallido
que no es definitivo o que deja el módulo listo; `IsVisible` que no consulta el frame; `Show`/`Hide` sin verificar el resultado o que
afirman éxito si el frame falla; `Toggle` invertido; operaciones sin comprobar `not_ready`; cerrar que destruye la ventana; medidas, capa o
colores fuera de Theme; tokens de Theme sin validar o ausentes; capa por encima del Popup; sin límite de pantalla; título, separación y zona
de contenido alterados; scripts extra; Codex requerido, sin depender de Theme o dependiendo de Discovery; y lectura de `ChronicleCharDB` o
uso de temporizadores.

**Historial (transparencia):** la primera pasada dio 32 de 34. X15 (cerrar destruye la ventana) solo producía una excepción de Lua y
X23 (Codex dependiendo de Discovery) no se detectaba: se añadió la prueba 11i y se protegieron los bucles de las pruebas. Otras tres
se detectaban con excepción posterior; se endurecieron las pruebas y se añadió a `Codex.lua` una guarda de invariante (listo pero sin
ventana → `false, "ui_error"` en vez de lanzar un error). Se repitió la batería completa: 34 de 34.


## Limitaciones conocidas

- **No probado en un cliente real de Classic Era:** el aspecto, las proporciones, `BackdropTemplate`, `UIPanelCloseButton`,
  `UISpecialFrames`, `SetClampedToScreen`, el arrastre y la capa (`MEDIUM` frente al `HIGH` del Popup). Todo lo anterior se ha
  verificado con un mock estricto que valida la lógica, no el dibujo.
- La posición no se guarda; no hay redimensionado; no hay forma de abrir la ventana (ni `/chronicle` ni minimapa): solo `Codex:Show()`
  desde código. Es deliberado en esta fase.
- Las etiquetas «Navegación» y «Contenido» son literales provisionales, no pasan por Localization.
- Un `Init` fallido deja un frame parcial oculto hasta cerrar el juego (ver «Inicialización segura»).

## Fuera de alcance (no implementado)

Árbol de navegación, navegación entre entidades, páginas de lore, breadcrumbs o historial, enlaces entre nombres y entidades, modelos 3D
de NPC, integración con Discovery o avisos de proximidad, persistencia de posición o tamaño, panel de opciones, botón del minimapa,
comando `/chronicle`, trivia, FreshCharacterCheck y nuevas fuentes de datos.

## Archivos

Nuevos: `Chronicle/UI/Codex.lua`, `tests/codex_tests.lua`, `docs/fase8_codex_base.md`.
Modificados: `Chronicle/Chronicle.toc`, `Chronicle/Core/Init.lua` (una línea de módulo), `Chronicle/UI/Theme.lua` (tokens `CODEX_*` y
`strata.CODEX`), `tests/harness.js` (un fichero de pruebas más), `tests/popup_tests.lua` (acotar la prueba 1f).
