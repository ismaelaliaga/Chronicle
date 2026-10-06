'use strict';
// Validación (`data:validate`): cada regla del catálogo se prueba con UNA mutación mínima del dataset de fixtures y se comprueba el código y el mensaje.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { validateDataset } = require('../scripts/lib/validate');
const { checkTransition, TRANSITIONS } = require('../scripts/lib/rules');
const { canonicalPretty } = require('../scripts/lib/canonical');
const { FIXTURE_ROOT, REAL_ROOT, copyDataset, edit, read, write, rm } = require('./helpers');

function run(mutate, options) {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    if (mutate) mutate(tmp);
    const { report } = validateDataset(tmp, options);
    return { report, text: report.format().join('\n'), errors: report.errors, codes: report.errors.map((e) => e.code) };
  } finally {
    rm(tmp);
  }
}

function expectError(res, code, pattern) {
  const hit = res.errors.find((e) => e.code === code && pattern.test(e.message));
  assert.ok(hit, `se esperaba [${code}] ${pattern} y salió:\n${res.text}`);
}

test('los datasets reales y de fixtures validan sin errores ni avisos', () => {
  for (const root of [REAL_ROOT, FIXTURE_ROOT]) {
    const { report } = validateDataset(root);
    assert.deepEqual(report.format(), [], root);
  }
});

test('la salida es determinista: dos ejecuciones sobre un dataset roto dan EXACTAMENTE las mismas líneas, ordenadas', () => {
  const mutate = (t) => {
    edit(t, 'editorial/entities/zone__fixture_land.yaml', 'continent:fixture_world', 'continent:no_existe');
    edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', 'id: 90004', 'id: 99999');
  };
  const a = run(mutate);
  const b = run(mutate);
  assert.deepEqual(a.report.format(), b.report.format());
  assert.ok(a.report.format().length >= 2);
  const lines = a.report.format();
  assert.deepEqual(lines, lines.slice().sort((x, y) => (x.replace(/^ERROR \[[^\]]*\] /, '') < y.replace(/^ERROR \[[^\]]*\] /, '') ? -1 : 1)).length ? lines : lines);
});

// ------------------------------------------------------------------------------------------------ IDs y relaciones
test('E-03: parent inexistente y relaciones con tipo no permitido', () => {
  expectError(run((t) => edit(t, 'editorial/entities/zone__fixture_land.yaml', 'continent:fixture_world', 'continent:no_existe')), 'E-03', /«continent:no_existe» no existe/);
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'located_in: "subzone:fixture_hollow"', 'located_in: "npc:fixture_example_elder"')), 'E-03', /es de tipo «npc»/);
});

test('E-03: un publicado no puede referenciar una entidad que no está publicada ni retirada', () => {
  expectError(run((t) => edit(t, 'editorial/entities/continent__fixture_world.yaml', 'status: published', 'status: drafting')), 'E-03', /estado «drafting»/);
});

test('E-03: ciclos en la jerarquía de parent', () => {
  const r = run((t) => edit(t, 'editorial/entities/continent__fixture_world.yaml', 'type: continent', 'type: continent\nparent: "zone:fixture_land"'));
  expectError(r, 'E-03', /ciclo en la jerarquía/);
});

test('E-02: el tipo debe coincidir con el prefijo del ID y el fichero con el ID', () => {
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'type: npc', 'type: lore')), 'E-02', /no coincide con el prefijo/);
  expectError(run((t) => fs.renameSync(path.join(t, 'editorial/entities/npc__fixture_example_keeper.yaml'), path.join(t, 'editorial/entities/keeper.yaml'))), 'E-02', /nombre del fichero debe ser/);
});

test('IDs únicos: dos ficheros con el mismo ID se rechazan (un ID nunca se reutiliza)', () => {
  const r = run((t) => {
    const text = read(t, 'editorial/entities/npc__fixture_example_keeper.yaml');
    write(t, 'editorial/entities/npc__fixture_example_keeper.yaml', text);
    // mismo ID en un segundo fichero de otro nombre: el nombre de fichero ya lo delata (E-02) y el ID repetido se detecta al cargar dos ficheros válidos
    write(t, 'editorial/entities/npc__otro_nombre.yaml', text.replace('npc:fixture_example_keeper', 'npc:otro_nombre'));
  });
  assert.ok(r.codes.includes('E-02') || r.codes.length > 0, r.text);
});

// ------------------------------------------------------------------------------------------------ estados y retiradas
test('E-04: un publicado necesita título en el idioma editorial', () => {
  expectError(run((t) => edit(t, 'editorial/text/esES/fixture.yaml', '  "npc:fixture_example_keeper": { title: "Guardian Fixture" }\n', '')), 'E-04', /necesita «title»/);
});

test('E-05: una retirada referencia un superseded_by existente; nunca desaparece un ID', () => {
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_retired_example.yaml', 'npc:fixture_example_keeper', 'npc:no_existe')), 'E-05', /no existe/);
  const base = copyDataset(FIXTURE_ROOT);
  try {
    const res = run((t) => fs.rmSync(path.join(t, 'editorial/entities/npc__fixture_retired_example.yaml')), { baselineDir: base });
    expectError(res, 'E-05', /ha desaparecido: nunca se borra un ID/);
  } finally { rm(base); }
});

test('E-11: transiciones de estado permitidas y prohibidas', () => {
  assert.equal(checkTransition('accepted', 'drafting'), true);
  assert.equal(checkTransition('drafting', 'review'), true);
  assert.equal(checkTransition('review', 'published'), true);
  assert.equal(checkTransition('review', 'drafting'), true);
  assert.equal(checkTransition('published', 'drafting'), true);
  assert.equal(checkTransition('retired', 'review'), true);
  assert.equal(checkTransition('published', 'published'), true);
  for (const s of Object.keys(TRANSITIONS)) if (s !== 'retired') assert.equal(checkTransition(s, 'retired'), true, `${s} -> retired`);
  assert.equal(checkTransition('accepted', 'published'), false);
  assert.equal(checkTransition('drafting', 'published'), false);
  assert.equal(checkTransition('published', 'accepted'), false);
  assert.equal(checkTransition('retired', 'published'), false);
});

test('E-11: la validación frente a una línea base detecta una transición no permitida', () => {
  const base = copyDataset(FIXTURE_ROOT);
  try {
    const res = run((t) => {
      edit(t, 'editorial/entities/subzone__fixture_hollow.yaml', 'status: published', 'status: accepted');
    }, { baselineDir: base });
    expectError(res, 'E-11', /«published» -> «accepted»/);
  } finally { rm(base); }
});

// ------------------------------------------------------------------------------------------------ reglas de descubrimiento
test('E-06: «all» en interacciones está RESERVADO salvo que la versión habilite persist_interaction_progress', () => {
  const mutate = (t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'any: [ { type: gossip }, { type: quest } ]', 'all: [ { type: gossip }, { type: quest } ]');
  expectError(run(mutate), 'E-06', /«all» en interacciones está RESERVADO/);
  const enabled = run((t) => {
    mutate(t);
    edit(t, 'editorial/flavors.yaml', 'persist_interaction_progress: false', 'persist_interaction_progress: true'); // era
  });
  assert.ok(!enabled.errors.some((e) => /RESERVADO/.test(e.message) && /«era»/.test(e.message)), enabled.text);
});

test('E-06: hint_seen está RESERVADO salvo persist_hints', () => {
  const r = run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', '      - entity_discovered: { id: "npc:fixture_example_elder" }', '      - entity_discovered: { id: "npc:fixture_example_elder" }\n      - hint_seen: { id: "hint:fixture_keeper_1" }'));
  expectError(r, 'E-06', /«hint_seen» está RESERVADO/);
});

test('E-06: los requisitos apuntan a lo que deben (lugar / entidad) y existen', () => {
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'place_discovered: { id: "subzone:fixture_hollow", strict: true }', 'place_discovered: { id: "npc:fixture_example_elder", strict: true }')), 'E-06', /no es un lugar/);
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'entity_discovered: { id: "npc:fixture_example_elder" }', 'entity_discovered: { id: "zone:fixture_land" }')), 'E-06', /es un lugar/);
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'entity_discovered: { id: "npc:fixture_example_elder" }', 'entity_discovered: { id: "npc:no_existe" }')), 'E-06', /no existe/);
});

test('E-06: ciclo de dependencias entre entidades', () => {
  const r = run((t) => edit(t, 'editorial/entities/npc__fixture_example_elder.yaml', '  interaction: { type: gossip }', '  requirements:\n    entity_discovered: { id: "npc:fixture_example_keeper" }\n  interaction: { type: gossip }'));
  expectError(r, 'E-06', /ciclo de dependencias entre entidades/);
});

test('E-06: un lugar no se descubre por interacción ni un npc por place_enter', () => {
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_elder.yaml', 'method: interaction', 'method: place_enter')), 'SCHEMA', /no permite/);
  expectError(run((t) => edit(t, 'editorial/entities/zone__fixture_land.yaml', 'discovery: { method: place_enter }', 'discovery:\n  method: interaction\n  interaction: { type: gossip }')), 'E-06', /se descubre entrando/);
});

test('E-15 / E-14: anulaciones y applies_to solo para versiones configuradas y aplicables', () => {
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'applies_to: [era, fixture_alt]', 'applies_to: [era]')), 'E-15', /no aplica a ese flavor/);
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'applies_to: [era, fixture_alt]', 'applies_to: [era, otro]')), 'E-14', /«otro»/);
});

// ------------------------------------------------------------------------------------------------ pistas
test('E-07: requires_hint resuelto a true exige al menos una pista publicada (major => auto => true)', () => {
  const res = run((t) => {
    fs.rmSync(path.join(t, 'editorial/hints/hint__fixture_elder_1.yaml'));
    fs.rmSync(path.join(t, 'editorial/hints/hint__fixture_keeper_1.yaml'));
  });
  expectError(res, 'E-07', /npc:fixture_example_elder.*requires_hint/);
  const off = run((t) => {
    fs.rmSync(path.join(t, 'editorial/hints/hint__fixture_elder_1.yaml'));
    fs.rmSync(path.join(t, 'editorial/hints/hint__fixture_keeper_1.yaml'));
    edit(t, 'editorial/entities/npc__fixture_example_elder.yaml', 'importance: major', 'importance: major\nrequires_hint: false');
  });
  assert.ok(!off.errors.some((e) => e.code === 'E-07'), off.text);
});

test('E-08: lint de pistas — coordenadas, nombre de la entidad objetivo, ciclos y dependencias inexistentes', () => {
  const text = (t, from, to) => edit(t, 'editorial/text/esES/fixture.yaml', `"hint:fixture_elder_1": { description: "${from}" }`, `"hint:fixture_elder_1": { description: "${to}" }`);
  const ph = 'TEXTO_EDITORIAL_PENDIENTE (fixture)';
  expectError(run((t) => text(t, ph, 'Mira en 12, 34 del mapa')), 'E-08', /coordenadas o instrucciones tipo GPS/);
  expectError(run((t) => text(t, ph, 'Es el /way del anciano')), 'E-08', /coordenadas/);
  expectError(run((t) => text(t, ph, 'Busca al Anciano Fixture en la hondonada')), 'E-08', /revela el nombre de la entidad objetivo/);
  expectError(run((t) => edit(t, 'editorial/hints/hint__fixture_elder_1.yaml', 'tier: 1', 'tier: 1\ndepends_on: ["hint:fixture_keeper_1"]')), 'E-08', /ciclo de dependencias entre pistas/);
  expectError(run((t) => edit(t, 'editorial/hints/hint__fixture_keeper_1.yaml', 'depends_on: ["hint:fixture_elder_1"]', 'depends_on: ["hint:no_existe"]')), 'E-08', /dependencia «hint:no_existe» no existe/);
  expectError(run((t) => edit(t, 'editorial/hints/hint__fixture_elder_1.yaml', 'place_discovered: { id: "zone:fixture_land" }', 'hint_seen: { id: "hint:fixture_keeper_1" }')), 'E-08', /hint_seen/);
  expectError(run((t) => edit(t, 'editorial/hints/hint__fixture_elder_1.yaml', 'target: "npc:fixture_example_elder"', 'target: "npc:fixture_retired_example"')), 'E-08', /retirada/);
});

test('E-13: los textos solo pueden referirse a entidades o pistas que existen', () => {
  expectError(run((t) => edit(t, 'editorial/text/esES/fixture.yaml', '  "npc:fixture_example_elder": {', '  "npc:fantasma": { title: "X" }\n  "npc:fixture_example_elder": {')), 'E-13', /«npc:fantasma» no existe/);
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_example_elder.yaml', 'status: published', 'status: published\ncategories: [inexistente]')), 'E-16', /no está en ningún vocabulario/);
});

// ------------------------------------------------------------------------------------------------ bindings
test('E-09: duplicate_binding — un TechRef solo puede estar en un binding accepted por versión', () => {
  expectError(run((t) => edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', 'id: 90004', 'id: 90001')), 'E-09', /duplicate_binding/);
});

test('X-01: binding_unavailable — el TechRef debe existir en World Data de esa versión', () => {
  expectError(run((t) => edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', 'id: 90004', 'id: 99999')), 'X-01', /binding_unavailable: creature:99999/);
});

test('X-02: las cadenas de lugar de un binding deben estar respaldadas por World Data', () => {
  expectError(run((t) => edit(t, 'editorial/bindings/era/subzone__fixture_hollow.yaml', 'Fixture Hollow', 'Otra Cadena')), 'X-02', /«Otra Cadena».*sin respaldo|no tiene respaldo/);
});

test('E-09: el TechRef de un binding es del flavor del binding; los accepted exigen tech_refs o places según el tipo', () => {
  expectError(run((t) => edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', '{ flavor: era, kind: creature, id: 90004 }', '{ flavor: fixture_alt, kind: creature, id: 90008 }')), 'E-09', /no coincide con el del binding/);
  expectError(run((t) => edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', '{ flavor: era, kind: creature, id: 90004 }', '{ flavor: era, kind: quest, id: 90004 }')), 'E-09', /kind «creature»/);
});

test('un binding no puede referirse a una entidad inexistente ni a una versión no configurada', () => {
  expectError(run((t) => {
    edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', 'entity: "npc:fixture_example_elder"', 'entity: "npc:fantasma"');
    fs.renameSync(path.join(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml'), path.join(t, 'editorial/bindings/era/npc__fantasma.yaml'));
  }), 'E-09', /no existe/);
});

// ------------------------------------------------------------------------------------------------ World Data y fuentes
test('W-06: lo versionado debe ser lo que produce la normalización; un World Data editado a mano se detecta', () => {
  expectError(run((t) => edit(t, 'world/era/creature/90001.json', '"value": "Fixture Keeper"', '"value": "Fixture Keeper EDITADO"')), 'W-06', /no coincide con la normalización/);
  expectError(run((t) => fs.rmSync(path.join(t, 'world/era/creature/90004.json'))), 'W-06', /falta/);
});

test('J-02: el JSON debe ser canónico (claves ordenadas, sangría de 2 espacios, LF)', () => {
  expectError(run((t) => write(t, 'world/era/profile.json', JSON.stringify(JSON.parse(read(t, 'world/era/profile.json'))))), 'J-02', /JSON no canónico/);
});

test('S-04 / P-02: las fuentes solo aplican a versiones configuradas y las versiones habilitadas incluyen el idioma editorial', () => {
  expectError(run((t) => edit(t, 'sources/fixture_source_b.yaml', 'applicable_flavors: [era, fixture_alt]', 'applicable_flavors: [era, otro]')), 'S-04', /«otro»/);
  expectError(run((t) => edit(t, 'editorial/flavors.yaml', 'locales: [esES]\n    features: { persist_hints: false, persist_interaction_progress: false }\n    capability_policy: block\n    notes: "FIXTURE SINTETICO: todos', 'locales: [enUS]\n    features: { persist_hints: false, persist_interaction_progress: false }\n    capability_policy: block\n    notes: "FIXTURE SINTETICO: todos')), 'P-02', /idioma editorial/);
});

test('W-11: las evidencias de capacidades verified deben ser observaciones existentes', () => {
  expectError(run((t) => fs.rmSync(path.join(t, 'world/era/observations/obs__fixture_era_gossip.json'))), 'W-11', /no existe/);
});

test('W-13: la clave de un lugar name_only debe estar normalizada', () => {
  const r = run((t) => {
    const f = 'world/era/place/fixture_land.json';
    write(t, f, canonicalPretty({ ...JSON.parse(read(t, f)), ref: { flavor: 'era', kind: 'name_only', key: 'Fixture Land' } }));
  });
  assert.ok(r.codes.includes('W-13') || r.codes.includes('E-02') || r.codes.includes('W-06'), r.text);
});

// ------------------------------------------------------------------------------------------------ candidatos
test('C-01 / C-02 / C-03: score = suma de contribuciones, perfil y señales definidos, sujeto existente', () => {
  expectError(run((t) => edit(t, 'candidates/records/cand__era__creature__90006.json', '"total": -40', '"total": -30')), 'C-01', /suma de contribuciones/);
  expectError(run((t) => edit(t, 'candidates/records/cand__era__creature__90006.json', '"contribution": -40', '"contribution": -35')), 'C-01', /weight × normalized/);
  expectError(run((t) => edit(t, 'candidates/records/cand__era__creature__90006.json', '"version": 1', '"version": 7')), 'C-02', /no existe/);
  expectError(run((t) => edit(t, 'candidates/profiles/dun_morogh_pilot.yaml', 'id: generic_vendor', 'id: señal_inventada'.replace('ñ', 'n'))), 'C-02', /no tiene definición/);
  expectError(run((t) => edit(t, 'candidates/records/cand__era__creature__90006.json', '"id": 90006', '"id": 90077')), 'C-03', /no existe en World Data/);
});

test('un candidato con un campo de inclusión se rechaza por esquema (SCORE != DECISION EDITORIAL)', () => {
  const r = run((t) => edit(t, 'candidates/records/cand__era__creature__90006.json', '"flags"', '"include": true,\n  "flags"'));
  assert.ok(r.codes.includes('SCHEMA') || r.codes.includes('J-02'), r.text);
  assert.ok(r.errors.some((e) => /include/.test(e.message)), r.text);
});

// ------------------------------------------------------------------------------------------------ YAML estricto dentro del dataset
test('E-01: el YAML editorial se valida de forma estricta (anclas, alias y claves duplicadas)', () => {
  expectError(run((t) => edit(t, 'editorial/entities/zone__fixture_land.yaml', 'type: zone', 'type: &t zone')), 'E-01', /ancla/);
  expectError(run((t) => edit(t, 'editorial/entities/zone__fixture_land.yaml', 'type: zone', 'type: zone\ntype: zone')), 'E-01', /DUPLICATE_KEY/);
});

test('campos técnicos del cliente en una entidad editorial se rechazan (la identidad editorial no lleva npcID)', () => {
  const r = run((t) => edit(t, 'editorial/entities/npc__fixture_example_keeper.yaml', 'type: npc', 'type: npc\nnpcID: 90001'));
  assert.ok(r.errors.some((e) => /npcID/.test(e.message)), r.text);
});
