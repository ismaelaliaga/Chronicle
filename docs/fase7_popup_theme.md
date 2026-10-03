# Fase 7: Popup + Theme

Infraestructura visual reutilizable para mostrar un título y un texto en una ventana emergente de Chronicle:

| Módulo | Responsabilidad |
|---|---|
| `Chronicle.Theme` (`UI/Theme.lua`) | Los estilos visuales compartidos (colores, fuentes, medidas, texturas) en un único sitio. Independiente del contenido |
| `Chronicle.Popup` (`UI/Popup.lua`) | La ventana emergente y su ciclo de vida: mostrar, actualizar, cerrar, cola, posición. No decide qué mostrar |

**Qué no es:** no es el Codex ni una aplicación de lore. Nada la conecta todavía a Discovery, ZoneDiscovery ni Proximity: no se
muestra nada automáticamente. Quien use el Popup construye el contenido y se lo pasa.

> **Verificación honesta:** todo se ha probado con un mock **estricto** de la interfaz y con frames manipulados para provocar
> fallos. Eso verifica la lógica (ciclo de vida, cola, validación, estados coherentes), **no que la ventana se vea o
> funcione bien dentro de un cliente de Classic Era**. Ningún cliente se ha ejecutado en esta fase.

## Auditoría funcional del popup original

Fuente leída (solo lectura): `UI/LoreFrame.lua` y `Core/Theme.lua` del addon original, y el tema de la maqueta del Códex
(`UI/Codex/Theme/*`). Qué hacía el original y qué se decide:

| Comportamiento del original | Decisión | Motivo |
|---|---|---|
| Una única ventana (`ChronicleLoreFrame`) creada al cargar, reutilizada siempre | **Conservado** (`ChroniclePopupFrame`, creada en `Init`) | evita ventanas duplicadas |
| Título + separador + cuerpo + botón de cierre estándar (`UIPanelCloseButton`) | **Conservado** | |
| Medidas: 420 de ancho, alto = `max(140, 70 + texto)`, título a 20, separador a 44, cuerpo a 54, margen 24 | **Conservado** (en `Theme`) | |
| Capa `HIGH`, anclada arriba y centrada 160 bajo el borde | **Conservado** | |
| Cerrar con Escape (`UISpecialFrames`) | **Conservado** | comportamiento nativo esperado |
| Arrastrable con el botón izquierdo | **Conservado** (solo en sesión; limitada a la pantalla) | |
| Posición arrastrada guardada en `ChronicleCharDB.lorePopupPoint` | **No conservado**: se emite el evento `Chronicle.Popup.Moved` | la UI no puede tocar State; persistirla exige añadir una clave al estado: decisión pendiente |
| Cola FIFO: lo que llega con un popup visible espera su turno | **Conservado** (`Enqueue`) | caso real: una comprobación de zona descubre zona y subzona a la vez y son dos avisos |
| La cola avanza al ocultarse, tras una pausa de 0,2 s con `C_Timer.After` | **Cambiado**: avanza al instante, sin temporizador | no hay temporizadores en esta fase |
| Aparece con fundido (0,25 s) y se cierra sola a los 12 s con fundido (0,5 s), con `OnUpdate` | **No conservado** | son de un aviso transitorio, no de una ventana de lectura; sin animaciones ni temporizadores |
| Un clic en el cuerpo la cierra | **No conservado** | el texto tendrá enlaces más adelante; quedan la X y Escape |
| Dos temas (oscuro y «pergamino»), elegible por un ajuste | **Un solo tema** (oscuro/bronce/oro) | no hay panel de opciones ni sistema de temas |
| El texto pasa por `TextLinker.LinkNames` (enlaces a entidades) | **No conservado** | TextLinker es de una fase posterior |
| Respeta el interruptor global `Chronicle.enabled` | **No conservado** | decidir si mostrar algo es cosa de quien llama |
| Un único canal (`ShowLore`) para zonas, lugares, misiones, curiosidades y proximidad | **Igual**: un único tipo de popup | el original no distinguía un popup «de lore» de otros avisos |

**Incertidumbres del original que no se han podido determinar:** el comportamiento exacto de `UIFrameFadeIn/Out` en
Classic Era (usaba un respaldo si no existían), y si el orden entre el fundido de salida y `OnHide` tenía algún efecto
visible. No se han reproducido, así que no se inventa nada sobre ellos.

## Theme

Un único tema. Los valores salen del diseño original: la paleta y las fuentes de la maqueta del Códex («para que se sienta
integrado en WoW Classic y no como una web»), y las texturas y medidas del popup original.

```lua
local T = Chronicle.Theme
T:GetColor("GOLD")              --> { 0.80, 0.64, 0.30, 1 }      (copia)
T:GetFontRole("TITLE")          --> { font = "Fonts\\MORPHEUS.ttf", size = 20, color = {...}, shadow = true }
T:GetLayout("POPUP_WIDTH")      --> 420
T:GetSpacing("MD")  T:GetStrata("POPUP")  T:GetTexture("SOLID")  T:GetBackdrop("WINDOW")
T:ApplyText(fontString, "BODY") --> true | false, motivo
T:ApplyBackdrop(frame, "WINDOW", "BG_WINDOW", "BORDER") --> true | false, motivo
T:Init()  T:IsReady()
```

- **Colores:** `BG_WINDOW`, `BG_PANEL` (fondo y superficie), `BORDER`, `DIVIDER`, `GOLD` y `GOLD_DIM` (títulos y destacados),
  `TEXT_IVORY` (texto principal), `TEXT_MUTED` (secundario) y `SHADOW`.
- **Roles tipográficos:** `TITLE` (Morpheus 20, oro, con sombra), `BODY` (Friz Quadrata 13, marfil) y `SECONDARY` (11, apagado).
- **Espaciado:** `XS 4, SM 8, MD 12, LG 20, XL 32`. **Medidas del popup** en `GetLayout` (`POPUP_*`).
- **Botones:** el popup usa el botón de cierre estándar del cliente; no se define un estilo propio hasta que una fase lo necesite.
- Todas las consultas devuelven **copias**. **No hay API para modificar estilos** en tiempo de ejecución: nada lo necesita y no se
  construye por anticipado.
- `Init` valida las definiciones (colores en [0, 1], tamaños razonables, roles que usan colores existentes, strata válidos,
  backdrops completos y todas las claves que la interfaz da por existentes) y **lanza un error descriptivo** si no son coherentes.
- Un error visual (`SetFont` que devuelve `false`, un método de interfaz que falla) **nunca lanza error**: `ApplyText` conserva la fuente
  de la plantilla, o devuelve `false, "ui_error"`.
- Las fuentes (`MORPHEUS`, `FRIZQT__`) las dio por existentes el addon original desde Vanilla; **aquí no se han comprobado en un
  cliente**, y solo cubren el alfabeto latino.

## Popup

```lua
local P = Chronicle.Popup
P:Show({ title = "Dun Morogh", body = "…" })   --> true | false, motivo   (reemplaza lo mostrado)
P:Enqueue({ title = "…", body = "…" })          --> true, "shown" | true, "queued" | false, motivo
P:Close()      --> true si había algo visible        P:CloseAll()  --> vacía la cola y cierra
P:IsVisible()  P:GetQueueSize()  P:GetContent()  --> copia { title, body } | nil
P:GetPosition() --> { point, relativePoint, x, y }   P:SetPosition(point, relativePoint, x, y)   P:ResetPosition()
P:GetSize()     --> ancho, alto        P:Init()   P:IsReady()
-- Evento Chronicle.Popup.Moved (Popup.EVENT_MOVED): (point, relativePoint, x, y) al soltar tras arrastrar
```

### Contrato del contenido

Una tabla `{ title = cadena, body = cadena }`.

| Entrada | Resultado |
|---|---|
| Ambos campos presentes y al menos uno con texto | se muestra tal cual |
| Falta uno de los dos (cuenta como `""`) | válido, mientras el otro tenga texto |
| Título y cuerpo vacíos o solo espacios | `false, "empty_content"` |
| No es una tabla, o un campo no es una cadena | `false, "invalid_content"` |
| Antes de `Init` o con `Init` fallido | `false, "not_ready"` |
| Cola con 50 pendientes | `false, "queue_full"` |

Nunca se lanza error por contenido o argumentos inválidos, y una entrada inválida **no cambia nada** (ni lo mostrado ni la cola).
Los textos se muestran **tal cual**; las secuencias de color del cliente (`|cff…|r`) se interpretarían, y quien pasa el texto es
responsable de él. El Popup guarda **copias** del contenido.

### Ciclo de vida

1. `Init` crea la ventana (oculta) una sola vez; es idempotente. **Un `Init` fallido es definitivo** en la sesión: repetirlo da el mismo
   error sin crear otra ventana, para no dejar ventanas huérfanas (un fallo por Theme no listo sí se puede reintentar).
2. `Show`, `Enqueue` y `Close` antes de `Init` devuelven `not_ready`: nunca crean la ventana por su cuenta.
3. El estado «visible» es siempre el del frame real. Si una llamada de interfaz falla, se comunica por `geterrorhandler`, se devuelve
   `"ui_error"` y la ventana queda con el contenido que tenía (o cerrada), no a medias.
4. **Cerrar por cualquier vía** (`Close`, la X o Escape) muestra enseguida el siguiente de la cola, si lo hay. Un pendiente que no se
   puede mostrar se descarta (comunicado) y se pasa al siguiente: la cola no se atasca.

### Cola

`Show` **reemplaza** lo mostrado y no toca la cola. `Enqueue` muestra al instante si no hay nada visible; si lo hay, añade al final
(FIFO, máximo 50). `Close` avanza la cola; `CloseAll` la vacía y cierra. No hay temporizadores: el avance es inmediato. El límite
de 50 evita crecer sin control si algo encola en bucle; superado, `Enqueue` lo dice (`queue_full`) en vez de perder entradas en
silencio.

### Posición y tamaño

El ancho es el de Theme y el alto sigue al texto: **no hay `SetSize`**. La posición se puede leer y fijar (relativa a `UIParent`,
puntos válidos del cliente, números finitos) y la ventana se puede arrastrar (limitada a la pantalla). La posición **no se guarda**:
al soltar tras arrastrar se emite `Chronicle.Popup.Moved`, por si otro módulo (con acceso a State) decide persistirla.

## Dependencias e inicialización

- **Popup depende de Theme** (`requires = { "Theme" }`) y del bus `Events` solo para el aviso de movimiento. **No depende** de State,
  Discovery, Registry, Localization, Resolver ni de ningún servicio: no accede a `ChronicleCharDB`.
- **Carga (`.toc`):** `UI/Theme.lua` y `UI/Popup.lua` tras los servicios y antes de `Core/Init.lua`. Los ficheros solo definen módulos.
- **Inicialización:** en `ADDON_LOADED`, con los recursos del cliente ya cargados. Ambos módulos son **opcionales** (`required = false`):
  un fallo puramente visual no debe impedir que funcionen Discovery y los servicios ni que se anuncie el arranque; queda diagnosticado
  en `Init.failed`, y si falla Theme, Popup queda en `Init.skipped`. **Consecuencia:** `Chronicle.Initialized` se emite aunque la interfaz
  haya fallado, así que quien use el Popup debe comprobar `Popup:IsReady()`.
- Instancias propias: `Theme.New(definiciones)` y `Popup.New({ theme, events, createFrame, uiParent, specialFrames })`.

## Mock de la interfaz

`tests/mock.lua` ahora incluye frames con estado real (visibilidad, anclajes, textos, scripts `OnShow`/`OnHide`) y **solo los métodos que
usa Chronicle**: llamar a otro lanza «attempt to call a nil value», como el cliente real. La altura del texto es simulada (16 por línea
de 60 caracteres). Sigue siendo un mock: no dibuja nada.

## Pruebas

```
cd tests
npm test
```

Resultado de la ejecución final: **986 superadas, 0 fallidas, código de salida 0** (811 de las fases 1 a 6, 66 de Theme en
`theme_tests.lua` y 109 de Popup en `popup_tests.lua`). Cubren: la API de Theme y sus tipos, los valores tomados del original, las
copias, las definiciones inválidas, que los consumidores no dupliquen constantes visuales; el arranque, la idempotencia de `Init`,
mostrar/actualizar/cerrar, Escape y la X, contenido vacío e inválido, la cola (orden, límite, cierre y reapertura, `CloseAll`), posición y
arrastre, fallos de la interfaz en `Init` y en uso, el aislamiento (nada de State/Discovery/`ChronicleCharDB`, ni temporizadores ni
eventos del cliente) y la integración con `Core/Init`.

### Mutaciones probadas (restauradas después)

Se introdujo cada defecto de forma aislada y se comprobó que `npm test` fallaba. **Criterio estricto:** una mutación solo cuenta
como detectada si produce al menos una aserción `[FAIL]` clara; un fallo del intérprete por una excepción de Lua no cuenta. Tras
cada mutación se restauró el fichero y al final se verificó que todos quedaron idénticos a la versión final.
**39 mutaciones, las 39 detectadas con aserciones claras y sin ninguna excepción posterior.**

- **Popup (26):** `Init` no idempotente; un `Init` fallido que reintenta y duplica la ventana; `Enqueue` que pisa lo visible; cola LIFO;
  cola que duplica entradas; cola sin límite; cerrar sin avanzar la cola; `CloseAll` sin vaciar la cola; aceptar contenido vacío;
  aceptar un título que no es cadena; no verificar que la ventana quedó visible; no restaurar el contenido tras un fallo a mitad de
  actualización; afirmar éxito aunque falle la interfaz; no registrar Escape; `SetPosition` sin validar; no emitir el evento de
  movimiento; ignorar la altura mínima; guardar el contenido sin copiarlo; cerrar algo cerrado devolviendo `true`; recortar el cuerpo;
  una cola que reinserta lo ya mostrado; un ancho que no sale de Theme; y cuatro de aislamiento (leer `ChronicleCharDB`, usar
  Discovery, añadir un temporizador, fijar un color saltándose Theme).
- **Theme (9):** colores fuera de [0, 1]; no exigir las claves que usa la interfaz; consultas sin copia; `ApplyText` que ignora el
  color; un valor del tema alterado; `Init` que no lanza error; `ApplyText` que no informa de fallos; usar el estado del Core; un
  tamaño de fuente alterado.
- **Core/Init (4):** Theme o Popup como módulos requeridos; Popup sin depender de Theme; Popup dependiendo de Discovery.

**Historial (transparencia):** una primera pasada dio 36 de 39. Tres no contaban: dos eran **huecos reales de las pruebas** (la
restauración del contenido tras un fallo a mitad de actualización no se ejercitaba, porque el fallo ocurría en la primera llamada; y los
espacios al principio y al final del texto no se comprobaban) y una era un **mutante equivalente** (no cambiaba el comportamiento), que
se sustituyó por un defecto real. Además, tres mutaciones dejaban una excepción de Lua tras el `[FAIL]` claro; se endurecieron las
pruebas (accesos que no lanzan error y bucles acotados) y se repitió la batería completa.

### Cambios en pruebas anteriores

Ninguna prueba se eliminó ni se debilitó. El mock se amplió (los frames antiguos eran vacíos) y las 811 pruebas anteriores siguen pasando
sin modificar ninguna.

## Limitaciones conocidas

- **No probado en un cliente real de Classic Era:** `BackdropTemplate`, `UIPanelCloseButton`, `UISpecialFrames`, `SetClampedToScreen`, la
  textura `WHITE8X8` y las fuentes, ni el aspecto real. Son los mismos recursos que usaba el popup original (que su autor probó), salvo
  `SetClampedToScreen`, que el original no usaba (se llama solo si existe).
- Los títulos muy largos pueden envolver y solaparse con el separador (no se recortan).
- Las fuentes solo cubren el alfabeto latino.
- La posición arrastrada no persiste entre sesiones.
- No hay cierre automático, fundidos ni sonido (decisión deliberada).
- No hay enlaces en el texto (TextLinker).

## Para la Fase 8 (deliberadamente fuera)

El Codex y su árbol de navegación, las páginas de entidad, el historial, el modelo 3D de los NPC, el TextLinker y los enlaces, la
persistencia de la posición (que exige una decisión sobre el estado), el panel de opciones y el botón del minimapa, y conectar
Discovery/ZoneDiscovery/Proximity con avisos visibles.

## Archivos

**Creados:** `Chronicle/UI/Theme.lua`, `Chronicle/UI/Popup.lua`, `tests/theme_tests.lua`, `tests/popup_tests.lua`,
`docs/fase7_popup_theme.md`.

**Modificados:** `Chronicle/Chronicle.toc` (dos líneas), `Chronicle/Core/Init.lua` (los módulos `Theme` y `Popup`, opcionales),
`tests/mock.lua` (frames con estado), `tests/harness.js` (dos líneas).

`State`, `Events`, `Schema`, `Registry`, `Localization`, `Resolver`, `Discovery`, `MapPosition`, `Proximity` y `ZoneDiscovery` no se han
tocado, ni los datos, textos, IDs o alias, ni las SavedVariables.
