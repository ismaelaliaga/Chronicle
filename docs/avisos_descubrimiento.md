# Avisos de descubrimiento (rama `correccion-avisos-descubrimiento`)

Base: `1bf73990731439f84759ef605c253ce857473876` (candidata + alias Thunderbrew + corrección del árbol del Codex + traza temporal del árbol). **No probado en WoW Classic Era.**

## Recorrido de extremo a extremo (código actual)
1. **Evento del cliente** (`PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`) → frame de `ZoneDiscovery`.
2. `ZoneDiscovery:Check()` lee los nombres (`MapPosition`), los resuelve (`Resolver`) y llama a `Discovery:Discover(id)`.
3. `Discovery:Discover(id)`: `true, "new"` la primera vez (guarda y **emite** `Chronicle.Discovery.Discovered(id)`); `true, "already"` si ya estaba (**no emite**).
4. Suscriptores del evento **antes de esta corrección: solo el Codex** (para repintarse). **Nadie pedía un aviso al Popup.**
5. Selección del contenido, llamada al `Popup` y visualización: **no existían**.

`/chronicle test` llama a `Popup:Show` directamente, por eso funcionaba: demuestra el Popup, no el enlace con Discovery.

## Causa raíz (demostrada con el addon real y el mock; la prueba N1 fallaba antes)
Falta de conexión: no había ningún módulo que escuchara `Chronicle.Discovery.Discovered` para pedir un aviso al Popup.

## Corrección
`UI/DiscoveryNotice.lua` (módulo opcional, inicializado tras Discovery): se suscribe una vez al evento y, por cada descubrimiento **nuevo**, hace `Popup:Enqueue({ title = nombre, body = descripción })` con los textos localizados de la entidad.
- Solo avisa si `Discovery:IsDiscovered(id)` lo confirma; sin nombre ni descripción no avisa (nunca muestra el ID).
- Un error o rechazo del Popup no afecta a Discovery y **no es silencioso**: se cuenta en `GetStats().failed[motivo]` y se comunica una vez por motivo.
- Sin temporizadores, sin frames, sin SavedVariables, sin opciones nuevas.
- Descubrir zona y subzona a la vez deja dos avisos: el primero visible y el segundo en la cola del Popup.

## Personajes (NPC): qué existe realmente
- `ZoneDiscovery` solo trata zona, ciudad y subzona: **nunca descubre NPC**.
- `Proximity` es un motor genérico implementado y probado, pero **no tiene ningún objetivo** (no hay coordenadas ni `mapID` verificados; el Schema no tiene dónde guardarlos) y **nadie llama a `Evaluate()`**: hoy no puede descubrir ningún NPC.
- Para descubrir un NPC harían falta: (1) objetivos `{ id, mapID, x, y, radius, verified = true }` medidos en el cliente real, (2) un proveedor de objetivos, (3) un disparador que llame a `Proximity:Evaluate()`. No se ha inventado nada de esto.
- Cuando un NPC se descubra por cualquier vía, saldrá su aviso con este mismo módulo (usa el mismo evento).

## Probar en el cliente real
1. Instala la rama, `/console scriptErrors 1`.
2. Con un personaje o con la lista de descubiertos sin una subzona nueva, entra en esa subzona: debe salir un aviso con su nombre y descripción. Si descubres varias a la vez, los avisos salen uno tras otro al cerrar cada uno.
3. Vuelve a entrar en lugares ya descubiertos: **no** debe salir ningún aviso.
4. Si no sale: `/chronicle where` (¿reconoce el nombre?) y dime si aparece algún error en rojo con «DiscoveryNotice».
