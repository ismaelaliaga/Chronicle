'use strict';
// Carga un dataset (la raíz real `pipeline/` o un dataset de fixtures) y valida cada fichero contra su esquema.
// Un fichero con errores NO entra en el dataset (para no encadenar errores derivados); el error queda en el informe.
//
// Disposición (relativa a la raíz del dataset):
//   sources/<id>.yaml                       manifiestos de fuentes (YAML)
//   sources/records/<source>.json           registros crudos con procedencia (salida de importadores)
//   world/<flavor>/creature/<id>.json       World Data normalizado   (los escribe `normalize`)
//   world/<flavor>/place/<slug>.json        World Data normalizado   (los escribe `normalize`)
//   world/<flavor>/conflicts/conf__<h>.json conflictos              (los escribe `normalize`)
//   world/links/link__<h>.json              enlaces de reconciliación propuestos (los escribe `normalize`)
//   world/<flavor>/profile.json             perfil de cliente        (entrada)
//   world/<flavor>/observations/*.json      observaciones            (entrada)
//   editorial/flavors.yaml                  configuración de versiones
//   editorial/entities|hints|overrides|decisions|link_decisions|vocab/*.yaml, editorial/bindings/<flavor>/*.yaml, editorial/text/<locale>/*.yaml
//   candidates/records/*.json, candidates/profiles/*.yaml, candidates/signals/*.yaml
const fs = require('fs');
const path = require('path');
const { parseStrictYaml } = require('./yaml-strict');
const { validateDoc } = require('./schemas');
const { canonicalPretty } = require('./canonical');
const { cmp } = require('./report');
const { linkFileBase } = require('./links');

const idToFileBase = (id) => id.replace(/:/g, '__');

// Slug de fichero de un lugar identificado solo por su nombre (sin tildes, minúsculas, '_').
function placeSlug(key) {
  return String(key).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'x';
}

function listDir(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => cmp(a.name, b.name));
}

function subdirs(dir) {
  return listDir(dir).filter((e) => e.isDirectory()).map((e) => e.name);
}

function filesIn(dir) {
  return listDir(dir).filter((e) => e.isFile()).map((e) => e.name);
}

function readText(abs) {
  return fs.readFileSync(abs, 'utf8').replace(/\r\n/g, '\n');
}

function loadDataset(root, report, options = {}) {
  const ds = {
    root,
    flavors: null,
    sources: [],
    records: [],
    world: { entities: [], places: [], profiles: [], observations: [], conflicts: [], links: [] },
    editorial: { entities: [], bindings: [], hints: [], texts: [], overrides: [], decisions: [], linkDecisions: [], vocab: [] },
    candidates: { records: [], profiles: [], signals: [] },
  };

  const rel = (abs) => path.relative(root, abs).split(path.sep).join('/');

  // Lee un fichero, lo parsea (YAML estricto o JSON canónico) y lo valida. Devuelve el documento o null.
  function loadFile(abs, schemaName, expectedSchema) {
    const file = rel(abs);
    const ext = path.extname(abs);
    const text = readText(abs);
    let doc;
    if (ext === '.yaml') {
      const r = parseStrictYaml(text, file, report);
      if (!r.ok) return null;
      doc = r.value;
    } else if (ext === '.json') {
      try {
        doc = JSON.parse(text);
      } catch (e) {
        report.error('J-01', file, '', `JSON no válido: ${e.message}`);
        return null;
      }
      if (text !== canonicalPretty(doc)) {
        report.error('J-02', file, '', 'JSON no canónico (claves ordenadas, sangría de 2 espacios, LF y salto final); regenérelo con el pipeline');
      }
    } else {
      report.error('L-01', file, '', `extensión no admitida «${ext}» (se esperan .yaml o .json)`);
      return null;
    }
    if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
      report.error('SCHEMA', file, '/', 'el documento debe ser un objeto');
      return null;
    }
    if (expectedSchema && doc.schema !== expectedSchema) {
      report.error('SCHEMA', file, '/schema', `se esperaba schema «${expectedSchema}» en esta ubicación`);
      return null;
    }
    if (!validateDoc(schemaName, doc, report, file)) return null;
    return doc;
  }

  function collect(dir, ext, schemaName, expectedSchema, target, check) {
    for (const name of filesIn(dir)) {
      if (!name.endsWith(ext)) {
        report.error('L-01', rel(path.join(dir, name)), '', `extensión no admitida en este directorio (se espera ${ext})`);
        continue;
      }
      const abs = path.join(dir, name);
      const doc = loadFile(abs, schemaName, expectedSchema);
      if (!doc) continue;
      const file = rel(abs);
      if (check && !check(doc, file, name)) continue;
      target.push({ file, doc });
    }
  }

  const expectName = (expected) => (doc, file, name) => {
    if (name !== expected(doc)) {
      report.error('E-02', file, '', `el nombre del fichero debe ser «${expected(doc)}»`);
      return false;
    }
    return true;
  };

  // ---- configuración de versiones
  const flavorsPath = path.join(root, 'editorial', 'flavors.yaml');
  if (fs.existsSync(flavorsPath)) {
    const doc = loadFile(flavorsPath, 'pipeline.flavors', 'chronicle.pipeline.flavors/1');
    if (doc) ds.flavors = { file: rel(flavorsPath), doc };
  } else {
    report.error('P-01', 'editorial/flavors.yaml', '', 'falta la configuración de versiones');
  }

  // ---- fuentes y registros
  collect(path.join(root, 'sources'), '.yaml', 'world.source', 'chronicle.world.source/1', ds.sources, expectName((d) => d.id + '.yaml'));
  collect(path.join(root, 'sources', 'records'), '.json', 'world.claim_records', 'chronicle.world.claim_records/1', ds.records, expectName((d) => d.source + '.json'));

  // ---- World Data
  if (!options.skipWorld) {
    collect(path.join(root, 'world', 'links'), '.json', 'world.link', 'chronicle.world.link/1', ds.world.links, expectName((d) => linkFileBase(d.id) + '.json'));
  }
  for (const flavor of options.skipWorld ? [] : subdirs(path.join(root, 'world')).filter((d) => d !== 'links')) {
    const base = path.join(root, 'world', flavor);
    collect(path.join(base, 'creature'), '.json', 'world.entity', 'chronicle.world.entity/1', ds.world.entities, (doc, file, name) => {
      if (doc.ref.flavor !== flavor) { report.error('W-12', file, '/ref/flavor', `el flavor «${doc.ref.flavor}» no coincide con el directorio «${flavor}»`); return false; }
      if (doc.ref.kind !== 'creature') { report.error('W-12', file, '/ref/kind', 'en este directorio solo se admite kind «creature»'); return false; }
      return expectName((d) => d.ref.id + '.json')(doc, file, name);
    });
    collect(path.join(base, 'place'), '.json', 'world.place', 'chronicle.world.place/1', ds.world.places, (doc, file, name) => {
      if (doc.ref.flavor !== flavor) { report.error('W-12', file, '/ref/flavor', `el flavor «${doc.ref.flavor}» no coincide con el directorio «${flavor}»`); return false; }
      const slug = doc.ref.kind === 'name_only' ? placeSlug(doc.ref.key) : `${doc.ref.kind}_${doc.ref.id}`;
      return expectName(() => slug + '.json')(doc, file, name);
    });
    collect(path.join(base, 'observations'), '.json', 'world.observation', 'chronicle.world.observation/1', ds.world.observations, (doc, file, name) => {
      if (doc.flavor !== flavor) { report.error('W-12', file, '/flavor', `el flavor «${doc.flavor}» no coincide con el directorio «${flavor}»`); return false; }
      return expectName((d) => idToFileBase(d.id) + '.json')(doc, file, name);
    });
    collect(path.join(base, 'conflicts'), '.json', 'world.conflict', 'chronicle.world.conflict/1', ds.world.conflicts, expectName((d) => idToFileBase(d.id) + '.json'));
    const profilePath = path.join(base, 'profile.json');
    if (fs.existsSync(profilePath)) {
      const doc = loadFile(profilePath, 'world.client_profile', 'chronicle.world.client_profile/1');
      if (doc) {
        if (doc.flavor !== flavor) report.error('W-12', rel(profilePath), '/flavor', `el flavor «${doc.flavor}» no coincide con el directorio «${flavor}»`);
        else ds.world.profiles.push({ file: rel(profilePath), doc });
      }
    }
  }

  // ---- editorial
  const ed = path.join(root, 'editorial');
  collect(path.join(ed, 'entities'), '.yaml', 'editorial.entity', 'chronicle.editorial.entity/1', ds.editorial.entities, expectName((d) => idToFileBase(d.id) + '.yaml'));
  collect(path.join(ed, 'hints'), '.yaml', 'editorial.hint', 'chronicle.editorial.hint/1', ds.editorial.hints, expectName((d) => idToFileBase(d.id) + '.yaml'));
  collect(path.join(ed, 'overrides'), '.yaml', 'editorial.override', 'chronicle.editorial.override/1', ds.editorial.overrides, expectName((d) => idToFileBase(d.id) + '.yaml'));
  collect(path.join(ed, 'decisions'), '.yaml', 'editorial.candidate_decision', 'chronicle.editorial.candidate_decision/2', ds.editorial.decisions);
  collect(path.join(ed, 'link_decisions'), '.yaml', 'editorial.link_decision', 'chronicle.editorial.link_decision/1', ds.editorial.linkDecisions);
  collect(path.join(ed, 'vocab'), '.yaml', 'editorial.vocab', 'chronicle.editorial.vocab/1', ds.editorial.vocab);
  for (const flavor of subdirs(path.join(ed, 'bindings'))) {
    collect(path.join(ed, 'bindings', flavor), '.yaml', 'editorial.binding', 'chronicle.editorial.binding/1', ds.editorial.bindings, (doc, file, name) => {
      if (doc.flavor !== flavor) { report.error('E-02', file, '/flavor', `el flavor «${doc.flavor}» no coincide con el directorio «${flavor}»`); return false; }
      return expectName((d) => idToFileBase(d.entity) + '.yaml')(doc, file, name);
    });
  }
  for (const locale of subdirs(path.join(ed, 'text'))) {
    collect(path.join(ed, 'text', locale), '.yaml', 'editorial.text', 'chronicle.editorial.text/1', ds.editorial.texts, (doc, file) => {
      if (doc.locale !== locale) { report.error('E-02', file, '/locale', `el idioma «${doc.locale}» no coincide con el directorio «${locale}»`); return false; }
      return true;
    });
  }

  // ---- candidatos (el generador del pack NO los lee: `skipCandidates`)
  if (options.skipCandidates) return ds;
  collect(path.join(root, 'candidates', 'records'), '.json', 'candidate.record', 'chronicle.candidate.record/1', ds.candidates.records, expectName((d) => idToFileBase(d.id) + '.json'));
  collect(path.join(root, 'candidates', 'profiles'), '.yaml', 'candidate.scoring_profile', 'chronicle.candidate.scoring_profile/1', ds.candidates.profiles);
  collect(path.join(root, 'candidates', 'signals'), '.yaml', 'candidate.signal', 'chronicle.candidate.signal/1', ds.candidates.signals);

  return ds;
}

module.exports = { loadDataset, placeSlug, idToFileBase };
