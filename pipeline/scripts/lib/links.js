'use strict';
// Reconciliación (Fase 18): enlaces PROPUESTOS por la máquina entre referencias técnicas distintas que podrían describir el mismo sujeto.
//
// Principios (diseño aprobado 18.1/18.2):
//   - Un Link NO es una decisión editorial y NUNCA crea una Entity. `matched` significa «las evidencias permiten reconciliar estas referencias técnicas
//     como una misma referencia/sujeto dentro del ámbito de la regla»; NO significa que Chronicle haya decidido incluir ese NPC.
//   - La máquina solo propone `probable_match`, `conflict` o `unresolved`. `matched` solo lo produce una LinkDecision humana (confirm).
//     (La identidad por el MISMO TechRef no es un Link: se fusiona al normalizar y no necesita enlace.)
//   - El nombre solo nunca supera `unresolved`. Los nombres genéricos no producen `probable_match`. Los nombres repetidos no producen enlaces.
//   - displayID es solo evidencia AUXILIAR: nunca identifica ni promueve un enlace por sí mismo.
//   - Cross-flavor: nunca `matched` automático; requiere una decisión humana.
//   - Solo cuentan los datos respaldados por al menos una claim de una fuente con usage.candidate_generation = true (D-02).
//   - `reject` (different_from) humano impide que la pareja vuelva a proponerse.
const { fingerprint, sha256Hex, deepEqual } = require('./canonical');
const { normalizeName, isGenericName } = require('./rules');
const { cmp } = require('./report');

const RULE_VERSION = 1;

const refKey = (r) => `${r.flavor}:${r.kind}:${r.id}`;

function orderedPair(x, y) {
  return cmp(refKey(x), refKey(y)) <= 0 ? [x, y] : [y, x];
}

// Identificador estable de la pareja (independiente del orden y de la evidencia).
function linkIdFor(x, y) {
  const [a, b] = orderedPair(x, y);
  return 'link:' + sha256Hex(`${refKey(a)}|${refKey(b)}`).slice(0, 16);
}

const linkFileBase = (id) => id.replace(/:/g, '__');

// Fuentes que pueden originar candidatos y enlaces (usage.candidate_generation = true y no bloqueadas).
function candidateSourceIds(sourcesById) {
  const out = new Set();
  for (const s of sourcesById.values()) if (s.usage && s.usage.candidate_generation === true && s.status !== 'blocked') out.add(s.id);
  return out;
}

// Valor resuelto de un campo SOLO si lo respalda al menos una claim de una fuente de `allowed`. Devuelve { value, sources } o null.
function supportedValue(field, allowed) {
  if (!field || !field.resolved || field.resolved.value === null || field.resolved.value === undefined) return null;
  const sources = new Set();
  for (const c of field.claims || []) {
    if (allowed.has(c.provenance.source) && deepEqual(c.value, field.resolved.value)) sources.add(c.provenance.source);
  }
  return sources.size ? { value: field.resolved.value, sources: Array.from(sources).sort(cmp) } : null;
}

function factsOf(doc, allowed) {
  const names = {};
  for (const [locale, f] of Object.entries(doc.names || {})) {
    const s = supportedValue(f, allowed);
    if (s) names[locale] = { value: s.value, key: normalizeName(s.value), sources: s.sources };
  }
  const places = new Map();
  const p = supportedValue(doc.places, allowed);
  if (p) for (const t of p.value) places.set(`${t.kind}:${t.id}`, p.sources);
  const d = supportedValue(doc.attributes && doc.attributes.display_id, allowed);
  return { ref: doc.ref, key: refKey(doc.ref), names, places, displayId: d };
}

const union = (...lists) => Array.from(new Set([].concat(...lists))).sort(cmp);

// Construye los enlaces propuestos. `creatureDocs`: documentos world.entity; `rejectedIds`: Set de LinkId con LinkDecision reject.
function buildLinks(creatureDocs, sourcesById, rejectedIds = new Set()) {
  const allowed = candidateSourceIds(sourcesById);
  const facts = creatureDocs.map((d) => factsOf(d, allowed)).sort((a, b) => cmp(a.key, b.key));

  // índice: clave de nombre -> hechos que la tienen
  const byKey = new Map();
  for (const f of facts) {
    for (const k of new Set(Object.values(f.names).map((n) => n.key))) {
      if (!byKey.has(k)) byKey.set(k, []);
      byKey.get(k).push(f);
    }
  }
  const countIn = (key, flavor) => (byKey.get(key) || []).filter((f) => f.ref.flavor === flavor).length;

  const pairs = new Map(); // linkId -> [fa, fb]
  for (const group of byKey.values()) {
    for (let i = 0; i < group.length; i++) {
      for (let j = i + 1; j < group.length; j++) {
        const [a, b] = group[i].key <= group[j].key ? [group[i], group[j]] : [group[j], group[i]];
        pairs.set(linkIdFor(a.ref, b.ref), [a, b]);
      }
    }
  }

  const links = [];
  for (const id of Array.from(pairs.keys()).sort(cmp)) {
    if (rejectedIds.has(id)) continue; // different_from humano: la pareja no vuelve a proponerse
    const [a, b] = pairs.get(id);
    const sameFlavor = a.ref.flavor === b.ref.flavor;

    const bKeys = new Set(Object.values(b.names).map((n) => n.key));
    const sharedKeys = Object.keys(a.names).sort(cmp).map((l) => a.names[l]).filter((n) => bKeys.has(n.key));
    const mismatches = [];
    for (const locale of Object.keys(a.names).sort(cmp)) {
      if (b.names[locale] && a.names[locale].key !== b.names[locale].key) mismatches.push({ locale, a: a.names[locale], b: b.names[locale] });
    }
    // un grupo de nombres repetidos no produce enlaces (evita explosión combinatoria y falsos positivos)
    const repeated = sharedKeys.some((n) => (sameFlavor ? countIn(n.key, a.ref.flavor) > 2 : countIn(n.key, a.ref.flavor) > 1 || countIn(n.key, b.ref.flavor) > 1));
    if (repeated || sharedKeys.length === 0) continue;

    const evidence = [];
    const seen = new Set();
    for (const n of sharedKeys) {
      if (seen.has(n.key)) continue;
      seen.add(n.key);
      const other = Object.values(b.names).find((x) => x.key === n.key);
      evidence.push({ kind: 'same_name', value: n.key, sources: union(n.sources, other.sources) });
    }
    const generic = sharedKeys.find((n) => isGenericName(n.value));
    if (generic) evidence.push({ kind: 'generic_name', value: generic.key, sources: generic.sources });
    for (const m of mismatches) evidence.push({ kind: 'name_mismatch', value: `${m.locale}: ${m.a.key} != ${m.b.key}`, sources: union(m.a.sources, m.b.sources) });
    const commonPlaces = Array.from(a.places.keys()).filter((k) => b.places.has(k)).sort(cmp);
    for (const k of commonPlaces) evidence.push({ kind: 'same_place', value: k, sources: union(a.places.get(k), b.places.get(k)) });
    if (a.displayId && b.displayId && a.displayId.value === b.displayId.value) {
      evidence.push({ kind: 'same_display_id', value: a.displayId.value, sources: union(a.displayId.sources, b.displayId.sources) });
    }
    evidence.sort((x, y) => cmp(x.kind, y.kind) || cmp(String(x.value), String(y.value)));

    const hasPlace = commonPlaces.length > 0;
    let status = 'unresolved'; // el nombre solo nunca supera «unresolved»; displayID nunca promueve
    if (!generic && hasPlace) status = mismatches.length ? 'conflict' : 'probable_match';

    const [ra, rb] = orderedPair(a.ref, b.ref);
    const doc = {
      schema: 'chronicle.world.link/1',
      id,
      relation: sameFlavor ? 'same_subject' : 'same_entity_across_flavors',
      a: ra,
      b: rb,
      status,
      evidence,
      rule_version: RULE_VERSION,
    };
    doc.fingerprint = fingerprint({ a: ra, b: rb, evidence, rule_version: RULE_VERSION });
    links.push(doc);
  }
  return links;
}

// Estado EFECTIVO de un enlace = propuesta de la máquina + decisión humana (si la hay y sigue vigente).
//   - confirm vigente (misma huella de evidencia)  -> matched
//   - confirm desfasada (la evidencia cambió)      -> vuelve a la propuesta de la máquina (stale = true)
//   - reject: la pareja no se propone; su estado efectivo es `different_from` (ver `rejectedStatus`)
function effectiveLinkStatus(link, decision) {
  if (decision && decision.decision === 'confirm') {
    if (decision.evidence_fingerprint === link.fingerprint) return { status: 'matched', via: 'decision', stale: false };
    return { status: link.status, via: 'machine', stale: true };
  }
  return { status: link.status, via: 'machine', stale: false };
}

module.exports = {
  RULE_VERSION, refKey, orderedPair, linkIdFor, linkFileBase, candidateSourceIds, supportedValue, buildLinks, effectiveLinkStatus,
};
