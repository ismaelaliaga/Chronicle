# Fase 15.1 — Revisión y corrección de la arquitectura de datos y del pipeline

**Rama:** `fase15-data-pipeline-architecture` (local, **no publicada**). Parte de `docs/fase15_data_pipeline_architecture.md` (commit `082d209`), que **no se reescribe**: este documento lo revisa e indica qué partes sustituye.
**Alcance:** exclusivamente documental. No se ha tocado `Chronicle/`, `tests/`, `main` ni ningún ZIP. No hay código funcional, importadores, generador ni soporte Forever.
**Estado de la arquitectura:** *pendiente de aprobación del supervisor.* Los estados de D1–D16 de este documento recogen las conclusiones de la revisión externa comunicadas por el supervisor; no equivalen a una aprobación de la arquitectura completa.

## 0. Leyenda

| Etiqueta | Significado |
|---|---|
| **[HECHO]** | Comprobado en el repositorio real. |
| **[INVESTIGADO]** | Leído en una fuente externa (ver el Anexo A de la Fase 15 para fuentes y fiabilidad). |
| **[PROPUESTA]** | Diseño recomendado; no es un hecho ni está implementado. |
| **[INFERENCIA]** | Conclusión sin verificación directa. |
| **[PENDIENTE EN CLIENTE]** | Solo se puede confirmar con el cliente real (Classic Era o Forever). |
| **[DECISIÓN DEL PROPIETARIO]** | Corresponde al dueño del proyecto; no se decide aquí. |

---

## 1. Estado de D1–D16 (resumen)

| # | Tema | Estado | Nota breve |
|---|---|---|---|
| D1 | Generador (Node.js en `pipeline/`, fuera del ZIP) | APPROVED | Sin cambios respecto a la Fase 15. |
| D2 | Formato editorial (YAML/JSON con esquema) | APPROVED | Sub-decisión residual: YAML (parser como dependencia **de desarrollo**, solo en el pipeline) o JSON (sin dependencias, sin comentarios). |
| D3 | Versionar los packs generados + `data:check` | APPROVED | Sin cambios. |
| D4 | Empaquetado: un ZIP por versión | APPROVED_WITH_VALIDATION | Qué `.toc` carga Forever y su `Interface` deben validarse en cliente. |
| D5 | Detección de cliente | **REVISED** | Pasa a una abstracción `ClientAdapter` con `ClientFlavor` (§5.2). |
| D6 | Semántica de descubrimiento de NPC | **REVISED** | Rehecha: identificación → reglas de descubrimiento → interacción válida → `Discovery` (§6). |
| D7 | Contexto geográfico (zona ancestro por defecto) | APPROVED | Con requisito estricto configurable por entidad (§6.4). |
| D8 | Licencias | **PENDING_OWNER_DECISION** | No se decide la licencia de Chronicle (§7.1). |
| D9 | Flujo editorial | **REVISED** | Revisor opcional al principio (§7.2). |
| D10 | Pistas | APPROVED_WITH_ADJUSTMENT | Ninguna pista obligatoria por defecto salvo `requires_hint` (§7.3). |
| D11 | `Interface` | **REVISED** | Se documenta que debe verificarse y revisarse por parche (§7.4). |
| D12 | Herramienta de captura | APPROVED | Sin cambios (§7.8). |
| D13 | Idiomas | **REVISED** | Separación estricta texto editorial / nombres observados (§7.5). |
| D14 | Valores secretos | APPROVED | `issecretvalue` antes de operar; `pcall` como última barrera (§5.4). |
| D15 | IDs canónicos | APPROVED_WITH_ADJUSTMENT | Regla `retired` explícita (§7.6). |
| D16 | Score | APPROVED | Configurable, versionado, reproducible y explicable (§7.7). |

La tabla final del documento (§11) repite estos estados en el formato solicitado.

---

## 2. Cambios realizados respecto a la Fase 15

| Elemento | Fase 15 | Fase 15.1 |
|---|---|---|
| Principio de arquitectura | Mundo vs Chronicle | Se añade **IDENTIFICATION ≠ DISCOVERY ≠ EDITORIAL INCLUSION** como principio fundamental (§3). |
| D5 | Señales (`GetBuildInfo`, `WOW_PROJECT_ID`, cabecera del pack) | Abstracción `ClientAdapter` + `ClientFlavor { ERA, FOREVER, UNKNOWN }`; nunca depender solo de `WOW_PROJECT_ID` o `Interface` (§5). |
| D6 | «Zona descubierta + `GOSSIP_SHOW`» | **Sustituida:** requisitos de contexto + **tipo de interacción configurable por entidad** (`gossip`, `quest`, `merchant`, `trainer`, `flight_master`, `profession`, `other`, con `any`/`all`), traducido a eventos técnicos por el adaptador (§6). |
| D7 | Zona ancestro por defecto | Igual, más requisito estricto por entidad (`strict: true`) (§6.4). |
| D8 | Recomendación de licencia y política de fuentes | **No se recomienda ni se decide licencia.** Se fija el principio de no incorporar datasets sin procedencia y licencia conocidas, y la separación CODE / DATA / EDITORIAL CONTENT (§7.1). |
| D9 | Revisor obligatorio por entidad | `author`, `reviewer` (opcional), `reviewed_at` (§7.2). |
| D10 | ≥1 pista necesaria por entidad | **No** se exige pista a toda entidad: propiedad `requires_hint`; por defecto sí para lore importante (§7.3). |
| D11 | Probar 11507 vs 11509 | Se documenta que Classic Era usa hoy un `Interface` más reciente que 11507, que debe verificarse en cliente y revisarse por parche (§7.4). |
| D13 | `enUS` como base de nombres oficiales | **Retirado como requisito:** los nombres del cliente son observaciones por idioma; `esES` es el idioma editorial; no se mete inglés en `esES` artificialmente (§7.5). |
| D14 | `issecretvalue` + «no identificable» | Se endurece: `issecretvalue` **antes** de comparar/operar/almacenar; `pcall` solo como última barrera; forma parte de `ClientAdapter` (§5.4). |
| D15 | IDs inmutables, `retired` en vez de borrar | Se explicita que un ID `retired` **sigue conocido por el Registry** para no dejar huérfanos los descubrimientos guardados (§7.6). |
| Datos | Mundo / Chronicle | **Cuatro niveles:** World Data, Candidate Data, Chronicle Editorial Data, Generated Data (§4). |
| Pipeline | Flujo de 9 pasos | Flujo completo hasta `Client Adapter → Chronicle Runtime`; ninguna fuente pasa a entidad sin la capa editorial (§4.2). |
| `ClientAdapter` | Mencionado en §5.3 de la Fase 15 | Sección propia con responsabilidades y límites de `Core` (§5). |

Todo lo no mencionado en esta tabla **se mantiene** como en la Fase 15.

---

## 3. Principio fundamental: IDENTIFICATION ≠ DISCOVERY ≠ EDITORIAL INCLUSION

Tres conceptos distintos que **nunca se infieren uno de otro**:

| Concepto | Pregunta que responde | Quién lo posee [PROPUESTA] | Dónde vive |
|---|---|---|---|
| **Identification** (identificación) | ¿Qué entidad **del mundo del juego** estoy observando o con la que interactúo? | `ClientAdapter` (por versión) | Datos de mundo (World Data) + lectura del cliente en runtime |
| **Discovery** (descubrimiento) | ¿Ha cumplido el jugador las **condiciones** para desbloquear esa entidad en Chronicle? | Servicio de reglas de descubrimiento + `Discovery` (persistencia) | Reglas en datos editoriales; progreso en `ChronicleCharDB` vía `State` |
| **Editorial inclusion** (inclusión editorial) | ¿Forma esa entidad **parte del contenido** de Chronicle? | Chronicle Editorial Data (decisión humana) | Datos editoriales |

### 3.1 Combinaciones posibles (todas válidas)
| Identificable | Incluida | Descubierta | Ejemplo | Consecuencia |
|---|---|---|---|---|
| Sí | **No** | — | Un guardia de Ventormenta, un niño, un vendedor genérico | Se puede identificar (y capturar como observación), pero **nunca** se descubre ni aparece en el Codex. |
| Sí | Sí | **No** | Grelin Whitebeard al llegar a Coldridge Valley | Está en el catálogo, bloqueada (`???`); verla, señalarla o apuntarla **no** la desbloquea. |
| Sí | Sí | Sí | Grelin tras cumplir contexto e interactuar | Desbloqueada. |
| No (en esta versión) | Sí | No | Entidad aún sin presencia verificada en Forever | Existe en el catálogo editorial; no puede descubrirse en esa versión hasta tener identificación. |
| Sí | **Retirada** | Sí (antiguo progreso) | Una entidad `retired` que un jugador ya tenía | Sigue conocida; el comportamiento de UI se decide después (§7.6). |

### 3.2 Reglas derivadas
1. **Identificar no descubre.** Reconocer un GUID, un nombre, un `npcID` o una unidad (objetivo, ratón, placa, proximidad) solo alimenta la identificación.
2. **Estar incluida no implica estar descubierta**, ni haber sido identificada alguna vez.
3. **Estar descubierta no implica que siga incluida:** una entidad retirada conserva su historial.
4. **Que algo sea identificable no lo hace candidato ni lo incluye.** El score y los candidatos solo sirven a la inclusión editorial.
5. **Ningún dato de una capa autoriza automáticamente una acción de otra.** Un `npcID` conocido no habilita el descubrimiento; una regla de descubrimiento no incluye una entidad en el catálogo.

### 3.3 Cómo está hoy el código [HECHO]
La Fase 14 **mezcla los tres conceptos en un solo servicio:**
- *Identificación:* `ParseGuid` + lectura de `UnitGUID`/`UnitName` en `Services/NpcDiscovery.lua`.
- *Inclusión (técnica):* `Data/NpcTargets.lua` es a la vez la «lista de NPC incluidos» y la «lista de NPC descubribles».
- *Descubrimiento:* `NpcDiscovery` llama a `Discovery:Discover(id)` **directamente** al identificar, desde `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `NAME_PLATE_UNIT_ADDED` y `GOSSIP_SHOW`.

Por tanto **`NpcDiscovery` de la Fase 14 NO representa la semántica definitiva de producto**: descubre mediante eventos de observación/identificación. La Fase 14 validó el **circuito técnico de identificación** (formato real del GUID, extracción del `npcID`, eventos que entregan identidad, encadenamiento con `Discovery`, avisos y Codex). Eso se conserva como conocimiento y como código reutilizable de identificación; **no se convierte en la regla de producto**. [Este documento no cambia el código.]

### 3.4 Cómo se refleja en toda la arquitectura [PROPUESTA]
- **Datos:** la identidad técnica (World Data) está separada de la decisión editorial (inclusión) y de las reglas de descubrimiento (que son datos editoriales).
- **Código:** `ClientAdapter` identifica; un servicio de reglas decide; `Discovery` registra.
- **Pipeline:** las fuentes alimentan World Data y Candidate Data; solo la capa editorial incluye.
- **Tests (futuros):** cada concepto se prueba por separado, y se prueba explícitamente que identificar **no** descubre.

---

## 4. Arquitectura de datos: cuatro niveles

### 4.1 Los cuatro niveles
| Nivel | Qué contiene | Quién lo escribe | ¿Se edita a mano? | ¿Va en el addon? |
|---|---|---|---|---|
| **1. WORLD DATA** | Lo observado/investigado sobre el mundo: NPC, misiones, zonas, mapas, relaciones, IDs técnicos, **nombres por idioma**, etc., **por versión del juego**, con procedencia y confianza | Importadores + reconciliación + capturas del cliente | No (se regenera; las correcciones son *overrides* explícitos) | No (solo la parte necesaria entra al pack generado) |
| **2. CANDIDATE DATA** | Resultado del análisis de World Data: posibles personajes relevantes, **score**, señales y su desglose, procedencia | Análisis automático (reproducible) | No | No |
| **3. CHRONICLE EDITORIAL DATA** | Decisión humana: entidades aceptadas, lore, pistas, relaciones narrativas, **reglas de descubrimiento**, estado editorial, bindings, rechazados | Personas (con revisión) | **Sí; es la única capa escrita a mano** | No (solo su resultado generado) |
| **4. GENERATED DATA** | El pack Lua por versión | El generador (determinista) | **Nunca** | **Sí** |

### 4.2 Flujo conceptual completo
```
 Sources
   ↓
 Import
   ↓
 Normalize
   ↓
 Reconcile
   ↓
 World Data ───────────────────────────────┐
   ↓                                       │
 Candidate Analysis  → Candidate Data      │
   ↓                                       │
 Editorial Review  (decisión humana)       │
   ↓                                       │
 Chronicle Data (editorial)                │
   ↓                                       ▼
 Generator  ◄──────────  World Data (la parte que el pack necesita: identidades, nombres por idioma, lugares)
   ↓
 Generated Data Pack   (uno por versión)
   ↓
 Client Adapter        (por versión: Era / Forever)
   ↓
 Chronicle Runtime     (Core, Discovery, Codex…)
```
**Regla fundamental:** una fuente externa **nunca** pasa a entidad de Chronicle de forma automática. `source → Chronicle entity` **no existe**; siempre `source → World Data → candidato → revisión editorial → entidad`.

### 4.3 Qué está absolutamente prohibido
1. Que el addon en runtime sea fuente editorial: el addon **no escribe lore, pistas, inclusión ni reglas**; en `ChronicleCharDB` solo guarda **progreso del jugador** (qué descubrió), vía `State`.
2. Que un importador o el generador cree o borre entidades editoriales o lore.
3. Que un score o una regla automática decida inclusión.
4. Editar a mano un fichero generado.
5. Que un conflicto de fuentes se resuelva en silencio.

### 4.4 Qué cambia respecto a la Fase 15
La Fase 15 hablaba de dos mundos (World Data / Chronicle Data) y trataba candidatos como una fase intermedia. Aquí **Candidate Data es un nivel propio** (con su procedencia y su explicación) y **Generated Data es un nivel propio** (con la garantía de reproducibilidad). El resto del modelo (presencias por versión, bindings, procedencia, conflictos y overrides) se mantiene como en la Fase 15, §6–§7.

---

## 5. ClientAdapter

### 5.1 Principio: lo que `Core` no debe saber
`Core` (y, en general, todo lo que no sea el adaptador) **no debe conocer**:
- el análisis de GUID ni el formato de las unidades;
- el `npcID`;
- los eventos concretos del cliente;
- los valores secretos;
- las diferencias de API entre clientes;
- los nombres concretos de zonas y subzonas.

Todo eso pertenece al `ClientAdapter`. [PROPUESTA]

**Estado actual [HECHO]:** esa responsabilidad está repartida y acoplada al cliente: `NpcDiscovery` lee `UnitGUID`/`UnitName` y parsea el GUID; `MapPosition` y `ZoneDiscovery` leen `GetRealZoneText`/`GetSubZoneText`/`C_Map`; `FreshCharacterCheck` y `Trivia` llaman a APIs del cliente. No existe ninguna abstracción de cliente.

### 5.2 `ClientFlavor` y adaptadores
```
ClientFlavor:  ERA | FOREVER | UNKNOWN

ClientAdapter
├── identifyUnit(unitToken)        → resultado de identificación (ver 5.4)
├── getUnitName(unitToken)         → nombre observado o "no disponible ahora"
├── getUnitGUID(unitToken)         → GUID crudo o "no disponible ahora"   (nunca se interpreta fuera del adaptador)
├── getCurrentPlace()              → lugar observado { zona, subzona, locale, ... } o "no disponible"
├── getInteractionContext()        → contexto normalizado de interacción { tipo, unidad identificada } o nada
├── isSecretValue(value)           → booleano; se usa ANTES de operar con un valor del cliente
└── capabilities                   → qué sabe hacer este cliente (eventos de interacción disponibles, valores secretos activos, …)

EraAdapter       (cliente Classic Era)
ForeverAdapter   (cliente Forever)
```
`ClientFlavor = UNKNOWN` es un valor legítimo: significa «no sé en qué cliente estoy».

La **API exacta no se define ni se implementa todavía.** Lo anterior es un esquema de responsabilidades.

### 5.3 D5 revisada: detección del cliente
**Principio:** la arquitectura **no depende exclusivamente** de `WOW_PROJECT_ID` ni de `Interface`.
- Forever puede compartir valores de identificación con Mainline/retail (según [INVESTIGADO]: `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`; tipo de juego interno `camelot`) y utilizar características propias. Ninguna señal aislada distingue el cliente.
- **No se asume que los valores observados en la beta sean inmutables** (el sufijo de TOC es provisional según la wiki; el nombre interno podría renombrarse antes del lanzamiento).

**Diseño [PROPUESTA]:**
1. Cada adaptador declara **cómo reconoce su cliente** a partir de varias señales independientes (versión/build/`Interface` de `GetBuildInfo()`, `WOW_PROJECT_ID`, características/capabilities presentes). La combinación y su precedencia son un detalle **a validar con los clientes reales**.
2. El resultado es un `ClientFlavor` (`ERA`, `FOREVER` o `UNKNOWN`) y un motivo de diagnóstico.
3. **Cabecera del pack:** el pack generado declara el `flavor` para el que se generó. Al arrancar se contrasta con el `ClientFlavor` detectado.
4. **Desajuste o `UNKNOWN`:** el módulo afectado queda en `Init.failed` y el addon pasa a **modo seguro**: no se activan descubrimiento ni datos del pack, no se escribe progreso, y se informa claramente. El resto del addon (que no depende de datos de mundo de otra versión) sigue funcionando. **Qué incluye exactamente el modo seguro** es un detalle de diseño pendiente de la fase de implementación. [PROPUESTA]
5. La arquitectura queda **preparada para**: Era, Forever y posibles cambios de `Interface`/build, sin reescribir el sistema (un cambio de señales afecta al adaptador, no a `Core`).

**[PENDIENTE EN CLIENTE]:** los valores reales de `GetBuildInfo()`, `WOW_PROJECT_ID` y características en cada cliente; qué combinación es fiable.

### 5.4 D14: valores secretos (ahora responsabilidad del adaptador)
Según la wiki de API [INVESTIGADO], los valores secretos no se pueden comparar, medir, usar como clave ni **analizar como cadena**. Para Forever las restricciones de Midnight se aplicarían [INVESTIGADO, secundaria]; en Classic Era [DESCONOCIDO] si están activas (`issecretvalue` existe en 1.15.9).

**Regla [PROPUESTA]:** un valor secreto **no es un error del addon.** Se trata como **`NO_IDENTIFICABLE_AHORA`** y el sistema continúa sin romper nada.
- El adaptador comprueba `isSecretValue(...)` (basado en `issecretvalue`) **antes** de:
  - comparar;
  - operar con cadenas;
  - parsear;
  - almacenar;
  - usar el valor para identificación.
- **`pcall` es la última barrera**, no el mecanismo principal de detección.
- Un resultado `NO_IDENTIFICABLE_AHORA` **no** genera descubrimiento, error ni mensaje repetido; no se confunde con «no es criatura» ni con «no incluida».
- **Estado actual [HECHO]:** `NpcDiscovery` no comprueba `issecretvalue`; con un valor secreto, un `pcall` externo atrapa el error y se informa. Se corregirá cuando exista `ClientAdapter`.
- **[PENDIENTE EN CLIENTE]:** si `UnitGUID`/`UnitName` son secretos en alguna situación en Classic Era y en Forever; qué devuelve `UnitGUID("npc")` en una conversación.

### 5.5 Qué `ClientAdapter` no es
No decide inclusión, no descubre, no contiene lore ni reglas editoriales, y no persiste nada. Solo traduce «lo que dice este cliente» a un formato común y dice con claridad cuándo **no puede** decir algo.

---

## 6. D6 revisada — modelo conceptual de descubrimiento y de interacción de NPC

### 6.1 Definición de producto (decisión del supervisor) [HECHO como requisito]
Un NPC **solo** se descubre cuando se cumplen **ambas** condiciones:
1. el jugador ha descubierto el **contexto geográfico requerido**; y
2. el jugador realiza una **interacción válida** con ese NPC.

**No descubren** (solo sirven para *identificación*): ver al NPC, *mouseover*, objetivo, placa de nombre, *proximity*, detectar un GUID, detectar el nombre.

### 6.2 Cadena conceptual
```
 NPC identification        (ClientAdapter.identifyUnit)         ← ¿quién es?
        ↓
 DiscoveryRules            (servicio de reglas)                 ← ¿se cumplen los requisitos de contexto y la interacción es válida?
        ↓
 valid interaction         (ClientAdapter.getInteractionContext) ← ¿qué tipo de interacción se está produciendo?
        ↓
 Discovery:Discover(id)    (sin cambios)                        ← registrar y emitir el evento
```
Identificación e interacción llegan desde el adaptador; la decisión la toma el servicio de reglas; `Discovery` solo registra. `DiscoveryNotice`, Codex y el bus de eventos no cambian.

### 6.3 Representación en los datos (por entidad) [PROPUESTA]
```yaml
# Entidad editorial: reglas de descubrimiento
id: npc:grelin_whitebeard
discovery:
  requirements:
    place_discovered:
      id: zone:dun_morogh          # por defecto, el ancestro de zona (D7)
  interaction:
    type: gossip
```
**Tipos de interacción (conceptuales; semánticos, no técnicos):** `gossip`, `quest`, `merchant`, `trainer`, `flight_master`, `profession`, `other`.

**Una entidad puede aceptar uno o varios tipos:**
```yaml
interaction:
  type: quest
```
```yaml
interaction:
  any:                # basta con cualquiera
    - gossip
    - quest
```
`all:` (todas) queda previsto para casos excepcionales. **El requisito de interacción es configurable por entidad.**

**Requisitos adicionales previstos (opcionales):** `entity_discovered` (dependencia narrativa de otra entidad) y `hint_seen` (solo si se decide persistir pistas; ver D6/D10). La lista es abierta.

**Qué eventos técnicos corresponden a cada tipo:** **no se asume.** Cada `ClientAdapter` declara en sus `capabilities` qué tipos de interacción sabe detectar en su cliente y cómo. Un tipo que un cliente no puede detectar de forma fiable **no está disponible** para las entidades de esa versión (la validación de datos lo marca). Esto **debe resolverse mediante `ClientAdapter` y validación real.** **[PENDIENTE EN CLIENTE]:** en Era y en Forever, qué eventos y qué unidad corresponden a `gossip`, `quest`, `merchant`, `trainer`, `flight_master`, `profession`; si los NPC que solo dan o completan misiones activan el mismo evento que los de conversación; si `UnitGUID("npc")` responde durante la interacción.

### 6.4 D7: contexto geográfico
**Por defecto**, para un NPC: `place_discovered` = **zona ancestro** de su lugar narrativo (cadena `parent`: subzona → zona o ciudad). **No** se exige subzona salvo que el contenido editorial lo requiera **y** el reconocimiento de esa subzona esté verificado en cliente.

Requisito más estricto por entidad:
```yaml
requires:
  place:
    id: subzone:coldridge_valley
    strict: true
```
**Robustez:** el comportamiento por defecto debe tolerar diferencias de nombres e idioma. Hay precedentes reales en el proyecto: `Valle de Crestanevada` y `Destilería Thunderbrew` no se reconocían hasta añadir su alias observado. Por eso el listón por defecto es la **zona**, no la subzona. El reconocimiento de lugares lo hace el adaptador (`getCurrentPlace()`) con los **nombres observados por idioma** (§7.5).

### 6.5 Resultado de una interacción (semántica) [PROPUESTA]
| Situación | Resultado | Efecto |
|---|---|---|
| NPC identificado, incluido, requisitos cumplidos, interacción de un tipo aceptado | `discovered` | `Discovery:Discover(id)`; aviso y Codex como siempre |
| Requisitos de contexto **no** cumplidos | `requirements_not_met` | Nada; sin pistas ni spoilers en el cliente |
| Interacción de un tipo **no** aceptado por esa entidad | `interaction_not_accepted` | Nada |
| NPC identificado pero **no incluido** en Chronicle | `not_included` | Nada |
| Identidad no disponible o secreta | `NO_IDENTIFICABLE_AHORA` | Nada; sin error |
| Ya descubierto | `already` | Nada (idempotente, como hoy) |
Los códigos son conceptuales; no definen la API.

### 6.6 Persistencia
`Discovery` y su persistencia **no cambian.** No se persiste nada nuevo en esta arquitectura inicial: las pistas pueden mostrarse según lo ya descubierto. Si más adelante se decide persistir progreso de pistas (`hint_seen`), pasará por `State` con migración de esquema (`schemaVersion` 1 → 2).

### 6.7 Validación posterior
Cuando se implemente, habrá que **revalidar en cliente real** a Grelin Whitebeard y Sten Stoutarm con la regla definitiva, y comprobar explícitamente que ver, apuntar, ratón y placa **no** descubren. **Esta fase no cambia el código de la Fase 14.**

---

## 7. Decisiones revisadas o ajustadas

### 7.1 D8 — Licencias: PENDING_OWNER_DECISION [DECISIÓN DEL PROPIETARIO]
- **La licencia final de Chronicle no se decide aquí.** La Fase 15 la planteaba como decisión previa; esa recomendación **no se mantiene como decisión tomada.** [HECHO: el repositorio no tiene fichero de licencia.]
- **Principio establecido:** **no se incorporará automáticamente a Chronicle ningún dataset externo** si no se conocen suficientemente: (1) su procedencia; (2) su licencia; (3) sus condiciones de redistribución; (4) si el dato es derivado de otro; (5) la compatibilidad con la distribución de Chronicle.
- **Separación conceptual de tres cosas:**
  | | Qué es | Ejemplo |
  |---|---|---|
  | **CODE** | El código del addon y del pipeline | `Chronicle/`, `pipeline/` |
  | **DATA** | Datos técnicos (de mundo y generados) | `npcID`, nombres observados, packs generados |
  | **EDITORIAL CONTENT** | Lo que Chronicle escribe: lore, pistas, relaciones narrativas | Textos en `esES` |
  Cada una puede tener un régimen distinto; esa elección corresponde al propietario.
- **Uso de fuentes externas sin redistribución:** una fuente puede servir para **investigación**, **contraste**, **validación local** y **generación de candidatos**, **sin que eso implique poder redistribuir sus datos.**
- **No se copian** textos de misiones, diálogos ni contenido protegido solo porque una fuente los proporcione. El lore es escrito por Chronicle.
- **No se implementan importadores.**
- La tabla de licencias de la Fase 15 (§11.3) se conserva como **análisis**, no como decisión. No es asesoramiento legal.

### 7.2 D9 — Flujo editorial: REVISED
- **Estados** (sin cambios): `candidate → shortlisted → accepted → drafting → review → published`, más `rejected`, `deferred`, `retired`.
- **Cambio:** **no** es obligatorio, desde el principio, un segundo revisor humano por entidad. El modelo prevé:
  ```yaml
  author: …
  reviewer: …         # opcional en la fase inicial
  reviewed_at: …      # opcional
  ```
- La revisión por *pull request* de GitHub puede proporcionar después el proceso de revisión.
- **Principio:** **EL SCORE NO DECIDE QUÉ ENTRA EN CHRONICLE.** Solo prioriza candidatos para la revisión editorial.

### 7.3 D10 — Pistas: APPROVED_WITH_ADJUSTMENT
- **Se mantienen las pistas estructuradas** (no solo texto libre). Campos conceptuales: `id`, `target`/`entity`, `kind`, `necessity`, `tier`, `reveals_when`, `depends_on`, `related_to`, `text`.
- **Lint** (futuro) que impida: coordenadas; instrucciones tipo GPS; revelar directamente el nombre de una entidad bloqueada; ciclos de dependencia; dependencias inexistentes.
- **Ajuste:** **no** se exige que todas las entidades tengan pista. Propiedad `requires_hint: true | false` por entidad. **Por defecto, para entidades de lore importantes, `requires_hint = true`**; para el resto, `false`; siempre sobrescribible por decisión editorial.
- **Experiencia buscada:** leer → pensar → relacionar → investigar → encontrar → interactuar → descubrir. **No:** leer → recibir coordenadas → ir directamente.
- **No se implementa la UI de pistas** en esta arquitectura.

### 7.4 D11 — `Interface`: REVISED
- **Dato [INVESTIGADO]:** Classic Era figura hoy con un `Interface` **más reciente que el 11507** original de Chronicle (11509 en las fuentes consultadas: build 1.15.9). **[HECHO]** el `.toc` actual declara 11507.
- **Deberá verificarse en el cliente**; **no se asume** que una versión de `Interface` sea inmutable. La política debe **revisarse por parche**.
- **Forever tendrá su propio `.toc`** (su `Interface` y sufijo están sin confirmar); los packs se generan **por cliente/flavor**.
- **No se hace ninguna migración funcional del addon** en esta fase.

### 7.5 D13 — Idiomas: REVISED
Separación estricta:
| | Qué es | Dónde vive | Ejemplo |
|---|---|---|---|
| **EDITORIAL TEXT** | Lo que Chronicle escribe (título, resumen, lore, pistas) | Datos editoriales, por idioma | Texto en `esES` |
| **CLIENT OBSERVED NAMES** | Lo que el cliente **devuelve** | World Data, como observación | `locale → nombre observado → procedencia` |
- **Idioma editorial inicial: `esES`.**
- **No se meten artificialmente nombres ingleses dentro de `esES`** solo porque sean nombres propios. **[HECHO]** hoy los textos migrados (`Localization/esES/*`) contienen nombres propios en inglés; **no se cambian en esta fase.** Migrarlos a «nombres observados» es una tarea futura.
- **Preparado para** `enUS`, `esES` y futuros idiomas, **pero soportar todos los idiomas no es un requisito para continuar.** *(La Fase 15 recomendaba `enUS` como base de nombres oficiales; esa recomendación se retira.)*
- **El `Resolver` debe poder usar los nombres observados por idioma** (hoy se alimenta de nombres de `Localization` y de alias a mano con marcas `[C]/[J]/[W]/[O]`, precursores de la procedencia).
- **[PENDIENTE EN CLIENTE]:** los nombres exactos de zonas, subzonas y NPC por idioma en Era y en Forever.

### 7.6 D15 — IDs canónicos: APPROVED_WITH_ADJUSTMENT
**Regla (se mantiene):** IDs **estables e independientes del cliente.**
| Sí | No |
|---|---|
| `npc:grelin_whitebeard` | `npc:786` |
| | `era:npc:786` |
| | `forever:npc:786` |
El mismo personaje puede tener `npcID = 786` en Era y otro ID técnico en Forever, y seguir siendo `npc:grelin_whitebeard`. Los IDs **no cambian** al cambiar nombre, idioma, `npcID` ni versión del juego.

**Ajuste explícito — entidades retiradas:**
- Si una entidad deja de utilizarse, **no se borra su ID.** Se marca `status: retired`.
- **Un ID `retired` debe seguir siendo conocido por el Registry**, para que los descubrimientos antiguos de `ChronicleCharDB` no queden huérfanos.
- **Por qué importa [HECHO]:** `Discovery:IsDiscovered`, `GetIds`, `Count` y `Discover` solo aceptan IDs que el Registry conoce (`registry:Has(id)`). Si un ID desapareciera del Registry, los descubrimientos guardados dejarían de contarse y de verse.
- **Consecuencia para el diseño:** el pack generado debe seguir incluyendo las entidades `retired` (con los datos mínimos) en **todas** las versiones.
- **[HECHO]** el esquema actual no tiene un campo `status` (los campos comunes permitidos son `id`, `type`, `parent`, `located_in`, `related_to`, `nameKey`, `descriptionKey`); añadirlo es un cambio futuro de `Schema`, no de esta fase.
- **El comportamiento de la interfaz para entidades `retired` se decide posteriormente.**

### 7.7 D16 — Score: APPROVED
**SCORE ≠ DECISIÓN EDITORIAL.** El score sirve para **encontrar** candidatos, **priorizarlos** y **explicar** por qué parecen interesantes.
- **Configurable** (pesos externos al código), **versionado**, **reproducible** (mismas entradas y configuración → mismo resultado) y **explicable** (desglose por señales).
- Ejemplo conceptual de desglose (los pesos **no son definitivos**):
  ```
  quest_relevance     +30
  lore_relation       +25
  faction_relevance   +15
  unique_role         +20
  generic_vendor      −40
  ----------------------
  total               +50   (solo ordena la cola de revisión)
  ```
- **El piloto de Dun Morogh servirá para calibrar** los pesos (casos positivos conocidos y negativos genéricos).
- No se implementa todavía.

### 7.8 D12 — Herramienta de captura: APPROVED
Se mantiene. La herramienta de captura debe ser:
- **separada del runtime** (no va en el ZIP de Chronicle);
- **mínima** al principio;
- **exportable**;
- basada en **observaciones reales del cliente**;
- consciente del **locale**;
- consciente de la **versión/build**;
- útil **especialmente para Forever**.
Respeta los límites de §5.4 (sin capturar en combate/instancias cuando los valores sean secretos; sin nombres de jugadores; sin volcar textos del juego). No se implementa todavía.

### 7.9 Decisiones sin cambios
D1 (Node.js en `pipeline/`), D2 (formato editorial estructurado y validado), D3 (packs generados versionados con `data:check`), D4 (un ZIP por versión, con validación en cliente de Forever) y D7 se mantienen como en la Fase 15 (D7 con la adición de §6.4).

---

## 8. Clasificación de decisiones

### 8.1 Aprobadas (según la revisión comunicada; pendiente la aprobación global)
D1, D2, D3, D7, D12, D14, D16 · con ajuste: D10, D15 · con validación: D4.

### 8.2 Revisadas en esta fase
D5, D6, D9, D11, D13 (sustituyen o corrigen a las de la Fase 15).

### 8.3 Pendientes de decisión del propietario
D8 (licencia de Chronicle y régimen de CODE / DATA / EDITORIAL CONTENT).
Detalles abiertos menores: D2 (YAML vs JSON), flujo de revisión por PR (D9) y qué cubre el «modo seguro» (D5).

### 8.4 Requieren validación en cliente real
| Decisión | Qué hay que comprobar |
|---|---|
| D4 | Qué `.toc` carga Forever; aceptación de su `Interface`; sufijo definitivo |
| D5 | Valores reales de `GetBuildInfo()`/`WOW_PROJECT_ID`/características; qué combinación es fiable; efecto de cambios entre beta y lanzamiento |
| D6 | Qué eventos y unidad corresponden a cada tipo de interacción; si `UnitGUID("npc")` responde; comportamiento de NPC que solo dan/completan misiones, comercian, entrenan, etc. |
| D7 | Reconocimiento de zonas y subzonas por idioma en cada cliente |
| D11 | Cómo se comporta Chronicle con el `Interface` actual de Classic Era y con el de Forever |
| D12 | Por naturaleza: la herramienta se ejecuta en ambos clientes |
| D13 | Nombres observados por idioma en cada cliente |
| D14 | Si hay valores secretos en cada cliente y en qué contextos |

---

## 9. Riesgos todavía abiertos

| # | Riesgo | Etiqueta | Mitigación prevista |
|---|---|---|---|
| R1 | Los eventos de interacción pueden no existir, diferir o no cubrir ciertos NPC (quest-only, comerciantes…) en Era o Forever | [PENDIENTE EN CLIENTE] | Capacidades declaradas por el adaptador; tipos no detectables = no disponibles; validación real |
| R2 | Forever puede cambiar `Interface`, sufijo de TOC, tipo de juego o `WOW_PROJECT_ID` antes del lanzamiento | [INVESTIGADO: provisional] | Detección por varias señales + `UNKNOWN` + modo seguro; sin suponer inmutabilidad |
| R3 | Valores secretos pueden impedir la identificación en contextos restringidos | [INVESTIGADO + INFERENCIA] | `isSecretValue` primero; `NO_IDENTIFICABLE_AHORA`; descubrimiento solo por interacción |
| R4 | Nombres de zonas/subzonas por idioma y versión; el reconocimiento puede fallar (como ya ocurrió) | [HECHO: precedentes] | Requisito de zona por defecto; nombres observados con procedencia; captura |
| R5 | Licencia y redistribución de datos derivados sin resolver | [DECISIÓN DEL PROPIETARIO] | Principio de no incorporar datasets sin procedencia/licencia; revisión legal antes de publicar datos derivados |
| R6 | Cambiar el comportamiento de `NpcDiscovery` obliga a **revalidar** Grelin y Sten con la regla definitiva | [HECHO] | Revalidación manual al implementar; tests que prueben que identificar no descubre |
| R7 | `Schema` no tiene `status`: añadir `retired` y el desacoplamiento entidad/presencia es un cambio estructural | [HECHO] | Fase de separación sin cambio de comportamiento, con los tests existentes |
| R8 | Los datos de Forever (NPC, misiones, mapas) pueden no coincidir con Era; las bases externas son de 1.12 | [INVESTIGADO] | World Data por versión; la captura es la fuente principal en Forever |
| R9 | Las pistas pueden revelar demasiado o resultar vagas | [PROPUESTA] | Lint + revisión editorial + pruebas manuales de la experiencia |
| R10 | Información de Forever recogida de prensa/terceros puede cambiar o ser inexacta | [INVESTIGADO: secundaria] | Marcar siempre como no verificada hasta tener el cliente |
| R11 | Qué cubre el «modo seguro» no está definido | [PROPUESTA] | Definirlo al diseñar `Init` y `ClientAdapter` |

---

## 10. Verificación de esta fase
- **Ficheros:** esta fase añade `docs/fase15_1_architecture_review.md` y una nota breve al inicio de `docs/fase15_data_pipeline_architecture.md` apuntando a esta revisión. No cambia `Chronicle/`, `tests/`, ni el `.toc`.
- **Tests:** `npm test` se ejecuta sin modificar nada (resultado en el informe de entrega).
- **No hay ZIP, ni merge, ni publicación de la rama.**
- Nada de esto está probado en WoW; es análisis y diseño.

## 11. Tabla final de estados

```
D1  APPROVED
D2  APPROVED
D3  APPROVED
D4  APPROVED_WITH_VALIDATION
D5  REVISED
D6  REVISED
D7  APPROVED
D8  PENDING_OWNER_DECISION
D9  REVISED
D10 APPROVED_WITH_ADJUSTMENT
D11 REVISED
D12 APPROVED
D13 REVISED
D14 APPROVED
D15 APPROVED_WITH_ADJUSTMENT
D16 APPROVED
```
