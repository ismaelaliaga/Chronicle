# Dataset de fixtures SINTETICOS

Todo lo de esta carpeta es **inventado** para probar el pipeline: IDs 900xx, nombres, textos y hasta una fuente "autorizada".
**No son datos de WoW**, la fuente `fixture_authorized_source` no es una fuente real ni su `owner_approval` es una aprobacion real,
y el flavor `fixture_alt` no representa a ningun cliente (en particular, no es Forever).

## Fase 18 (catalogo editorial)

Tambien son **inventados** los candidatos, enlaces, decisiones y entidades de esta carpeta:

- `candidates/profiles/dun_morogh_pilot.yaml` es un perfil **ILUSTRATIVO** (`approval: illustrative`), no un perfil editorial real ni aprobado; sus pesos no son definitivos.
- `candidates/records/cand__era__creature__90007.json` es el unico candidato puntuado (entrada escrita a mano); el resto los genera `data:candidates` sin puntuar.
- `world/links/` y `editorial/link_decisions/`: un enlace probable entre versiones (era 90004 / fixture_alt 90008) y su confirmacion humana ficticia.
- `editorial/decisions/`: decisiones accepted / rejected / deferred inventadas. `npc:fixture_pending_example` esta aceptada pero sin Binding ni contenido; `npc:fixture_bootstrap_example` es una entidad `origin: bootstrap` en `drafting` (prueba D-08).
