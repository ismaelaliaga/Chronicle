'use strict';
// Fase 18 — reconciliación (Link / LinkDecision) y generación de candidatos.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { buildLinks, linkIdFor, effectiveLinkStatus, orderedPair } = require('../scripts/lib/links');
const { buildCandidates } = require('../scripts/lib/candidates');
const { isGenericName } = require('../scripts/lib/rules');
const { validateDataset } = require('../scripts/lib/validate');
const { FIXTURE_ROOT, REAL_ROOT, copyDataset, edit, read, write, rm, cli } = require('./helpers');

// ----------------------------------------------------------------------------------------------- datos sintéticos en memoria
const src = (id, candidateGeneration = true) => ({ id, origin_group: id, status: 'active', usage: { research: true, contrast: true, local_validation: true, candidate_generation: candidateGeneration, generated_data: false } });
const sources = new Map([['s', src('s')], ['t', src('t')], ['r', src('r', false)]]);
const claim = (source, value, confidence = 'source_reported') => ({ value, confidence, provenance: { source, source_version: 'v', method: 'import' } });
const fld = (source, value) => ({ claims: [claim(source, value)], resolved: { value, status: 'resolved', rule: 'single_claim' } });
function creature(flavor, id, names, extra = {}, source = 's') {
  const doc = { schema: 'chronicle.world.entity/1', ref: { flavor, kind: 'creature', id }, exists: fld(source, 'present'), names: {} };
  for (const [l, v] of Object.entries(names)) doc.names[l] = fld(source, v);
  if (extra.place) doc.places = fld(source, [{ flavor, kind: 'area', id: extra.place }]);
  if (extra.display) doc.attributes = { display_id: fld(source, extra.display) };
  return doc;
}
const links = (docs, rejected) => buildLinks(docs, sources, rejected);

test('el nombre SOLO nunca supera «unresolved» (misma versión y entre versiones)', () => {
  for (const [fa, fb] of [['era', 'era'], ['era', 'alt']]) {
    const l = links([creature(fa, 1, { enUS: 'Aldric Stone' }), creature(fb, 2, { enUS: 'Aldric Stone' })]);
    assert.equal(l.length, 1);
    assert.equal(l[0].status, 'unresolved');
    assert.deepEqual(l[0].evidence.map((e) => e.kind), ['same_name']);
  }
});

test('nombre + lugar compartido => probable_match; el id y el orden de a/b son estables', () => {
  const x = creature('era', 1, { enUS: 'Aldric Stone' }, { place: 77 });
  const y = creature('alt', 2, { enUS: 'aldric  stone ' }, { place: 77 }); // normalizado: recorta y pliega espacios
  const l = links([x, y]);
  assert.equal(l.length, 1);
  assert.equal(l[0].status, 'probable_match');
  assert.equal(l[0].relation, 'same_entity_across_flavors');
  assert.deepEqual(l[0].evidence.map((e) => e.kind), ['same_name', 'same_place']);
  assert.equal(l[0].id, linkIdFor(x.ref, y.ref));
  assert.equal(linkIdFor(x.ref, y.ref), linkIdFor(y.ref, x.ref));
  assert.deepEqual(orderedPair(x.ref, y.ref), [y.ref, x.ref]); // orden canónico por «flavor:kind:id» (alt < era)
  assert.deepEqual(orderedPair(y.ref, x.ref), [y.ref, x.ref]);
  assert.deepEqual([l[0].a, l[0].b], [y.ref, x.ref]);
  assert.match(l[0].fingerprint, /^sha256:[a-f0-9]{64}$/);
  // el resultado no depende del orden de entrada
  assert.deepEqual(links([y, x]), l);
});

test('cross-flavor: la máquina NUNCA produce «matched» (solo una decisión humana lo hace)', () => {
  const cases = [
    [creature('era', 1, { enUS: 'A B' }), creature('alt', 2, { enUS: 'A B' })],
    [creature('era', 1, { enUS: 'A B' }, { place: 1, display: 5 }), creature('alt', 2, { enUS: 'A B' }, { place: 1, display: 5 })],
    [creature('era', 1, { enUS: 'A B' }, { place: 1 }), creature('era', 2, { enUS: 'A B' }, { place: 1 })],
  ];
  for (const docs of cases) for (const l of links(docs)) assert.ok(['probable_match', 'conflict', 'unresolved'].includes(l.status), l.status);
});

test('displayID es solo evidencia auxiliar: sin nombre no hay enlace; con nombre no promueve', () => {
  assert.deepEqual(links([creature('era', 1, { enUS: 'Uno' }, { display: 9 }), creature('alt', 2, { enUS: 'Dos' }, { display: 9 })]), []);
  const onlyName = links([creature('era', 1, { enUS: 'Uno' }, { display: 9 }), creature('alt', 2, { enUS: 'Uno' }, { display: 9 })]);
  assert.equal(onlyName[0].status, 'unresolved');
  assert.ok(onlyName[0].evidence.some((e) => e.kind === 'same_display_id'));
  const withPlace = links([creature('era', 1, { enUS: 'Uno' }, { display: 9, place: 3 }), creature('alt', 2, { enUS: 'Uno' }, { display: 9, place: 3 })]);
  assert.equal(withPlace[0].status, 'probable_match');
  assert.deepEqual(withPlace[0].evidence.map((e) => e.kind), ['same_display_id', 'same_name', 'same_place']);
});

test('los nombres genéricos no producen probable_match, aunque compartan lugar', () => {
  assert.equal(isGenericName('Dwarven Guard'), true);
  assert.equal(isGenericName('Guardia de la ciudad'), false);
  assert.equal(isGenericName('Aldric Stone'), false);
  const l = links([creature('era', 1, { enUS: 'Town Guard' }, { place: 4 }), creature('alt', 2, { enUS: 'Town Guard' }, { place: 4 })]);
  assert.equal(l.length, 1);
  assert.equal(l[0].status, 'unresolved');
  assert.ok(l[0].evidence.some((e) => e.kind === 'generic_name'));
});

test('los nombres repetidos no producen enlaces (ni siquiera «unresolved»)', () => {
  const three = [1, 2, 3].map((i) => creature('era', i, { enUS: 'Aldric Stone' }, { place: 1 }));
  assert.deepEqual(links(three), []);
  assert.deepEqual(links([creature('era', 1, { enUS: 'X Y' }, { place: 1 }), creature('era', 2, { enUS: 'X Y' }, { place: 1 }), creature('alt', 3, { enUS: 'X Y' }, { place: 1 })]).filter((l) => l.relation === 'same_entity_across_flavors'), []);
});

test('nombres incompatibles en un idioma compartido (con el mismo lugar) => conflict', () => {
  const l = links([creature('era', 1, { enUS: 'Aldric', esES: 'Aldrico' }, { place: 1 }), creature('alt', 2, { enUS: 'Aldric', esES: 'Otro' }, { place: 1 })]);
  assert.equal(l[0].status, 'conflict');
  assert.ok(l[0].evidence.some((e) => e.kind === 'name_mismatch'));
});

test('solo cuentan los datos respaldados por fuentes con candidate_generation (D-02)', () => {
  const research = [creature('era', 1, { enUS: 'Aldric' }, { place: 1 }, 'r'), creature('alt', 2, { enUS: 'Aldric' }, { place: 1 }, 'r')];
  assert.deepEqual(links(research), []);
});

test('different_from humano (reject): la pareja no vuelve a proponerse', () => {
  const docs = [creature('era', 1, { enUS: 'Aldric' }, { place: 1 }), creature('alt', 2, { enUS: 'Aldric' }, { place: 1 })];
  const [l] = links(docs);
  assert.deepEqual(links(docs, new Set([l.id])), []);
});

test('estado efectivo: confirm vigente => matched; confirm desfasada => vuelve a la propuesta; sin decisión => propuesta', () => {
  const [l] = links([creature('era', 1, { enUS: 'Aldric' }, { place: 1 }), creature('alt', 2, { enUS: 'Aldric' }, { place: 1 })]);
  assert.deepEqual(effectiveLinkStatus(l, null), { status: 'probable_match', via: 'machine', stale: false });
  assert.deepEqual(effectiveLinkStatus(l, { decision: 'confirm', evidence_fingerprint: l.fingerprint }), { status: 'matched', via: 'decision', stale: false });
  assert.deepEqual(effectiveLinkStatus(l, { decision: 'confirm', evidence_fingerprint: 'sha256:' + '0'.repeat(64) }), { status: 'probable_match', via: 'machine', stale: true });
});

// ----------------------------------------------------------------------------------------------- sobre datasets
test('dataset de fixtures: el enlace entre versiones es probable_match de la máquina y matched por decisión humana (sin crear Entity)', () => {
  const m = validateDataset(FIXTURE_ROOT).model;
  assert.equal(m.ds.world.links.length, 1);
  const link = m.ds.world.links[0].doc;
  assert.equal(link.status, 'probable_match');
  assert.deepEqual([link.a.id, link.b.id], [90004, 90008]);
  const dec = m.linkDecisions[0].doc;
  assert.equal(dec.decision, 'confirm');
  assert.equal(dec.evidence_fingerprint, link.fingerprint);
  assert.equal(effectiveLinkStatus(link, dec).status, 'matched');
});

test('el dataset real no tiene enlaces ni decisiones de enlace', () => {
  const m = validateDataset(REAL_ROOT).model;
  assert.equal(m.ds.world.links.length, 0);
  assert.equal(m.linkDecisions.length, 0);
});

test('LinkDecision reject en un dataset: normalize retira el enlace y los candidatos dejan de referenciarlo', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const file = fs.readdirSync(path.join(tmp, 'editorial/link_decisions'))[0];
    edit(tmp, `editorial/link_decisions/${file}`, 'decision: confirm', 'decision: reject');
    const r = cli(['pipeline', '--root', tmp]);
    assert.equal(r.code, 0, r.out);
    assert.deepEqual(fs.readdirSync(path.join(tmp, 'world/links')), []);
    assert.equal(JSON.parse(read(tmp, 'candidates/records/cand__era__creature__90004.json')).links, undefined);
  } finally { rm(tmp); }
});

function runValidate(mutate) {
  const tmp = copyDataset(FIXTURE_ROOT);
  try { mutate(tmp); return validateDataset(tmp).report; } finally { rm(tmp); }
}
const LD = () => fs.readdirSync(path.join(FIXTURE_ROOT, 'editorial/link_decisions'))[0];
const hasItem = (list, code, re) => list.some((i) => i.code === code && re.test(i.message));

test('reglas de las decisiones de enlace: orden canónico (L-03), criaturas existentes (L-02), duplicados (L-06), desfasadas (L-04) y huérfanas (L-05)', () => {
  const f = `editorial/link_decisions/${LD()}`;
  let r = runValidate((t) => edit(t, f, 'a: { flavor: era, kind: creature, id: 90004 }\nb: { flavor: fixture_alt, kind: creature, id: 90008 }', 'a: { flavor: fixture_alt, kind: creature, id: 90008 }\nb: { flavor: era, kind: creature, id: 90004 }'));
  assert.ok(hasItem(r.errors, 'L-03', /orden canónico/), r.format().join('\n'));
  r = runValidate((t) => edit(t, f, 'id: 90008', 'id: 99999'));
  assert.ok(hasItem(r.errors, 'L-02', /no existe en World Data/), r.format().join('\n'));
  r = runValidate((t) => write(t, 'editorial/link_decisions/copia.yaml', read(t, f)));
  assert.ok(hasItem(r.errors, 'L-06', /ya hay una decisión para este enlace/), r.format().join('\n'));
  r = runValidate((t) => edit(t, f, /evidence_fingerprint: "(sha256:[a-f0-9]{64})"/.exec(read(t, f))[1], 'sha256:' + 'c'.repeat(64)));
  assert.ok(hasItem(r.warnings, 'L-04', /desfasada/), r.format().join('\n'));
  assert.deepEqual(r.errors, []);
  r = runValidate((t) => edit(t, f, 'id: 90004', 'id: 90001'));
  assert.ok(hasItem(r.warnings, 'L-05', /no corresponde a ningún enlace propuesto/), r.format().join('\n'));
});

test('un enlace de World Data editado a mano o sobrante se detecta (W-06); el candidato que lo cita también (L-07)', () => {
  let r = runValidate((t) => edit(t, `world/links/${fs.readdirSync(path.join(FIXTURE_ROOT, 'world/links'))[0]}`, '"status": "probable_match"', '"status": "unresolved"'));
  assert.ok(hasItem(r.errors, 'W-06', /no coincide con la normalización/), r.format().join('\n'));
  r = runValidate((t) => edit(t, 'candidates/records/cand__era__creature__90004.json', '"links": [', '"links": [\n    "link:0000000000000000",'));
  assert.ok(hasItem(r.errors, 'L-07', /no existe entre los enlaces propuestos/), r.format().join('\n'));
});

// ----------------------------------------------------------------------------------------------- generación de candidatos
test('los candidatos generados son deterministas y no dependen del orden de entrada', () => {
  const m = validateDataset(FIXTURE_ROOT);
  const args = { creatureDocs: m.world.creatureDocs, conflicts: m.world.conflicts, sourcesById: m.model.sourcesById, links: m.world.links, scoredIds: new Set(['cand:era:creature:90007']) };
  const a = buildCandidates(args);
  const b = buildCandidates({ ...args, creatureDocs: args.creatureDocs.slice().reverse(), links: args.links.slice().reverse() });
  assert.deepEqual(a, b);
  assert.ok(a.every((c) => c.score === undefined && c.profile === undefined && c.rank === undefined));
  assert.ok(!a.some((c) => c.id === 'cand:era:creature:90007')); // el puntuado es entrada: no se genera
  const withConflict = a.find((c) => c.id === 'cand:era:creature:90005');
  assert.equal(withConflict.evidence_summary.open_conflicts, 1);
  assert.equal(withConflict.evidence_summary.independent_origins, 3);
});

test('un candidato lo origina SOLO una fuente con candidate_generation (D-02), y es configuración de datos, no código', () => {
  const tmp = copyDataset(REAL_ROOT);
  try {
    // el wiki pasa (hipotéticamente) a poder generar candidatos: el candidato ya cita el wiki y muestra su nombre
    edit(tmp, 'sources/warcraft_wiki.yaml', 'candidate_generation: false', 'candidate_generation: true');
    assert.equal(cli(['candidates', '--root', tmp]).code, 0);
    const c = JSON.parse(read(tmp, 'candidates/records/cand__era__creature__786.json'));
    assert.deepEqual(c.sources.map((s) => s.source), ['warcraft_wiki', 'wow_client']);
    assert.deepEqual(c.display, { names: { enUS: 'Grelin Whitebeard' } });
    assert.equal(c.data_gaps, undefined);
  } finally { rm(tmp); }
  const tmp2 = copyDataset(REAL_ROOT);
  try {
    // si ninguna fuente puede generar candidatos, no hay candidatos (y los obsoletos se retiran)
    edit(tmp2, 'sources/wow_client.yaml', 'candidate_generation: true', 'candidate_generation: false');
    const r = cli(['candidates', '--root', tmp2]);
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /0 candidato\(s\) sin puntuar \(0 escrito\(s\), 2 eliminado\(s\)\)/);
    assert.deepEqual(fs.readdirSync(path.join(tmp2, 'candidates/records')), []);
  } finally { rm(tmp2); }
});

test('data:candidates nunca reescribe ni borra un candidato puntuado (entrada)', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const f = 'candidates/records/cand__era__creature__90007.json';
    const before = read(tmp, f);
    fs.rmSync(path.join(tmp, 'candidates/records/cand__era__creature__90004.json'));
    const r = cli(['candidates', '--root', tmp]);
    assert.equal(r.code, 0, r.out);
    assert.equal(read(tmp, f), before);
    assert.ok(fs.existsSync(path.join(tmp, 'candidates/records/cand__era__creature__90004.json')), 'se regenera el candidato borrado');
  } finally { rm(tmp); }
});
