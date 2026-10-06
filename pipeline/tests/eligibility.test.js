'use strict';
// Regla de autorización para el pack (Fase 16, 5.2): usage.generated_data === true en AL MENOS UNA claim que respalde el valor resuelto.
const test = require('node:test');
const assert = require('node:assert/strict');
const { authorizedSourceIds, checkField } = require('../scripts/lib/eligibility');

const src = (id, generated, status = 'active') => ({ id, status, usage: { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: generated } });
const sourcesById = new Map([
  ['auth', src('auth', true)],
  ['client', src('client', false)],
  ['research', src('research', false, 'research_only')],
  ['blocked', src('blocked', false, 'blocked')],
]);
const authorized = authorizedSourceIds(sourcesById);
const claim = (source, value, confidence = 'source_reported') => ({ value, confidence, provenance: { source, source_version: 'v', method: 'import' } });
const field = (claims, resolved) => ({ claims, resolved: Object.assign({ value: claims[0].value, status: 'resolved', rule: 'single_claim' }, resolved) });

test('solo las fuentes activas con usage.generated_data=true están autorizadas', () => {
  assert.deepEqual(Array.from(authorized), ['auth']);
});

test('una claim de una fuente autorizada hace elegible el dato', () => {
  const r = checkField(field([claim('auth', 'present')]), sourcesById, authorized);
  assert.equal(r.eligible, true);
  assert.deepEqual(r.supportedBy, ['auth']);
});

test('client_verified NO equivale a autorización: un dato observado en el cliente de una fuente no autorizada NO es elegible', () => {
  const r = checkField(field([claim('client', 'present', 'client_verified')]), sourcesById, authorized);
  assert.equal(r.eligible, false);
  assert.deepEqual(r.blocked, [{ source: 'client', why: 'usage.generated_data = false' }]);
});

test('una fuente research_only o bloqueada explica el motivo y no es elegible', () => {
  const r1 = checkField(field([claim('research', 1354)]), sourcesById, authorized);
  assert.equal(r1.eligible, false);
  assert.equal(r1.blocked[0].why, 'status = research_only');
  const r2 = checkField(field([claim('blocked', 1)]), sourcesById, authorized);
  assert.equal(r2.blocked[0].why, 'status = blocked');
});

test('con varias claims del mismo valor basta UNA autorizada; las no autorizadas se listan como bloqueadas', () => {
  const r = checkField(field([claim('client', 'present', 'client_verified'), claim('auth', 'present')]), sourcesById, authorized);
  assert.equal(r.eligible, true);
  assert.deepEqual(r.supportedBy, ['auth']);
  assert.deepEqual(r.blocked.map((b) => b.source), ['client']);
});

test('una claim autorizada con OTRO valor no respalda el valor resuelto', () => {
  const f = { claims: [claim('auth', 'absent'), claim('client', 'present', 'client_verified')], resolved: { value: 'present', status: 'resolved', rule: 'tier_precedence' } };
  const r = checkField(f, sourcesById, authorized);
  assert.equal(r.eligible, false);
  assert.deepEqual(r.supportedBy, []);
});

test('un valor fijado por override (set_value) sin una claim autorizada que lo respalde no es elegible', () => {
  const f = { claims: [claim('auth', 'a'), claim('auth2', 'b')], resolved: { value: 'c', status: 'overridden', rule: 'override', override: 'ovr:x' } };
  const sources = new Map([...sourcesById, ['auth2', src('auth2', true)]]);
  assert.equal(checkField(f, sources, authorizedSourceIds(sources)).eligible, false);
});

test('un valor sin resolver (conflicto o desconocido) nunca es elegible', () => {
  const f = { claims: [claim('auth', 'a'), claim('auth', 'b')], resolved: { value: null, status: 'conflict', rule: 'none', conflict: 'conf:abcdef12' } };
  const r = checkField(f, sourcesById, authorized);
  assert.equal(r.eligible, false);
  assert.equal(r.noValue, true);
  assert.equal(checkField(undefined, sourcesById, authorized).eligible, false);
});

test('una fuente desconocida no está autorizada (falla en seguro)', () => {
  const r = checkField(field([claim('fantasma', 1)]), sourcesById, authorized);
  assert.equal(r.eligible, false);
  assert.equal(r.blocked[0].why, 'fuente desconocida');
});
