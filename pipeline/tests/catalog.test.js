'use strict';
// Fase 18 — catálogo editorial: decisiones, origen de las entidades, separación editorial/ship y herramientas de solo lectura.
// Los tests comprueban COMPORTAMIENTO real sobre copias temporales de los datasets (mutaciones mínimas), no la mera existencia de funciones.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { validateDataset } = require('../scripts/lib/validate');
const { buildFlavor } = require('../scripts/lib/pack');
const { shipEntity, REASON_ORDER } = require('../scripts/lib/ship');
const { TECHNICAL_SHIP_REASONS, REJECT_REASONS } = require('../scripts/lib/rules');
const { Report } = require('../scripts/lib/report');
const { getValidator } = require('../scripts/lib/schemas');
const { queueLines, explainLines, HYPOTHETICAL, NO_SCORING } = require('../scripts/lib/catalog');
const { FIXTURE_ROOT, REAL_ROOT, PIPELINE_DIR, copyDataset, edit, read, write, rm, cli } = require('./helpers');

function run(mutate, options, root = FIXTURE_ROOT) {
  const tmp = copyDataset(root);
  try {
    if (mutate) mutate(tmp);
    const res = validateDataset(tmp, options);
    return { res, report: res.report, errors: res.report.errors, warnings: res.report.warnings, text: res.report.format().join('\n') };
  } finally {
    rm(tmp);
  }
}
const has = (list, code, pattern) => list.some((e) => e.code === code && (!pattern || pattern.test(e.message)));
function expectError(r, code, pattern) { assert.ok(has(r.errors, code, pattern), `se esperaba [${code}] ${pattern || ''} y salió:\n${r.text}`); }

const check = (name, doc) => { const v = getValidator(name); return { ok: v(doc), errors: v.errors }; };
const FP = 'sha256:' + 'a'.repeat(64);
const DEC = 'editorial/decisions/';

// snapshot de TODOS los ficheros de un directorio (ruta -> contenido), para comprobar que una orden de solo lectura no escribe nada
function snapshot(dir) {
  const out = {};
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else out[path.relative(dir, p).split(path.sep).join('/')] = fs.readFileSync(p, 'utf8') + '|' + fs.statSync(p).mtimeMs;
    }
  };
  walk(dir);
  return out;
}

// ----------------------------------------------------------------------------------------------- Candidate
test('1. un Candidate SIN score es válido (esquema y dataset real)', () => {
  const rec = {
    schema: 'chronicle.candidate.record/1', id: 'cand:era:creature:5', flavor: 'era', subject: { flavor: 'era', kind: 'creature', id: 5 },
    sources: [{ source: 's', origin_group: 's', claims: 1 }], evidence_summary: { independent_origins: 1, client_verified: false, open_conflicts: 0 },
    research: { status: 'new' }, inputs_fingerprint: FP,
  };
  assert.equal(check('candidate.record', rec).ok, true);
  // los campos de scoring van en bloque: un perfil sin score, o un rank sin score, no es válido
  assert.equal(check('candidate.record', { ...rec, profile: { id: 'p', version: 1 } }).ok, false);
  assert.equal(check('candidate.record', { ...rec, rank: 1 }).ok, false);
  const real = validateDataset(REAL_ROOT);
  assert.deepEqual(real.report.format(), []);
  assert.equal(real.model.candidates.size, 2);
  for (const c of real.model.candidates.values()) assert.equal(c.doc.score, undefined);
});

test('2. un Candidate con score y perfil ILUSTRATIVO es válido y la cola lo etiqueta como no aprobado', () => {
  const r = run();
  assert.deepEqual(r.warnings.concat(r.errors), []);
  const prof = r.res.model.candidateProfiles.get('dun_morogh_pilot@1').doc;
  assert.equal(prof.approval, 'illustrative');
  const q = queueLines(r.res, { all: true }).join('\n');
  assert.match(q, /perfil «dun_morogh_pilot@1» \[ILUSTRATIVO — NO APROBADO\] — orden por rank/);
});

test('3. un perfil «proposed» es válido y se etiqueta como propuesta pendiente de aprobación', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    edit(tmp, 'candidates/profiles/dun_morogh_pilot.yaml', 'approval: illustrative', 'approval: proposed');
    const res = validateDataset(tmp);
    assert.deepEqual(res.report.errors, [], res.report.format().join('\n'));
    assert.match(queueLines(res, { all: true }).join('\n'), /\[PROPUESTA — pendiente de aprobación\]/);
  } finally { rm(tmp); }
});

test('4. NINGÚN perfil puede ser «approved» (C-05); el dataset real no tiene perfiles', () => {
  expectError(run((t) => edit(t, 'candidates/profiles/dun_morogh_pilot.yaml', 'approval: illustrative', 'approval: approved')), 'C-05', /puede ser «approved» todavía/);
  expectError(run((t) => edit(t, 'candidates/profiles/dun_morogh_pilot.yaml', 'approval: illustrative\n', '')), 'SCHEMA', /approval/);
  assert.equal(validateDataset(REAL_ROOT).model.candidateProfiles.size, 0);
});

test('D-02: los candidatos del dataset real solo los origina wow_client; wiki y legacy_addon no', () => {
  const m = validateDataset(REAL_ROOT).model;
  for (const c of m.candidates.values()) assert.deepEqual(c.doc.sources.map((s) => s.source), ['wow_client']);
  assert.equal(m.sourcesById.get('warcraft_wiki').usage.candidate_generation, false);
  assert.equal(m.sourcesById.get('legacy_addon').usage.candidate_generation, false);
  // los datos de esas fuentes siguen en World Data como investigación y NO entran en el candidato
  const c = m.candidates.get('cand:era:creature:786').doc;
  assert.equal(c.display, undefined);
  assert.deepEqual(c.data_gaps, ['display_name']);
  assert.ok(m.creatures.get('era|creature|786').doc.names.enUS.claims.some((x) => x.provenance.source === 'warcraft_wiki'));
});

test('D-02: un candidato que cita una fuente sin candidate_generation es un ERROR', () => {
  const tmp = copyDataset(REAL_ROOT);
  try {
    edit(tmp, 'candidates/records/cand__era__creature__786.json', '"origin_group": "wow_client",\n      "source": "wow_client"', '"origin_group": "warcraft_wiki",\n      "source": "warcraft_wiki"');
    const r = validateDataset(tmp);
    assert.ok(has(r.report.errors, 'D-02', /no tiene usage\.candidate_generation = true/), r.report.format().join('\n'));
  } finally { rm(tmp); }
});

test('C-04: los candidatos sin puntuar son regenerables: data:candidates es idempotente y un candidato editado, borrado o sobrante se detecta', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const again = cli(['candidates', '--root', tmp]);
    assert.equal(again.code, 0, again.out);
    assert.match(again.out, /0 escrito\(s\), 0 eliminado\(s\)/);
    assert.match(again.out, /1 puntuado\(s\) respetado\(s\)/); // el candidato puntuado (90007) es entrada: no se reescribe
  } finally { rm(tmp); }
  expectError(run((t) => edit(t, 'candidates/records/cand__era__creature__90004.json', '"status": "new"', '"status": "sufficient"')), 'C-04', /no coincide con lo que regenera data:candidates/);
  expectError(run((t) => fs.rmSync(path.join(t, 'candidates/records/cand__era__creature__90004.json'))), 'C-04', /falta el candidato/);
  expectError(run((t) => write(t, 'candidates/records/cand__era__creature__90077.json', read(t, 'candidates/records/cand__era__creature__90009.json').split('90009').join('90077'))), 'C-04', /fichero sobrante/);
});

// ----------------------------------------------------------------------------------------------- D-01 .. D-08
test('5/11. D-01: una Entity origin:candidate sin ninguna CandidateDecision accepted es un ERROR', () => {
  const r = run((t) => fs.rmSync(path.join(t, DEC + 'era__creature__90010.yaml')));
  expectError(r, 'D-01', /npc:fixture_pending_example.*origin «candidate»/);
});

test('6. D-03: la decisión accepted exige origin candidate en la Entity y su flavor en applies_to', () => {
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_pending_example.yaml', 'origin: candidate', 'origin: bootstrap')), 'D-03', /solo da lugar a entidades con origin «candidate»/);
  expectError(run((t) => edit(t, 'editorial/entities/npc__fixture_pending_example.yaml', 'applies_to: [era]', 'applies_to: [fixture_alt]')), 'D-03', /no está en applies_to/);
});

test('7/13. D-05: un mismo TechRef accepted hacia dos Entities es un ERROR', () => {
  const r = run((t) => write(t, DEC + 'copia.yaml', read(t, DEC + 'era__creature__90004.yaml').replace('npc:fixture_example_elder', 'npc:fixture_example_keeper')));
  expectError(r, 'D-05', /accepted hacia 2 entidades distintas/);
  expectError(r, 'D-09', /solo se admite una decisión vigente por sujeto/);
});

test('8. D-06: un Binding accepted que no coincide con ninguna decisión es un AVISO, no un error', () => {
  const r = run((t) => edit(t, 'editorial/bindings/era/npc__fixture_example_elder.yaml', 'id: 90004', 'id: 90009'));
  assert.ok(has(r.warnings, 'D-06', /ningún TechRef del binding coincide/), r.text);
  assert.ok(!r.errors.some((e) => e.code === 'D-06'), r.text);
});

test('9. D-07: si la evidencia del candidato cambió, la decisión sigue vigente y solo hay un AVISO', () => {
  const r = run((t) => edit(t, DEC + 'era__creature__90004.yaml', /evidence_fingerprint: "(sha256:[a-f0-9]{64})"/.exec(read(t, DEC + 'era__creature__90004.yaml'))[1], 'sha256:' + 'b'.repeat(64)));
  assert.ok(has(r.warnings, 'D-07', /ha cambiado desde que se tomó la decisión/), r.text);
  assert.deepEqual(r.errors, [], r.text);
});

test('10/24/25. D-08: una Entity bootstrap no puede estar en review ni published (regla editorial de validate.js)', () => {
  for (const status of ['review', 'published']) {
    const r = run((t) => edit(t, 'editorial/entities/npc__fixture_bootstrap_example.yaml', 'status: drafting', `status: ${status}`));
    expectError(r, 'D-08', new RegExp(`no puede estar en «${status}»`));
  }
  // y en el dataset real
  const tmp = copyDataset(REAL_ROOT);
  try {
    edit(tmp, 'editorial/entities/npc__grelin_whitebeard.yaml', 'status: drafting', 'status: published');
    assert.ok(has(validateDataset(tmp).report.errors, 'D-08'));
  } finally { rm(tmp); }
  // drafting es lo permitido
  assert.deepEqual(run().errors, []);
});

test('12. una decisión accepted que apunta a una Entity inexistente es un ERROR', () => {
  expectError(run((t) => edit(t, DEC + 'era__creature__90010.yaml', 'npc:fixture_pending_example', 'npc:fantasma')), 'E-12', /«npc:fantasma» no existe/);
});

test('el sujeto de una decisión debe existir en World Data (D-10)', () => {
  expectError(run((t) => edit(t, DEC + 'era__creature__90009.yaml', 'id: 90009', 'id: 99999')), 'D-10', /no existe en World Data/);
});

// ----------------------------------------------------------------------------------------------- CandidateDecision v2
test('CandidateDecision v2: motivos obligatorios según la decisión; v1 ya no es válido', () => {
  const base = { schema: 'chronicle.editorial.candidate_decision/2', subject: { flavor: 'era', kind: 'creature', id: 1 }, evidence_fingerprint: FP, policy_version: 1, by: 'x', at: '2026-10' };
  const ok = (d) => check('editorial.candidate_decision', { ...base, ...d }).ok;
  assert.equal(ok({ decision: 'shortlisted' }), true);
  assert.equal(ok({ decision: 'accepted', entity: 'npc:x', inclusion_reasons: ['own_story'] }), true);
  assert.equal(ok({ decision: 'accepted', entity: 'npc:x' }), false); // sin motivos
  assert.equal(ok({ decision: 'accepted', inclusion_reasons: ['own_story'] }), false); // sin entity
  assert.equal(ok({ decision: 'accepted', entity: 'npc:x', inclusion_reasons: [] }), false);
  assert.equal(ok({ decision: 'accepted', entity: 'npc:x', inclusion_reasons: ['cualquiera'] }), false);
  assert.equal(ok({ decision: 'rejected', reject_reasons: ['no_interest'] }), true);
  assert.equal(ok({ decision: 'rejected' }), false);
  assert.equal(ok({ decision: 'rejected', reject_reasons: ['duplicate_of'] }), false); // exige duplicate_of
  assert.equal(ok({ decision: 'rejected', reject_reasons: ['duplicate_of'], duplicate_of: { flavor: 'era', kind: 'creature', id: 2 } }), true);
  assert.equal(ok({ decision: 'deferred', defer_reason: 'insufficient_evidence' }), true);
  assert.equal(ok({ decision: 'deferred' }), false);
  assert.equal(ok({ decision: 'deferred', defer_reason: 'no_interest' }), false);
  assert.equal(ok({ decision: 'accepted', entity: 'npc:x', inclusion_reasons: ['own_story'], reject_reasons: ['no_interest'] }), false); // campos cruzados
  assert.equal(ok({ decision: 'rejected', reject_reasons: ['no_interest'], entity: 'npc:x' }), false);
  assert.equal(check('editorial.candidate_decision', { ...base, schema: 'chronicle.editorial.candidate_decision/1', decision: 'shortlisted' }).ok, false);
  const { policy_version, ...noPolicy } = base;
  assert.equal(check('editorial.candidate_decision', { ...noPolicy, decision: 'shortlisted' }).ok, false);
});

test('17/18. los motivos técnicos del ship-report NUNCA pueden ser reject_reasons (D-04)', () => {
  // la lista de prohibidos cubre TODOS los motivos que ship.js puede producir
  for (const r of REASON_ORDER) assert.ok(TECHNICAL_SHIP_REASONS.includes(r), `${r} debe estar prohibido como motivo de rechazo`);
  for (const r of TECHNICAL_SHIP_REASONS) assert.ok(!REJECT_REASONS.includes(r), r);
  for (const reason of TECHNICAL_SHIP_REASONS) {
    const r = run((t) => edit(t, DEC + 'era__creature__90007.yaml', 'reject_reasons: [generic_vendor]', `reject_reasons: [${reason}]`));
    expectError(r, 'D-04', /es un motivo técnico del ship-report/);
  }
  expectError(run((t) => edit(t, DEC + 'era__creature__90007.yaml', 'reject_reasons: [generic_vendor]', 'reject_reasons: [me_cae_mal]')), 'D-04', /no es un motivo de rechazo aprobado/);
  expectError(run((t) => edit(t, DEC + 'era__creature__90007.yaml', 'reject_reasons: [generic_vendor]', 'reject_reasons: [source_not_authorized_for_pack]')), 'D-04', /source_not_authorized_for_pack/);
  expectError(run((t) => edit(t, DEC + 'era__creature__90007.yaml', 'reject_reasons: [generic_vendor]', 'reject_reasons: [capability_unverified]')), 'D-04', /capability_unverified/);
});

test('«no sabemos lo suficiente» es deferred + insufficient_evidence, no rejected (fixture)', () => {
  const m = validateDataset(FIXTURE_ROOT).model;
  const d = m.decisions.find((x) => x.doc.subject.id === 90009).doc;
  assert.equal(d.decision, 'deferred');
  assert.equal(d.defer_reason, 'insufficient_evidence');
  assert.equal(m.decisions.find((x) => x.doc.subject.id === 90007).doc.decision, 'rejected');
});

// ----------------------------------------------------------------------------------------------- Entity.editorial.origin
test('editorial.origin: solo candidate y bootstrap (authored y legacy_migration están reservados); obligatorio en npc', () => {
  const base = { schema: 'chronicle.editorial.entity/1', id: 'npc:x', type: 'npc', status: 'drafting', applies_to: ['era'], discovery: { method: 'none' } };
  const ent = (editorial) => check('editorial.entity', { ...base, editorial }).ok;
  assert.equal(ent({ author: 'a', origin: 'candidate' }), true);
  assert.equal(ent({ author: 'a', origin: 'bootstrap' }), true);
  assert.equal(ent({ author: 'a', origin: 'authored' }), false);
  assert.equal(ent({ author: 'a', origin: 'legacy_migration' }), false);
  assert.equal(ent({ author: 'a', origin: 'original' }), false);
  assert.equal(ent({ author: 'a' }), false); // npc sin origin
  const place = { schema: 'chronicle.editorial.entity/1', id: 'zone:x', type: 'zone', status: 'published', parent: 'continent:y', applies_to: ['era'], editorial: { author: 'a' } };
  assert.equal(check('editorial.entity', place).ok, true); // los lugares bootstrap de Fase 17 no se tocan
});

test('hints: text_origin: original es obligatorio y distinto de Entity.editorial.origin', () => {
  const hint = read(FIXTURE_ROOT, 'editorial/hints/hint__fixture_elder_1.yaml');
  assert.match(hint, /text_origin: original/);
  expectError(run((t) => edit(t, 'editorial/hints/hint__fixture_elder_1.yaml', 'text_origin: original\n', '')), 'SCHEMA', /text_origin/);
  expectError(run((t) => edit(t, 'editorial/hints/hint__fixture_elder_1.yaml', 'text_origin: original', 'text_origin: authored')), 'SCHEMA', /valor no permitido \(permitidos: original\)/);
});

test('el estado heredado «accepted» de Entity sigue en el modelo de Fase 16 (no se elimina) y ningún dato lo usa', () => {
  const { checkTransition } = require('../scripts/lib/rules');
  assert.equal(checkTransition('accepted', 'drafting'), true);
  for (const root of [REAL_ROOT, FIXTURE_ROOT]) {
    for (const e of validateDataset(root).model.entityDocs.values()) assert.notEqual(e.status, 'accepted', e.id);
  }
});

// ----------------------------------------------------------------------------------------------- editorial != ship
function buildPack(root, flavor, mutate) {
  const tmp = copyDataset(root);
  try {
    if (mutate) mutate(tmp);
    const { model, report } = validateDataset(tmp, { scope: 'publish' });
    assert.deepEqual(report.errors, [], report.format().join('\n'));
    const r = new Report();
    const built = buildFlavor(model, flavor, r);
    assert.deepEqual(r.errors, [], r.format().join('\n'));
    built.model = model;
    return built;
  } finally { rm(tmp); }
}
const eval1 = (b, id, flavor = 'era') => shipEntity(b.model, b.model.entityDocs.get(id), flavor);

test('14/15. accepted no implica Binding ni published: aceptada, en drafting y sin Binding no entra al pack', () => {
  const b = buildPack(FIXTURE_ROOT, 'era');
  const m = b.model;
  assert.ok(m.decisions.some((d) => d.doc.decision === 'accepted' && d.doc.entity === 'npc:fixture_pending_example'));
  assert.equal(m.entityDocs.get('npc:fixture_pending_example').status, 'drafting');
  assert.ok(!Array.from(m.bindings.values()).some((x) => x.doc.entity === 'npc:fixture_pending_example'));
  assert.equal(b.pack.entities['npc:fixture_pending_example'], undefined);
  assert.equal(b.shipReport.entries.find((e) => e.entity === 'npc:fixture_pending_example'), undefined);
  // la evaluación hipotética de ship.js dice por qué faltaría (dimensión técnica), sin convertirlo en un rechazo
  assert.deepEqual(eval1(b, 'npc:fixture_pending_example').reasons, ['no_binding']);
});

test('16. published no implica available ni Binding válido: publicadas pero no disponibles', () => {
  const b = buildPack(FIXTURE_ROOT, 'era');
  for (const [id, reason] of [['npc:fixture_unauthorized_example', 'source_not_authorized_for_pack'], ['npc:fixture_conflicted_example', 'blocked_by_conflict']]) {
    assert.equal(b.model.entityDocs.get(id).status, 'published', id);
    const e = b.shipReport.entries.find((x) => x.entity === id);
    assert.equal(e.available, false, id);
    assert.ok(e.reasons.includes(reason), id);
    assert.equal(b.pack.discovery[id], undefined, id);
  }
});

test('published ≠ Binding válido: una entidad publicada SIN Binding es válida editorialmente y el ship la marca no_binding', () => {
  const b = buildPack(FIXTURE_ROOT, 'era', (t) => {
    edit(t, 'editorial/entities/npc__fixture_pending_example.yaml', 'status: drafting', 'status: published');
    edit(t, 'editorial/text/esES/fixture.yaml', '  "npc:fixture_unauthorized_example"', '  "npc:fixture_pending_example": { title: "Pendiente Fixture" }\n  "npc:fixture_unauthorized_example"');
  });
  const e = b.shipReport.entries.find((x) => x.entity === 'npc:fixture_pending_example');
  assert.equal(e.available, false);
  assert.deepEqual(e.reasons, ['no_binding']);
});

test('ship.js no conoce el estado editorial ni el origen: ni lo lee ni emite motivos derivados (pack.js solo filtra la entrada)', () => {
  const src = fs.readFileSync(path.join(PIPELINE_DIR, 'scripts/lib/ship.js'), 'utf8').replace(/\/\/.*$/gm, '');
  for (const word of ['bootstrap', 'origin', 'drafting', 'review', 'not_published', 'not_editorially_reviewed', 'editorial.']) assert.ok(!src.includes(word), `ship.js no debe mencionar «${word}»`);
  assert.ok(!/entity\.status|entity\.editorial/.test(src));
  assert.deepEqual(REASON_ORDER.filter((r) => /draft|review|publish|bootstrap/.test(r)), []);
  // comportamiento: la evaluación es idéntica para la misma entidad con cualquier estado u origen editorial
  const b = buildPack(FIXTURE_ROOT, 'era');
  const base = b.model.entityDocs.get('npc:fixture_example_elder');
  const ref = JSON.stringify(shipEntity(b.model, base, 'era'));
  for (const status of ['drafting', 'review', 'published']) {
    for (const origin of ['candidate', 'bootstrap']) {
      const clone = JSON.parse(JSON.stringify(base));
      clone.status = status;
      clone.editorial.origin = origin;
      assert.equal(JSON.stringify(shipEntity(b.model, clone, 'era')), ref, `${status}/${origin}`);
    }
  }
});

test('el generador (pack/ship/eligibility/lua) no lee Candidate Data (comprobación estática)', () => {
  for (const f of ['pack.js', 'ship.js', 'eligibility.js', 'lua.js']) {
    const src = fs.readFileSync(path.join(PIPELINE_DIR, 'scripts/lib', f), 'utf8').replace(/\/\/.*$/gm, '');
    assert.ok(!/candidates|candidate\./i.test(src), `${f} no debe leer Candidate Data`);
    assert.ok(!/require\('\.\/(candidates|links|catalog)'\)/.test(src), `${f} no debe importar la capa de candidatos`);
  }
});

test('22/23. el pack es IDÉNTICO con y sin candidates/ (y aunque candidates/ esté corrupto), byte a byte', () => {
  for (const [root, flavors] of [[FIXTURE_ROOT, ['era', 'fixture_alt']], [REAL_ROOT, ['era']]]) {
    for (const f of flavors) {
      const withC = buildPack(root, f);
      const without = buildPack(root, f, (t) => fs.rmSync(path.join(t, 'candidates'), { recursive: true, force: true }));
      const garbage = buildPack(root, f, (t) => { write(t, 'candidates/records/basura.json', '{ esto no es json'); write(t, 'candidates/profiles/basura.yaml', 'a: &x 1\nb: *x\n'); });
      for (const other of [without, garbage]) {
        assert.equal(other.lua, withC.lua);
        assert.deepEqual(other.manifest, withC.manifest);
        assert.deepEqual(other.shipReport, withC.shipReport);
      }
      // ninguna huella ni dato de un Candidate entra en el pack
      assert.ok(!/cand:|inputs_fingerprint|evidence_summary|independent_origins/.test(withC.lua + JSON.stringify(withC.manifest) + JSON.stringify(withC.shipReport)));
    }
  }
});

test('22. un Candidate no entra directamente en el pack: un candidato sin Entity (p. ej. 90009) no deja rastro', () => {
  const b = buildPack(FIXTURE_ROOT, 'era');
  for (const frag of ['90009', 'Fixture Drifter', '90007', 'Fixture Vendor', 'Fixture Scribe', 'Fixture Bootstrap']) assert.ok(!b.lua.includes(frag), frag);
});

test('la CLI genera con el dataset SIN candidates/ y el resultado coincide con lo versionado', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    fs.rmSync(path.join(tmp, 'candidates'), { recursive: true });
    fs.rmSync(path.join(tmp, 'generated'), { recursive: true });
    const g = cli(['generate', '--root', tmp]);
    assert.equal(g.code, 0, g.out);
    for (const f of ['era', 'fixture_alt']) assert.equal(read(tmp, `generated/${f}/Pack.lua`), read(FIXTURE_ROOT, `generated/${f}/Pack.lua`));
    assert.equal(cli(['check', '--root', tmp]).code, 0);
  } finally { rm(tmp); }
});

// ----------------------------------------------------------------------------------------------- la máquina nunca crea una Entity
test('19/20/21. matched no crea Entity, un TechRef no crea Entity y la máquina nunca crea una Entity', () => {
  const tmp = copyDataset(FIXTURE_ROOT);
  try {
    const before = snapshot(path.join(tmp, 'editorial'));
    const entitiesBefore = fs.readdirSync(path.join(tmp, 'editorial/entities')).sort();
    // una confirmación humana (matched) ya existe en el dataset; la tubería completa no debe tocar NADA de editorial/
    const r = cli(['pipeline', '--root', tmp]);
    assert.equal(r.code, 0, r.out);
    assert.deepEqual(snapshot(path.join(tmp, 'editorial')), before);
    assert.deepEqual(fs.readdirSync(path.join(tmp, 'editorial/entities')).sort(), entitiesBefore);
    // hay TechRefs en World Data (p. ej. 90009) sin Entity, sin Binding y sin decisión accepted: siguen sin Entity
    const m = validateDataset(tmp).model;
    const bound = new Set();
    for (const { doc: b } of m.bindings.values()) (b.tech_refs || []).forEach((t) => bound.add(`${t.flavor}|${t.kind}|${t.id}`));
    const orphan = Array.from(m.creatures.keys()).filter((k) => !bound.has(k));
    assert.ok(orphan.includes('era|creature|90009'));
    assert.equal(m.entities.size, entitiesBefore.length);
    // y el enlace confirmado es «matched» pero eso NO es una decisión de inclusión
    const link = m.ds.world.links[0].doc;
    assert.equal(link.status, 'probable_match'); // la máquina propone; matched solo existe como estado EFECTIVO de una decisión humana
  } finally { rm(tmp); }
});

test('Grelin y Sten: bootstrap + drafting, conservan su Binding y NO tienen decisión editorial', () => {
  const m = validateDataset(REAL_ROOT).model;
  for (const [id, tech] of [['npc:grelin_whitebeard', 786], ['npc:sten_stoutarm', 658]]) {
    const e = m.entityDocs.get(id);
    assert.equal(e.status, 'drafting', id);
    assert.equal(e.editorial.origin, 'bootstrap', id);
    const b = m.bindings.get(`${id}|era`).doc;
    assert.equal(b.status, 'accepted');
    assert.deepEqual(b.tech_refs, [{ flavor: 'era', kind: 'creature', id: tech }]);
    assert.equal(m.decisions.length, 0);
  }
  // los lugares bootstrap de Fase 17 no se han tocado
  for (const id of ['continent:eastern_kingdoms', 'zone:dun_morogh', 'subzone:coldridge_valley']) assert.equal(m.entityDocs.get(id).status, 'published');
});

// ----------------------------------------------------------------------------------------------- workflow editorial
test('workflow editorial: drafting → review → published (humano); published → drafting; nada de saltos', () => {
  const { checkTransition } = require('../scripts/lib/rules');
  assert.equal(checkTransition('drafting', 'review'), true);
  assert.equal(checkTransition('review', 'published'), true);
  assert.equal(checkTransition('published', 'drafting'), true);
  assert.equal(checkTransition('drafting', 'published'), false);
  const base = copyDataset(FIXTURE_ROOT);
  try {
    const r = run((t) => {
      edit(t, 'editorial/entities/npc__fixture_pending_example.yaml', 'status: drafting', 'status: published');
    }, { baselineDir: base });
    expectError(r, 'E-11', /«drafting» -> «published»/);
  } finally { rm(base); }
});

// ----------------------------------------------------------------------------------------------- data:queue / data:explain
test('28. data:queue no escribe ningún fichero y distingue scoring de orden técnico', () => {
  for (const root of [REAL_ROOT, FIXTURE_ROOT]) {
    const before = snapshot(root);
    const r = cli(['queue', '--root', root]);
    assert.equal(r.code, 0, r.out);
    assert.deepEqual(snapshot(root), before, 'queue no debe escribir ni modificar ficheros');
  }
  const real = cli(['queue', '--root', REAL_ROOT]).out;
  assert.match(real, /sin scoring — orden técnico por TechRef/);
  assert.match(real, /NO es una prioridad editorial/);
  assert.match(real, /cand:era:creature:658[^\n]*\[bootstrap_entity/);
  assert.match(real, /cand:era:creature:786[^\n]*npc:grelin_whitebeard \(origin: bootstrap, status: drafting/);
  assert.ok(real.indexOf('creature:658') < real.indexOf('creature:786'), 'orden ascendente por TechRef');
  const fx = cli(['queue', '--root', FIXTURE_ROOT, '--all']).out;
  assert.match(fx, /== Con scoring: perfil «dun_morogh_pilot@1» \[ILUSTRATIVO — NO APROBADO\] — orden por rank ==/);
  assert.match(fx, /decisión=rejected \[generic_vendor\]/);
  assert.match(fx, /decisión=deferred \[insufficient_evidence\]/);
  assert.match(fx, new RegExp(NO_SCORING));
  // por defecto solo lista los pendientes: ni accepted ni rejected
  const pending = cli(['queue', '--root', FIXTURE_ROOT]).out;
  assert.ok(!/decisión=accepted/.test(pending));
  assert.ok(!/decisión=rejected/.test(pending));
  assert.match(pending, /decisión=deferred/);
});

test('29/30. data:explain no escribe ficheros y etiqueta la evaluación hipotética (drafting) frente a la del generador (published)', () => {
  const before = snapshot(REAL_ROOT);
  const g = cli(['explain', 'npc:grelin_whitebeard', '--root', REAL_ROOT]);
  assert.equal(g.code, 0, g.out);
  assert.deepEqual(snapshot(REAL_ROOT), before);
  assert.ok(g.out.includes(HYPOTHETICAL), 'la evaluación de una entidad en drafting debe etiquetarse como hipotética');
  assert.ok(g.out.includes('evaluación técnica hipotética — no forma parte del Generated Pack'));
  assert.match(g.out, /source_not_authorized_for_pack, capability_unverified:interaction\.gossip/);
  assert.match(g.out, /\[13\] Entity\.editorial\.origin: bootstrap/);
  assert.match(g.out, /\[14\] Entity\.status \(dimensión EDITORIAL\): drafting/);
  assert.match(g.out, /\[9\] CandidateDecision: ninguna \(pendiente de revisión editorial\)/);
  assert.match(g.out, /candidate_generation=true/);
  assert.match(g.out, /warcraft_wiki[^\n]*candidate_generation=false/);
  assert.match(g.out, /solo investigación: ninguna fuente con candidate_generation/);
  for (let i = 1; i <= 17; i++) assert.ok(g.out.includes(`[${i}]`), `falta el apartado [${i}]`);

  const p = cli(['explain', 'npc:fixture_example_elder', '--root', FIXTURE_ROOT]);
  assert.equal(p.code, 0, p.out);
  assert.ok(!p.out.includes(HYPOTHETICAL), 'una entidad published se explica con el ship-report real, no con una evaluación hipotética');
  assert.match(p.out, /era: ship-report \(evaluación del generador\)\n\s+resultado: available/);
  assert.match(p.out, /autorizada por: fixture_authorized_source/);
  assert.match(p.out, /\[9\] CandidateDecision: accepted/);
  assert.match(p.out, /\[11\] policy_version: 1/);

  const u = cli(['explain', 'npc:fixture_unauthorized_example', '--root', FIXTURE_ROOT]).out;
  assert.match(u, /resultado: source_not_authorized_for_pack/);
  assert.ok(!u.includes(HYPOTHETICAL));

  const c = cli(['explain', 'cand:era:creature:90004', '--root', FIXTURE_ROOT]);
  assert.equal(c.code, 0, c.out);
  assert.match(c.out, /enlace link:[a-f0-9]{16}[^\n]*propuesta=probable_match; efectivo=matched \[decisión humana: confirm\]/);
  assert.match(c.out, /matched NO significa inclusión editorial/);

  assert.equal(cli(['explain', 'npc:no_existe', '--root', FIXTURE_ROOT]).code, 1);
  assert.equal(cli(['explain', '--root', FIXTURE_ROOT]).code, 2);
});

test('explain muestra el vínculo Entity → CandidateDecision → Candidate → World Data → Sources', () => {
  const out = explainLines(validateDataset(FIXTURE_ROOT), 'npc:fixture_example_keeper').lines.join('\n');
  assert.match(out, /Candidate cand:era:creature:90001/);
  assert.match(out, /Candidate cand:fixture_alt:creature:90002/);
  assert.match(out, /CandidateDecision: accepted/);
  assert.match(out, /World Data: world\/era\/creature\/90001\.json/);
  assert.match(out, /fixture_authorized_source {2}status=active {2}research=true {2}candidate_generation=true {2}generated_data=true/);
});
