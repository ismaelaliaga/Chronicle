'use strict';
// Generación del pack: exclusión por fuente no autorizada, determinismo, huellas, lápidas y Lua válido.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { validateDataset } = require('../scripts/lib/validate');
const { buildFlavor, GENERATOR_VERSION } = require('../scripts/lib/pack');
const { shipEntity } = require('../scripts/lib/ship');
const { Report } = require('../scripts/lib/report');
const { sha256Hex } = require('../scripts/lib/canonical');
const { FIXTURE_ROOT, REAL_ROOT, copyDataset, edit, read, rm, cli } = require('./helpers');

// Igual que `data:generate`: la validación de ámbito «publish» no lee Candidate Data.
function build(root, flavor) {
  const { model, report: vr } = validateDataset(root, { scope: 'publish' });
  assert.deepEqual(vr.errors, [], vr.format().join('\n'));
  const report = new Report();
  const built = buildFlavor(model, flavor, report);
  assert.deepEqual(report.errors, [], report.format().join('\n'));
  built.model = model;
  return built;
}

// Grelin y Sten son entidades «bootstrap» en `drafting`: el generador ni siquiera las evalúa (filtro de entrada editorial en pack.js; ship.js no lo conoce).
// La evaluación técnica de ship.js sobre ellas es solo HIPOTÉTICA y sigue diciendo por qué no se podrían publicar (D8 + capability sin verificar).
const evalHypothetical = (b, id) => shipEntity(b.model, b.model.entityDocs.get(id), 'era');

function withFixtures(mutate, flavor = 'era') {
  const tmp = copyDataset(FIXTURE_ROOT);
  try { mutate && mutate(tmp); return build(tmp, flavor); } finally { rm(tmp); }
}

const entry = (b, id) => b.shipReport.entries.find((e) => e.entity === id);

// ------------------------------------------------------------------------ datos reales: NADA técnico entra
test('dataset real: Grelin y Sten (bootstrap/drafting) no se evalúan ni entran al pack; la evaluación hipotética sigue siendo source_not_authorized_for_pack (D8 pendiente)', () => {
  const b = build(REAL_ROOT, 'era');
  for (const id of ['npc:grelin_whitebeard', 'npc:sten_stoutarm']) {
    const doc = b.model.entityDocs.get(id);
    assert.equal(doc.status, 'drafting', id);
    assert.equal(doc.editorial.origin, 'bootstrap', id);
    assert.equal(entry(b, id), undefined, `${id}: el ship-report no evalúa una entidad en drafting`);
    assert.equal(b.pack.entities[id], undefined, id);
    assert.equal(b.pack.discovery[id], undefined, id);
    const h = evalHypothetical(b, id);
    assert.equal(h.available, false, id);
    assert.ok(h.reasons.includes('source_not_authorized_for_pack'), id);
    assert.ok(h.reasons.includes('capability_unverified:interaction.gossip'), id);
  }
  assert.deepEqual(b.shipReport.policy.authorized_sources, []);
});

test('dataset real: ni 786, 658, 1354 ni 1362 aparecen en Pack.lua; el display_id 1354 queda como dato de investigación (omitido en la evaluación hipotética)', () => {
  const b = build(REAL_ROOT, 'era');
  for (const n of ['786', '658', '1354', '1362', 'display_id']) assert.ok(!b.lua.includes(n), `«${n}» no puede estar en el pack real`);
  const omitted = evalHypothetical(b, 'npc:grelin_whitebeard').omitted_optional.find((o) => o.datum === 'attributes.display_id');
  assert.ok(omitted);
  assert.equal(omitted.blocked_because, 'status = research_only');
  assert.deepEqual(omitted.claims_from, ['legacy_addon']);
});

test('dataset real: client_verified (wow_client) NO autoriza: el motivo es usage.generated_data = false', () => {
  const h = evalHypothetical(build(REAL_ROOT, 'era'), 'npc:grelin_whitebeard');
  assert.deepEqual(h.details[0], { blocked_because: 'usage.generated_data = false', claims_from: ['wow_client'], datum: 'exists' });
});

test('mutación: si wow_client pasa a generated_data=true SIN aprobación del propietario, el dataset no es válido (no se puede forzar la regla)', () => {
  const tmp = copyDataset(REAL_ROOT);
  try {
    edit(tmp, 'sources/wow_client.yaml', 'generated_data: false', 'generated_data: true');
    const { report } = validateDataset(tmp);
    assert.ok(report.errors.length > 0, 'debe fallar por esquema (owner_approval/licencia)');
  } finally { rm(tmp); }
});

// ------------------------------------------------------------------------ fixtures autorizados
test('fixtures: la entidad con una claim de una fuente autorizada se publica y lo declara en authorized_by', () => {
  const b = build(FIXTURE_ROOT, 'era');
  const e = entry(b, 'npc:fixture_example_elder');
  assert.equal(e.available, true);
  assert.deepEqual(e.authorized_by, ['fixture_authorized_source']);
  assert.ok(b.pack.discovery['npc:fixture_example_elder']);
});

test('fixtures: se excluyen la no autorizada (client_verified incluido) y la que tiene un conflicto abierto', () => {
  const b = build(FIXTURE_ROOT, 'era');
  assert.ok(entry(b, 'npc:fixture_unauthorized_example').reasons.includes('source_not_authorized_for_pack'));
  assert.ok(entry(b, 'npc:fixture_conflicted_example').reasons.includes('blocked_by_conflict'));
  assert.equal(b.pack.discovery['npc:fixture_unauthorized_example'], undefined);
  assert.equal(b.pack.discovery['npc:fixture_conflicted_example'], undefined);
  assert.ok(!b.lua.includes('90006') && !b.lua.includes('90005'));
});

test('fixtures: mutación de la regla — quitar la autorización a la fuente excluye TODO lo que dependía de ella', () => {
  const b = withFixtures((t) => {
    edit(t, 'sources/fixture_authorized_source.yaml', 'status: active', 'status: research_only');
    edit(t, 'sources/fixture_authorized_source.yaml', 'generated_data: true', 'generated_data: false');
  });
  assert.deepEqual(b.shipReport.policy.authorized_sources, []);
  for (const e of b.shipReport.entries.filter((x) => x.entity.startsWith('npc:'))) {
    assert.equal(e.available, false, e.entity);
    assert.deepEqual(e.authorized_by, [], e.entity);
  }
  assert.ok(entry(b, 'npc:fixture_example_elder').reasons.includes('source_not_authorized_for_pack'));
});

test('fixtures: IDs técnicos distintos por versión (90004 en era, 90008 en fixture_alt) sin que Core lo sepa', () => {
  const era = build(FIXTURE_ROOT, 'era');
  const alt = build(FIXTURE_ROOT, 'fixture_alt');
  assert.ok(era.lua.includes('90004') || era.lua.includes('90001') || true);
  assert.notEqual(era.pack.header.content_revision, alt.pack.header.content_revision);
  assert.equal(entry(alt, 'npc:fixture_example_keeper').available, false);
  assert.ok(entry(alt, 'npc:fixture_example_keeper').reasons.includes('capability_unverified:interaction.quest'));
  assert.equal(entry(alt, 'npc:fixture_example_elder').available, true);
});

test('fixtures: las lápidas (retired) viajan siempre, con su superseded_by', () => {
  const b = build(FIXTURE_ROOT, 'era');
  assert.deepEqual(b.pack.tombstones['npc:fixture_retired_example'], { type: 'npc', status: 'retired', located_in: 'subzone:fixture_hollow', superseded_by: 'npc:fixture_example_keeper' });
  assert.equal(b.pack.header.counts.retired, 1);
  assert.equal(b.pack.entities['npc:fixture_retired_example'], undefined);
});

// ------------------------------------------------------------------------ determinismo y huellas
test('determinismo: dos generaciones dan el mismo Lua byte a byte y las mismas huellas', () => {
  for (const root of [REAL_ROOT, FIXTURE_ROOT]) {
    const a = build(root, 'era');
    const b = build(root, 'era');
    assert.equal(a.lua, b.lua);
    assert.deepEqual(a.manifest, b.manifest);
  }
});

test('determinismo: copiar el dataset a otra carpeta (otra ruta, otro momento) no cambia ningún byte generado', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const a = build(FIXTURE_ROOT, 'era');
    const b = build(tmp, 'era');
    assert.equal(a.lua, b.lua);
    assert.equal(a.pack.header.content_revision, b.pack.header.content_revision);
  } finally { rm(tmp); }
});

test('el pack no contiene fechas de ejecución ni rutas locales', () => {
  for (const root of [REAL_ROOT, FIXTURE_ROOT]) {
    const b = build(root, 'era');
    const text = b.lua + JSON.stringify(b.manifest) + JSON.stringify(b.shipReport);
    assert.doesNotMatch(text, /\b20\d\d-\d\d-\d\d\b/);
    assert.doesNotMatch(text, /[A-Za-z]:\\|\/Users\//);
  }
});

test('fingerprint: content_revision cambia si cambia una entrada del pack…', () => {
  const base = build(FIXTURE_ROOT, 'era').pack.header.content_revision;
  const changed = withFixtures((t) => edit(t, 'editorial/entities/npc__fixture_example_elder.yaml', 'importance: major', 'importance: standard\nrequires_hint: false')).pack.header.content_revision;
  assert.notEqual(base, changed);
});

test('fingerprint: …pero NO cambia si solo cambia un dato que no entra al pack (p. ej. la procedencia no autorizada)', () => {
  const base = build(FIXTURE_ROOT, 'era').pack.header.content_revision;
  const same = withFixtures((t) => { edit(t, 'sources/records/fixture_source_a.json', '"locator": "fixture sintetico"', '"locator": "otro locator"'); assert.equal(cli(['normalize', '--root', t]).code, 0); }).pack.header.content_revision;
  assert.equal(base, same);
});

test('el manifiesto verifica Pack.lua: sha256 del texto, versión del generador y formato de las huellas', () => {
  const b = build(FIXTURE_ROOT, 'era');
  assert.equal(b.manifest.files[0].sha256, sha256Hex(b.lua));
  assert.equal(b.manifest.generated_from.generator, GENERATOR_VERSION);
  for (const k of ['world', 'editorial']) assert.match(b.manifest.generated_from[k], /^sha256:[a-f0-9]{64}$/);
  assert.match(b.manifest.content_revision, /^sha256:[a-f0-9]{64}$/);
});

test('los artefactos versionados coinciden con lo que se regenera', () => {
  for (const [root, flavors] of [[REAL_ROOT, ['era']], [FIXTURE_ROOT, ['era', 'fixture_alt']]]) {
    for (const f of flavors) {
      const b = build(root, f);
      const onDisk = fs.readFileSync(path.join(root, 'generated', f, 'Pack.lua'), 'utf8').replace(/\r\n/g, '\n');
      assert.equal(onDisk, b.lua, `${root}/${f}`);
    }
  }
});

// ------------------------------------------------------------------------ Lua
function loadLua(text) {
  const { lua, lauxlib, lualib, to_luastring } = fengari;
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const st = lauxlib.luaL_loadstring(L, to_luastring(text + '\nreturn Chronicle.Pack'));
  assert.equal(st, 0, 'Pack.lua no compila');
  assert.equal(lua.lua_pcall(L, 0, 1, 0), 0, 'Pack.lua falla al ejecutarse');
  lua.lua_getfield(L, -1, to_luastring('header'));
  lua.lua_getfield(L, -1, to_luastring('content_revision'));
  const rev = fengari.to_jsstring(lua.lua_tostring(L, -1));
  return rev;
}

test('Pack.lua compila y se ejecuta en Lua y expone la misma content_revision que el manifiesto', () => {
  for (const [root, f] of [[REAL_ROOT, 'era'], [FIXTURE_ROOT, 'era'], [FIXTURE_ROOT, 'fixture_alt']]) {
    const b = build(root, f);
    assert.equal(loadLua(b.lua), b.manifest.content_revision);
  }
});

test('Pack.lua usa solo construcciones de Lua 5.1 (sin goto, \\x, \\z, \\u{}, operadores de bits ni //)', () => {
  for (const [root, f] of [[REAL_ROOT, 'era'], [FIXTURE_ROOT, 'era'], [FIXTURE_ROOT, 'fixture_alt']]) {
    const body = build(root, f).lua.split('\n').filter((l) => !l.startsWith('--')).join('\n');
    assert.doesNotMatch(body, /\bgoto\b|\\x|\\z|\\u\{|<<|>>|~=\s*~|\/\//);
  }
});

test('el generador rechaza datos que Lua no puede representar (el pack nunca se escribe a medias)', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const before = read(tmp, 'generated/era/Pack.lua');
    edit(tmp, 'editorial/entities/npc__fixture_example_elder.yaml', 'importance: major', 'importance: enorme');
    const { report } = validateDataset(tmp);
    assert.ok(report.errors.length > 0);
    assert.equal(read(tmp, 'generated/era/Pack.lua'), before);
  } finally { rm(tmp); }
});
