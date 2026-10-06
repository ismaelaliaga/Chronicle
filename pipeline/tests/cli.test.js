'use strict';
// CLI: códigos de salida, idempotencia, detección de manipulaciones y de artefactos obsoletos.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { FIXTURE_ROOT, REAL_ROOT, copyDataset, edit, read, write, cli, rm } = require('./helpers');

const rootArg = (r) => ['--root', r];

test('uso incorrecto: comando o argumento desconocido => código 2', () => {
  assert.equal(cli(['volar']).code, 2);
  assert.equal(cli(['validate', '--nada']).code, 2);
  assert.equal(cli([]).code, 2);
});

test('validate / check sobre los datasets versionados terminan con 0', () => {
  for (const r of [REAL_ROOT, FIXTURE_ROOT]) {
    assert.equal(cli(['validate', ...rootArg(r)]).code, 0, r);
    const c = cli(['check', ...rootArg(r)]);
    assert.equal(c.code, 0, c.out);
    assert.match(c.out, /check: era: correcto/);
  }
});

test('pipeline es idempotente: dos ejecuciones sobre una copia no modifican ningún fichero la segunda vez', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const a = cli(['pipeline', ...rootArg(tmp)]);
    assert.equal(a.code, 0, a.out);
    const snapshot = (dir) => {
      const out = {};
      const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); e.isDirectory() ? walk(p) : (out[path.relative(tmp, p)] = fs.readFileSync(p, 'utf8')); } };
      walk(dir);
      return out;
    };
    const s1 = snapshot(tmp);
    const b = cli(['pipeline', ...rootArg(tmp)]);
    assert.equal(b.code, 0, b.out);
    assert.doesNotMatch(b.out, /escrito |borrado /);
    assert.deepEqual(snapshot(tmp), s1);
  } finally { rm(tmp); }
});

test('el resultado de la pipeline en una copia es IDÉNTICO a lo versionado (Pack.lua y manifiesto)', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    fs.rmSync(path.join(tmp, 'generated'), { recursive: true });
    assert.equal(cli(['pipeline', ...rootArg(tmp)]).code, 0);
    for (const f of ['era', 'fixture_alt']) for (const n of ['Pack.lua', 'pack-manifest.json', 'ship-report.json']) {
      assert.equal(read(tmp, `generated/${f}/${n}`), read(FIXTURE_ROOT, `generated/${f}/${n}`), `${f}/${n}`);
    }
  } finally { rm(tmp); }
});

test('check: editar Pack.lua a mano => código 1 (artefacto generado)', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    write(tmp, 'generated/era/Pack.lua', read(tmp, 'generated/era/Pack.lua') + '-- manual\n');
    const r = cli(['check', ...rootArg(tmp)]);
    assert.equal(r.code, 1);
    assert.match(r.out, /G-01/);
    assert.match(r.out, /no se edita a mano/);
  } finally { rm(tmp); }
});

test('check: falta del manifiesto, sha256 manipulado y artefactos de una versión no habilitada', () => {
  let tmp = copyDataset(FIXTURE_ROOT);
  try {
    fs.rmSync(path.join(tmp, 'generated/era/pack-manifest.json'));
    assert.match(cli(['check', ...rootArg(tmp)]).out, /falta el artefacto generado/);
  } finally { rm(tmp); }
  tmp = copyDataset(FIXTURE_ROOT);
  try {
    const m = JSON.parse(read(tmp, 'generated/era/pack-manifest.json'));
    m.files[0].sha256 = '0'.repeat(64);
    write(tmp, 'generated/era/pack-manifest.json', JSON.stringify(m, null, 2) + '\n');
    const r = cli(['check', ...rootArg(tmp)]);
    assert.equal(r.code, 1);
    assert.match(r.out, /sha256/);
  } finally { rm(tmp); }
  tmp = copyDataset(FIXTURE_ROOT);
  try {
    write(tmp, 'generated/viejo/Pack.lua', '-- x\n');
    const r = cli(['check', ...rootArg(tmp)]);
    assert.equal(r.code, 1);
    assert.match(r.out, /versión no habilitada/);
  } finally { rm(tmp); }
});

test('generate: no escribe NADA si el dataset no valida', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const before = read(tmp, 'generated/era/Pack.lua');
    edit(tmp, 'editorial/entities/zone__fixture_land.yaml', 'continent:fixture_world', 'continent:no_existe');
    edit(tmp, 'editorial/entities/npc__fixture_example_elder.yaml', 'importance: major', 'importance: standard\nrequires_hint: false');
    const r = cli(['generate', ...rootArg(tmp)]);
    assert.equal(r.code, 1);
    assert.match(r.out, /E-03/);
    assert.equal(read(tmp, 'generated/era/Pack.lua'), before);
  } finally { rm(tmp); }
});

test('validate: un error produce código 1 y un mensaje con código, fichero y ruta; la salida es estable', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    edit(tmp, 'editorial/bindings/era/npc__fixture_example_elder.yaml', 'id: 90004', 'id: 99999');
    const a = cli(['validate', ...rootArg(tmp)]);
    const b = cli(['validate', ...rootArg(tmp)]);
    assert.equal(a.code, 1);
    assert.match(a.out, /ERROR \[X-01\] editorial\/bindings\/era\/npc__fixture_example_elder\.yaml/);
    assert.equal(a.out.replace(/«[^»]*chronicle-pipeline-[^»]*»/g, '«tmp»'), b.out.replace(/«[^»]*chronicle-pipeline-[^»]*»/g, '«tmp»'));
  } finally { rm(tmp); }
});

test('normalize: reescribe World Data editado a mano y borra lo huérfano sin tocar lo ajeno', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    edit(tmp, 'world/era/creature/90001.json', '"value": "Fixture Keeper"', '"value": "EDITADO"');
    write(tmp, 'world/era/creature/12345.json', '{}\n');
    const r = cli(['normalize', ...rootArg(tmp)]);
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /escrito +world\/era\/creature\/90001\.json/);
    assert.match(r.out, /borrado +world\/era\/creature\/12345\.json/);
    assert.equal(read(tmp, 'world/era/creature/90001.json'), read(FIXTURE_ROOT, 'world/era/creature/90001.json'));
    assert.ok(fs.existsSync(path.join(tmp, 'world/era/profile.json')));
  } finally { rm(tmp); }
});

test('baseline: el CLI acepta --baseline-dir y detecta que un ID retirado ha desaparecido', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    fs.rmSync(path.join(tmp, 'editorial/entities/npc__fixture_retired_example.yaml'));
    const r = cli(['validate', ...rootArg(tmp), '--baseline-dir', FIXTURE_ROOT]);
    assert.equal(r.code, 1);
    assert.match(r.out, /E-05/);
  } finally { rm(tmp); }
});
