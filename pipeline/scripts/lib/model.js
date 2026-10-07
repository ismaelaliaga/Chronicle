'use strict';
// Índices en memoria de un dataset ya cargado (todos sus ficheros pasaron su esquema). Detecta duplicados entre ficheros.
const { authorizedSourceIds } = require('./eligibility');

function addUnique(map, key, value, report, code, what) {
  if (map.has(key)) {
    report.error(code, value.file, '', `${what} «${key}» duplicado (ya definido en ${map.get(key).file})`);
    return;
  }
  map.set(key, value);
}

function buildModel(ds, report) {
  const m = {
    ds,
    flavors: ds.flavors ? ds.flavors.doc : null,
    sourcesById: new Map(),
    authorized: new Set(),
    entities: new Map(),
    entityDocs: new Map(),
    bindings: new Map(),
    hints: new Map(),
    hintDocs: new Map(),
    texts: new Map(), // locale -> Map(id -> { file, entry })
    creatures: new Map(), // `${flavor}|${kind}|${id}` -> { file, doc }
    places: new Map(), // `${flavor}|${key}` -> { file, doc }   (solo lugares name_only)
    profiles: new Map(),
    observations: new Map(),
    conflicts: ds.world.conflicts.map((c) => c.doc),
    candidates: new Map(), // id -> { file, doc }   (vacío si el dataset se cargó sin candidatos: el generador no los lee)
    candidateProfiles: new Map(), // `${id}@${version}` -> { file, doc }
    decisions: ds.editorial.decisions,
    linkDecisions: ds.editorial.linkDecisions,
    links: new Map(), // id -> { file, doc }
  };

  for (const s of ds.sources) addUnique(m.sourcesById, s.doc.id, { file: s.file, doc: s.doc }, report, 'S-03', 'fuente');
  for (const [id, v] of m.sourcesById) m.sourcesById.set(id, v.doc);
  m.authorized = authorizedSourceIds(m.sourcesById);

  for (const e of ds.editorial.entities) addUnique(m.entities, e.doc.id, e, report, 'E-02', 'ID de entidad');
  for (const [id, v] of m.entities) m.entityDocs.set(id, v.doc);

  for (const b of ds.editorial.bindings) addUnique(m.bindings, `${b.doc.entity}|${b.doc.flavor}`, b, report, 'E-09', 'binding (entidad|flavor)');
  for (const h of ds.editorial.hints) addUnique(m.hints, h.doc.id, h, report, 'E-08', 'ID de pista');
  for (const [id, v] of m.hints) m.hintDocs.set(id, v.doc);

  for (const t of ds.editorial.texts) {
    if (!m.texts.has(t.doc.locale)) m.texts.set(t.doc.locale, new Map());
    const byId = m.texts.get(t.doc.locale);
    for (const id of Object.keys(t.doc.entries)) {
      if (byId.has(id)) report.error('E-13', t.file, `/entries/${id}`, `texto de «${id}» duplicado en el idioma ${t.doc.locale} (ya definido en ${byId.get(id).file})`);
      else byId.set(id, { file: t.file, entry: t.doc.entries[id] });
    }
  }

  for (const c of ds.world.entities) addUnique(m.creatures, `${c.doc.ref.flavor}|${c.doc.ref.kind}|${c.doc.ref.id}`, c, report, 'W-12', 'entidad del mundo');
  for (const p of ds.world.places) {
    if (p.doc.ref.kind === 'name_only') addUnique(m.places, `${p.doc.ref.flavor}|${p.doc.ref.key}`, p, report, 'W-12', 'lugar del mundo');
  }
  for (const l of ds.world.links) addUnique(m.links, l.doc.id, l, report, 'W-12', 'enlace');
  for (const c of ds.candidates.records) addUnique(m.candidates, c.doc.id, c, report, 'C-03', 'candidato');
  for (const pr of ds.candidates.profiles) addUnique(m.candidateProfiles, `${pr.doc.id}@${pr.doc.version}`, pr, report, 'C-02', 'perfil de scoring (id@versión)');
  for (const p of ds.world.profiles) addUnique(m.profiles, p.doc.flavor, p, report, 'W-12', 'perfil de cliente');
  for (const o of ds.world.observations) addUnique(m.observations, o.doc.id, o, report, 'W-12', 'observación');
  return m;
}

module.exports = { buildModel };
