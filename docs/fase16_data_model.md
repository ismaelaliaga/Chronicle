# Fase 16 — Diseño concreto del modelo de datos

**Rama:** `fase16-data-model`, creada desde el commit aprobado de la Fase 15.1 (`3d35b0641c4a51d854f20c6e234430fdce0283e0`).
**Alcance:** exclusivamente **diseño y documentación**. No se ha tocado `Chronicle/`, `tests/`, `main` ni ningún ZIP. No hay importadores, generador, pipeline ni soporte Forever. Los ejemplos completos están en el documento auxiliar [`fase16_data_model_examples.md`](fase16_data_model_examples.md).
**Base arquitectónica:** `fase15_1_architecture_review.md` (aprobada). Donde este documento concreta algo de la 15.1, la 15.1 sigue siendo la referencia de intención.
**Honestidad de datos:** no se inventa ningún dato de WoW. Los valores reales que aparecen son los ya verificados en fases anteriores (p. ej. `npcID` 786 y 658 en Classic Era). Todo valor de Forever es «desconocido» o un *fixture sintético* marcado como tal.

## 0. Leyenda

| Etiqueta | Significado |
|---|---|
| **[HECHO]** | Comprobado en el repositorio real. |
| **[APROBADO 15.1]** | Decisión ya aprobada en la Fase 15.1; aquí solo se concreta. |
| **[PROPUESTA]** | Diseño nuevo de esta fase, pendiente de revisión. |
| **[PENDIENTE]** | Decisión abierta (ver §14). |
| **[PENDIENTE EN CLIENTE]** | Solo se puede confirmar con un cliente real. |

---

## 1. Resumen: qué se diseña y qué se decide

Se diseñan los esquemas de las **cuatro capas** aprobadas y sus reglas de convivencia:

| Capa | Quién la escribe | Formato | Qué contiene |
|---|---|---|---|
| **1. World Data** | Importadores, capturas del cliente y reconciliación | **JSON canónico** (generado) | Qué existe en el mundo, por versión del juego, con procedencia, confianza y conflictos |
| **2. Candidate Data** | Análisis automático reproducible (+ un perfil de puntuación escrito a mano) | **JSON canónico** (resultado) / **YAML** (perfil) | Candidatos priorizados con score y desglose; **nunca decisiones** |
| **3. Chronicle Editorial Data** | **Personas** (única capa escrita a mano) | **YAML** (subconjunto estricto) | Entidades, lore, pistas, reglas de descubrimiento, bindings, decisiones, overrides |
| **4. Generated Data** | El generador | **Lua** (pack) + JSON (manifiesto/informes) | El pack por versión que carga el addon |

**Decisiones tomadas en esta fase** (todas [PROPUESTA] hasta la revisión del supervisor):
1. **YAML vs JSON (cuestión pendiente de la 15.1): formato híbrido por autoría** — lo que escriben personas, en **YAML 1.2 restringido**; lo que escriben máquinas, en **JSON canónico**; lo que carga el addon, en **Lua generado** (§3).
2. **Lenguaje de esquemas:** JSON Schema (borrador 2020-12) para los documentos del pipeline; `Schema.lua` sigue siendo el validador del runtime (§3.4).
3. **Tres niveles de identidad separados:** identidad editorial (`npc:grelin_whitebeard`) → presencia/versionado (`entity × flavor`) → identificación técnica del cliente (`TechRef`). Los IDs técnicos nunca aparecen en la identidad editorial (§2.2).
4. **Un dato técnico = lista de afirmaciones (*claims*) con procedencia + un valor resuelto** calculado por reglas; los conflictos son registros de primera clase (§5.4).
5. **Los *bindings* (entidad ↔ identidad técnica) son datos editoriales**, no resultado de importación (§7.3).
6. **Las reglas de descubrimiento son datos editoriales** con una gramática explícita (requisitos y tipos de interacción con `any`/`all`), con anulaciones por versión; **no** se asume ningún evento técnico (§7.4).
7. **Las pistas son documentos estructurados**; `requires_hint` es una **puerta de calidad editorial**, distinta del requisito de juego `hint_seen` (§7.5).
8. **Las entidades `retired` se conservan** en el pack (como *lápidas*), en todas las versiones (§10).
9. **«Se publica en una versión» es una conclusión derivada** (decisión editorial ∧ binding ∧ presencia ∧ capacidades ∧ sin conflictos bloqueantes), no un campo escrito a mano (§9).
10. **Determinismo:** ningún artefacto generado lleva marcas de tiempo ni orden dependiente del sistema (§4.6).

**Qué se deja pendiente:** ver §14 (12 puntos P1–P12 más dos decisiones heredadas), incluyendo la semántica de `interaction.all`, la clave de identidad de los lugares mientras no haya `areaID` verificado y la política de capacidades sin verificar.

---

## 2. Modelo conceptual (antes de los esquemas)

### 2.1 Mapa de objetos y flechas de dependencia
```
 FUENTES                                               CLIENTE REAL
   │ (manifiesto: licencia, uso permitido)                 │ (herramienta de captura)
   ▼                                                       ▼
 [Source]──────────────►[Observation]◄──────────────────────┘
   │                       │
   ▼                       ▼
 raw (fuera del repo) → [WorldEntity / WorldPlace]  ◄── [ClientProfile]
                           │  claims[] → resolved           (capacidades observadas)
                           │  conflicts[]  ◄───────────── [Override]  (única entrada editorial que ve World Data)
                           ▼
              ┌────────────┴─────────────┐
              ▼                          ▼
        [Candidate]                [EditorialIndex]  (ids/estado/tech_refs, solo lectura)
        (score, señales)                  ▲
              │                            │
              ▼   (la persona decide)      │
        [CandidateDecision] ───────► [Entity] ──► [Binding] (entity × flavor → TechRef)
                                        │            │
                                        ├──► [Hint]  │
                                        └──► [Text]  │
                                                     ▼
                                   GENERADOR ──► [Pack Lua por versión] ──► ClientAdapter ──► addon
```
**Dirección de dependencia (regla):** *Editorial → World* (referencia por `TechRef`), *Candidate → World*, *Generated ← World + Editorial*. **World Data nunca referencia IDs de Chronicle.** La única excepción es que World Data **consume `Override`** (un tipo de documento editorial) para resolver sus conflictos.

### 2.2 Tres niveles de identidad (requisito de esta fase)
```
 IDENTIDAD EDITORIAL            PRESENCIA / VERSIONADO               IDENTIFICACIÓN TÉCNICA DEL CLIENTE
 npc:grelin_whitebeard   ──►   (npc:grelin_whitebeard, era)    ──►   TechRef { flavor: era, kind: creature, id: 786 }
 (estable, única,              (npc:grelin_whitebeard, forever) ──►   TechRef { flavor: forever, kind: creature, id: <desconocido> }
  independiente del            = Binding + presencia derivada          nombres observados por locale (World Data)
  cliente, idioma, nombre)     (puede no existir, no estar          capacidades de interacción por cliente
                                disponible o no verificarse)
```
| Nivel | Clave | Quién la define | Puede cambiar | Dónde vive |
|---|---|---|---|---|
| Identidad editorial | `ChronicleId` | Editorial (una vez) | **Nunca** (se retira, no se renombra) | `Entity` |
| Presencia/versionado | `(ChronicleId, FlavorId)` | Editorial (`applies_to`, `Binding`) + World Data (existencia) | Sí (estado del binding, disponibilidad) | `Binding` + *presencia derivada* (§9) |
| Identificación técnica | `TechRef` | World Data (observada/importada) | Sí (las fuentes cambian; el cliente cambia) | `WorldEntity` / `Observation` |
Regla: **de un nivel nunca se infiere el siguiente automáticamente** (principio IDENTIFICATION ≠ DISCOVERY ≠ EDITORIAL INCLUSION de la 15.1). Un `TechRef` conocido no crea ni habilita una entidad editorial; una entidad editorial sin `TechRef` en una versión simplemente no se publica ahí.

### 2.3 Conceptos transversales
| Concepto | Qué es |
|---|---|
| **`FlavorId`** | `era`, `forever` (extensible). No existe `unknown` en los datos: `UNKNOWN` es un estado del *runtime* (`ClientFlavor`), no un valor de datos. |
| **`TechRef`** | Identidad técnica concreta: `{ flavor, kind, id }` (p. ej. `{ flavor: era, kind: creature, id: 786 }`). |
| **`Provenance`** | De dónde sale un dato (fuente, versión de la fuente, método, localizador, build del cliente si es captura). |
| **`Claim<T>`** | Una afirmación sobre un valor, con su `Provenance` y su `confidence`. |
| **`Field<T>`** | Un campo de World Data: lista de `claims` + un `resolved` calculado. |
| **`Fingerprint`** | Huella determinista del contenido de un conjunto de entradas (para detectar cambios y atar overrides). |

---

## 3. Formato: resolución de YAML vs JSON

### 3.1 Decisión [PROPUESTA — resuelve la cuestión pendiente de la 15.1]
**El formato se elige por quién escribe el fichero:**

| Artefacto | Formato | Motivo principal |
|---|---|---|
| Lo que **escriben personas**: entidades, bindings, pistas, textos, decisiones, overrides, perfil de puntuación, fuentes (manifiestos) | **YAML 1.2, subconjunto estricto** | Comentarios, texto largo multilínea (lore), revisión legible en *pull request* |
| Lo que **escriben máquinas** y no se edita: World Data normalizado, observaciones, candidatos, conflictos, informes, manifiesto del pack | **JSON canónico** | Sin ambigüedad, diffs estables, sin comentarios que perder |
| Lo que **carga el addon** | **Lua generado** (compatible con Lua 5.1) | Sin dependencias, sin parser en el cliente |

### 3.2 Alternativas consideradas
| Alternativa | A favor | En contra | Resultado |
|---|---|---|---|
| Todo JSON | Sin parser extra (Node lo lee); sin ambigüedades | **Sin comentarios**; el lore multilínea es incómodo; mala experiencia de revisión para texto largo | Descartada para lo editorial |
| Todo YAML | Un solo formato | YAML tiene trampas de tipado implícito y de sangrado; para máquinas no aporta | Descartada para lo generado |
| JSON con comentarios (JSONC/JSON5) | Comentarios sin YAML | Node no lo lee de forma nativa (también requiere parser); ecosistema menor | Descartada |
| TOML | Legible, tipado más estricto | Anidamiento profundo (reglas de descubrimiento, pistas) poco natural | Descartada |
| Tablas Lua (como hoy en `Localization/esES`) | Ya existe; cero parser | Mezcla datos con código; difícil de validar con herramientas estándar; mala fuente para el pipeline | Se mantiene **solo como salida generada** |
| Markdown con cabecera para el lore | Cómodo para textos largos | Dos formatos para una misma entidad | Descartada; el texto largo va como escalar de bloque YAML |

### 3.3 Reglas del YAML estricto [PROPUESTA]
Para neutralizar las trampas conocidas de YAML, un *lint* previo (parte de `data:validate`) rechaza:
1. **Anclas, alias, claves de fusión (`<<`) y etiquetas personalizadas** (`!!…`).
2. **Claves duplicadas** en un mismo mapa.
3. **Tipado implícito ambiguo:** solo `true`/`false` como booleanos; los identificadores, códigos de idioma y valores tipo versión **siempre entre comillas** si podrían interpretarse como número, fecha, booleano o nulo.
4. Más de un documento por fichero, tabulaciones de sangrado, y codificación distinta de **UTF-8 sin BOM con fin de línea LF**.
5. Campos **desconocidos** (el esquema rechaza lo no declarado, como ya hace `Schema.lua`).
Los tipos reales los fija el **esquema** tras cargar el YAML (un valor mal tipado falla la validación aunque el YAML sea válido).

### 3.4 Lenguaje de esquemas [PROPUESTA]
- **JSON Schema (2020-12)** describe todos los documentos del pipeline (YAML y JSON cargados al mismo modelo de datos). Los esquemas viven en `pipeline/schemas/` (futuro).
- **`Chronicle/Data/Schema.lua` no se sustituye:** valida en runtime las entidades del pack (formato de ID, relaciones por tipo). Los dos conjuntos de reglas deben coincidir en lo común y se contrastan con un test (Fase 17+).
- **Dependencias:** el *parser* YAML y el validador de JSON Schema serían **dependencias de desarrollo del pipeline** (nunca del addon; el ZIP no cambia). Precedente en el proyecto: `tests/` ya usa `fengari` como dependencia de desarrollo [HECHO]. La elección concreta de paquetes (y su licencia y mantenimiento) se hace al implementar (Fase 17), no aquí.
- **Plan B si se rechaza cualquier dependencia YAML:** JSON para todo y los comentarios pasan a un fichero Markdown adjunto. Se considera peor, no inviable.

---

## 4. Convenciones comunes

### 4.1 Identificadores
| Tipo | Patrón | Ejemplo | Quién lo asigna | Notas |
|---|---|---|---|---|
| `ChronicleId` | `^(continent\|zone\|city\|subzone\|npc\|lore):[a-z0-9]+(_[a-z0-9]+)*$`, slug ≤ 64 | `npc:grelin_whitebeard` | Editorial | **Igual que `Schema.lua` hoy** [HECHO]; extensible con nuevos tipos. Inmutable. |
| `HintId` | `^hint:[a-z0-9]+(_[a-z0-9]+)*$` | `hint:grelin_whitebeard_1` | Editorial | Namespace propio; **no** es una entidad del Registry (no tiene página en el Codex). |
| `FlavorId` | `^[a-z][a-z0-9_]*$` | `era`, `forever` | Proyecto | Lista cerrada por configuración. |
| `Locale` | `^[a-z]{2}[A-Z]{2}$` | `esES`, `enUS` | WoW | Igual que `Localization` hoy [HECHO]. |
| `SourceId` | `^[a-z0-9_]+$` | `wow_client`, `warcraft_wiki` | Proyecto | Definido en el manifiesto de la fuente. |
| `TechRef` | `{flavor, kind, id:int≥1}` | `{era, creature, 786}` | World Data | `kind` ∈ `creature`, `quest`, `area`, `ui_map`, `map` (extensible). |
| `ObservationId` | `obs:<fingerprint corto>` | — | Herramienta de captura / normalizador | Derivado del contenido: reimportar no duplica. |
| `ConflictId` | `conf:<fingerprint corto>` | — | Reconciliación | Derivado de (clase, sujeto, campo, afirmaciones). |
| `OverrideId` | `^ovr:[a-z0-9]+(_[a-z0-9]+)*$` | `ovr:grelin_name_enus` | Editorial | — |
| `CandidateId` | `cand:<flavor>:<kind>:<id>` | `cand:era:creature:786` | Análisis | Determinista a partir del `TechRef`. |

### 4.2 Cabecera común de documento
Todo documento lleva `schema: "<namespace>/<major>"` (p. ej. `chronicle.editorial.entity/1`). **Cambio de `major` = incompatible**; añadir campos opcionales no cambia el `major`. Un `major` desconocido se rechaza. El migrador de esquemas de ficheros editoriales es trabajo futuro.

### 4.3 Enumeraciones compartidas
| Enum | Valores | Significado |
|---|---|---|
| `Confidence` (de mayor a menor) | `client_verified` > `source_confirmed` > `source_reported` > `inferred` | **client_verified:** observado en el cliente real **de esa versión** (con build). **source_confirmed:** ≥2 fuentes **independientes** coinciden (independencia = distinto `origin_group` en el manifiesto; dos bases que comparten linaje cuentan como una). **source_reported:** una sola fuente. **inferred:** derivado por regla de otros datos. La ausencia de afirmación es «desconocido» (no un nivel). |
| `ProvenanceMethod` | `import`, `capture`, `manual`, `derived` | Cómo llegó el dato. |
| `ResolutionStatus` | `resolved`, `unknown`, `conflict`, `overridden` | Estado del valor resuelto de un campo. |
| `ConflictSeverity` | `blocking`, `high`, `medium`, `low` | Gravedad. |
| `ConflictStatus` | `open`, `overridden`, `accepted`, `wontfix`, `stale` | Estado del conflicto. |
| `EditorialStatus` (entidad) | `accepted`, `drafting`, `review`, `published`, `retired` | Ver §7.1. |
| `CandidateDecisionKind` | `shortlisted`, `accepted`, `rejected`, `deferred` | Decisión humana sobre un candidato. |

> Nota: la 15.1 usaba `source_confirmed` y `client_verified` en `NpcTargets` [HECHO]; este modelo los conserva y añade `source_reported` e `inferred` para cubrir el resto de casos. Las marcas de `Aliases.lua` se mapean así (§13): `[C]`→`client_verified`, `[W]`/`[O]`→`source_reported`, `[J]`→`source_reported` [INFERENCIA: la fuente dice que se vio en un mensaje del juego sin confirmarlo].

### 4.4 Tipo `Provenance`
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `source` | `SourceId` | Sí | Debe existir en los manifiestos. Para capturas, `wow_client`. |
| `source_version` | string | Sí | Commit/versión/hash de la fuente, o build del cliente. |
| `method` | `ProvenanceMethod` | Sí | — |
| `retrieved_at` | fecha ISO-8601 | No | **Metadato de entrada** (cuándo se obtuvo). Nunca se copia al pack. |
| `source_url` | string | No | — |
| `locator` | string | No | Dónde dentro de la fuente (tabla/clave/página). |
| `client_build` | string | Sí si `method=capture` | Build del cliente. |
| `by` | string | Sí si `method=manual` | Persona. |

### 4.5 Tipos `Claim<T>`, `Resolved<T>` y `Field<T>`
```yaml
Claim<T>:     { value: T, provenance: Provenance, confidence: Confidence }
Resolved<T>:  { value: T | null, status: ResolutionStatus,
                rule: single_claim | agreement | tier_precedence | override | none,
                override: OverrideId?, conflict: ConflictId? }
Field<T>:     { claims: [Claim<T>], resolved: Resolved<T> }
```
**El `resolved` nunca se escribe a mano:** lo calcula la reconciliación (§5.4). Si `status` es `conflict`, `value` es `null` (no se «elige» en silencio).

### 4.6 Determinismo y serialización [PROPUESTA]
- **Artefactos generados** (World normalizado, candidatos, informes, pack): claves ordenadas, listas ordenadas por clave de negocio, números sin formato regional, LF, UTF-8 sin BOM, **sin marcas de tiempo ni rutas absolutas ni nombres de máquina** en el contenido. Cualquier dato de tiempo viaja solo como metadato de **entrada** (`retrieved_at`, `observed_at`) y en un `run.json` aparte (no versionado).
- **Fingerprints:** SHA-256 sobre la serialización canónica (el módulo criptográfico de Node no requiere dependencias). La elección definitiva del algoritmo queda para la Fase 17 [PENDIENTE P11].
- **Pack Lua (compatibilidad con Lua 5.1 y con el análisis estático actual):** sin `goto`, operadores de bits ni `//`; **solo escapes decimales (`\ddd`)** en las cadenas (no `\x`, `\z`, `\u{}`), como ya exige el proyecto [HECHO: análisis de la Fase 13].

### 4.7 Niveles de validación
Cada capa se valida en cuatro pasadas: **(1) esquema** (tipos, obligatorios, campos desconocidos), **(2) referencias** (todo ID/ref existe), **(3) invariantes** (ciclos, unicidad, coherencia), **(4) reglas de política** (licencias, spoilers, capacidades). Los fallos de (1)–(3) bloquean siempre; los de (4) tienen gravedad configurable.

---

## 5. Nivel 1 — WORLD DATA

**Qué es:** «qué existe en el mundo», **por versión del juego**, con procedencia. **Qué no es:** nada editorial (ni lore, ni inclusión, ni importancia, ni IDs de Chronicle).

### 5.1 Tipos de documento
| Documento | `schema` | Quién lo escribe | Formato |
|---|---|---|---|
| `Source` (manifiesto de fuente) | `chronicle.world.source/1` | Persona (configuración) | YAML |
| `Observation` | `chronicle.world.observation/1` | Herramienta de captura | JSON |
| `WorldEntity` | `chronicle.world.entity/1` | Normalización + reconciliación | JSON canónico |
| `WorldPlace` | `chronicle.world.place/1` | Ídem | JSON canónico |
| `ClientProfile` | `chronicle.world.client_profile/1` | Capturas/sondas (+ revisión) | JSON canónico |
| `Conflict` | `chronicle.world.conflict/1` | Reconciliación / validación | JSON canónico |

### 5.2 `Source` — manifiesto de fuente
Implementa el principio de la 15.1/D8: **ningún dataset entra al pack sin procedencia, licencia y aprobación del propietario.**

| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id` | — / `SourceId` | Sí | — |
| `name` | string | Sí | — |
| `kind` | enum `client_capture`, `client_export`, `community_db`, `server_emulator_db`, `wiki`, `editorial`, `other` | Sí | Determina el `trust_tier` por defecto. |
| `origin_group` | string | Sí | Fuentes del mismo linaje comparten grupo (para decidir si dos fuentes son «independientes»). |
| `trust_tier` | entero 1–7 | Sí | 1 = override editorial; 2 = captura de cliente; 3 = export del cliente; 4 = BD comunitaria curada; 5 = BD de servidor; 6 = wiki/manual; 7 = secundaria (solo contexto). **Menor número = más confianza.** [PROPUESTA; la jerarquía viene de la Fase 15] |
| `applicable_flavors` | `FlavorId[]` | Sí | Una fuente de 1.12 **no** se declara aplicable a `forever`. |
| `obtained` | `{method, url?, version, sha256?, retrieved_at?}` | Sí | `method` ∈ `capture`, `git_clone`, `manual_download`, `api`. |
| `license` | `{status, identifier?, summary, redistribution, derived_data, attribution?}` | Sí | `status` ∈ `known`, `unknown`. `redistribution` y `derived_data` ∈ `allowed`, `restricted`, `unknown`. |
| `usage` | `{research, contrast, local_validation, candidate_generation, generated_data}` (bool) | Sí | **Todo `false` por defecto.** |
| `owner_approval` | `{by, scope}` | Condicional | Obligatorio si `usage.generated_data = true`. |
| `status` | `active`, `research_only`, `blocked` | Sí | `blocked` no se lee. |
| `notes` | string | No | — |

**Validaciones propias:**
- `usage.generated_data = true` **exige** `license.status = known`, `redistribution ≠ unknown`, `derived_data ≠ unknown` y `owner_approval`. Sin eso, falla (**garantiza** que lo desconocido nunca llega al pack).
- Una fuente `research_only` solo puede alimentar *contraste*, *validación local* y *candidatos*, nunca el pack.
- Los snapshots crudos de las fuentes **no se versionan en el repositorio** (viven fuera); solo se versionan los hechos mínimos normalizados.

### 5.3 `Observation` — captura del cliente real
Registro inmutable de **una cosa observada** en un cliente concreto. Máxima confianza posible (`client_verified`).

| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id` (`ObservationId`) | — | Sí | `id` derivado del contenido. |
| `flavor`, `locale` | `FlavorId`, `Locale` | Sí | — |
| `client` | `{build, interface, version?, signals}` | Sí | `signals`: mapa de **señales de detección tal como se observaron** (p. ej. lo que devuelve la API de versión). El esquema **no enumera** nombres de señal: no se asume cuáles existen. |
| `captured_with` | `{tool, version}` | Sí | — |
| `observed_at` | fecha ISO-8601 | Sí | Metadato de entrada. |
| `restricted_context` | bool | Sí | `true` si se observó en combate/instancia/PvP (valores potencialmente restringidos). |
| `kind` | `unit`, `place`, `interaction`, `capability_probe` | Sí | Determina `payload`. |
| `payload` | por tipo (abajo) | Sí | — |

`payload` por tipo:
- **`unit`:** `{unit_type: creature\|pet\|player\|other\|unavailable, npc_id?: int, name?: string, subname?: string, secret: bool}`. Si `unit_type=player` **no se guarda ni el nombre ni nada identificable** (los jugadores no se capturan). Si `secret=true`, los campos de identidad **no existen** (valor no identificable ahora). El GUID **crudo no se guarda** (no aporta; contiene identificadores de servidor): solo el `npc_id` ya interpretado. Capturas de diagnóstico con GUID crudo se marcan `diagnostic: true` y **no entran a la normalización**.
- **`place`:** `{zone_text?: string, subzone_text?: string, ui_map_id?: int, area_id?: int, player_position?: {map: int, x: number, y: number}}`. Los textos son **exactamente lo que devolvió el cliente** (sin normalizar). La posición es **solo la del jugador** (la API de posición solo cubre jugador/grupo).
- **`interaction`:** `{unit: <payload unit>, raw_event: string, unit_token: string, interaction_hint?: string}`. `raw_event` es el **nombre del evento que se observó**, un hecho; **`interaction_hint` es una etiqueta semántica propuesta por la herramienta, no verificada** (la correspondencia evento ↔ tipo de interacción es justo lo que se está descubriendo).
- **`capability_probe`:** `{capability: string, result: available\|unavailable\|restricted\|error, detail?: string}`.

**Validaciones:** `unit_type=player` ⇒ sin nombre; `secret=true` ⇒ sin campos de identidad; `restricted_context=true` ⇒ no se usa como `client_verified` salvo que `secret=false`; ningún campo de GUID crudo fuera de `diagnostic`.

### 5.4 `WorldEntity` y el modelo de reclamaciones (*claims*)
Un `WorldEntity` es la **vista normalizada de una identidad técnica** en una versión.

| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `ref` (`TechRef`) | — | Sí | Clave. Único por `(flavor, kind, id)`. |
| `exists` | `Field<present\|absent>` | Sí | ¿Existe en esa versión? Las fuentes de otra versión **no** aportan claims de existencia. |
| `names` | `map<Locale, Field<string>>` | No | Nombre **tal como lo devuelve el cliente** en cada idioma (observación). |
| `subnames` | `map<Locale, Field<string>>` | No | Título/rol mostrado. |
| `attributes` | `map<AttrName, Field<escalar>>` | No | Atributos técnicos del catálogo de campos (abajo). |
| `relations` | `map<RelName, Field<TechRef[]>>` | No | p. ej. misiones que ofrece/completa. |
| `spawns` | `Field<Spawn[]>` | No | Ubicaciones; **opcional y nunca bloqueante**. `Spawn = {map?: int, x?: number, y?: number, coordinate_system: unknown\|uimap_percent\|world_xyz}`. `unknown` es válido. |
| `places` | `Field<TechRef[]>` | No | Zonas/áreas donde aparece (referencias a `area`/`ui_map`). |

**Catálogo de atributos de `creature` (inicial; se cierra al diseñar los importadores) [PROPUESTA]:** `npc_flags:int`, `rank:string`, `level_min:int`, `level_max:int`, `faction_template:int`, `creature_type:string`, `display_id:int`. Los nombres de campo salen de los esquemas estudiados (QuestieDB/VMaNGOS) [INVESTIGADO en la Fase 15]; **ninguno se rellena sin una fuente**. Un atributo fuera del catálogo se rechaza.

**Resolución de un `Field` (reconciliación) [PROPUESTA]:**
1. Se descartan las *claims* de fuentes con `usage` que no lo permita o no aplicables a ese `flavor`.
2. **Una sola claim →** `resolved.value = claim.value`, `rule = single_claim`.
3. **Varias coinciden →** `rule = agreement` (y, si proceden de `origin_group` distintos, la confianza es `source_confirmed`).
4. **Discrepan →** se aplica la **precedencia por `trust_tier`**: gana la de menor número **solo si** su `confidence` es estrictamente mayor (`client_verified` sobre cualquier otra); `rule = tier_precedence`. Si hay empate o no hay ventaja estricta → **`status = conflict`, `value = null`**, y se crea un `Conflict`.
5. Un `Override` aplicable (atado a la huella de las claims) fija el valor: `status = overridden`, `rule = override`.
6. Dos claims `client_verified` distintas (p. ej. de builds diferentes) → **conflicto** (clase `drift`); **la política de «el build más reciente gana» no se aplica automáticamente** [PENDIENTE P11b].

### 5.5 `WorldPlace`
Lugares (zonas, subzonas, ciudades) tal como los ve el cliente.

| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `ref` | — | Sí | `ref = {flavor, kind: area\|ui_map\|name_only, id?: int, key?: string}`. Mientras no haya `area_id`/`ui_map_id` **verificado**, el lugar se identifica por `kind: name_only` con `key` = nombre observado normalizado y `identity_quality: name_only`. [PENDIENTE P6] |
| `texts` | `map<Locale, {zone_text?: Field<string>, subzone_text?: Field<string>}>` | No | Qué devuelve cada API del cliente. Corresponde a lo que hoy resuelve `Resolver` mediante `Aliases.lua`. |
| `parent_place` | `Field<ref>` | No | Jerarquía **del mundo** (afirmaciones; no es la jerarquía de Chronicle). |

### 5.6 `ClientProfile` (capacidades observadas por cliente)
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `flavor`, `build`, `interface` | — | Sí | Una entrada por `(flavor, build)`. |
| `signals` | `map<string, escalar>` | Sí | Señales de detección observadas (sin enumerar nombres). |
| `capabilities` | `map<CapabilityId, {status, evidence: ObservationId[]}>` | Sí | `status` ∈ `verified`, `unverified`, `unavailable`, `restricted`. **Por defecto `unverified`.** |
**`CapabilityId` son capacidades *lógicas*, no eventos:** p. ej. `unit_identity.target`, `unit_identity.mouseover`, `unit_identity.nameplate`, `interaction.gossip`, `interaction.quest`, `interaction.merchant`, `interaction.trainer`, `interaction.flight_master`, `interaction.profession`, `place.zone_text`, `place.subzone_text`, `secret_values.active`. El adaptador de cada cliente (código, no dato) decide cómo se detectan; **este modelo no asume ningún evento**. `verified` exige al menos una `Observation` de ese build. [PENDIENTE EN CLIENTE: todos los valores reales]

### 5.7 `Conflict`
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id`, `scope` | — / — / `world`\|`binding` | Sí | `world`: lo crea la reconciliación; `binding`: lo crea la validación al cruzar editorial con World Data (§7.3). |
| `class` | enum | Sí | `identity`, `existence`, `location`, `name_locale`, `duplicate_tech`, `drift`, y (`scope=binding`) `binding_identity_mismatch`, `binding_unavailable`, `duplicate_binding`, `capability_gap`. |
| `severity`, `status` | enums | Sí | Gravedad por defecto según la clase y si la entidad se publica. |
| `subject` | `TechRef` \| `{entity, flavor}` | Sí | — |
| `field` | string | Condicional | Campo en disputa. |
| `claims` | `Claim[]` | Sí (`world`) | Valores en disputa **con procedencia**. |
| `fingerprint` | `Fingerprint` | Sí | Huella de las claims/fuentes **en el momento de detectar**. |
| `resolution` | `{kind: chose_claim\|override\|accepted\|wontfix, override?: OverrideId, reason, by}` | Condicional | Presente cuando `status ≠ open`. |
| `blocks_publish` | bool | Sí (derivado) | `true` si es `blocking`, o `high` y el sujeto está publicado/vinculado. |
Reglas: **ningún conflicto desaparece sin una resolución registrada.** Si cambia la huella de las fuentes, un conflicto `overridden` pasa a `stale` y **vuelve a levantarse** (así un override no queda ciego para siempre).

### 5.8 Qué puede consumir y qué tiene prohibido
| | Puede leer | Puede escribir | **Prohibido leer** | **Prohibido modificar** |
|---|---|---|---|---|
| **World Data** (importadores, normalización, reconciliación) | Manifiestos `Source`; fuentes crudas (fuera del repo); `Observation`; **`Override`** (único documento editorial) | `WorldEntity`, `WorldPlace`, `ClientProfile`, `Conflict` (scope `world`), informe de reconciliación | `Entity`, `Text`, `Hint`, `Binding`, `CandidateDecision`; cualquier ID de Chronicle; Candidate/Generated | Cualquier fichero editorial, Candidate, Generated |

### 5.9 Validaciones de World Data (catálogo)
| Código | Regla | Gravedad |
|---|---|---|
| W-01 | `schema` conocido; campos desconocidos rechazados | bloquea |
| W-02 | `Provenance` completa; `source` existe y su `status ≠ blocked` | bloquea |
| W-03 | Claims de fuentes no aplicables a ese `flavor` rechazadas | bloquea |
| W-04 | `usage.generated_data` coherente con licencia y aprobación (§5.2) | bloquea |
| W-05 | `unit_type=player` sin datos identificables; `secret=true` sin identidad | bloquea |
| W-06 | `resolved` coherente con las claims (recalculado, nunca escrito a mano) | bloquea |
| W-07 | Dos entidades técnicas con el mismo nombre no son error; **un mismo `TechRef` con nombres distintos en el mismo locale sí es conflicto** `identity` | conflicto |
| W-08 | `spawns` con `coordinate_system` ≠ `unknown` exige `map`; las coordenadas nunca son obligatorias | bloquea |
| W-09 | Sin marcas de tiempo en el contenido resuelto (determinismo) | bloquea |
| W-10 | Atributo fuera del catálogo | bloquea |

---

## 6. Nivel 2 — CANDIDATE DATA

**Qué es:** el resultado reproducible de analizar World Data para **proponer** candidatos a revisión editorial. **`SCORE ≠ DECISIÓN EDITORIAL`** [APROBADO 15.1]: este nivel **no tiene ningún campo que exprese inclusión**.

### 6.1 Tipos de documento
| Documento | `schema` | Quién lo escribe | Formato |
|---|---|---|---|
| `ScoringProfile` | `chronicle.candidate.scoring_profile/1` | **Persona** (configuración calibrada) | YAML |
| `SignalDef` (catálogo) | `chronicle.candidate.signal/1` | Persona/proyecto | YAML |
| `Candidate` | `chronicle.candidate.record/1` | Análisis automático | JSON canónico |

### 6.2 `SignalDef` y `ScoringProfile`
`SignalDef`: `id`, `description`, `inputs` (rutas de campos de `WorldEntity`), `type` (`count`, `bool`, `ratio`, `text_match`…), `extractor_version` (entero), `polarity` (`positive`\|`negative`), `normalization` (`{kind: none\|cap\|log, cap?: number}`), `needs` (qué datos de World Data hacen falta; si faltan se registra un `data_gap`, **no se asume 0**).

`ScoringProfile`:
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id`, `version` | — / id / entero | Sí | **Inmutable una vez usado:** un cambio crea una `version` nueva. |
| `flavors` | `FlavorId[]` | Sí | Perfiles por versión (la calibración de Forever será propia). |
| `signals` | `[{id, weight: number, enabled: bool}]` | Sí | Los pesos son **configuración** (no son definitivos). |
| `queue` | `{min_score?: number, max_items?: int}` | No | **Solo dimensiona la cola de revisión; no excluye ni incluye nada.** |
| `calibration` | `{notes, reference_positive: TechRef[], reference_negative: TechRef[], attested_by}` | No | Casos de referencia usados para calibrar (piloto de Dun Morogh). |
| `author`, `reviewer?` | string | Sí/No | — |

### 6.3 `Candidate`
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id` (`CandidateId`) | — | Sí | Determinista a partir del `subject`. |
| `flavor`, `subject` (`TechRef`) | — | Sí | Un candidato es una **identidad técnica**, no una entidad de Chronicle. |
| `display` | `{names: map<Locale,string>, subnames?: map}` | Sí | Copia de los valores **resueltos** de World Data, solo para facilitar la revisión. |
| `profile` | `{id, version}` | Sí | — |
| `signals` | `[{id, raw, normalized, weight, contribution, evidence: [ref]}]` | Sí | `contribution = weight × normalized`. |
| `score` | `{total: number}` | Sí | `total = Σ contribuciones` (comprobable). |
| `rank` | entero | Sí | Posición dentro de `(flavor, profile)` (empates por `CandidateId`). |
| `flags` | `string[]` | No | Etiquetas objetivas (`already_bound`, `previously_rejected`, `previously_deferred`, `generic_name_pattern`, `data_gap`). |
| `data_gaps` | `string[]` | No | Qué señales no se pudieron calcular por falta de datos. |
| `inputs_fingerprint` | `Fingerprint` | Sí | Huella de (World resuelto relevante + perfil + defs de señales). |
**Prohibido en el esquema:** cualquier campo `include`, `accepted`, `status`, `decision` o equivalente. Un candidato **no tiene estado editorial**: la decisión vive en `CandidateDecision` (§7.7).

### 6.4 Versionado y reproducibilidad
Mismas entradas (World resuelto + `ScoringProfile.version` + `SignalDef.extractor_version`) ⇒ **mismo resultado byte a byte.** No hay marcas de tiempo en `Candidate`. Cambiar un peso exige una `version` nueva del perfil; los candidatos antiguos conservan su `profile.version` para poder compararlos.

### 6.5 Qué puede consumir y qué tiene prohibido
| | Puede leer | Puede escribir | **Prohibido leer** | **Prohibido modificar** |
|---|---|---|---|---|
| **Candidate Data** (análisis) | World Data **resuelto**; `ScoringProfile`; `SignalDef`; **`EditorialIndex`** (solo IDs, estado y `tech_refs` de entidades/bindings, para marcar `already_bound`); `CandidateDecision` (solo para etiquetar `previously_rejected/deferred` y suprimir de la cola) | `Candidate`, informe de candidatos | Textos, lore, pistas, reglas de descubrimiento, `Override` | World Data, cualquier dato editorial, Generated. **Nunca altera un score por una decisión editorial.** |

### 6.6 Validaciones (catálogo)
| Código | Regla | Gravedad |
|---|---|---|
| C-01 | `contribution = weight × normalized`; `score.total = Σ contribuciones` | bloquea |
| C-02 | `profile.version` existe y está congelada | bloquea |
| C-03 | `subject` existe en World Data de ese `flavor` | bloquea |
| C-04 | Sin campos de inclusión/decisión en el registro | bloquea |
| C-05 | Una señal con datos insuficientes produce `data_gap`, no un valor inventado | bloquea |
| C-06 | Sin marcas de tiempo; orden determinista | bloquea |
| C-07 | Los candidatos con `data_gap` en señales clave se marcan, no se ocultan | aviso |

---

## 7. Nivel 3 — CHRONICLE EDITORIAL DATA

**Qué es:** la **decisión humana** sobre qué cuenta Chronicle. Es la **única capa escrita a mano.** Todo se referencia por `ChronicleId`; **nada técnico del cliente vive aquí** salvo las referencias a World Data que establece el `Binding`.

### 7.1 Tipos de documento
| Documento | `schema` | Qué es |
|---|---|---|
| `Entity` | `chronicle.editorial.entity/1` | Identidad editorial, relaciones, reglas de descubrimiento, estado |
| `Binding` | `chronicle.editorial.binding/1` | Unión `entidad × versión → identidad técnica` (+ nombres observados de lugares) |
| `Hint` | `chronicle.editorial.hint/1` | Pista estructurada |
| `Text` | `chronicle.editorial.text/1` | Textos por idioma (título, descripción, lore, etc.) |
| `CandidateDecision` | `chronicle.editorial.candidate_decision/1` | Qué se decidió de un candidato |
| `Override` | `chronicle.editorial.override/1` | Resolución explícita de un conflicto de World Data |
| `Vocabulary` | `chronicle.editorial.vocab/1` | Vocabularios controlados (categorías, etc.) |

### 7.2 `Entity`
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id` (`ChronicleId`), `type` | — | Sí | `type` = prefijo del `id` (como `Schema.lua` [HECHO]). |
| `status` | `accepted`, `drafting`, `review`, `published`, `retired` | Sí | Transiciones abajo. |
| `importance` | `major`, `standard`, `minor` | No (`standard`) | **Editorial**, no es el score. |
| `categories` | `string[]` | No | Del `Vocabulary`. |
| `parent` | `ChronicleId` | Según tipo | Obligatorio en `zone`, `city`, `subzone`; prohibido en el resto (**igual que hoy** [HECHO]). |
| `located_in` | `ChronicleId` | No | Según tipo (**igual que hoy**). |
| `related_to` | `ChronicleId[]` | No | Relación libre; una sola fuente de verdad. |
| `applies_to` | `FlavorId[]` | Sí (no vacío salvo `retired`) | **Intención editorial:** en qué versiones debe existir la historia. **No** afirma que exista. |
| `discovery` | `DiscoveryRules` | Sí para `npc`/`lore`; implícito para lugares | Ver §7.4. |
| `flavors` | `map<FlavorId, {discovery?: DiscoveryRules, notes?: string}>` | No | **Anulaciones por versión** de las reglas (p. ej. otra interacción en Forever). No crean otra entidad. |
| `requires_hint` | `true`, `false`, `"auto"` | No (`"auto"`) | Puerta de calidad editorial (§7.5). `"auto"` ⇒ `true` si `importance = major`. |
| `editorial` | `{author, reviewer?, reviewed_at?, notes?}` | `author` sí; el resto no | **`reviewer` opcional** en la fase inicial [APROBADO 15.1]. |
| `retired` | `{reason, since?, superseded_by?: ChronicleId}` | Sí si `status = retired` | Ver §10. |
Los **textos no están aquí** (viven en `Text`), ni ningún `npcID`, `displayID`, nombre del cliente o coordenada.

**Transiciones de estado** (las valida la herramienta):
```
accepted → drafting → review → published
            ↑          │  ↓
            └──────────┘  (published → drafting para revisar)
cualquier estado → retired
retired → review   (reposición explícita; el ID es el mismo)
```
`rejected` y `deferred` **no son estados de entidad:** una entidad solo existe tras aceptar un candidato; el rechazo/aplazamiento es una `CandidateDecision`.

### 7.3 `Binding` — de la identidad editorial a la presencia por versión
Es **una decisión editorial revisada**, no un resultado de importación [APROBADO 15.1]. Ninguna importación lo sobrescribe.

| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `entity` (`ChronicleId`), `flavor` | — | Sí | Clave `(entity, flavor)`, única. |
| `status` | `proposed`, `accepted`, `rejected`, `unavailable`, `superseded` | Sí | `unavailable` = editorialmente se sabe que **no existe** en esa versión (distinto de «aún sin binding»). |
| `tech_refs` | `TechRef[]` | Sí si `status = accepted` y la entidad no es un lugar | Todas con `flavor` igual al del binding. Permite varias (p. ej. un mismo personaje con más de una plantilla). |
| `places` | `PlaceName[]` | Sí si la entidad es un lugar y `accepted` | `PlaceName = {locale, api: zone_text\|subzone_text, string, evidence: ObservationId[], confidence}`. **Es el sucesor de `Aliases.lua`:** el texto exacto que el cliente devuelve para ese lugar, con su procedencia. |
| `area_id`, `ui_map_id` | int | No | Solo si están **verificados**. |
| `evidence` | `ObservationId[]` | No | Qué observaciones respaldan el binding. |
| `attested` | `{by, method: capture\|manual_review\|source_review, at}` | Sí si `accepted` | Quién y cómo lo dio por bueno. |
| `notes` | string | No | — |

**Invariantes:**
- Un `TechRef` solo puede estar en **un** binding `accepted` por `flavor` (si no: conflicto `duplicate_binding`, **bloqueante**).
- Un binding `accepted` apunta a un `TechRef` que **existe** en World Data de ese `flavor` (si no: `binding_unavailable`).
- Si World Data **cambia** el nombre/atributos del `TechRef` ya vinculado de forma incompatible con lo atestiguado: conflicto `binding_identity_mismatch` (el binding **no se toca**; se revisa).
- Los lugares con `places[]` solo sirven para que el `Resolver` reconozca nombres; el binding **no** crea el lugar.

### 7.4 Reglas de descubrimiento (`DiscoveryRules`)
Gramática [APROBADO 15.1: requisitos configurables por entidad, interacción configurable]:
```
DiscoveryRules:
  method:        interaction | place_enter | none
  requirements:  Requirement | { all: [Requirement] } | { any: [Requirement] }     # opcional
  interaction:   InteractionSpec                                                    # obligatorio si method = interaction

InteractionSpec:  { type: InteractionType }
                | { any: [InteractionSpec] }
                | { all: [InteractionSpec] }                                         # RESERVADO (ver nota)
InteractionType:  gossip | quest | merchant | trainer | flight_master | profession | other
                  (other exige: label: string)

Requirement:
  { place_discovered: { id: ChronicleId, strict: bool = false } }
  { entity_discovered: { id: ChronicleId } }
  { hint_seen:        { id: HintId } }                                               # RESERVADO
```
**Semántica:**
- `method: place_enter` es el de los lugares (lo hace `ZoneDiscovery` hoy [HECHO]); `none` = no se descubre por juego (solo informativa).
- **`requirements` ausente** (NPC): se **materializa** al generar como `place_discovered` de la **zona/ciudad ancestro** de su `located_in` (por la cadena `parent`) [D7 APROBADA]; queda marcado `derived: true` en el pack. **`strict: true`** exige exactamente el lugar indicado (p. ej. una subzona), y solo debe usarse si el reconocimiento de esa subzona está verificado en cliente.
- **`all` / `any` de `requirements`** se evalúan sobre el **estado de descubrimiento actual** (sin persistencia nueva).
- **`InteractionSpec.any`:** basta que **una** interacción ocurra y encaje; **se soporta sin estado nuevo.**
- **`InteractionSpec.all`: RESERVADO.** Exigir varias interacciones *distintas* requeriría **recordar progreso parcial** (persistencia nueva en `State`, migración 1→2). Mientras esa característica no esté habilitada en el pack (`features.persist_interaction_progress = false`), `all` en interacciones **falla la validación.** [PENDIENTE P1]
- **`hint_seen` RESERVADO:** necesita persistir qué pistas se vieron (`features.persist_hints`). [PENDIENTE P2]
- **Tipos técnicos:** **no se asume qué evento del cliente implementa cada tipo.** Cada `ClientAdapter` declara qué `interaction.*` sabe detectar (capacidades, §5.6). Una interacción cuyo tipo no está soportado en una versión **impide publicar la entidad ahí** (§9), no se «adivina».
- **Ver, ratón, objetivo, placa, proximidad y detectar GUID/nombre NO son interacciones** y no existen como tipos: son *identificación* [APROBADO 15.1].
- **Anulaciones por versión:** `flavors.forever.discovery` sustituye por completo las reglas para esa versión (no se fusionan campo a campo, para evitar combinaciones ambiguas).

**Capacidades requeridas (derivadas):** el generador calcula, por entidad y versión, `required_capabilities` = `{interaction.<tipo>…}` de sus reglas + `place.*` de los requisitos. Se contrastan con `ClientProfile` (§9).

### 7.5 `Hint` — pista estructurada y `requires_hint`
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id` (`HintId`) | — | Sí | — |
| `target` | `ChronicleId` | Sí | Entidad a la que ayuda a encontrar. |
| `kind` | `narrative`, `contextual` | Sí | Narrativa (lore) o del entorno. |
| `necessity` | `required`, `optional` | Sí | `required`: forma parte del camino mínimo para encontrar la entidad; `optional`: refuerzo. |
| `tier` | entero ≥ 1 | Sí | **Aparición progresiva** (1, 2, 3…). |
| `reveals_when` | `Requirement` / `all` / `any` | No | **Misma gramática** que los requisitos de descubrimiento, **sin** interacciones y **sin** `hint_seen` en el esquema inicial. Sin valor ⇒ visible desde el principio. |
| `depends_on` | `HintId[]` | No | **Orden:** la pista solo está disponible si las listadas también lo están (relación de revelado, no de «lectura»). |
| `related_to` | `ChronicleId[]` | No | Relación narrativa (sin coordenadas) para enlaces y validación de spoilers. |
| `text` | clave en `Text` (`hint:<slug>`) | Sí | **Nunca texto inline.** |
| `applies_to` | `FlavorId[]` | No (hereda de `target`) | Una pista puede existir solo en algunas versiones. |
| `status` | `draft`, `review`, `published`, `retired` | Sí | — |
| `editorial` | `{author, reviewer?, reviewed_at?}` | `author` sí | — |

**`requires_hint` (campo de `Entity`)** — **dos conceptos distintos que no se confunden** [PROPUESTA; aclara la 15.1]:
| | `requires_hint` | `hint_seen` |
|---|---|---|
| Qué es | **Puerta de calidad editorial** | **Requisito de juego** |
| Qué exige | La entidad **debe tener ≥1 pista `published`** (idealmente una `required`) para poder publicarse | El jugador **debe haber visto** una pista concreta para descubrir |
| Dónde se evalúa | En `data:validate` (build) | En runtime (reservado) |
| Persistencia nueva | No | Sí (reservado hasta decidirlo) |
`requires_hint: "auto"` ⇒ `true` si `importance = major`. Se puede poner `false` con justificación en `editorial.notes`.

**Lint de pistas [APROBADO 15.1]** (política, gravedad configurable):
1. Sin **coordenadas** ni instrucciones tipo GPS (patrones de pares numéricos, direcciones cardinales con distancias, comandos de marcado de ruta).
2. Sin **revelar el nombre** de la entidad objetivo bloqueada ni sus nombres observados/alias (se comprueba contra los nombres de todas las versiones e idiomas disponibles).
3. **Sin ciclos** en `depends_on` (grafo global).
4. **Sin dependencias inexistentes** (`depends_on`, `reveals_when`, `related_to`, `target`).
5. Una pista `published` con `target` `retired` o inexistente es error.
La experiencia buscada es *leer → pensar → relacionar → investigar → encontrar → interactuar → descubrir*, no *leer → recibir coordenadas → ir directamente*. **No se diseña UI.**

### 7.6 `Text`
```
Text:  { schema, locale, entries: map< ChronicleId | HintId, TextEntry > }
TextEntry: { title?, description?, summary?, body?, role?, race? }
```
Correspondencia con el runtime actual [HECHO: `Localization` admite `name, description, hint, race, role`]: `title→name`, `description→description`, `role→role`, `race→race`; `body` es el cuerpo de lore (`textKey`, que hoy ninguna entidad declara). El campo antiguo `hint` (un texto por entidad) se migrará a documentos `Hint` (ver §13).
**Reglas:** `title` es obligatorio en el **idioma editorial** (`esES`) para publicar; otros idiomas son opcionales y siguen el respaldo de `Localization` (idioma pedido → predeterminado). **Idioma editorial inicial: `esES`.** [APROBADO 15.1] **Los nombres que devuelve el cliente NO viven aquí** (son `WorldEntity.names` / `Binding.places`): el título editorial y el nombre observado son cosas distintas. Preparado para `enUS` y futuros idiomas sin exigirlos.

### 7.7 `CandidateDecision`
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `subject` (`TechRef`), `decision` | — | Sí | `shortlisted`, `accepted`, `rejected`, `deferred`. |
| `reason` | string | Sí (salvo `shortlisted`) | — |
| `entity` | `ChronicleId` | Sí si `accepted` | La entidad creada. |
| `evidence_fingerprint` | `Fingerprint` | Sí | Huella de las señales del candidato **en el momento de decidir**. |
| `resurface` | `{policy: never\|on_signal_change, threshold?}` | No (`on_signal_change`) | Cuándo un rechazo/aplazamiento puede volver a la cola. |
| `by`, `at` | — | Sí | — |
Los rechazados **no reaparecen** salvo que cambie su evidencia según `resurface` (así la cola no se repite en cada ejecución).

### 7.8 `Override` — resolución de conflictos de World Data
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `schema`, `id` (`OverrideId`) | — | Sí | — |
| `target` | `{conflict: ConflictId}` \| `{subject: TechRef, field}` | Sí | — |
| `decision` | `{set_value: any}` \| `{prefer_claim: Provenance}` \| `{reject_claim: Provenance}` | Sí | — |
| `reason` | string | Sí | **Motivo obligatorio.** |
| `evidence` | `ObservationId[]` / refs | No | — |
| `bound_to_fingerprint` | `Fingerprint` | Sí | Huella de las claims en el momento de decidir. |
| `on_drift` | `resurface` | Sí (constante) | Si la huella cambia, el conflicto **vuelve a abrirse**. |
| `author`, `reviewer?`, `reviewed_at?`, `created_at` | — | `author` sí | — |
**Un override solo cambia World Data; no toca lore, pistas ni la decisión de incluir.**

### 7.9 Qué puede consumir y qué tiene prohibido
| | Puede leer | Puede escribir | **Prohibido leer / hacer** | **Prohibido modificar** |
|---|---|---|---|---|
| **Editorial (personas y sus herramientas)** | World Data **resuelto** (para referenciar y validar); Candidate Data (para revisar); `EditorialIndex` | Ficheros editoriales (las personas) | Que un importador, el generador o el score escriban aquí; que el **addon** sea fuente editorial | World Data, Candidate Data, Generated. **No se edita un fichero generado.** |

### 7.10 Validaciones editoriales (catálogo)
| Código | Regla | Gravedad |
|---|---|---|
| E-01 | `schema` conocido; campos desconocidos rechazados; YAML estricto (§3.3) | bloquea |
| E-02 | `id` con patrón válido, único **entre todos los ficheros** y `type` = prefijo | bloquea |
| E-03 | Relaciones (`parent`, `located_in`, `related_to`, `target`…) resuelven a entidades **conocidas** (incluidas las `retired`); tipos válidos por relación; **árbol de `parent` sin ciclos** | bloquea |
| E-04 | `published` ⇒ `title` en el idioma editorial; `author` presente | bloquea |
| E-05 | `retired` ⇒ objeto `retired` completo; un ID `retired` **no se elimina ni se reutiliza** | bloquea |
| E-06 | `DiscoveryRules` cumple la gramática; las características reservadas (`all` en interacción, `hint_seen`) solo con su `feature` habilitada | bloquea |
| E-07 | `requires_hint` resuelto a `true` ⇒ ≥1 `Hint` `published` | bloquea al publicar |
| E-08 | Lint de pistas (§7.5) | según política |
| E-09 | Binding: unicidad de `TechRef` por versión; referencia existente en World Data | bloquea / conflicto |
| E-10 | Ninguna entidad editorial referencia un **`TechRef`** salvo vía `Binding` | bloquea |
| E-11 | Transición de estado permitida (§7.2) | bloquea |
| E-12 | Ningún texto del juego protegido copiado de fuentes `research_only` (lint de coincidencia contra snapshots locales) | aviso/bloquea [PENDIENTE] |

---

## 8. Nivel 4 — GENERATED DATA

**Qué es:** el resultado **reproducible** del generador: `World + Editorial → Lua`. **No se edita a mano.** **Prohibido** que el addon en runtime sea fuente editorial.

### 8.1 Artefactos
| Artefacto | Formato | Va en el ZIP |
|---|---|---|
| **Pack por versión** (`Chronicle/Data/Generated/<flavor>/…`) | Lua 5.1 | **Sí** |
| `pack-manifest.json` (cabecera ampliada, recuentos, huellas) | JSON | No (o solo la cabecera dentro del pack) |
| Informe de publicación (`ship-report`), informe de conflictos | JSON | No |
La división física del pack en ficheros (por sección y por idioma) se decide en la Fase 17 [PENDIENTE P7]; aquí se define el **contenido lógico**.

### 8.2 Cabecera del pack (validada por el addon al cargar)
| Campo | Tipo | Oblig. | Regla |
|---|---|---|---|
| `pack_schema` | entero | Sí | Un `major` desconocido ⇒ el pack **se rechaza** (`Init.failed`). |
| `flavor` | `FlavorId` | Sí | **Se contrasta con el `ClientFlavor` detectado** por el adaptador; desajuste ⇒ modo seguro [APROBADO 15.1]. |
| `client` | `{interface: int[]}` | Sí | `Interface` objetivo del pack (**informativo**; el `.toc` es independiente). |
| `content_revision` | `Fingerprint` | Sí | Huella de las entradas. |
| `generated_from` | `{world: Fingerprint, editorial: Fingerprint, generator: string}` | Sí | **Sin fechas.** |
| `counts` | `{entities, published, retired, hints, …}` | Sí | Coherencia interna. |
| `features` | `{persist_hints: bool, persist_interaction_progress: bool}` | Sí | Puertas de las características reservadas (por defecto `false`). |
| `locales` | `Locale[]` | Sí | Idiomas incluidos. |
**El runtime no verifica el checksum** (coste y utilidad dudosos en Lua 5.1); la huella sirve al pipeline (`data:check`). El runtime valida **cabecera + estructura**.

### 8.3 Secciones lógicas
| Sección | Contenido | Clave |
|---|---|---|
| `entities` | `{type, status, parent?, located_in?, related_to?, importance, categories?}` — **sin** datos técnicos | `ChronicleId` |
| `presence` | Para este `flavor`: `{available: bool, reason?, tech: [{kind, id}], attributes?: {display_id?: int}}` | `ChronicleId` |
| `discovery` | Regla **materializada** (defaults expandidos, `derived: true` donde corresponda) y `required_capabilities` | `ChronicleId` |
| `hints` | Pistas publicadas de esta versión (estructura completa) | `HintId` |
| `texts` | Textos por idioma | `locale → ChronicleId\|HintId → TextEntry` |
| `names` | Índice **observado** para el `Resolver`: `locale → api → cadena normalizada → ChronicleId` (sucesor de `Aliases.lua`) | — |
| `tombstones` | Entidades `retired` (mínimo: `id`, `type`, `status`, `parent?`, `located_in?`, `superseded_by?`) | `ChronicleId` |
**Qué NO entra nunca al pack:** Candidate Data, claims/procedencia completas, conflictos, fuentes, entidades no `published`/`retired`, **GUID crudos**, coordenadas (en el esquema inicial), textos de misiones/diálogos de fuentes externas, nada de fuentes `research_only`.

### 8.4 Qué consume el runtime y qué tiene prohibido
| | Puede leer | Puede escribir | **Prohibido** |
|---|---|---|---|
| **Addon (runtime)** | El pack Lua (solo lectura) a través de un cargador; la API del cliente **solo mediante `ClientAdapter`** | `ChronicleCharDB` **solo vía `State`**, y únicamente **progreso del jugador** (qué descubrió) | Escribir en el pack; contener o alterar lore, pistas, inclusión o reglas; leer World/Candidate/Editorial/fuentes; hacer importaciones |

### 8.5 Validaciones del generador (catálogo)
| Código | Regla | Gravedad |
|---|---|---|
| G-01 | Determinismo: regenerar produce **los mismos bytes** que lo versionado (`data:check`) | bloquea |
| G-02 | Solo entidades `published`/`retired`; las `retired` van como lápidas **en todas las versiones** | bloquea |
| G-03 | Cada entidad del pack tiene `presence.available` calculada según §9 | bloquea |
| G-04 | Ningún conflicto con `blocks_publish` abierto afecta a lo que se publica | bloquea |
| G-05 | Referencias del pack resuelven (incluidas lápidas) y el árbol de `parent` no tiene ciclos | bloquea |
| G-06 | `discovery` materializado coincide con la gramática y con las `features` | bloquea |
| G-07 | Lua válido para 5.1 (análisis estático existente) y sin `\x`, `\z`, `\u{}` | bloquea |
| G-08 | Ninguna fuente `research_only` ni dato con licencia desconocida en el pack | bloquea |
| G-09 | La cabecera declara `flavor` y `pack_schema`; recuentos coherentes | bloquea |
| G-10 | Los índices `names` no tienen colisiones ambiguas dentro de un mismo `(locale, api)` (si las hay, se registran como `ambiguous` y no resuelven) | aviso/bloquea |

---

## 9. Una misma entidad editorial en varias versiones

**Objetivo:** `npc:grelin_whitebeard` es **una** entidad editorial con presencia, identidad técnica, nombres, capacidades y disponibilidad **distintos por versión**, sin duplicar entidades.

### 9.1 Dónde vive cada cosa
| Aspecto | Dónde se representa | Por versión |
|---|---|---|
| Existencia de la historia/lore, categoría, importancia, relaciones narrativas | `Entity` | **Compartido** |
| Qué versiones debería cubrir | `Entity.applies_to` | Compartido (intención) |
| Título editorial, descripción, lore, pistas (texto) | `Text` / `Hint` | Por **idioma** (y `Hint.applies_to` por versión) |
| ¿Qué criatura es en cada cliente? (`npcID`) | `Binding.tech_refs` → `WorldEntity` | **Por versión** |
| Nombre que devuelve cada cliente | `WorldEntity.names` | Por versión y **por locale** |
| ¿Existe y está disponible en esa versión? | `WorldEntity.exists` + `Binding.status` | **Por versión** |
| Qué interacciones acepta y qué requisitos | `Entity.discovery` + `Entity.flavors.<v>.discovery` | **Por versión** (anulación) |
| Qué interacciones **sabe detectar** ese cliente | `ClientProfile.capabilities` | **Por versión** |
| Ubicación (lugares donde aparece) | `WorldEntity.places` / `spawns` | Por versión (opcional) |
| Modelo 3D (`display_id`) | `WorldEntity.attributes.display_id` → `presence.attributes` | **Por versión** |

### 9.2 La conclusión derivada «se publica en la versión V» (nunca un campo a mano)
Para cada `(entidad, versión)` el generador calcula `presence.available` ⇔ **todas** estas condiciones:
1. `Entity.status = published` (o `retired`, que va como lápida, §10).
2. `V ∈ Entity.applies_to`.
3. Existe un `Binding` `accepted` para `(entidad, V)` con `tech_refs` (o `places` si es lugar).
4. Cada `TechRef` **existe** en World Data de `V` (`exists.resolved = present`).
5. Las `required_capabilities` de sus reglas de descubrimiento están **soportadas** en `ClientProfile` de `V` (política para las `unverified`: §9.3).
6. Ningún conflicto con `blocks_publish` abierto afecta al sujeto.
Si alguna falla, **no se publica en esa versión** y el `ship-report` explica **cuál** (`not_applicable`, `no_binding`, `tech_ref_missing`, `entity_absent`, `capability_unavailable`, `capability_unverified`, `blocked_by_conflict`). La entidad y su lore **siguen intactos** en la capa editorial.

### 9.3 Capacidades sin verificar [PENDIENTE P10]
Mientras una capacidad esté `unverified` en un cliente (caso inicial de **Forever**), hay dos políticas posibles: **(a) estricta:** no se publica el descubrimiento de esa entidad en esa versión; **(b) permisiva con aviso:** se publica y se marca `capability_unverified` en el informe. Recomiendo **(a) para Forever** hasta validarlo en cliente y **(b) para Era** con lo ya validado en la Fase 14.

### 9.4 Casos cubiertos
| Caso | Cómo se representa |
|---|---|
| En ambas versiones, mismo personaje, distinto `npcID` | 1 `Entity`, 2 `Binding` (cada uno con su `TechRef`) |
| Solo en una versión | 1 `Entity` con `applies_to` de una versión; no hay binding en la otra |
| Existe en el mundo de una versión pero no se quiere contar ahí | `applies_to` sin esa versión |
| El personaje se quitó del juego en una versión | `Binding.status = unavailable` (o `WorldEntity.exists = absent`); la entidad sigue |
| Distintos nombres por locale | `WorldEntity.names` por `(flavor, locale)`; el título editorial no cambia |
| Interacción distinta por versión | `Entity.flavors.<v>.discovery` |
| Sin datos verificados en Forever | Sin binding `accepted` ⇒ no se publica ahí; sin perder nada editorial |
| Misma criatura con varias plantillas en una versión | `Binding.tech_refs` con varias |
Los ejemplos completos (incluido un *fixture sintético* con IDs distintos por versión, claramente marcado como no real) están en el documento auxiliar.

---

## 10. Entidades retiradas (`status: retired`)
- **Regla [APROBADO 15.1]:** al dejar de usarse una entidad **no se borra su ID**; se marca `status: retired` y **el Registry debe seguir conociéndola**, para que los descubrimientos guardados en `ChronicleCharDB` no queden huérfanos.
- **Por qué es necesario [HECHO]:** `Discovery:IsDiscovered`, `GetIds`, `Count` y `Discover` solo reconocen IDs que `registry:Has(id)`; si el ID desapareciera, esos descubrimientos dejarían de contarse y verse.
- **Diseño:**
  - `Entity` con `status: retired` y `retired: {reason, since?, superseded_by?}`. Se conserva el fichero editorial.
  - **El pack incluye una *lápida* (`tombstones`) en todas las versiones**, con los datos **mínimos** (`id`, `type`, `status`, `parent?`, `located_in?`, `superseded_by?`), aunque la entidad no estuviera disponible en esa versión.
  - Sin texto, sin pistas ni reglas de descubrimiento activas para una entidad retirada (sus `Hint` pasan a `retired`).
  - **Las referencias a una entidad retirada siguen siendo válidas** (`parent`, `located_in`, `related_to`): una subzona retirada puede seguir siendo ancestro de un descubrimiento antiguo.
  - **Un ID retirado no se reutiliza** para otra entidad; `retired → review` permite reponerla con el **mismo** ID.
- **Cambios necesarios en el código (futuro, no ahora) [HECHO: el esquema actual no tiene `status`]:** añadir `status` a `Schema.lua` y hacer que `Registry` acepte lápidas; **el comportamiento de la interfaz** (mostrar, ocultar o atenuar una entidad retirada que el jugador ya descubrió) **se decide más adelante** [APROBADO 15.1].

---

## 11. Versionado y procedencia por capa (resumen)
| Capa | Qué se versiona | Mecanismo | Procedencia |
|---|---|---|---|
| World | Esquema (`major`); cada fuente (versión/commit/hash en su manifiesto); el conjunto resuelto por versión | `schema`; `Source.obtained.version`; `world_fingerprint` | Por **campo** y por claim (`Provenance`) |
| Candidate | Perfil (`version` inmutable); defs de señales (`extractor_version`) | `profile.version`; `inputs_fingerprint` | Cada contribución cita su evidencia |
| Editorial | Esquema (`major`); historial en git; `editorial_fingerprint` del subconjunto publicado | `schema`; git | `editorial.author/reviewer`; `Binding.attested`; `Override.reason` |
| Generated | `pack_schema`; `content_revision`; versión del generador | Cabecera | `generated_from` (huellas, **sin fechas**) |
Cada fuente de datos debe poder rastrearse **hasta su origen**; el pack **no** lleva la procedencia completa (solo `content_revision` y `generated_from`), que queda en World/Editorial y en el informe.

---

## 12. Matriz global de consumo y modificación

| Capa → | World | Candidate | Editorial | Generated | Addon (runtime) |
|---|---|---|---|---|---|
| **World** | escribe | — | lee **solo `Override`** | — | — |
| **Candidate** | lee (resuelto) | escribe | lee **solo `EditorialIndex`** y `CandidateDecision` (para etiquetar/suprimir) | — | — |
| **Editorial** | lee (resuelto) | lee (para revisar) | **escriben las personas** | — | — |
| **Generated** | lee (resuelto + conflictos) | **no lo lee** | lee lo `published`/`retired` | escribe | — |
| **Addon** | no | no | no | **lee (solo lectura)** | escribe **solo progreso** en `ChronicleCharDB` vía `State` |
Prohibiciones transversales: (1) nadie edita Generated a mano; (2) el score no crea ni decide inclusión; (3) una fuente externa nunca crea una `Entity`; (4) el runtime nunca escribe contenido; (5) World Data nunca contiene IDs de Chronicle.

---

## 13. Relación con el código actual (qué cambiará; no se cambia ahora)

| Hoy [HECHO] | Destino en el modelo | Observación |
|---|---|---|
| `Data/Entities/*` (`id`, `type`, `parent`, `located_in`, `related_to`) | `Entity` → pack `entities` | Misma semántica y mismas reglas de relaciones. |
| `npcID` en la entidad | `Binding.tech_refs` → pack `presence.tech` | Sale de la identidad editorial. |
| **`displayID` en la entidad** | `WorldEntity.attributes.display_id` → pack `presence.attributes.display_id` | **Lo usa el Codex** (`CodexModel` decide el modelo 3D por `entity.displayID`): al implementarlo, el modelo pasará a depender de la **presencia por versión**. |
| `Data/NpcTargets.lua` (lista manual con `confidence`) | `Binding` + `discovery` materializado | La lista «habilitados» pasa a ser **derivada** (publicado ∧ binding ∧ capacidades ∧ sin conflictos). Su `confidence` ya usa `client_verified`/`source_confirmed`. |
| `Localization/esES/*` (`name`, `description`, `hint`, `race`, `role`) | `Text` (`title`, `description`, `role`, `race`) y `Hint` | Los nombres propios en inglés dentro de `esES` **no se tocan ahora**; migrarlos a nombres observados es una tarea futura [APROBADO 15.1]. |
| `Localization/esES/Aliases.lua` (24 alias; `[C]` 5, `[J]` 1, `[W]` 17, `[O]` 1) | `Binding.places[]` con `evidence` y `confidence` | Mapeo: `[C]`→`client_verified`; `[W]`,`[O]`,`[J]`→`source_reported`. |
| `Resolver` (índice de nombres + alias) | Se alimenta de `names` del pack por `(locale, api)` | El Resolver deja de depender de ficheros escritos a mano. |
| `Discovery` (`entries[id] = {}`) | **Sin cambios** | API y persistencia intactas. |
| `ZoneDiscovery` | Usa `method: place_enter` | Sin cambio de semántica. |
| `NpcDiscovery` (Fase 14: descubre al identificar) | Se sustituye por identificación (`ClientAdapter`) + servicio de reglas | No representa la semántica definitiva [HECHO / APROBADO 15.1]. |
| `State` (`schemaVersion = 1`) | Sin cambios en la Fase 16 | Migración 1→2 **solo** si se habilitan `persist_hints` o `persist_interaction_progress`. |

---

## 14. Decisiones todavía pendientes [PENDIENTE]

| # | Decisión | Recomendación [PROPUESTA] |
|---|---|---|
| P1 | Semántica de `InteractionSpec.all` (varias interacciones distintas ⇒ progreso persistido) | Mantenerla **reservada**; el caso de uso inicial se cubre con `any`. |
| P2 | `hint_seen` y persistencia de pistas | Reservado hasta decidirlo; las pistas se muestran según lo ya descubierto. |
| P3 | Pistas como ficheros propios o anidadas en la entidad | **Ficheros propios** (varias por entidad, grafo de dependencias, `applies_to` por versión). |
| P4 | Significado de `requires_hint` | Puerta de calidad editorial (≥1 pista publicada), distinta de `hint_seen`. **Confirmar.** |
| P5 | Comportamiento de UI para entidades `retired` y contenido exacto de la lápida | Decidirlo en la fase de UI; el pack ya las conserva. |
| P6 | Clave de identidad de **lugares** mientras no haya `area_id`/`ui_map_id` verificados | `name_only` explícito con `identity_quality`; sustituir al verificar. |
| P7 | División física del pack en ficheros | Decidir con medidas de tamaño en la Fase 17. |
| P8 | Qué hacer con `displayID` (atributo de mundo que usa el Codex) | Moverlo a la presencia por versión; confirmar el impacto en el Codex. |
| P9 | Política de marcas de tiempo en metadatos editoriales | Permitidas en `editorial.*` y `Provenance` (son entradas), **nunca** en el contenido generado. |
| P10 | Política de capacidades `unverified` (estricta vs permisiva) | Estricta para Forever; permisiva con aviso para Era ya validado. |
| P11 | Algoritmo de huella y política de «build más reciente gana» entre `client_verified` | SHA-256; **sin** auto-resolución: conflicto `drift` y decisión humana. |
| P12 | Si el catálogo de atributos de `creature` se amplía (y con qué fuentes) | Se cierra al diseñar los importadores. |
| — | **Licencia de Chronicle (D8)** | **PENDING_OWNER_DECISION**: este modelo no la fija; solo garantiza que lo desconocido no llega al pack (§5.2). |
| — | Hallazgos **en cliente** (D4–D7, D11–D14 de la 15.1) | Siguen pendientes de validación real (§15). |

## 15. Qué sigue pendiente de validar en cliente real [PENDIENTE EN CLIENTE]
Heredado de la 15.1 y relevante para este modelo: valores reales de detección de versión; qué eventos y qué unidad corresponden a cada tipo de interacción (**todas las capacidades `interaction.*` salvo lo ya observado**); nombres exactos de zonas/subzonas y NPC por idioma; `npcID` y existencia de cada personaje en Forever; si `UnitGUID("npc")` responde durante una interacción; presencia de valores secretos; `Interface` y `.toc` efectivos. **Este modelo no asume ninguno:** los representa como `unverified` o ausentes.

## 16. Verificación de esta fase
- **Ficheros:** `docs/fase16_data_model.md` y `docs/fase16_data_model_examples.md`. Nada más.
- **Código y tests:** `Chronicle/` y `tests/` sin cambios; los tests existentes se ejecutan solo para comprobarlo.
- **No hay** importadores, generador, soporte Forever, ZIP, merge ni cambios en `main`.
- **Nada está probado en WoW:** es diseño.
