# Fase 17 — Implementación del pipeline de datos

Rama: `fase17-data-pipeline` (desde `fase16-data-model` @ `e47269377d9d70f84da66bbdbae9b0455a8cd853`).
Estado: **entregada para revisión. No se declara aprobada.**
Fase 16 no se ha modificado. No hay merge a `main` ni ZIP.

## 1. Alcance implementado

| Apartado | Entrega |
|---|---|
| A. Estructura | `pipeline/{schemas,sources,world,candidates,editorial,generated,scripts,tests,fixtures}` |
| B. YAML restringido | `scripts/lib/yaml-strict.js`: YAML 1.2 core, sin anclas/alias/merge/tags/valores vacíos/`~`/multi-doc/BOM/tabs, claves duplicadas rechazadas. `yaml` es dependencia **solo de desarrollo** del pipeline; el addon no la usa |
| C. Esquemas | 21 JSON Schema 2020-12 ejecutables (Ajv, modo estricto) en `pipeline/schemas/` |
| D. `data:validate` | Catálogo de reglas con código (E-xx, X-xx, W-xx, C-xx, S-xx, P-xx, J-02, G-xx); salida determinista y ordenada |
| E. Autorización | `scripts/lib/eligibility.js` + `ship.js`: un dato entra al pack solo si ≥1 claim que lo respalda viene de una fuente `active` con `usage.generated_data === true`. `client_verified` y los Binding no autorizan. Motivo: `source_not_authorized_for_pack` |
| F. Huellas | SHA-256 sobre JSON canónico sin claves de tiempo; sin fechas de ejecución; `content_revision` = huella de las entradas del pack |
| G. World Data | Normalización de afirmaciones → `world/` (creature, place, conflicts, profile) |
| H. Generador | `generated/<flavor>/{Pack.lua,pack-manifest.json,ship-report.json}`; lápidas siempre incluidas |
| I. ClientAdapter | `Chronicle/Services/{ClientAdapter,EraAdapter}.lua`, **sin cablear** al runtime |
| J. Tests | 126 tests del pipeline + 30 checks Lua (`tests/clientadapter_tests.lua`) |

## 2. Comandos (desde `pipeline/`, tras `npm install`)

```bash
npm run data:normalize   # sources/records -> world/
npm run data:validate    # valida todo; exit 1 si hay errores
npm run data:generate    # valida y escribe generated/
npm run data:check       # regenera en memoria y compara byte a byte + verifica manifiesto
npm run data:pipeline    # normalize + validate + generate + check
npm run data:all         # pipeline real + pipeline de fixtures
npm test                 # 126 tests Node
```

Variantes `:fixtures` para el dataset sintético. Códigos de salida: 0 correcto, 1 errores, 2 uso incorrecto.

## 3. Resultado sobre el dataset real

- Fuentes: `wow_client` (activa, `generated_data: false`), `warcraft_wiki` y `legacy_addon` (`research_only`).
- Con D8 pendiente **ninguna fuente real está autorizada**. Grelin y Sten (`786`/`658`) y el `displayID 1354` permanecen en World Data como investigación; el pack real no contiene ningún dato técnico (verificado por test: ni `786`, `658`, `1354`, `1362` ni `display_id` aparecen en `Pack.lua`).
- Grelin/Sten salen `available=false` con `source_not_authorized_for_pack`.

## 4. Fixtures sintéticos (todo inventado, `pipeline/fixtures/authorized/`)

Fuente `fixture_authorized_source` con `generated_data: true` (aprobación ficticia, solo fixtures). Cubren: entidad autorizada, no autorizada aunque `client_verified`, conflicto abierto bloqueante, entidad retirada (lápida), distintos IDs técnicos por versión (`era` 90004 / `fixture_alt` 90008), capacidad no verificada (`capability_unverified`) y reglas `all`/`any`.

## 5. Contradicciones / desviaciones respecto a Fase 16

No se ha modificado Fase 16. Puntos donde la implementación concreta algo que Fase 16 dejaba abierto o ambiguo:

1. **Eligibilidad de overrides**: un `set_value` sin claim autorizada que lo respalde no es elegible (consecuencia de «no simplificar» la regla E). Fase 16 no lo decía explícitamente.
2. **Lugares sin dato técnico** (p. ej. continente con `method: none`) se publican sin `authorized_by`: no llevan TechRef, así que no hay dato que autorizar.
3. **`all` en interacciones y `hint_seen`** se tratan como RESERVADOS salvo que la versión habilite `persist_interaction_progress` / `persist_hints` (E-06).
4. **ID de entidad**: patrón con «al menos una letra» para impedir `npc:786` (IDs numéricos del cliente no son IDs editoriales).
5. Los esquemas se generaron con un script auxiliar no versionado; los `.json` versionados son la fuente de verdad desde ahora.

Ninguna es una contradicción demostrable que obligue a cambiar Fase 16.

## 6. Decisiones pendientes (no resueltas aquí)

- **D8** (licencia/política de fuentes): `PENDING_OWNER_DECISION`. Mientras siga así el pack real no contendrá datos técnicos.
- **D11**: valores de `Interface` por versión; el `11507` de `era` es informativo.
- **P10**: política de capacidades (`block` vs `warn`) — se usa `block`.
- **Forever**: `enabled: false`, sin Interface ni capacidades. `ForeverAdapter` es un stub (`not_implemented`). No se asume nada, ni Interface 16001.
- Contenido editorial real (textos, pistas, importancia) de Grelin/Sten: marcado como pendiente; el catálogo no se ha poblado.
- Cableado de `ClientAdapter` y consumo del pack desde el runtime: fuera de alcance.

## 7. Límites conocidos

- `pipeline/` es herramienta de desarrollo: no entra en el ZIP del addon.
- `Chronicle.zip` sin seguimiento en la raíz es preexistente y no forma parte de esta fase.
- `data:validate` frente a línea base (`--baseline-dir`) es opcional; sin ella no se comprueban transiciones de estado ni desapariciones de ID.
