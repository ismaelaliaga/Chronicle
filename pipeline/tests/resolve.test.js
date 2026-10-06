'use strict';
// Reconciliación de afirmaciones y normalización de World Data (Fase 16, 5.4).
const test = require('node:test');
const assert = require('node:assert/strict');
const { resolveField } = require('../scripts/lib/resolve');
const { buildWorld } = require('../scripts/lib/normalize');
const { loadDataset } = require('../scripts/lib/loader');
const { fingerprint, canonicalPretty } = require('../scripts/lib/canonical');
const { Report } = require('../scripts/lib/report');
const { FIXTURE_ROOT, REAL_ROOT, copyDataset, edit, read, write, rm } = require('./helpers');
const fs = require('fs');
const path = require('path');

const sources = new Map([
  ['a', { id: 'a', trust_tier: 6 }],
  ['b', { id: 'b', trust_tier: 6 }],
  ['cap', { id: 'cap', trust_tier: 2 }],
  ['cap2', { id: 'cap2', trust_tier: 2 }],
]);
const claim = (source, value, confidence = 'source_reported', method = 'import') => ({ value, confidence, provenance: { source, source_version: 'v1', method } });
const subject = { flavor: 'era', kind: 'creature', id: 1 };

function resolve(claims, overrides = []) {
  const report = new Report();
  const r = resolveField(claims, { sourcesById: sources, overrides, subject, field: 'names.enUS', report, file: 'f.json' });
  return { ...r, report };
}

test('una sola claim: single_claim', () => {
  const r = resolve([claim('a', 'X')]);
  assert.deepEqual(r.resolved, { value: 'X', status: 'resolved', rule: 'single_claim' });
  assert.equal(r.conflict, null);
});

test('varias claims iguales: agreement', () => {
  assert.equal(resolve([claim('a', 'X'), claim('b', 'X')]).resolved.rule, 'agreement');
});

test('precedencia por tier SOLO con confianza estrictamente mayor: tier_precedence', () => {
  const r = resolve([claim('a', 'viejo'), claim('cap', 'nuevo', 'client_verified', 'capture')]);
  assert.deepEqual(r.resolved, { value: 'nuevo', status: 'resolved', rule: 'tier_precedence' });
});

test('mismo tier y misma confianza con valores distintos: CONFLICTO con valor null (nunca se elige en silencio)', () => {
  const r = resolve([claim('a', 'X'), claim('b', 'Y')]);
  assert.equal(r.resolved.status, 'conflict');
  assert.equal(r.resolved.value, null);
  assert.match(r.conflict.id, /^conf:[a-f0-9]{16}$/);
  assert.equal(r.conflict.status, 'open');
  assert.equal(r.conflict.class, 'identity');
  assert.equal(r.conflict.blocks_publish, true);
  assert.equal(r.conflict.claims.length, 2);
});

test('mejor tier pero SIN ventaja estricta de confianza: también es conflicto', () => {
  const r = resolve([claim('a', 'X', 'client_verified', 'capture'), claim('cap', 'Y', 'client_verified', 'capture')]);
  assert.equal(r.resolved.status, 'conflict');
});

test('dos observaciones client_verified distintas: conflicto de clase «drift» (nunca «gana la más reciente»)', () => {
  const r = resolve([claim('cap', 'X', 'client_verified', 'capture'), claim('cap2', 'Y', 'client_verified', 'capture')]);
  assert.equal(r.conflict.class, 'drift');
  assert.equal(r.resolved.status, 'conflict');
});

test('el id y la huella del conflicto son deterministas y no dependen del orden de las claims', () => {
  const a = resolve([claim('a', 'X'), claim('b', 'Y')]);
  const b = resolve([claim('b', 'Y'), claim('a', 'X')]);
  assert.equal(a.conflict.id, b.conflict.id);
  assert.equal(a.conflict.fingerprint, b.conflict.fingerprint);
  assert.deepEqual(a.claims, b.claims);
});

const override = (fp, decision, id = 'ovr:x') => ({ id, target: { subject, field: 'names.enUS' }, decision, reason: 'motivo', bound_to_fingerprint: fp, author: 'p', created_at: '2026-10' });

test('un override atado a la huella actual resuelve el conflicto: prefer_claim', () => {
  const base = resolve([claim('a', 'X'), claim('b', 'Y')]);
  const r = resolve([claim('a', 'X'), claim('b', 'Y')], [override(base.conflict.fingerprint, { prefer_claim: { source: 'b', source_version: 'v1', method: 'import' } })]);
  assert.deepEqual(r.resolved, { value: 'Y', status: 'overridden', rule: 'override', override: 'ovr:x' });
  assert.equal(r.conflict.status, 'overridden');
  assert.equal(r.conflict.blocks_publish, false);
  assert.equal(r.conflict.resolution.override, 'ovr:x');
});

test('override set_value y reject_claim', () => {
  const base = resolve([claim('a', 'X'), claim('b', 'Y')]);
  const set = resolve([claim('a', 'X'), claim('b', 'Y')], [override(base.conflict.fingerprint, { set_value: 'Z' })]);
  assert.equal(set.resolved.value, 'Z');
  const rej = resolve([claim('a', 'X'), claim('b', 'Y')], [override(base.conflict.fingerprint, { reject_claim: { source: 'a', source_version: 'v1', method: 'import' } })]);
  assert.equal(rej.resolved.value, 'Y');
  assert.equal(rej.resolved.status, 'overridden');
});

test('si las fuentes cambian, el override ya no vale: el conflicto VUELVE a abrirse (stale) y se avisa', () => {
  const base = resolve([claim('a', 'X'), claim('b', 'Y')]);
  const changed = [claim('a', 'X'), claim('b', 'Y2')];
  const r = resolve(changed, [override(base.conflict.fingerprint, { prefer_claim: { source: 'b', source_version: 'v1', method: 'import' } })]);
  assert.equal(r.resolved.status, 'conflict');
  assert.equal(r.resolved.value, null);
  assert.equal(r.conflict.status, 'stale');
  assert.ok(r.report.warnings.some((w) => w.code === 'W-OVERRIDE-STALE'));
});

test('un override que no se puede aplicar es un error, no se aplica a medias', () => {
  const base = resolve([claim('a', 'X'), claim('b', 'Y')]);
  const r = resolve([claim('a', 'X'), claim('b', 'Y')], [override(base.conflict.fingerprint, { prefer_claim: { source: 'a', source_version: 'otra', method: 'import' } })]);
  assert.ok(r.report.errors.some((e) => e.code === 'W-OVERRIDE-INVALID'));
  assert.equal(r.resolved.status, 'conflict');
});

// ---------------------------------------------------------------- normalización sobre datasets
function normalized(root) {
  const report = new Report();
  const ds = loadDataset(root, report, { skipWorld: true });
  const w = buildWorld(ds, report);
  return { report, ds, w };
}

test('normalización del dataset real: 3 documentos, sin errores, display_id como dato de investigación con su procedencia', () => {
  const { report, w } = normalized(REAL_ROOT);
  assert.deepEqual(report.format(), []);
  assert.deepEqual(Array.from(w.outputs.keys()).sort(), ['world/era/creature/658.json', 'world/era/creature/786.json', 'world/era/place/valle_de_crestanevada.json']);
  const grelin = w.outputs.get('world/era/creature/786.json');
  assert.equal(grelin.attributes.display_id.resolved.value, 1354);
  assert.equal(grelin.attributes.display_id.claims[0].provenance.source, 'legacy_addon');
  assert.equal(grelin.exists.claims[0].confidence, 'client_verified');
  assert.equal(grelin.exists.claims[0].provenance.source, 'wow_client');
});

test('normalización: el resultado NO depende del orden de los registros', () => {
  const { ds, w } = normalized(FIXTURE_ROOT);
  const reversed = { ...ds, records: ds.records.slice().reverse().map((r) => ({ ...r, doc: { ...r.doc, records: r.doc.records.slice().reverse() } })) };
  const report = new Report();
  const w2 = buildWorld(reversed, report);
  assert.deepEqual(Array.from(w2.outputs.entries()).map(([k, v]) => [k, canonicalPretty(v)]), Array.from(w.outputs.entries()).map(([k, v]) => [k, canonicalPretty(v)]));
});

test('normalización del dataset de fixtures: el conflicto sintético queda abierto y bloqueante', () => {
  const { w } = normalized(FIXTURE_ROOT);
  assert.equal(w.conflicts.length, 1);
  assert.equal(w.conflicts[0].subject.id, 90005);
  assert.equal(w.conflicts[0].status, 'open');
  const doc = w.outputs.get('world/era/creature/90005.json');
  assert.equal(doc.names.enUS.resolved.status, 'conflict');
  assert.equal(doc.exists.resolved.value, 'present');
});

function withTmp(fn) {
  const tmp = copyDataset(FIXTURE_ROOT);
  try { return fn(tmp); } finally { rm(tmp); }
}

test('registros inválidos: fuente desconocida, flavor no aplicable, flavor desconocido, campo de texto en una criatura', () => {
  withTmp((tmp) => {
    const doc = JSON.parse(read(tmp, 'sources/records/fixture_source_a.json'));
    doc.source = 'fantasma'; // fichero con el nombre correcto, pero sin manifiesto en sources/
    write(tmp, 'sources/records/fantasma.json', canonicalPretty(doc));
    const { report } = normalized(tmp);
    assert.ok(report.errors.some((e) => e.code === 'R-05' && /fantasma/.test(e.message)));
  });
  withTmp((tmp) => {
    edit(tmp, 'sources/fixture_source_a.yaml', 'applicable_flavors: [era, fixture_alt]', 'applicable_flavors: [fixture_alt]');
    const { report } = normalized(tmp);
    assert.ok(report.errors.some((e) => e.code === 'R-03'), report.format().join('\n'));
  });
  withTmp((tmp) => {
    edit(tmp, 'editorial/flavors.yaml', '  fixture_alt:', '  otro:');
    const { report } = normalized(tmp);
    assert.ok(report.errors.some((e) => e.code === 'R-07'));
  });
  withTmp((tmp) => {
    const f = 'sources/records/fixture_source_a.json';
    const doc = JSON.parse(read(tmp, f));
    doc.records[0].field = 'texts.esES.zone_text';
    write(tmp, f, canonicalPretty(doc));
    const { report } = normalized(tmp);
    assert.ok(report.errors.some((e) => e.code === 'R-09'));
  });
});

test('una entidad del mundo sin afirmación de existencia es un error', () => {
  withTmp((tmp) => {
    const f = 'sources/records/fixture_source_a.json';
    const doc = JSON.parse(read(tmp, f));
    doc.records[0].subject = { flavor: 'era', kind: 'creature', id: 90077 };
    write(tmp, f, canonicalPretty(doc));
    const { report } = normalized(tmp);
    assert.ok(report.errors.some((e) => e.code === 'R-06' && /90077/.test(e.file)));
  });
});

test('una fuente bloqueada no puede aportar registros', () => {
  withTmp((tmp) => {
    edit(tmp, 'sources/fixture_source_b.yaml', 'status: research_only', 'status: blocked');
    edit(tmp, 'sources/fixture_source_b.yaml', 'usage: { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: false }', 'usage: { research: false, contrast: false, local_validation: false, candidate_generation: false, generated_data: false }');
    const { report } = normalized(tmp);
    assert.ok(report.errors.some((e) => e.code === 'R-04'));
  });
});

test('la huella del conflicto es la de sus claims (sin fechas): el override del fixture coincide', () => {
  const { w } = normalized(FIXTURE_ROOT);
  const c = w.conflicts[0];
  assert.equal(c.fingerprint, fingerprint(c.claims));
});
