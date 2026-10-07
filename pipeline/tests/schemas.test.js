'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { listSchemas, getValidator, validateDoc } = require('../scripts/lib/schemas');
const { Report } = require('../scripts/lib/report');
const { loadDataset } = require('../scripts/lib/loader');
const { FIXTURE_ROOT, REAL_ROOT } = require('./helpers');

const FP = 'sha256:' + 'a'.repeat(64);

function check(name, doc) {
  const report = new Report();
  const ok = validateDoc(name, doc, report, 'x');
  return { ok, text: report.format().join('\n') };
}

const source = (over = {}) => Object.assign({
  schema: 'chronicle.world.source/1', id: 's', name: 'S', kind: 'other', origin_group: 'g', trust_tier: 6, applicable_flavors: ['era'],
  obtained: { method: 'manual_download', version: 'v' },
  license: { status: 'known', summary: 's', redistribution: 'allowed', derived_data: 'allowed' },
  usage: { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: false }, status: 'active',
}, over);

test('todos los esquemas del pipeline son ejecutables (compilan en modo estricto)', () => {
  const names = listSchemas();
  assert.ok(names.length >= 20, `se esperaban ≥20 esquemas y hay ${names.length}`);
  for (const n of ['common', 'world.source', 'world.entity', 'world.place', 'world.observation', 'world.client_profile', 'world.conflict',
    'candidate.record', 'candidate.scoring_profile', 'editorial.entity', 'editorial.binding', 'editorial.hint', 'editorial.text', 'editorial.override', 'pack.manifest', 'report.ship']) {
    assert.ok(names.includes(n), `falta el esquema ${n}`);
  }
  for (const n of names) if (n !== 'common') assert.equal(typeof getValidator(n), 'function', n);
});

test('cada esquema del directorio es JSON válido con $id y draft 2020-12', () => {
  const dir = path.join(REAL_ROOT, 'schemas');
  for (const f of fs.readdirSync(dir)) {
    const s = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    assert.equal(s.$schema, 'https://json-schema.org/draft/2020-12/schema', f);
    assert.equal(s.$id, 'https://chronicle.local/schemas/' + f, f);
  }
});

test('world.source: generated_data=true exige owner_approval, licencia conocida y status active', () => {
  const usage = { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: true };
  assert.equal(check('world.source', source({ usage })).ok, false); // sin owner_approval
  assert.match(check('world.source', source({ usage })).text, /owner_approval/);
  assert.equal(check('world.source', source({ usage, owner_approval: { by: 'x', scope: 'y' } })).ok, true);
  assert.equal(check('world.source', source({ usage, owner_approval: { by: 'x', scope: 'y' }, license: { status: 'unknown', summary: 's', redistribution: 'allowed', derived_data: 'allowed' } })).ok, false);
  assert.equal(check('world.source', source({ usage, owner_approval: { by: 'x', scope: 'y' }, license: { status: 'known', summary: 's', redistribution: 'unknown', derived_data: 'allowed' } })).ok, false);
});

test('world.source: una fuente research_only o blocked nunca puede alimentar el pack', () => {
  const usage = { research: true, contrast: true, local_validation: true, candidate_generation: true, generated_data: true };
  assert.equal(check('world.source', source({ usage, owner_approval: { by: 'x', scope: 'y' }, status: 'research_only' })).ok, false);
  assert.equal(check('world.source', source({ usage, owner_approval: { by: 'x', scope: 'y' }, status: 'blocked' })).ok, false);
  assert.equal(check('world.source', source({ status: 'research_only' })).ok, true);
});

test('Provenance: capture exige client_build y manual exige by', () => {
  const rec = (provenance) => ({ schema: 'chronicle.world.claim_records/1', source: 's', records: [{ flavor: 'era', subject: { flavor: 'era', kind: 'creature', id: 1 }, field: 'exists', value: 'present', confidence: 'client_verified', provenance }] });
  assert.equal(check('world.claim_records', rec({ source_version: 'v', method: 'capture' })).ok, false);
  assert.equal(check('world.claim_records', rec({ source_version: 'v', method: 'capture', client_build: 'b' })).ok, true);
  assert.equal(check('world.claim_records', rec({ source_version: 'v', method: 'manual' })).ok, false);
  assert.equal(check('world.claim_records', rec({ source_version: 'v', method: 'manual', by: 'x' })).ok, true);
  assert.equal(check('world.claim_records', rec({ method: 'import' })).ok, false); // falta source_version: sin procedencia no hay dato
});

test('world.claim_records: el campo debe ser uno del catálogo (atributos fuera del catálogo se rechazan)', () => {
  const rec = (field) => ({ schema: 'chronicle.world.claim_records/1', source: 's', records: [{ flavor: 'era', subject: { flavor: 'era', kind: 'creature', id: 1 }, field, value: 1, confidence: 'source_reported', provenance: { source_version: 'v', method: 'import' } }] });
  assert.equal(check('world.claim_records', rec('attributes.display_id')).ok, true);
  assert.equal(check('world.claim_records', rec('attributes.coordenadas_inventadas')).ok, false);
  assert.equal(check('world.claim_records', rec('exists')).ok, true);
});

test('IDs: ChronicleId, HintId, TechRef y flavor rechazan formatos inválidos', () => {
  const entity = (id) => ({ schema: 'chronicle.editorial.entity/1', id, type: 'subzone', status: 'published', applies_to: ['era'], editorial: { author: 'x' } });
  assert.equal(check('editorial.entity', entity('subzone:ok_slug')).ok, true);
  for (const bad of ['npc:786', 'Subzone:x', 'subzone:Mayus', 'subzone:con-guion', 'subzone:_x', 'subzone:x__y', 'otro:x', 'subzone:']) {
    assert.equal(check('editorial.entity', entity(bad)).ok, false, bad);
  }
  assert.equal(check('editorial.hint', { schema: 'chronicle.editorial.hint/1', id: 'npc:x', target: 'npc:x', kind: 'narrative', necessity: 'required', tier: 1, text: 'hint:x', status: 'draft', editorial: { author: 'x' } }).ok, false);
});

test('editorial.entity: npc exige discovery salvo si está retirada; una retirada exige «retired» y no lleva reglas', () => {
  const base = { schema: 'chronicle.editorial.entity/1', id: 'npc:x', type: 'npc', applies_to: ['era'], editorial: { author: 'a', origin: 'candidate' } };
  assert.equal(check('editorial.entity', { ...base, status: 'published' }).ok, false);
  assert.equal(check('editorial.entity', { ...base, status: 'published', discovery: { method: 'interaction', interaction: { type: 'gossip' } } }).ok, true);
  assert.equal(check('editorial.entity', { ...base, status: 'retired', applies_to: [], retired: { reason: 'r' } }).ok, true);
  assert.equal(check('editorial.entity', { ...base, status: 'retired', applies_to: [] }).ok, false);
  assert.equal(check('editorial.entity', { ...base, status: 'retired', applies_to: [], retired: { reason: 'r' }, discovery: { method: 'none' } }).ok, false);
  assert.equal(check('editorial.entity', { ...base, status: 'published', discovery: { method: 'none' }, retired: { reason: 'r' } }).ok, false);
});

test('editorial.entity: no admite campos técnicos del cliente (npcID, displayID, coordenadas)', () => {
  const doc = { schema: 'chronicle.editorial.entity/1', id: 'npc:x', type: 'npc', status: 'published', applies_to: ['era'], editorial: { author: 'a', origin: 'candidate' }, discovery: { method: 'none' } };
  for (const extra of [{ npcID: 786 }, { displayID: 1 }, { x: 1, y: 2 }, { name: 'texto' }]) assert.equal(check('editorial.entity', { ...doc, ...extra }).ok, false, JSON.stringify(extra));
});

test('DiscoveryRules: gramática de interacción (type/any/all) y requisitos; other exige label', () => {
  const entity = (discovery) => ({ schema: 'chronicle.editorial.entity/1', id: 'npc:x', type: 'npc', status: 'published', applies_to: ['era'], editorial: { author: 'a', origin: 'candidate' }, discovery });
  const ok = (d) => check('editorial.entity', entity(d)).ok;
  assert.equal(ok({ method: 'interaction', interaction: { type: 'quest' } }), true);
  assert.equal(ok({ method: 'interaction', interaction: { any: [{ type: 'gossip' }, { type: 'quest' }] } }), true);
  assert.equal(ok({ method: 'interaction', interaction: { all: [{ type: 'gossip' }, { type: 'trainer' }] } }), true); // el esquema lo admite; la validación lo trata como RESERVADO
  assert.equal(ok({ method: 'interaction', interaction: { type: 'ver' } }), false);
  assert.equal(ok({ method: 'interaction', interaction: { type: 'other' } }), false);
  assert.equal(ok({ method: 'interaction', interaction: { type: 'other', label: 'x' } }), true);
  assert.equal(ok({ method: 'interaction' }), false); // interaction obligatoria
  assert.equal(ok({ method: 'none', interaction: { type: 'gossip' } }), false);
  assert.equal(ok({ method: 'interaction', interaction: { type: 'gossip' }, requirements: { all: [{ place_discovered: { id: 'zone:a', strict: true } }, { entity_discovered: { id: 'npc:b' } }] } }), true);
  assert.equal(ok({ method: 'interaction', interaction: { type: 'gossip' }, requirements: { place_discovered: { id: 'zone:a' }, entity_discovered: { id: 'npc:b' } } }), false);
  // ver / ratón / objetivo / placa / proximidad NO son interacciones
  for (const t of ['mouseover', 'target', 'nameplate', 'proximity', 'see']) assert.equal(ok({ method: 'interaction', interaction: { type: t } }), false, t);
});

test('world.observation: un jugador no aporta datos identificables y un valor secreto no aporta identidad', () => {
  const obs = (unit) => ({
    schema: 'chronicle.world.observation/1', id: 'obs:abcd', flavor: 'era', locale: 'esES',
    client: { build: 'b', interface: 1, signals: {} }, captured_with: { tool: 't', version: '1' }, observed_at: '2026-10', restricted_context: false,
    kind: 'unit', payload: unit,
  });
  assert.equal(check('world.observation', obs({ unit_type: 'creature', npc_id: 5, name: 'N', secret: false })).ok, true);
  assert.equal(check('world.observation', obs({ unit_type: 'player', name: 'Jugador', secret: false })).ok, false);
  assert.equal(check('world.observation', obs({ unit_type: 'player', secret: false })).ok, true);
  assert.equal(check('world.observation', obs({ unit_type: 'creature', npc_id: 5, secret: true })).ok, false);
  assert.equal(check('world.observation', obs({ unit_type: 'creature', secret: true })).ok, true);
  assert.equal(check('world.observation', obs({ unit_type: 'creature', npc_id: 5, secret: false, guid: 'Creature-0-1-0-2-5-3' })).ok, false); // el GUID crudo no se guarda
});

test('candidate.record: ningún campo de inclusión o decisión (SCORE != DECISION EDITORIAL)', () => {
  const rec = {
    schema: 'chronicle.candidate.record/1', id: 'cand:era:creature:1', flavor: 'era', subject: { flavor: 'era', kind: 'creature', id: 1 },
    display: { names: {} }, profile: { id: 'p', version: 1 }, signals: [], score: { total: 0 }, rank: 1, inputs_fingerprint: FP,
    sources: [{ source: 's', origin_group: 's', claims: 1 }], evidence_summary: { independent_origins: 1, client_verified: false, open_conflicts: 0 }, research: { status: 'new' },
  };
  assert.equal(check('candidate.record', rec).ok, true);
  for (const extra of [{ include: true }, { accepted: true }, { status: 'accepted' }, { decision: 'accept' }]) assert.equal(check('candidate.record', { ...rec, ...extra }).ok, false, JSON.stringify(extra));
});

test('world.client_profile: una capacidad verified exige evidencia', () => {
  const p = (cap) => ({ schema: 'chronicle.world.client_profile/1', flavor: 'era', build: 'b', interface: 1, signals: {}, capabilities: { 'interaction.gossip': cap } });
  assert.equal(check('world.client_profile', p({ status: 'verified', evidence: [] })).ok, false);
  assert.equal(check('world.client_profile', p({ status: 'verified', evidence: ['obs:abcd'] })).ok, true);
  assert.equal(check('world.client_profile', p({ status: 'unverified', evidence: [] })).ok, true);
});

test('world.entity: Resolved coherente (conflict => null y conflicto; overridden => override)', () => {
  const prov = { source: 's', source_version: 'v', method: 'import' };
  const entity = (resolved) => ({ schema: 'chronicle.world.entity/1', ref: { flavor: 'era', kind: 'creature', id: 1 }, exists: { claims: [{ value: 'present', provenance: prov, confidence: 'source_reported' }], resolved } });
  assert.equal(check('world.entity', entity({ value: 'present', status: 'resolved', rule: 'single_claim' })).ok, true);
  assert.equal(check('world.entity', entity({ value: 'present', status: 'conflict', rule: 'none', conflict: 'conf:abcdef12' })).ok, false);
  assert.equal(check('world.entity', entity({ value: null, status: 'conflict', rule: 'none' })).ok, false);
  assert.equal(check('world.entity', entity({ value: null, status: 'conflict', rule: 'none', conflict: 'conf:abcdef12' })).ok, true);
  assert.equal(check('world.entity', entity({ value: 'present', status: 'overridden', rule: 'single_claim' })).ok, false);
});

test('los datasets reales y de fixtures cargan sin errores de esquema (todos sus ficheros pasan su contrato)', () => {
  for (const root of [REAL_ROOT, FIXTURE_ROOT]) {
    const report = new Report();
    loadDataset(root, report);
    assert.deepEqual(report.format(), [], root);
  }
});
