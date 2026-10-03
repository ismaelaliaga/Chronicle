# Fase 10 — Integración entre Discovery y Codex

Estado: implementada y pendiente de revisión del supervisor. Commit base: `72c4d5edba5bd72172ee16a335940a2ceb797846` (comprobado: `main`
estaba en ese commit y las interfaces descritas seguían vigentes). **No se ha empezado la Fase 11.**

## Resumen

El Codex consulta a Discovery qué entidades ha descubierto el personaje. Las **descubiertas** se ven como en la Fase 9. Las
**no descubiertas** siguen en el árbol pero se llaman `???` y su página no contiene ningún dato. Cuando Discovery avisa de un
descubrimiento nuevo, el Codex se actualiza. El Codex **no escribe nada** ni descubre nada al mostrar, seleccionar o expandir.

## Contratos reales utilizados

Leídos del código, no deducidos. (El módulo es `Chronicle.Discovery`, en `Services/Discovery.lua`; el enunciado lo llamaba
`Chronicle.Services.Discovery`, que no existe. Tampoco hay `Localization/Resolver.lua`: el Resolver está en `Services/Resolver.lua` y no
interviene en esta fase.)

| Contrato | Uso |
|---|---|
| `Discovery:IsReady()` → `true` tras un `Init` correcto | el modelo exige `true` exacto |
| `Discovery:IsDiscovered(id)` → `true`/`false`; `false` para ID inválido, desconocido o sin estado; **consultar no descubre ni emite** | fuente de verdad única |
| `Discovery.EVENT_DISCOVERED` = `"Chronicle.Discovery.Discovered"`, **un solo argumento**: el ID canónico recién descubierto; se emite **después de guardar**, una vez por descubrimiento nuevo, nunca al consultar ni al repetir | el Codex se suscribe |
| `Chronicle.Events:Register(nombre, función)`: registrar la misma función dos veces **no** la duplica | un único manejador |
| Los errores de los listeners los aísla el propio `Events` | — |

La API existente es suficiente y fiable: **no se ha ampliado ni cambiado ningún contrato**, ni de Discovery, ni de State, ni del bus.
`schemaVersion` y el formato de persistencia no cambian. Si el evento llega sin ID (o con algo que no es una cadena), se ignora.

## Política de visibilidad

1. **Descubierta ⇔ el servicio dice `true`.** Una entidad se considera descubierta si y solo si `Discovery:IsReady() == true` e
   `IsDiscovered(id) == true`. **Cualquier otra cosa es «bloqueada»**: sin servicio, sin esos métodos, servicio no listo, un valor que
   no sea el `true` exacto, un error al consultar (de `IsReady`, de `IsDiscovered` o al obtener el servicio). Nunca se supone
   descubierta por defecto. Los errores al consultar se comunican por `geterrorhandler` **una sola vez por mensaje** (no en cada
   repintado) y no se propagan; no se envuelve nada más en `pcall`.
2. **Cada entidad se evalúa por sí sola.** Descubrir un lugar no descubre lo que hay en él, ni un NPC sus artículos; nada es
   recursivo. No se tocan `parent`, `located_in` ni `related_to`.
3. **Una entidad bloqueada:**
   - se llama **`???`** en todos los sitios donde el modelo da un nombre: filas, breadcrumbs y la ubicación contextual de otras páginas.
     **Nunca se devuelve su nombre real ni su ID como nombre de reserva** (el fallback del ID de la Fase 9 solo aplica a las descubiertas);
   - su página es `{ locked = true, name = "???" }` y nada más: **sin ID, tipo, ubicación, descripción, cuerpo, raza ni rol**. La vista
     la pinta con el título `???` en el color `LOCKED` y una línea («Aún no has descubierto esta entrada.»);
   - sigue en el árbol, **se puede seleccionar y expandir**, y conserva su sitio en el orden (tipo e ID);
   - la fila seleccionada conserva el fondo de selección pero su texto va en `LOCKED`, no en oro: «bloqueada» y «seleccionada» no se
     confunden.
4. **Descendientes bajo un ancestro bloqueado** (política explícita; elegida por ser la menos reveladora sin inventar datos ni tocar
   relaciones): se muestran **por su propio estado**. Una descendiente descubierta aparece con su nombre; los ancestros bloqueados
   siguen siendo `???` en su breadcrumb y en su ubicación contextual. Una descendiente bloqueada es `???`. El nombre de un ancestro
   bloqueado nunca sale por la página de un descendiente.
5. **Lo que sí se ve de una entrada bloqueada (limitación documentada):** que *existe* una entrada en ese lugar del árbol, su
   profundidad, cuántos hijos tiene y su **orden**. El orden se calcula con el tipo y el ID (no con el nombre mostrado), así que
   también refleja el orden alfabético de los identificadores canónicos, que son nombres ingleses en minúsculas. Ocultarlo del todo
   exigiría reordenar de forma no determinista o quitar entradas del árbol, lo que contradice el enunciado («no deben desaparecer del
   catálogo»). Se deja explícito para que el supervisor decida si es aceptable.
6. **El cuerpo del artículo** (`textKey`, sin cambios respecto a la Fase 9) pertenece a la propia entrada: se muestra si **la entrada** está
   descubierta. La entidad a la que apunta `textKey` es solo un contenedor de texto y no se consulta por separado. Abierta por sí sola
   sin estar descubierta, esa entidad es una entrada bloqueada más.
7. **No hay nada pendiente de decisión por falta de API.** Sí queda abierto lo del punto 5.

## Flujo de consulta y refresco

- **Consulta:** `CodexModel` recibe `discovery` (objeto o función que lo devuelve; en el addon `Chronicle.Discovery`) y lo consulta **cada
  vez** que necesita un nombre o una página: **no guarda ningún estado de descubrimiento**. Las vistas (`CodexNavigation`,
  `CodexPage`, `CodexScroll`) **no nombran a Discovery**: pintan lo que da el modelo. Ningún módulo del Codex toca `ChronicleCharDB`,
  `State` ni `Discover`.
- **Suscripción:** al terminar `Init` con éxito, el Codex se suscribe **una vez** a `Discovery.EVENT_DISCOVERED` con una función fija.
  Abrir, cerrar, alternar o repetir `Init` **no** vuelve a registrar nada (comprobado contando los registros).
- **Con la ventana visible:** al llegar un descubrimiento se repinta lo afectado. El árbol y los breadcrumbs siempre (se reutilizan los
  mismos widgets; no se reconstruye nada). La **página** solo si la entidad descubierta es la página actual o su ubicación contextual
  (`CodexModel:AffectsPage`); si no, el punto de lectura no se mueve.
- **Con la ventana oculta:** no se pinta nada (se anota que hay cambios). **Al abrirla** se aplican. Si no hubo suscripción (sin bus,
  sin Discovery listo o sin nombre de evento), cada apertura repinta por completo, así que el estado mostrado es siempre el actual.
- **Sin bucle:** repintar solo consulta; nunca descubre ni emite eventos.

## Inicialización y errores

- Discovery es una dependencia **blanda**. `Core/Init.lua` **no cambia**: el Codex sigue siendo opcional y depende de Theme, Registry y
  Localization. Si Discovery falla o no está listo, el Codex se inicializa igual **con todo bloqueado** y **sin suscribirse**
  (comprobado: `Init.failed.Discovery`, el Codex listo, cero registros). Un fallo del Codex no impide arrancar los servicios (ya probado
  en la Fase 8, repetido aquí).
- La suscripción solo se intenta si Discovery está listo y hay bus y nombre de evento. Si `Register` lanza un error, el Codex se
  inicializa igual y el fallo se comunica.
- Un error al repintar en uso se comunica por `geterrorhandler` sin romper el modelo (Fase 9). El patrón de construcción segura y
  limpieza del frame parcial (Fase 8) no cambia.

## Theme

Se añadió **un** token central: `colors.LOCKED`. Hace falta para distinguir lo bloqueado de lo secundario (`TEXT_MUTED`, que ya usan los
textos secundarios y el nombre de reserva de una entrada descubierta), de lo seleccionado (`SELECTION` es un fondo, y el oro es el texto
seleccionado) y de lo normal. Es más apagado que `TEXT_MUTED`. El Codex comprueba al inicializar que Theme lo tiene (y `SELECTION`). Las
vistas no definen ningún color propio.

## Archivos

Modificados: `Chronicle/UI/CodexModel.lua`, `CodexNavigation.lua`, `CodexPage.lua`, `Codex.lua`, `Theme.lua`, `tests/harness.js`,
`tests/codex_nav_tests.lua` y `tests/codex_tests.lua` (ver «Cambios en pruebas anteriores»).
Nuevos: `tests/codex_discovery_tests.lua` y este documento.
**No** se modificaron `Core/Init.lua`, `Discovery`, `State`, `Schema`, `Registry`, `Localization`, `.toc`, SavedVariables, el mock ni los datos.

## Verificación

`npm test` desde `tests`: **1241 superadas, 0 fallidas, código de salida 0** (1168 de las fases 1 a 9 y 73 nuevas de
`tests/codex_discovery_tests.lua`); tras la corrección posterior, **1270** (ver más abajo).

Qué cubren las pruebas nuevas, en dos niveles que no hay que confundir:

- **Lógica** (`CodexModel`): descubierta frente a bloqueada; la página bloqueada contiene solo `locked`, `name = "???"` y poco más (sin
  ID, tipo, ubicación ni textos) y un recorrido por todas las páginas del catálogo comprueba que ningún dato del modelo contiene un
  nombre, texto o ID reales; servicio ausente, vacío, sin métodos, no listo, con respuestas que no son el `true` exacto, o que lanzan
  errores (se comunican **una vez**) → todo bloqueado y sin excepciones; el árbol bloqueado tiene las mismas filas, orden y profundidad
  que con todo descubierto; `parent`, `located_in` y `related_to` conservan su semántica; descendientes bajo un ancestro bloqueado.
- **Interfaz con el mock estricto, con una prueba de fugas sobre toda la presentación:** se leen los textos de **todos** los widgets
  (visibles, ocultos y reutilizados) tras seleccionar **cada** entrada bloqueada, tras Atrás/Adelante y tras contraer, y se buscan los
  nombres, descripciones, cuerpo, raza, rol, pista e IDs reales (y sus *slugs*). También: la página bloqueada, sus colores (`LOCKED`
  frente a oro, a `TEXT_MUTED` y a la selección), los breadcrumbs, la ubicación contextual, y — con el Discovery **real** — descubrir con
  la ventana visible (fila, página y breadcrumb se actualizan), con la ventana oculta (no se pinta nada y se aplica al abrir), un único
  registro del manejador tras abrir y cerrar muchas veces, que ver/seleccionar/expandir **no llama a `Discover`** ni escribe en
  `ChronicleCharDB` (se compara con el estado esperado), que las entidades canónicas no cambian, que un aviso con un ID inválido se
  ignora, y que Discovery caído, sin bus o con un `Register` que falla no impiden que el Codex arranque.

**Mutaciones** (criterio estricto: solo cuenta una aserción `[FAIL]` clara): **39 mutaciones, las 39 detectadas por aserciones, ninguna
con excepción posterior**; tras cada una se restauró el fichero y al final se verificó que todos eran idénticos a la versión final.
Cubren: devolver el nombre real o la página completa de lo bloqueado, incluir el ID o la descripción en la página bloqueada, ignorar
`IsReady`, aceptar cualquier valor no nulo, dar por descubierta una entidad si Discovery lanza un error (de `IsReady` o de
`IsDiscovered`) o no existe, repetir el error en cada repintado, mostrar el nombre real en los breadcrumbs o en la ubicación, no marcar
las filas bloqueadas, marcar el nombre bloqueado como reserva, descubrir al seleccionar, no actualizar la página cuando se descubre su
ubicación o rehacerla siempre; colores `LOCKED` ausentes en filas, títulos, breadcrumbs y ubicación, oro en la fila bloqueada
seleccionada, filas o tramos de breadcrumb ocultos que conservan texto, página bloqueada sin motivo, página que no se rehace al
descubrirla; no suscribirse, suscribirse en cada apertura o aunque Discovery no esté listo, pintar con la ventana oculta, no aplicar
lo pendiente al abrir, rehacer la página siempre o nunca, avisos sin ID válido que provocan repintados, no comprobar el color
`LOCKED`; el Codex requerido por Discovery; y el color `LOCKED` ausente o confundido con `TEXT_MUTED`.

**Historial (transparencia):** la primera pasada completa dio 36 de 39. Tres mutaciones no se detectaban (el color de un tramo de
breadcrumb bloqueado, un aviso sin ID válido que provoca un repintado, y no comprobar el token `LOCKED` de Theme) y dos se detectaban
con una excepción posterior en el script de pruebas. Se añadieron las pruebas `9b2`, `14c` y `22`, y guardas en el script para que los
fallos salgan como aserciones, y se **repitió la batería completa desde un estado limpio**: 39 de 39. No se interrumpió ninguna
ejecución en esta fase.

## Corrección posterior: suscripción a Discovery a prueba de fallos

**Defecto** (encontrado en la revisión de la Fase 10, commit `3def28d`): en `Codex.lua`, `Subscribe()` se llama al final de `Init()`,
con la ventana ya construida y `frame`, `views`, `model` y `ready = true` ya asignados. Obtenía la dependencia con `Dep("discovery")` y
preguntaba `discovery:IsReady()` **sin protección**. Si cualquiera de las dos lanzaba un error, la excepción salía de `Init()` con el
Codex ya construido y marcado como listo: un estado incoherente para quien lo inicializa y un incumplimiento del carácter opcional
de Discovery. (Reproducido: con el código anterior, las pruebas de regresión fallan por aserción y la excepción `IsReady roto` escapa
de `Init`.)

**Solución mínima:**
- La pregunta «¿hay un Discovery utilizable?» pasa al modelo como `CodexModel:IsDiscoveryReady()`, que ya protegía y deduplicaba los
  errores de Discovery. Obtener el servicio o llamar a `IsReady()` y fallar significa **«no disponible»**: devuelve `false`, comunica el
  error **una sola vez** por mensaje y nunca lo propaga. `IsDiscovered` usa la misma función, de modo que sin confirmación de que el
  servicio está listo **no se consulta ninguna entrada como descubierta** (todo queda bloqueado, como antes).
- `Subscribe()` empieza por `model:IsDiscoveryReady()` y obtiene el bus y Discovery (para el nombre del evento) con `pcall`. No puede
  lanzar errores. Si algo no está disponible, **no se registra nada** y cada apertura repinta por completo (comportamiento ya
  existente sin suscripción).
- **Valor de `Events:Register`** (contrato real: `true` si añadió el manejador, `false` solo si esa misma función ya estaba registrada;
  los argumentos inválidos lanzan error): solo un `true` cuenta como suscripción activa. Un `false` no se interpreta como suscripción;
  un error se comunica y tampoco la activa. En ambos casos el Codex se inicializa y se repinta al abrir.
- Sin cambios en `Discovery`, `Events`, `State`, `Registry`, `Localization`, `Core/Init.lua`, el `.toc`, el contrato de visibilidad
  de lo bloqueado ni el manejo de errores de la construcción de la ventana (un fallo real al construirla sigue haciendo fallar `Init`).

**Pruebas de regresión** (`tests/codex_discovery_tests.lua`, bloques `R1` a `R7`), que comprueban el estado real del Codex, su
visibilidad, los registros del bus y el contenido presentado, no solo que `Init` no lance:
- obtener Discovery lanza un error → Codex inicializado, oculto, con una ventana; el bus no recibe **ninguna** llamada; todo `???` sin
  datos reales en ningún widget; abrir, cerrar, expandir y seleccionar no lanzan; el error se comunica **una vez**;
- `IsReady` lanza un error → Codex inicializado, **ninguna consulta** de entradas como descubiertas, ningún manejador, todo bloqueado,
  error comunicado una vez; al recuperarse el servicio, la siguiente apertura repinta con el estado consultable; un aviso del bus no
  hace nada porque nadie lo recibe;
- Discovery inestable (falla en llamadas alternas, las dos paridades), obtener el bus que falla, evento sin nombre o con nombre no
  válido, `Register` que devuelve `false` y `Register` que lanza error;
- comportamiento normal sin cambios: una única suscripción, sin duplicados tras abrir y cerrar y repetir `Init`; repintado con la
  ventana visible; sin trabajo con la ventana oculta; sin errores comunicados;
- a nivel del addon completo, con `Discovery:IsReady` roto en el arranque: el Codex se inicializa (no falla ni se omite), no hay
  registros, y Registry, Localization, Resolver, Theme y Popup arrancan.

**Resultados reales:** `npm test` desde `tests`: **1270 superadas, 0 fallidas, código de salida 0** (1241 + 29 nuevas). Mutaciones:
**12 nuevas de esta corrección, las 12 detectadas por aserciones claras**, y **se repitió la batería de 39 de la Fase 10, también 39
de 39**, ambas sin excepciones posteriores, con los ficheros restaurados y verificados idénticos al terminar. Historial: la primera pasada
de las 12 dio 10 de 12 (obtener Discovery dentro de `Subscribe` solo falla con un servicio inestable, y un evento sin nombre); se
añadieron las pruebas `R6`, `R7` y `R7c`, se protegió el bloque de `IsReady` roto para que un fallo salga como aserción, y se repitió. En
la repetición de las 39 abortaron dos veces las anclas de dos mutaciones (D5, D10 y C7) por el refactor: se actualizaron antes de
escribir nada (sin residuos) y se repitió entera desde un estado limpio.

## Cambios en pruebas anteriores

Ninguna se eliminó ni se debilitó. Como el Codex ahora solo muestra lo que Discovery confirma, las pruebas de la Fase 9, que describen la
**vista completa** del catálogo, usan un Discovery de prueba que lo da todo por descubierto (en la parte de lógica y en los montajes) o
sustituyen `IsDiscovered` por `true` al arrancar (en la parte de interfaz del addon real, para no escribir en `ChronicleCharDB`). En la
Fase 8, `12d` (la lista exacta de dependencias del Codex incluye ahora Discovery y Events, inyectados) y `12e` (el Codex usa el bus de
eventos de Chronicle, no los del cliente; el resto de lo prohibido sigue prohibido). Se aclaró el título de `A6` de la Fase 9.

## Limitaciones no verificadas en WoW Classic Era real

Todo lo anterior se probó con un mock estricto que valida la **lógica**; **no se ha ejecutado en el juego**. Además de las de la Fase 9:

- Que de verdad no se filtre nada: la prueba de fugas lee el texto de todos los widgets del mock (visibles, ocultos y reutilizados), pero
  no puede ver lo que haría el cliente real (p. ej. herramientas de accesibilidad o texto residual del propio motor).
- El aspecto de lo bloqueado (`LOCKED` frente a `TEXT_MUTED`, oro y selección) sobre el fondo real.
- El recorrido real de un descubrimiento desde el juego (eventos de zona o NPC) hasta el Codex: Discovery se invoca aquí a mano. Nada
  detecta aún zonas o NPC hacia el Codex en este flujo de interfaz.
- Hoy el Codex solo se abre con `Codex:Show()` desde código (sin `/chronicle` ni minimapa, por alcance), de modo que un jugador no puede
  verlo todavía.
- El orden y la estructura de lo bloqueado revelan lo descrito en el punto 5 de la política.

## Fuera de alcance (no implementado)

Modelos 3D de NPC, enlaces automáticos, contenido de lore nuevo, campo `body` en Localization, datos geográficos o NPC nuevos, minimapa,
opciones, comandos slash, Trivia, FreshCharacterCheck, persistencia del historial, migraciones de SavedVariables y refactorizaciones no
necesarias.
