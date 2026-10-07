'use strict';
// Detección de candidatos (Fase 18). Un Candidate es una PROPUESTA DE REVISIÓN de un sujeto técnico identificado en un flavor, acompañada de las
// evidencias, referencias técnicas y reconciliaciones que justifican revisarlo. NO es un TechRef, NO es una Entity y NO decide nada.
//
//   - Solo las fuentes con usage.candidate_generation = true pueden originar un candidato (D-02); el resto de datos sigue siendo investigación.
//   - Los candidatos que genera la máquina están SIN PUNTUAR (no hay perfil de scoring aprobado ni calibración): sin profile/signals/score/rank.
//   - Un candidato con perfil (puntuado) es un fichero de entrada que esta herramienta nunca reescribe ni borra.
//   - Es una función pura de World Data (y de los enlaces propuestos): no lee nada editorial y el generador del pack no lee su resultado.
const { fingerprint } = require('./canonical');
const { candidateSourceIds, supportedValue, refKey } = require('./links');
const { cmp } = require('./report');

const candidateId = (ref) => `cand:${ref.flavor}:${ref.kind}:${ref.id}`;
const candidateFileBase = (id) => id.replace(/:/g, '__');
const sameRef = (x, y) => x.flavor === y.flavor && x.kind === y.kind && x.id === y.id;

// [ruta del campo, campo] de un documento world.entity (exists, names.*, subnames.*, attributes.*, relations.*, spawns, places).
function fieldsOf(doc) {
  const out = [];
  if (doc.exists) out.push(['exists', doc.exists]);
  for (const group of ['names', 'subnames', 'attributes', 'relations']) {
    for (const k of Object.keys(doc[group] || {}).sort(cmp)) out.push([`${group}.${k}`, doc[group][k]]);
  }
  for (const k of ['spawns', 'places']) if (doc[k]) out.push([k, doc[k]]);
  return out;
}

// `scoredIds`: ids de candidatos que ya existen CON perfil (los gestiona una persona/herramienta de scoring; aquí se respetan).
function buildCandidates({ creatureDocs, conflicts, sourcesById, links, scoredIds = new Set() }) {
  const allowed = candidateSourceIds(sourcesById);
  const out = [];
  for (const doc of creatureDocs.slice().sort((a, b) => cmp(refKey(a.ref), refKey(b.ref)))) {
    const id = candidateId(doc.ref);
    if (scoredIds.has(id)) continue;

    const perSource = new Map();
    const claimsByField = {};
    let clientVerified = false;
    for (const [path, field] of fieldsOf(doc)) {
      for (const c of field.claims || []) {
        const s = c.provenance.source;
        if (!allowed.has(s)) continue;
        perSource.set(s, (perSource.get(s) || 0) + 1);
        (claimsByField[path] = claimsByField[path] || []).push(c);
        if (c.confidence === 'client_verified') clientVerified = true;
      }
    }
    if (perSource.size === 0) continue; // ninguna fuente autorizada para generar candidatos lo respalda

    const sources = Array.from(perSource.keys()).sort(cmp).map((s) => ({ source: s, origin_group: sourcesById.get(s).origin_group, claims: perSource.get(s) }));
    const names = {};
    for (const locale of Object.keys(doc.names || {}).sort(cmp)) {
      const v = supportedValue(doc.names[locale], allowed);
      if (v) names[locale] = v.value;
    }
    const gaps = Object.keys(names).length ? [] : ['display_name'];
    const mine = (links || []).filter((l) => sameRef(l.a, doc.ref) || sameRef(l.b, doc.ref)).map((l) => l.id).sort(cmp);
    const openConflicts = (conflicts || []).filter((c) => sameRef(c.subject, doc.ref) && (c.status === 'open' || c.status === 'stale')).length;

    const cand = {
      schema: 'chronicle.candidate.record/1',
      id,
      flavor: doc.ref.flavor,
      subject: doc.ref,
      sources,
      evidence_summary: {
        independent_origins: new Set(sources.map((s) => s.origin_group)).size,
        client_verified: clientVerified,
        open_conflicts: openConflicts,
      },
      research: { status: 'new' },
      inputs_fingerprint: fingerprint({ ref: doc.ref, claims: claimsByField }),
    };
    if (Object.keys(names).length) cand.display = { names };
    if (mine.length) cand.links = mine;
    if (gaps.length) { cand.data_gaps = gaps; cand.flags = ['data_gap']; }
    out.push(cand);
  }
  return out;
}

module.exports = { candidateId, candidateFileBase, sameRef, fieldsOf, buildCandidates };
