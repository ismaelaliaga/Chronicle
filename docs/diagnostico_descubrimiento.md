# Diagnóstico del descubrimiento automático (rama `diagnostico-descubrimiento`)

Base: candidata `c37260e41e5941a236c55551cb68d23324655adb`. Esta rama **solo añade una herramienta de observación** (`UI/Diagnostics.lua`, el comando
`/chronicle debug discovery`). **No corrige nada todavía**: no hay una causa demostrada. El diagnóstico en WoW real **no se ha podido hacer desde el entorno de
desarrollo** (no hay cliente): hay que ejecutarlo en el juego y mirar la salida.

## Qué se ha podido establecer sin el cliente (evidencia estática y con mock)

- **[verificado con el mock y el catálogo real]** Con un cliente simulado que devuelve `Dun Morogh` / `Kharanos`, el recorrido completo funciona: el Resolver da
  `zone:dun_morogh` y `subzone:kharanos`, `Discover` devuelve `new`, se emite `Chronicle.Discovery.Discovered`, `Discovery:IsDiscovered` pasa a `true` y un modelo de
  Codex nuevo muestra los nombres. Por tanto el fallo **no está en la lógica pura**: algo es distinto en el cliente real.
- **[inferencia, sin confirmar]** Tu informe dice que `/chronicle where` mostró los nombres reales. `where` imprime `???` cuando el nombre resuelve a una entidad **bloqueada**,
  y el nombre tal cual cuando es de una entidad **descubierta** o cuando el Resolver **no lo reconoce**. Como el Codex sigue mostrando `???`, esto encaja con dos hipótesis:
  - **H1**: el Resolver no reconoce el nombre que entrega el cliente (no se intenta ningún `Discover`).
  - **H2**: sí se descubre, pero el Codex no lo refleja.
  Hay además otras posibles: H3 el evento no llega al frame de `ZoneDiscovery`; H4 `Discover` se rechaza (`read_only`, `not_ready`, `persist_failed`). La herramienta distingue las cuatro.

## Cómo repetir la prueba en el cliente

1. Cierra WoW. Instala `Chronicle-diagnostic-1.zip` (copia su carpeta `Chronicle` a `_classic_era_/Interface/AddOns/`, sustituyendo la candidata). Activa «Mostrar errores de Lua» (`/console scriptErrors 1`).
2. Entra con el personaje **en Dun Morogh**. Las trazas están **activas desde el arranque** (máximo 40 líneas): copia lo que salga en el chat al entrar al mundo.
3. Escribe `/chronicle debug discovery` y copia **todo** el resultado (la instantánea).
4. Escribe `/chronicle debug discovery check` y copia el resultado (ejecuta la misma comprobación que el evento).
5. Muévete a otra subzona y luego a otra zona (o cruza una puerta). Copia las líneas `[evento]`, `[check]`, `[discover]` y `[descubierto]` que aparezcan, y repite `/chronicle where` en cada sitio.
6. Abre el Codex (botón del minimapa) y di qué filas están desbloqueadas. Repite el paso 3.
7. `/chronicle debug discovery off` desactiva las trazas. No hace falta tocar nada más.

## Cómo leer la salida

| Lo que ves | Significa |
|---|---|
| Nunca aparece `[evento] ...` al entrar | el cliente no entrega los eventos de zona a ningún frame del addon (o las trazas empezaron tarde) |
| Aparece `[evento]` pero no `[check]` | el frame de `ZoneDiscovery` no recibe el evento o su manejador falla: mira `Init.failed` / `Init.skipped` y `ZoneDiscovery=` en `IsReady` |
| `[check] ... estado=not_ready` | `ZoneDiscovery` o `Discovery` no están listos |
| `zona{estado=unavailable ...}` | `MapPosition` no entrega el nombre en ese momento |
| `estado=unrecognized` y `Resolver:Resolve(...) -> ... not_found` | **H1**: el nombre del cliente no coincide con ningún nombre/alias. Compara el texto entre comillas y sus bytes con el catálogo (espacios, mayúsculas, otro idioma). **No se inventa ningún alias**: se añadiría solo con el valor real |
| `estado=ambiguous` | varias entidades con ese nombre; no se descubre ninguna |
| `[discover] Discover(id) -> false, read_only` / `not_ready` / `persist_failed` | **H4**: el rechazo está en State/Discovery |
| `[discover] ... -> true, new` y `[descubierto] ... IsDiscovered=true` pero el Codex sigue en `???` | **H2**: mira la línea «Modelo de Codex nuevo»: si ya da el nombre real, el fallo está en la ventana del Codex (suscripción o repintado) |
| `soloLectura=true` o `schemaVersion=` raro | las SavedVariables heredadas dejan a State en solo lectura |

## Qué toca esta rama

Nuevos: `Chronicle/UI/Diagnostics.lua`, `tests/diagnostics_tests.lua`, este documento. Modificados: `Chronicle.toc` (carga el módulo), `Core/Init.lua` (una entrada
opcional `Diagnostics`), `tests/harness.js`, y `tests/codex_discovery_tests.lua` (tres pruebas que **cuentan los registros del evento de Discovery** anulan el `Init` del
depurador para seguir contando solo los del Codex; sus aserciones no cambian). Es **temporal**: no debe fusionarse en `main` tal cual.
