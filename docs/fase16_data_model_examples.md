# Fase 16 — Ejemplos del modelo de datos (documento auxiliar)

Complementa [`fase16_data_model.md`](fase16_data_model.md). **Justificación de este documento aparte:** los ejemplos completos (YAML, JSON y Lua) son largos y romperían la lectura del modelo; aquí se muestra cómo se ven los esquemas con datos concretos.

## Reglas de honestidad de los ejemplos
1. **Datos reales de WoW:** solo los **ya verificados o ya presentes en el repositorio**: `npcID` 786 (Grelin Whitebeard) y 658 (Sten Stoutarm) en Classic Era (descubiertos por GUID en el cliente real en la Fase 14), la subzona `Valle de Crestanevada` (observada con `/chronicle where`), y los `displayID` heredados del addon original (**no contrastados**, Fase 11). Las dos observaciones de `npcID` 705 y 1354 (`not_enabled`) son las que mostró `/chronicle npc` en la Fase 14.
2. **Todo valor de Forever es «desconocido»** (campo ausente o `unverified`). **No se inventa ningún dato de Forever.**
3. Para demostrar el caso «`npcID` distinto por versión» se usa un **FIXTURE SINTÉTICO** (`npc:fixture_*`, IDs `900xx`). **Sus valores no son datos de WoW**: son inventados a propósito para probar el esquema, y cualquier validador debe tratarlos como tales.
4. **Los textos editoriales (lore, pistas) son marcadores** (`TEXTO_EDITORIAL_PENDIENTE`): redactarlos es trabajo editorial, no de esta fase.
5. Los pesos y puntuaciones de candidatos son **ilustrativos** y **no son definitivos**.
6. Los separadores `---` dentro de un mismo bloque YAML solo sirven para **presentar varios documentos juntos**; en el repositorio real **cada documento va en su propio fichero**.
7. **Comprobación sintáctica de estos ejemplos:** los 3 bloques Lua cargan y se ejecutan en el intérprete de los tests (fengari) y no usan construcciones ajenas a Lua 5.1; los 8 bloques JSON son JSON válido. **Los bloques YAML NO se han validado automáticamente** (no hay *parser* YAML en el entorno y no se instalan dependencias): se validarán con el *parser* elegido en la Fase 17.
8. **Coherencia con la política de fuentes (§5.2 y §9.2 del documento principal):** ningún ejemplo de *pack* contiene un dato cuya única procedencia sea una fuente sin `usage.generated_data = true`. **Con D8 pendiente (`PENDING_OWNER_DECISION`) ninguna fuente real lo tiene**, así que los datos reales (`npcID`, nombres, `display_id`) aparecen como **World Data / investigación**, con su procedencia, y **no** en ningún *pack*. Los únicos ejemplos con `available = true` usan una **fuente sintética autorizada (FIXTURE)**.

---

## 1. Capa editorial (YAML)

### 1.1 `Entity` — un NPC real: `npc:grelin_whitebeard`
```yaml
schema: "chronicle.editorial.entity/1"
id: "npc:grelin_whitebeard"
type: npc
status: published                 # accepted | drafting | review | published | retired
importance: major                 # editorial (NO es el score)
categories: ["superviviente", "gnomeregan"]
located_in: "subzone:coldridge_valley"
related_to: ["npc:senir_whitebeard"]
applies_to: [era, forever]        # INTENCIÓN: la historia debería cubrir ambas versiones
requires_hint: auto               # major => true (puerta de calidad editorial)

discovery:
  method: interaction
  # requirements omitido: el generador materializa place_discovered de la ZONA ancestro
  # de located_in (subzone:coldridge_valley -> zone:dun_morogh) y lo marca derived: true
  interaction:
    type: gossip

editorial:
  author: "ismael"
  # reviewer y reviewed_at: opcionales en la fase inicial
```
Qué **no** aparece (a propósito): `npcID`, `displayID`, nombres del cliente, coordenadas y textos.

### 1.2 `Entity` — con requisito estricto y varias interacciones (sintético)
```yaml
schema: "chronicle.editorial.entity/1"
id: "npc:fixture_example_keeper"          # FIXTURE SINTÉTICO — no es un NPC de WoW
type: npc
status: published
importance: standard
located_in: "subzone:fixture_hollow"      # FIXTURE
applies_to: [era, forever]
requires_hint: false

discovery:
  method: interaction
  requirements:
    all:
      - place_discovered: { id: "subzone:fixture_hollow", strict: true }   # estricto: solo si su reconocimiento está verificado
      - entity_discovered: { id: "npc:fixture_example_elder" }             # dependencia narrativa
  interaction:
    any: [ { type: gossip }, { type: quest } ]                             # basta una de las dos

flavors:
  forever:
    discovery:                          # ANULACIÓN completa para esa versión (no se fusiona con la base)
      method: interaction
      interaction: { type: quest }

editorial:
  author: "ismael"
  notes: "Fixture para probar anulaciones por versión."
```

### 1.3 `Entity` — un lugar real
```yaml
schema: "chronicle.editorial.entity/1"
id: "subzone:coldridge_valley"
type: subzone
status: published
parent: "zone:dun_morogh"                 # igual que Schema.lua hoy
applies_to: [era]
discovery: { method: place_enter }        # lo hace ZoneDiscovery (sin cambios de semántica)
editorial: { author: "ismael" }
```

### 1.4 `Binding` — Classic Era (real) y Forever (ausente)
```yaml
schema: "chronicle.editorial.binding/1"
entity: "npc:grelin_whitebeard"
flavor: era
status: accepted
tech_refs:
  - { flavor: era, kind: creature, id: 786 }
evidence: []                             # aún no existe herramienta de captura: sin observaciones registradas
attested:
  by: "supervisor"
  method: manual_review                   # prueba manual en el cliente (Fase 14), no una captura registrada
  at: "2026-10"
notes: "npcID descubierto por GUID en WoW Classic Era (Fase 14); coincide con Warcraft Wiki."
```
> Este binding **por sí solo no basta para publicar**: atestigua la decisión editorial, pero el dato técnico (`TechRef` 786) necesita respaldo **autorizado** en World Data (§2.3). Hoy no lo tiene: ver §5 (`source_not_authorized_for_pack`).

**Forever: no existe fichero de binding.** Resultado derivado: `no_binding` ⇒ **no se publica en Forever**; la entidad, su lore y sus pistas quedan intactos. (Si se quisiera dejarlo explícito, un binding con `status: unavailable` significaría «sabemos que no existe»; **no** es el caso: simplemente aún no hay datos.)

### 1.5 `Binding` de un lugar: sucesor de `Aliases.lua`
```yaml
schema: "chronicle.editorial.binding/1"
entity: "subzone:coldridge_valley"
flavor: era
status: accepted
places:
  - locale: esES
    api: subzone_text                     # lo que devuelve la API de subzona del cliente
    string: "Valle de Crestanevada"       # EXACTAMENTE lo que mostró /chronicle where
    evidence: []
    confidence: client_verified
attested: { by: "supervisor", method: manual_review, at: "2026-10" }
```
> El índice `names` de un *pack* solo incluiría esta cadena si su procedencia fuera **elegible** (§5.2 del documento principal); hoy `wow_client` no está autorizada para el *pack*, así que **no se incluiría** (ver §4.1).

Mapeo de las marcas actuales de `Aliases.lua`: `[C]`→`client_verified`, `[W]`/`[O]`/`[J]`→`source_reported`. Ejemplo `[W]` (real, **sin verificar en el cliente**):
```yaml
schema: "chronicle.editorial.binding/1"
entity: "subzone:coldridge_pass"
flavor: era
status: accepted
places:
  - { locale: esES, api: subzone_text, string: "Desfiladero de Crestanevada", evidence: [], confidence: source_reported }
attested: { by: "ismael", method: source_review, at: "2026-10" }
```

### 1.6 Binding sintético: un NPC con `npcID` distinto por versión (FIXTURE)
```yaml
# FIXTURE SINTÉTICO — los IDs 90001 y 90002 son INVENTADOS para probar el esquema.
schema: "chronicle.editorial.binding/1"
entity: "npc:fixture_example_keeper"
flavor: era
status: accepted
tech_refs: [ { flavor: era, kind: creature, id: 90001 } ]
attested: { by: "fixture", method: manual_review, at: "2026-10" }
---
schema: "chronicle.editorial.binding/1"
entity: "npc:fixture_example_keeper"   # LA MISMA entidad editorial
flavor: forever
status: accepted
tech_refs: [ { flavor: forever, kind: creature, id: 90002 } ]   # OTRO identificador técnico
attested: { by: "fixture", method: manual_review, at: "2026-10" }
```
*(Un fichero real tendría un documento por fichero; aquí se separan solo para leer mejor.)* **No hay dos entidades editoriales**: hay una, con dos presencias.

### 1.7 `Hint` — cadena estructurada para `npc:grelin_whitebeard`
Los textos son **marcadores**; lo que se ilustra es la estructura.
```yaml
schema: "chronicle.editorial.hint/1"
id: "hint:grelin_whitebeard_1"
target: "npc:grelin_whitebeard"
kind: narrative
necessity: required
tier: 1
reveals_when:
  place_discovered: { id: "zone:dun_morogh" }       # visible al descubrir la zona
related_to: ["npc:senir_whitebeard"]                # relación narrativa, SIN coordenadas
text: "hint:grelin_whitebeard_1"                    # clave en Text; nunca texto inline
status: published
editorial: { author: "ismael" }
---
schema: "chronicle.editorial.hint/1"
id: "hint:grelin_whitebeard_2"
target: "npc:grelin_whitebeard"
kind: contextual
necessity: optional
tier: 2
depends_on: ["hint:grelin_whitebeard_1"]            # solo disponible si la 1 lo está
reveals_when:
  all:
    - place_discovered: { id: "zone:dun_morogh" }
    - entity_discovered: { id: "npc:sten_stoutarm" }  # se abre tras conocer a otro personaje
text: "hint:grelin_whitebeard_2"
status: draft
editorial: { author: "ismael" }
```
`Text` correspondiente (idioma editorial `esES`):
```yaml
schema: "chronicle.editorial.text/1"
locale: esES
entries:
  "npc:grelin_whitebeard":
    title: "TEXTO_EDITORIAL_PENDIENTE"
    description: "TEXTO_EDITORIAL_PENDIENTE"
    body: "TEXTO_EDITORIAL_PENDIENTE"
  "hint:grelin_whitebeard_1":
    description: "TEXTO_EDITORIAL_PENDIENTE"
```

### 1.8 Ejemplos de lo que el lint rechaza (textos sintéticos)
| Texto de una pista (sintético) | Regla | Resultado |
|---|---|---|
| «Ve a la posición 12, 34 del mapa» | Sin coordenadas / GPS | rechazada |
| «Es el gnomo llamado *Fixture Keeper*» (nombre de la entidad objetivo) | Sin revelar el nombre | rechazada |
| `depends_on: [hint:fixture_a]` y `hint:fixture_a` depende de la primera | Sin ciclos | rechazada |
| `depends_on: [hint:no_existe]` | Sin dependencias inexistentes | rechazada |
| Entidad `importance: major` con `requires_hint: auto` y **ninguna** pista publicada | `requires_hint` | no se puede publicar |

### 1.9 `CandidateDecision` y `Override`
```yaml
schema: "chronicle.editorial.candidate_decision/1"
subject: { flavor: era, kind: creature, id: 90003 }     # FIXTURE
decision: rejected
reason: "Vendedor genérico sin relevancia narrativa (fixture)."
evidence_fingerprint: "sha256:EJEMPLO"
resurface: { policy: on_signal_change, threshold: 20 }
by: "ismael"
at: "2026-10"
```
```yaml
schema: "chronicle.editorial.override/1"
id: "ovr:fixture_keeper_name_enus"
target: { conflict: "conf:EJEMPLO" }                     # FIXTURE
decision: { prefer_claim: { source: "wow_client", source_version: "fixture", method: manual } }
reason: "El nombre observado en el cliente prevalece sobre la fuente comunitaria (fixture)."
bound_to_fingerprint: "sha256:EJEMPLO"                   # si las fuentes cambian, el conflicto VUELVE a abrirse
author: "ismael"
created_at: "2026-10"
```

### 1.10 `Entity` retirada y su lápida (FIXTURE)
```yaml
schema: "chronicle.editorial.entity/1"
id: "npc:fixture_retired_example"       # FIXTURE
type: npc
status: retired
located_in: "subzone:fixture_hollow"
applies_to: []
retired:
  reason: "Fixture: entidad retirada para probar que el Registry la sigue conociendo."
  since: "2026-10"
  superseded_by: "npc:fixture_example_keeper"
editorial: { author: "ismael" }
```

---

## 2. World Data (JSON canónico)

### 2.1 Manifiestos de fuentes (YAML, configuración)
```yaml
schema: "chronicle.world.source/1"
id: wow_client
name: "Observaciones del cliente real (captura propia)"
kind: client_capture
origin_group: wow_client
trust_tier: 2
applicable_flavors: [era, forever]
obtained: { method: capture, version: "por build", retrieved_at: null }
license:
  status: known
  summary: "Observaciones de nuestro propio cliente; el contenido del juego es de Blizzard (política de addons no revisada aquí)."
  redistribution: unknown
  derived_data: unknown
usage: { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: false }
status: active
```
> `usage.generated_data` está en `false`: **esta fuente no puede aportar datos al *pack*** mientras la licencia de Chronicle sea **PENDING_OWNER_DECISION**. Activarlo exigiría `license` conocida, `redistribution`/`derived_data` distintos de `unknown` y `owner_approval`, y **no se decide aquí**. Sigue siendo válida para resolver conflictos, validar y generar candidatos: **autorización para el pack ≠ confianza** (§5.2 del documento principal).
```yaml
schema: "chronicle.world.source/1"
id: warcraft_wiki
name: "Warcraft Wiki (warcraft.wiki.gg)"
kind: wiki
origin_group: warcraft_wiki
trust_tier: 6
applicable_flavors: [era]
obtained: { method: manual_download, url: "https://warcraft.wiki.gg/", version: "consulta manual", retrieved_at: "2026-10-04" }
license:
  status: known
  identifier: "CC-BY-SA-4.0"
  summary: "Texto bajo CC BY-SA 4.0; la propiedad intelectual de Warcraft sigue siendo de Blizzard."
  redistribution: restricted           # atribución + compartir igual
  derived_data: restricted
  attribution: "Warcraft Wiki (CC BY-SA 4.0), página y fecha"
usage: { research: true, contrast: true, local_validation: true, candidate_generation: false, generated_data: false }
status: research_only
```
```yaml
schema: "chronicle.world.source/1"
id: cmangos_classic_db
name: "CMaNGOS classic-db"
kind: server_emulator_db
origin_group: mangos_lineage
trust_tier: 5
applicable_flavors: [era]               # contenido 1.12: NO aplica a forever
obtained: { method: git_clone, url: "https://github.com/cmangos/classic-db", version: "<commit fijado>" }
license:
  status: known
  identifier: "GPL-3.0"
  summary: "Código/BD GPL-3.0; su COPYRIGHT.md reconoce que el contenido de WoW es de Blizzard y no concede licencia de redistribución."
  redistribution: unknown
  derived_data: unknown
usage: { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: false }
status: research_only
```

```yaml
schema: "chronicle.world.source/1"
id: legacy_addon
name: "Addon Chronicle original (datos heredados)"
kind: other
origin_group: legacy_addon
trust_tier: 6
applicable_flavors: [era]
obtained: { method: manual_download, version: "addon original (solo lectura)" }
license:
  status: unknown
  summary: "Datos heredados cuyo origen declarado (Wowhead Classic) no tiene condiciones verificadas; los displayID no se han contrastado (Fase 11)."
  redistribution: unknown
  derived_data: unknown
usage: { research: true, contrast: true, local_validation: true, candidate_generation: false, generated_data: false }
status: research_only
```
```yaml
# FIXTURE SINTÉTICO. NO es una fuente real ni una decisión de licencia ni una aprobación real.
# Existe solo para poder ilustrar un pack con available = true.
schema: "chronicle.world.source/1"
id: fixture_authorized_source
name: "Fuente sintética autorizada (fixture)"
kind: other
origin_group: fixture
trust_tier: 6
applicable_flavors: [era, forever]
obtained: { method: manual_download, version: "fixture" }
license: { status: known, summary: "Fixture: licencia ficticia para probar el esquema.", redistribution: allowed, derived_data: allowed }
usage: { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: true }
owner_approval: { by: "fixture", scope: "solo fixtures; no es una aprobación real" }
status: active
```

### 2.2 `Observation` — reconstrucción de las capturas reales de la Fase 14
Las dos líneas que mostró `/chronicle npc` (unidades **no habilitadas**). El build y el `Interface` no se registraron entonces: se declaran como `unregistered` (**una herramienta de captura real los registraría**).
```json
{
  "schema": "chronicle.world.observation/1",
  "id": "obs:EJEMPLO_A",
  "flavor": "era",
  "locale": "esES",
  "client": { "build": "unregistered", "interface": "unregistered", "signals": {} },
  "captured_with": { "tool": "chronicle_npc_command", "version": "fase14" },
  "observed_at": "2026-10",
  "restricted_context": false,
  "kind": "interaction",
  "payload": {
    "unit": { "unit_type": "creature", "npc_id": 705, "secret": false },
    "raw_event": "NAME_PLATE_UNIT_ADDED",
    "unit_token": "nameplate2"
  }
}
```
```json
{
  "schema": "chronicle.world.observation/1",
  "id": "obs:EJEMPLO_B",
  "flavor": "era",
  "locale": "esES",
  "client": { "build": "unregistered", "interface": "unregistered", "signals": {} },
  "captured_with": { "tool": "chronicle_npc_command", "version": "fase14" },
  "observed_at": "2026-10",
  "restricted_context": false,
  "kind": "interaction",
  "payload": {
    "unit": { "unit_type": "creature", "npc_id": 1354, "secret": false },
    "raw_event": "UPDATE_MOUSEOVER_UNIT",
    "unit_token": "mouseover"
  }
}
```
Observaciones: (1) `kind: interaction` aquí describe un **evento observado**; **no** afirma que sea una «interacción de descubrimiento» (`interaction_hint` ausente a propósito); (2) no hay `name`: no se registró; (3) el GUID crudo **no** se guarda; (4) un valor secreto se representaría con `"secret": true` y **sin** `npc_id`:
```json
{ "unit": { "unit_type": "creature", "secret": true } }
```

### 2.3 `WorldEntity` — `creature 786` en Classic Era (real)
```json
{
  "schema": "chronicle.world.entity/1",
  "ref": { "flavor": "era", "kind": "creature", "id": 786 },
  "exists": {
    "claims": [
      { "value": "present", "confidence": "client_verified",
        "provenance": { "source": "wow_client", "source_version": "Classic Era (build no registrado)", "method": "manual", "by": "supervisor", "locator": "Fase 14: descubierto por GUID" } }
    ],
    "resolved": { "value": "present", "status": "resolved", "rule": "single_claim" }
  },
  "names": {
    "enUS": {
      "claims": [
        { "value": "Grelin Whitebeard", "confidence": "source_reported",
          "provenance": { "source": "warcraft_wiki", "source_version": "consulta manual", "method": "manual", "by": "ismael", "locator": "página Grelin Whitebeard" } }
      ],
      "resolved": { "value": "Grelin Whitebeard", "status": "resolved", "rule": "single_claim" }
    }
  },
  "attributes": {
    "display_id": {
      "claims": [
        { "value": 1354, "confidence": "source_reported",
          "provenance": { "source": "legacy_addon", "source_version": "addon original", "method": "import", "locator": "Data/NPCs (heredado; NO contrastado, Fase 11)" } }
      ],
      "resolved": { "value": 1354, "status": "resolved", "rule": "single_claim" }
    }
  }
}
```
**Qué muestra:** el `names.esES` **no existe** (no se capturó el nombre que devuelve el cliente en español): es «desconocido», no un valor inventado. `spawns` está ausente: **las coordenadas no son obligatorias**.

**Elegibilidad para el *pack* (la calcula el generador; no se guarda en este registro):**

| Campo | *Claims* (fuente) | ¿Fuente con `usage.generated_data = true`? | ¿Elegible para el *pack*? |
|---|---|---|---|
| `exists` | `wow_client` (`client_verified`) | **No** (`false`; D8 pendiente) | **No** |
| `names.enUS` | `warcraft_wiki` (`source_reported`) | **No** (`research_only`) | **No** |
| `attributes.display_id` | `legacy_addon` (`source_reported`) | **No** (`research_only`) | **No** |

Los tres son **World Data válido, con su procedencia** (sirven para validar, contrastar y generar candidatos), pero **ninguno puede viajar a un *pack*** con la política actual: la confianza (`client_verified`) **no** sustituye a la autorización. `display_id` seguirá fuera mientras su única procedencia sea `legacy_addon`. Qué decisión del propietario cambiaría esto: ver §9.5 del documento principal (no se decide aquí).

### 2.4 Conflicto y resolución (FIXTURE)
Dos fuentes dan nombres distintos para el mismo `TechRef` y mismo locale: **no se elige en silencio**.
```json
{
  "schema": "chronicle.world.conflict/1",
  "id": "conf:EJEMPLO",
  "scope": "world",
  "class": "identity",
  "severity": "blocking",
  "status": "open",
  "subject": { "flavor": "era", "kind": "creature", "id": 90001 },
  "field": "names.enUS",
  "claims": [
    { "value": "Fixture Keeper", "confidence": "source_reported",
      "provenance": { "source": "fixture_source_a", "source_version": "v1", "method": "import" } },
    { "value": "Fixture Warden", "confidence": "source_reported",
      "provenance": { "source": "fixture_source_b", "source_version": "v1", "method": "import" } }
  ],
  "fingerprint": "sha256:EJEMPLO",
  "blocks_publish": true
}
```
Con el `Override` de §1.9 (que prefiere la afirmación de `wow_client`), el campo pasa a `{ "status": "overridden", "rule": "override", "override": "ovr:fixture_keeper_name_enus" }` y el conflicto a `overridden`. Si **cambia** la huella de las fuentes, el conflicto pasa a `stale` y **vuelve a abrirse**.

### 2.5 `ClientProfile` — capacidades por cliente (FIXTURE para Forever)
```json
{
  "schema": "chronicle.world.client_profile/1",
  "flavor": "forever",
  "build": "unregistered",
  "interface": "unregistered",
  "signals": {},
  "capabilities": {
    "interaction.gossip":      { "status": "unverified", "evidence": [] },
    "interaction.quest":       { "status": "unverified", "evidence": [] },
    "unit_identity.target":    { "status": "unverified", "evidence": [] },
    "secret_values.active":    { "status": "unverified", "evidence": [] }
  }
}
```
Todo `unverified`: **ningún valor de Forever se ha observado**. Para Era, `unit_identity.target` y `unit_identity.mouseover` podrían marcarse `verified` con una `Observation` de ese build; **`interaction.gossip` sigue `unverified`** (la Fase 14 verificó la identificación, no la interacción).

---

## 3. Candidate Data (JSON canónico y YAML)

### 3.1 `ScoringProfile` (YAML; pesos ilustrativos, NO definitivos)
```yaml
schema: "chronicle.candidate.scoring_profile/1"
id: "dun_morogh_pilot"
version: 1
flavors: [era]
signals:
  - { id: quest_relevance,   weight: 30,  enabled: true }
  - { id: lore_relation,     weight: 25,  enabled: true }
  - { id: faction_relevance, weight: 15,  enabled: true }
  - { id: unique_role,       weight: 20,  enabled: true }
  - { id: generic_vendor,    weight: -40, enabled: true }
queue: { max_items: 50 }               # SOLO dimensiona la cola de revisión
calibration:
  notes: "Se calibrará con el piloto de Dun Morogh (casos positivos y negativos conocidos)."
  reference_positive: [ { flavor: era, kind: creature, id: 786 }, { flavor: era, kind: creature, id: 658 } ]
  reference_negative: []
  attested_by: "ismael"
author: "ismael"
```

### 3.2 `Candidate` (FIXTURE; valores inventados)
```json
{
  "schema": "chronicle.candidate.record/1",
  "id": "cand:era:creature:90003",
  "flavor": "era",
  "subject": { "flavor": "era", "kind": "creature", "id": 90003 },
  "display": { "names": { "enUS": "Fixture Vendor" } },
  "profile": { "id": "dun_morogh_pilot", "version": 1 },
  "signals": [
    { "id": "quest_relevance", "raw": 0, "normalized": 0.0, "weight": 30,  "contribution": 0,   "evidence": [] },
    { "id": "generic_vendor",  "raw": 1, "normalized": 1.0, "weight": -40, "contribution": -40, "evidence": [] }
  ],
  "score": { "total": -40 },
  "rank": 51,
  "flags": ["generic_name_pattern"],
  "data_gaps": ["lore_relation"],
  "inputs_fingerprint": "sha256:EJEMPLO"
}
```
Comprobaciones del esquema: `contribution = weight × normalized`; `score.total = Σ contribuciones`; **no existe** ningún campo de inclusión; `data_gaps` registra lo que no se pudo calcular (**no se asume 0**).

---

## 4. Generated Data (Lua 5.1)

### 4.1 Pack de Classic Era **bajo la política actual (D8 pendiente)**
Con D8 en `PENDING_OWNER_DECISION`, ninguna fuente real tiene `usage.generated_data = true` (§2.1), así que **ningún dato técnico real es elegible** (§5.2 del documento principal). El pack solo contiene lo **editorial propio**; la presencia técnica sale **no disponible**, sin `tech`, sin `display_id`, sin nombres observados y sin reglas de descubrimiento activas.
```lua
-- GENERADO. NO EDITAR A MANO. (Chronicle pack, flavor era) ESTADO ACTUAL: D8 pendiente.
-- Extracto: se omiten las entidades ancestras (zone:dun_morogh, continent:eastern_kingdoms...) y el resto del catalogo.
Chronicle.Pack = {
    header = {
        pack_schema = 1,
        flavor = "era",
        client = { interface = { 11507, 11509 } },
        content_revision = "sha256:EJEMPLO",
        generated_from = { world = "sha256:EJEMPLO", editorial = "sha256:EJEMPLO", generator = "0.0.0-ejemplo" },
        counts = { entities = 3, published = 3, available = 0, retired = 0, hints = 0 },
        features = { persist_hints = false, persist_interaction_progress = false },
        locales = { "esES" },
    },

    entities = {
        ["npc:grelin_whitebeard"] = { type = "npc", status = "published", importance = "major", located_in = "subzone:coldridge_valley", related_to = { "npc:senir_whitebeard" } },
        ["npc:sten_stoutarm"] = { type = "npc", status = "published", importance = "standard", located_in = "subzone:coldridge_valley" },
        ["subzone:coldridge_valley"] = { type = "subzone", status = "published", parent = "zone:dun_morogh" },
    },

    -- Sin datos tecnicos: ninguno es elegible (tech vacio, sin attributes).
    presence = {
        ["npc:grelin_whitebeard"] = { available = false, reason = "source_not_authorized_for_pack", tech = {} },
        ["npc:sten_stoutarm"] = { available = false, reason = "source_not_authorized_for_pack", tech = {} },
        ["subzone:coldridge_valley"] = { available = false, reason = "source_not_authorized_for_pack", tech = {} },
    },

    discovery = {},   -- solo para entidades disponibles: ninguna
    hints = {},       -- las pistas de entidades no disponibles no se incluyen (el contenido editorial queda intacto)
    names = {},       -- sin cadenas elegibles (ver 1.5 y 2.3)
    tombstones = {},
}
```
**Notas:**
- **`display_id` no aparece:** su única procedencia es `legacy_addon` (`research_only`). Sigue siendo World Data de investigación (§2.3), pero no puede entrar al pack.
- **Esto no cambia el addon actual** (Fases 1-14): sus datos se migraron a mano antes de existir esta política y no pasan por el generador (§9.5 del documento principal). Describe qué ocurriría **al generar** un pack con la política vigente.
- Compatible con Lua 5.1: sin `goto`, operadores de bits ni `//`; sin escapes `\x`/`\z`/`\u{}` (los textos con caracteres no ASCII usarían escapes decimales `\ddd`).

### 4.2 Pack con una fuente **autorizada** (FIXTURE SINTÉTICO)
Ilustra qué ocurre cuando una fuente **sí** está autorizada para el pack: aquí una fuente **sintética** (`fixture_authorized_source`, §2.1). **Todos los datos son inventados** y no son de WoW; no implica ninguna decisión sobre fuentes reales.
```lua
-- GENERADO. NO EDITAR A MANO. FIXTURE SINTETICO: todos los datos son inventados; fuente = fixture_authorized_source.
Chronicle.Pack = {
    header = {
        pack_schema = 1,
        flavor = "era",
        client = { interface = { 11507 } },
        content_revision = "sha256:EJEMPLO",
        generated_from = { world = "sha256:EJEMPLO", editorial = "sha256:EJEMPLO", generator = "0.0.0-ejemplo" },
        counts = { entities = 5, published = 5, available = 5, retired = 0, hints = 0 },
        features = { persist_hints = false, persist_interaction_progress = false },
        locales = { "esES" },
    },

    entities = {
        ["continent:fixture_world"] = { type = "continent", status = "published", importance = "standard" },
        ["zone:fixture_land"] = { type = "zone", status = "published", importance = "standard", parent = "continent:fixture_world" },
        ["subzone:fixture_hollow"] = { type = "subzone", status = "published", importance = "standard", parent = "zone:fixture_land" },
        ["npc:fixture_example_elder"] = { type = "npc", status = "published", importance = "standard", located_in = "subzone:fixture_hollow" },
        ["npc:fixture_example_keeper"] = { type = "npc", status = "published", importance = "standard", located_in = "subzone:fixture_hollow" },
    },

    presence = {
        ["continent:fixture_world"] = { available = true, tech = {} },
        ["zone:fixture_land"] = { available = true, tech = {} },
        ["subzone:fixture_hollow"] = { available = true, tech = {} },
        ["npc:fixture_example_elder"] = { available = true, tech = { { kind = "creature", id = 90004 } } },
        ["npc:fixture_example_keeper"] = { available = true, tech = { { kind = "creature", id = 90001 } } },
    },

    discovery = {
        ["continent:fixture_world"] = { method = "none" },
        ["zone:fixture_land"] = { method = "place_enter" },
        ["subzone:fixture_hollow"] = { method = "place_enter" },
        ["npc:fixture_example_elder"] = {
            method = "interaction",
            requirements = { place_discovered = { id = "zone:fixture_land", strict = false, derived = true } },
            interaction = { type = "gossip" },
            required_capabilities = { "interaction.gossip" },
        },
        ["npc:fixture_example_keeper"] = {
            method = "interaction",
            requirements = { all = {
                { place_discovered = { id = "subzone:fixture_hollow", strict = true } },
                { entity_discovered = { id = "npc:fixture_example_elder" } },
            } },
            interaction = { any = { { type = "gossip" }, { type = "quest" } } },
            required_capabilities = { "interaction.gossip", "interaction.quest" },
        },
    },

    hints = {},

    names = {
        esES = {
            zone_text = { ["fixture land"] = "zone:fixture_land" },
            subzone_text = { ["fixture hollow"] = "subzone:fixture_hollow" },
        },
    },

    tombstones = {},
}
```
Aquí **todo dato técnico es elegible** porque su valor está respaldado por una *claim* de una fuente con `usage.generated_data = true`. Los `id` `90001` y `90004` son **inventados**.

### 4.3 Lápida de una entidad retirada (FIXTURE)
```lua
    tombstones = {
        ["npc:fixture_retired_example"] = { type = "npc", status = "retired", located_in = "subzone:fixture_hollow", superseded_by = "npc:fixture_example_keeper" },
    },
```
Datos mínimos, sin texto ni reglas ni datos técnicos. Con esta lápida, `Registry:Has("npc:fixture_retired_example")` seguiría siendo `true`, y un descubrimiento antiguo guardado en `ChronicleCharDB` **no quedaría huérfano**.

---

## 5. Informe de publicación (`ship-report`, JSON, no va en el ZIP)

Para el NPC real y el fixture, **por versión**, con el motivo exacto. `available` respeta **todas** las condiciones de publicación (§9.2 del documento principal), incluida la **procedencia autorizada** (condición 6).
```json
{
  "schema": "chronicle.report.ship/1",
  "policy": { "capabilities_unverified": { "era": "warn", "forever": "block" }, "d8": "PENDING_OWNER_DECISION" },
  "entries": [
    {
      "entity": "npc:grelin_whitebeard", "flavor": "era", "available": false,
      "reasons": ["source_not_authorized_for_pack"],
      "details": [
        { "datum": "exists", "claims_from": ["wow_client"], "blocked_because": "usage.generated_data = false (D8 pendiente)" }
      ],
      "omitted_optional": [
        { "datum": "attributes.display_id", "claims_from": ["legacy_addon"], "blocked_because": "status = research_only" }
      ],
      "warnings": ["capability_unverified:interaction.gossip"]
    },
    {
      "entity": "npc:grelin_whitebeard", "flavor": "forever", "available": false,
      "reasons": ["no_binding"], "warnings": []
    },
    {
      "entity": "npc:fixture_example_keeper", "flavor": "era", "available": true,
      "reasons": [], "warnings": [], "authorized_by": ["fixture_authorized_source"]
    },
    {
      "entity": "npc:fixture_example_keeper", "flavor": "forever", "available": false,
      "reasons": ["capability_unverified:interaction.quest"], "warnings": []
    }
  ]
}
```
Lectura:
- **Grelin en Era: `available = false`.** Aunque tenga *binding* aceptado, la existencia de `creature 786` solo está respaldada por `wow_client`, que no está autorizada para el *pack* mientras D8 siga pendiente. La capacidad `interaction.gossip` sin verificar es solo un **aviso** en Era (política permisiva); **no** es lo que bloquea. `display_id` se **omite** (atributo opcional) y se registra.
- **Grelin en Forever: `available = false`** por `no_binding` (no hay datos de Forever), **sin perder nada editorial**.
- **Fixture en Era: `available = true`**: todos los datos técnicos son elegibles (fuente sintética autorizada) y sus capacidades se suponen `verified` en el perfil sintético de `era` (no mostrado).
- **Fixture en Forever: `available = false`** por la política **estricta** de capacidades `unverified` (§9.3 del documento principal); se publicaría en cuanto una `Observation` de ese build deje la capacidad `verified`.
- **Qué cambiaría si el propietario resolviera D8 autorizando `wow_client`:** `exists` de Grelin pasaría a ser elegible y `source_not_authorized_for_pack` desaparecería de esa entrada; `display_id` seguiría omitido. **Eso es una decisión del propietario y no se toma aquí.**

---

## 6. Qué casos cubren estos ejemplos (comprobación cruzada con el encargo)
| Requisito de la Fase 16 | Ejemplo |
|---|---|
| Una entidad editorial en varios clientes sin duplicarla | §1.1, §1.4, §1.6, §5 |
| Era → `npcID` 786 | §1.4, §2.3 |
| Forever → otro ID técnico | §1.6 (**fixture sintético**) |
| Nombres distintos por locale | §2.3 (`enUS` presente; `esES` desconocido) |
| Presencia/capacidades/disponibilidad distintas por versión | §1.2, §2.5, §5 |
| Contexto geográfico, interacción, `any`/`all`, dependencias | §1.1, §1.2, §4.2 |
| `requires_hint` y pistas estructuradas | §1.1, §1.7, §1.8 |
| Entidad retirada conocida por el Registry | §1.10, §4.3 |
| Procedencia, confianza, conflictos, overrides | §2.1-§2.4, §1.9 |
| **Autorización para el pack ≠ confianza** (política de fuentes coherente con los packs) | §2.1, §2.3, §4.1, §4.2, §5 |
| Candidatos sin decisión | §3.2, §1.9 |
| Pack Lua generado | §4.1 (política actual), §4.2 (fuente autorizada FIXTURE) |
