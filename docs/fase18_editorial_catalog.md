# Fase 18 — Catálogo editorial de NPCs y flujo Candidate → Entity

Rama `fase18-editorial-catalog`, a partir de `4ff259193d06de8732b2c5fd1ff9eed761f5da94` (Fase 17 aprobada).
Implementa el diseño aprobado en Fases 15, 15.1, 16, 17 y 18.2. **Pendiente de revisión del supervisor.**

## 1. Flujo y reparto de responsabilidades

```
FUENTES → WORLD DATA → CANDIDATE → RECONCILIATION (Link / LinkDecision)
        → HUMAN EDITORIAL DECISION (CandidateDecision) → ENTITY
        → EDITORIAL CONTENT / BINDING → SHIP EVALUATION → GENERATED PACK

(completamente separado)  CONTEXTO GEOGRÁFICO + INTERACCIÓN REAL → DISCOVERY → ChronicleCharDB
```

| La máquina | La persona |
|---|---|
| encuentra, normaliza, relaciona, puntúa, ordena, valida, explica | decide qué es el mismo sujeto cuando hay ambigüedad; decide qué NPC merecen formar parte de Chronicle; crea la Entity; escribe/revisa el contenido; decide los bindings; revisa el resultado final |

**La máquina nunca crea una Entity.** Un test ejecuta la tubería completa y comprueba que `editorial/` queda intacto.

## 2. Los seis ejes (ninguno se infiere de otro)

| # | Eje | Dónde vive |
|---|---|---|
| 1 | Encontrado en una fuente | `sources/records/` → `world/<flavor>/…` |
| 2 | Candidate | `candidates/records/` |
| 3 | Considerado relevante | `CandidateDecision` (`shortlisted`) |
| 4 | Incluido editorialmente | `CandidateDecision accepted` + `Entity` |
| 5 | Técnicamente publicable | `generated/<flavor>/ship-report.json` (derivado) |
| 6 | Descubrible por el jugador | `Entity.discovery` (reglas) + progreso en `ChronicleCharDB` (runtime) |

Invariantes documentadas y probadas:

```
published != generated          accepted != published
published != technically_publishable   accepted != Binding
published != Binding válido     accepted != technically_publishable
published != source authorized  Candidate != TechRef != Entity
published != capability verified   matched != inclusión editorial
Binding != autorización de datos   Discovery != inclusión editorial
```

## 3. Candidate

> Propuesta de revisión de un sujeto técnico identificado en un flavor, acompañada de las evidencias, referencias técnicas y reconciliaciones que justifican su revisión.

`chronicle.candidate.record/1` (cambios **aditivos** respecto a Fase 16/17):

- Obligatorios: `subject`, `sources[]`, `evidence_summary`, `research`, `inputs_fingerprint`.
- Opcionales: `display`, `links[]`, `data_gaps`, `flags`.
- **Scoring opcional y en bloque:** `profile`, `signals`, `score`, `rank` (un perfil sin score o un rank sin score es inválido). Un Candidate sin score es válido.
- Sigue sin existir ningún campo de inclusión o decisión.
- `research.status` (`new`, `investigating`, `sufficient`, `blocked`) es el estado de **investigación**, no editorial. Las lagunas de datos van en el campo `data_gaps` ya existente.

### Regla D-02
Un Candidate solo puede originarse en fuentes con `usage.candidate_generation = true`. En el dataset real **solo `wow_client`** lo cumple: `warcraft_wiki` y `legacy_addon` siguen siendo investigación (visible en `data:explain`, nunca dentro del Candidate). Por eso los candidatos reales de Grelin y Sten **no tienen nombre** (`data_gaps: [display_name]`): el nombre procede del wiki.

### `data:candidates`
Genera candidatos **sin puntuar** a partir de World Data. Es una función pura de World Data (y de los enlaces propuestos). Nunca reescribe ni borra un candidato con perfil (puntuado): esos son entrada.
**No existe extractor de señales:** el cálculo real del score queda para una fase posterior (ver límites).

## 4. Link / LinkDecision

- `chronicle.world.link/1` (generado, `world/links/`): propuesta de la máquina entre dos referencias técnicas **distintas**. Estados de la máquina: `probable_match`, `conflict`, `unresolved` (el esquema **no admite `matched`**).
- `chronicle.editorial.link_decision/1` (humano, `editorial/link_decisions/`): `confirm` | `reject`, atada a la huella de la evidencia.
- **Estado efectivo:** `confirm` vigente ⇒ `matched`; `confirm` desfasada ⇒ vuelve a la propuesta y avisa (L-04); `reject` ⇒ la pareja deja de proponerse (`different_from`).

Reglas de la máquina (`rule_version` 1; solo cuentan datos respaldados por una fuente con `candidate_generation`):

| Situación | Resultado |
|---|---|
| Nombre solo | `unresolved` (nunca más) |
| Nombre + lugar compartido | `probable_match` |
| Nombre + lugar, pero nombres distintos en otro idioma compartido | `conflict` |
| Nombre genérico | `unresolved`, aunque compartan lugar |
| Nombre repetido (más de 2 en una versión, o más de 1 por versión entre versiones) | **no se propone enlace** |
| `displayID` | evidencia auxiliar: nunca identifica ni promueve; sin nombre, no hay enlace |
| Entre versiones | nunca `matched` automático |

> **`matched` significa** que las evidencias permiten reconciliar los registros como una misma referencia técnica/sujeto dentro del ámbito de la regla. **No** significa que Chronicle haya decidido incluir ese NPC. Un Link nunca crea una Entity.

La identidad por el **mismo TechRef** (varias fuentes sobre `creature:786`) se fusiona al normalizar y no necesita un Link.

## 5. CandidateDecision v2

`chronicle.editorial.candidate_decision/2`: `shortlisted | accepted | rejected | deferred`, con `policy_version` obligatorio.

| Decisión | Motivo codificado |
|---|---|
| `accepted` | `entity` + `inclusion_reasons[]` (≥1): `own_story`, `lore_presence`, `event_participant`, `relevant_quest`, `leadership`, `represents_group_or_place`, `zone_context`, `memorable` |
| `rejected` | `reject_reasons[]` (≥1): `generic_vendor`, `generic_guard`, `repeated_filler`, `common_creature`, `technical_only`, `no_interest`, `duplicate_of` (+ `duplicate_of`) |
| `deferred` | `defer_reason`: `insufficient_evidence`, `awaiting_source_policy`, `awaiting_client_data`, `awaiting_editorial_review` |

- `deferred + insufficient_evidence` = «aún no sabemos lo suficiente» ≠ `rejected`.
- **Los motivos técnicos del ship-report no pueden ser `reject_reasons` (D-04):** `source_not_authorized_for_pack`, `no_binding`, `tech_ref_missing`, `entity_absent`, `capability_unavailable`, `capability_unverified`, `blocked_by_conflict`, `not_applicable`. Un test comprueba que cubren todos los motivos de `REASON_ORDER`.
- Una sola decisión vigente por sujeto (D-09). No hay historial append-only (fuera de alcance).

## 6. Entity: `editorial.origin` y trazabilidad

`editorial.origin` (obligatorio en `npc`): `candidate` | `bootstrap`. Reservados y **no implementados**: `authored`, `legacy_migration`. No describe procedencia textual.

- `candidate`: existe al menos una `CandidateDecision accepted` que apunta a la Entity.
- `bootstrap`: creada por la infraestructura (Fase 17) para validar el pipeline. **No afirma ninguna decisión editorial.**

**Trazabilidad auditable** (`data:explain` la recorre):

```
Entity ──(CandidateDecision.entity)──► CandidateDecision ──► Candidate ──► World Data ──► Sources
```
El vínculo principal es `CandidateDecision.entity`; `origin: candidate` es una validación de esa relación, no una segunda fuente de verdad. No se copia el Candidate ni el TechRef a la Entity.

| Regla | Comprobación |
|---|---|
| D-01 | `origin: candidate` ⇒ existe ≥1 decisión `accepted` hacia esa Entity (**error**) |
| D-03 | la decisión `accepted` apunta a una Entity existente con `origin: candidate` y su flavor está en `applies_to` (**error**) |
| D-05 | un mismo TechRef no puede estar `accepted` hacia dos Entities (**error**) |
| D-06 | un Binding `accepted` debería coincidir con un TechRef de alguna decisión (**aviso**) |
| D-07 | `evidence_fingerprint` ≠ evidencia actual del candidato (**aviso**: la decisión histórica no se invalida al regenerar candidatos) |
| D-08 | `origin: bootstrap` ⇒ no puede estar en `review` ni `published` (**error**, regla editorial de `validate.js`) |

### Creación de una Entity
Una persona escribe, en el mismo cambio, la `CandidateDecision accepted` y la Entity (`origin: candidate`, **`status: drafting`**). No nace en `review`: `accepted` significa «este sujeto merece estar en Chronicle», no «su contenido está terminado».

## 7. Separación editorial / ship

| Dimensión | Valores | Quién |
|---|---|---|
| **A. Estado editorial** de la Entity | `drafting`, `review`, `published`, `retired` (+ `accepted`, heredado de Fase 16, no se usa ni se elimina) | persona |
| **B. Evaluación técnica** | `available` o los motivos de `ship.js` | generador |

- `Entity.status = published` significa «aprobada editorialmente para formar parte de Chronicle». **No** significa que esté en el Generated Pack.
- `ship.js` **no lee ni interpreta** `status`, `origin`, `drafting`, `review`, `published` ni `bootstrap`, y no hay motivos técnicos como `not_published` o `not_editorially_reviewed`. Un test estático y uno de comportamiento (la evaluación es idéntica para cualquier estado/origen) lo garantizan.
- `pack.js` sí filtra la **entrada** por estado editorial (solo `published` y las `retired` como lápida), como ya estaba aprobado. Una entidad `drafting`/`review` simplemente no se evalúa.
- Transiciones editoriales (humanas): `drafting → review → published`; `published → drafting`. Binding, autorización de fuentes, capabilities y ship-report **no** las determinan.

## 8. Generador y Candidate Data

El generador **no lee Candidate Data**. `data:generate` y `data:check` validan con ámbito `publish` (no cargan `candidates/`), de modo que ni siquiera un `candidates/` corrupto los afecta. Tests: el pack es idéntico byte a byte con y sin `candidates/` (y con basura dentro) y ninguna huella de candidato entra en el pack.

## 9. Scoring

- Reproducible, versionado y solo para **ordenar** la cola. No acepta, rechaza, publica ni excluye.
- `ScoringProfile.approval`: `illustrative | proposed | approved`. **Ningún perfil puede ser `approved`** (C-05). El perfil de fixture es `illustrative`. No hay perfil real, ni pesos, ni calibración.
- `data:queue` muestra siempre la etiqueta del perfil (`ILUSTRATIVO — NO APROBADO`, `PROPUESTA — pendiente de aprobación`).

## 10. Herramientas de solo lectura

```bash
npm run data:queue                     # candidatos pendientes de revisión
npm run data:queue -- --all --flavor era
npm run data:explain -- npc:grelin_whitebeard
npm run data:explain -- cand:era:creature:786
```

- **`data:queue`:** candidato, flavor, TechRef, score, perfil y aprobación, orden usado, decisión previa, Entity asociada y `bootstrap_entity`. Sin score: **«sin scoring — orden técnico por TechRef»**, y lo declara como no prioritario.
- **`data:explain <id>`** (entidad, candidato o enlace): los 17 apartados (candidato, World Data, fuentes y su `candidate_generation`, evidencias, conflictos, investigación, score, decisión, motivos, `policy_version`, Entity, `origin`, `status`, Binding por flavor, estado técnico, fuentes implicadas).
  Para una entidad que el generador no evalúa (`drafting`/`review`) ejecuta la evaluación pura de `ship.js` y la muestra como **«evaluación técnica hipotética — no forma parte del Generated Pack»**. Para una `published` muestra el resultado real del ship-report.
- Ninguna escribe ficheros (tests con instantánea del directorio).

## 11. Workflow

| # | Paso | Quién | Comando |
|---|---|---|---|
| 1 | Importar fuentes | persona | `sources/…` |
| 2 | Normalizar (World Data y enlaces) | máquina | `data:normalize` |
| 3 | Detectar candidatos | máquina | `data:candidates` |
| 4 | Reconciliar | máquina propone, **persona decide** | `LinkDecision` |
| 5 | Puntuar | máquina (no hay extractor aún) | — |
| 6 | Revisar candidato | **persona** | `data:queue`, `data:explain` |
| 7 | Decidir editorialmente | **persona** | `CandidateDecision` |
| 8 | Textos y pista | **persona** | `editorial/text`, `editorial/hints` |
| 9 | Binding | **persona** | `editorial/bindings/…` |
| 10 | Validar | máquina | `data:validate` |
| 11 | Generar y comprobar | máquina; persona revisa el diff | `data:generate`, `data:check` |

`data:pipeline` encadena normalize → candidates → validate → generate → check. `data:all` lo ejecuta sobre el dataset real y el de fixtures.

## 12. Hints

Se mantienen las reglas (escritas por humanos, sin coordenadas ni GPS, sin revelar el nombre del NPC, sin ciclos ni dependencias inexistentes). Las pistas nuevas llevan `text_origin: original` (**obligatorio**; no es `Entity.editorial.origin`). Migrados los 2 hints de fixture.

## 13. Grelin y Sten

Migrados a `origin: bootstrap`, `status: drafting`, **conservando su Binding** (786 / 658). No existe ninguna `CandidateDecision` para ellos ni se les llama «original».

```
World Data → Candidate (sin puntuar, solo wow_client, sin nombre) → pendiente de revisión editorial
```

| Dimensión | Estado |
|---|---|
| Editorial | pendiente de revisión; no hay decisión |
| Técnica | el generador no las evalúa; la evaluación hipotética sigue siendo `source_not_authorized_for_pack` (D8) y `capability_unverified:interaction.gossip` |

**Consecuencia:** el ship-report real ya no lista a Grelin y Sten (el pack real pasa de 5 a 3 entidades; `content_revision` real `cdfd4d12…`). La evidencia de que quedan excluidas por D8 se ve ahora con `data:explain` y en los tests (vía `shipEntity`). Los tests de Fase 17 que leían esa evidencia del ship-report se adaptaron a esta vía.
Los lugares bootstrap (`continent:eastern_kingdoms`, `zone:dun_morogh`, `subzone:coldridge_valley`) no se han tocado.

## 14. Fixtures (todo inventado)

Dataset `pipeline/fixtures/authorized/`: fuente autorizada → Candidate → `Link probable_match` (era 90004 ↔ fixture_alt 90008) → `LinkDecision confirm` (efectivo `matched`) → `CandidateDecision accepted` → Entity `origin: candidate` → Binding → pista (`text_origin: original`) → `Generated Pack available=true`.
Contraejemplos: `rejected` (candidato puntuado con perfil ilustrativo), `deferred + insufficient_evidence`, `accepted` sin Binding (`npc:fixture_pending_example`, `drafting`), fuente no autorizada, conflicto, retirada y una entidad `bootstrap` en `drafting` (D-08).

## 15. Interpretaciones y límites (no resueltos aquí)

1. **`data:candidates`** no figuraba entre las órdenes pedidas; se añade porque sin él no existen candidatos reales (paso 3 del workflow aprobado). Solo genera candidatos sin puntuar.
2. **No hay extractor de scoring.** Los candidatos puntuados son ficheros de entrada (uno ilustrativo en fixtures). Calibración, pesos y señales reales: fase posterior.
3. **`research.data_gaps`:** las lagunas se guardan en el campo `data_gaps` ya existente, no duplicado dentro de `research`.
4. **Menciones sin TechRef** (p. ej. una fuente que solo da el nombre) **no se modelan**: un Link une dos TechRef existentes. El lugar de una criatura se toma de su campo `places` (referencias de área), única evidencia disponible; el dataset real no tiene ninguna.
5. **Nombres genéricos:** lista inicial en `rules.js` (`GENERIC_NAME_NOUNS`), **propuesta pendiente de aprobación**.
6. D-04 se valida en `validate.js` (mensaje claro) y no con un `enum` del esquema; el resto de enumeraciones sí están en el esquema.
7. Los nombres de fichero de las decisiones siguen la convención `<flavor>__<kind>__<id>.yaml` pero no se imponen (se detecta la duplicidad por sujeto, D-09).
8. `origin` solo es obligatorio en `npc`.
9. Quedan fuera: D8, Forever, `ClientAdapter` cableado, detección de interacciones, nuevas fuentes/NPC/datos reales, `mobility`/`also_found_in`/`flavors.<id>.located_in`, `suggested_interaction`, `origin: authored|legacy_migration`, historial append-only, eliminar `Entity.status = accepted`, casos geográficos especiales, calibración del score.
