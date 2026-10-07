#!/usr/bin/env node
'use strict';
// CLI del pipeline de datos.
// Uso: node scripts/cli.js <normalize|candidates|validate|queue|explain|generate|check|pipeline> [<id>] [--root <dir>] [--baseline-dir <dir>] [--flavor <id>] [--all]
// Códigos de salida: 0 correcto, 1 errores de validación o diferencias (o `explain` sin resultado), 2 uso incorrecto.
//
// Solo `normalize`, `candidates` y `generate` (y `pipeline`, que los encadena) escriben ficheros. `validate`, `queue`, `explain` y `check` son de SOLO LECTURA.
const fs = require('fs');
const path = require('path');
const { Report, cmp } = require('./lib/report');
const { loadDataset } = require('./lib/loader');
const { buildWorld, writeWorld } = require('./lib/normalize');
const { validateDataset } = require('./lib/validate');
const { buildFlavor, writeArtifacts, checkArtifacts } = require('./lib/pack');
const { buildCandidates, candidateFileBase } = require('./lib/candidates');
const { canonicalPretty } = require('./lib/canonical');
const { queueLines, explainLines } = require('./lib/catalog');

const DEFAULT_ROOT = path.resolve(__dirname, '..');
const COMMANDS = ['normalize', 'candidates', 'validate', 'queue', 'explain', 'generate', 'check', 'pipeline'];

function parseArgs(argv) {
  const args = { command: argv[0], root: DEFAULT_ROOT, baselineDir: null, flavor: null, all: false, positional: [] };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--root') args.root = path.resolve(argv[++i] || '');
    else if (argv[i] === '--baseline-dir') args.baselineDir = argv[++i];
    else if (argv[i] === '--flavor') args.flavor = argv[++i];
    else if (argv[i] === '--all') args.all = true;
    else if (!argv[i].startsWith('--')) args.positional.push(argv[i]);
    else return { error: `argumento desconocido: ${argv[i]}` };
  }
  return args;
}

function print(report, out = console.log) {
  for (const line of report.format()) out(line);
}

function relRoot(root) {
  const r = path.relative(process.cwd(), root);
  return r === '' ? '.' : r;
}

function cmdNormalize(root) {
  const report = new Report();
  const ds = loadDataset(root, report, { skipWorld: true });
  const world = buildWorld(ds, report);
  if (report.hasErrors()) {
    print(report);
    console.log(`\nnormalize: ${report.errors.length} error(es) en «${relRoot(root)}». No se ha escrito nada.`);
    return 1;
  }
  print(report);
  const r = writeWorld(root, world.outputs);
  console.log(`normalize: ${world.outputs.size} documento(s) de World Data (${r.written.length} escrito(s), ${r.removed.length} eliminado(s)) en «${relRoot(root)}/world».`);
  for (const f of r.written) console.log(`  escrito  ${f}`);
  for (const f of r.removed) console.log(`  borrado  ${f}`);
  return 0;
}

// Candidatos SIN PUNTUAR a partir de World Data (solo fuentes con usage.candidate_generation). Nunca reescribe ni borra un candidato con perfil (puntuado).
function cmdCandidates(root) {
  const report = new Report();
  const ds = loadDataset(root, report, { skipWorld: true });
  const world = buildWorld(ds, report);
  if (report.hasErrors()) {
    print(report);
    console.log(`\ncandidates: ${report.errors.length} error(es) en «${relRoot(root)}». No se ha escrito nada.`);
    return 1;
  }
  const sourcesById = new Map(ds.sources.map((s) => [s.doc.id, s.doc]));
  const existing = ds.candidates.records;
  const scoredIds = new Set(existing.filter((r) => r.doc.profile).map((r) => r.doc.id));
  const generated = buildCandidates({ creatureDocs: world.creatureDocs, conflicts: world.conflicts, sourcesById, links: world.links, scoredIds });
  const written = [];
  const removed = [];
  const dir = path.join(root, 'candidates', 'records');
  const keep = new Set();
  for (const c of generated) {
    const rel = `candidates/records/${candidateFileBase(c.id)}.json`;
    keep.add(rel);
    const abs = path.join(root, rel);
    const text = canonicalPretty(c);
    if (!fs.existsSync(abs) || fs.readFileSync(abs, 'utf8').replace(/\r\n/g, '\n') !== text) {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(abs, text, 'utf8');
      written.push(rel);
    }
  }
  for (const r of existing) {
    if (!r.doc.profile && !keep.has(r.file)) {
      fs.unlinkSync(path.join(root, r.file));
      removed.push(r.file);
    }
  }
  console.log(`candidates: ${generated.length} candidato(s) sin puntuar (${written.length} escrito(s), ${removed.length} eliminado(s)); ${scoredIds.size} puntuado(s) respetado(s) en «${relRoot(root)}/candidates».`);
  for (const f of written) console.log(`  escrito  ${f}`);
  for (const f of removed) console.log(`  borrado  ${f}`);
  return 0;
}

function cmdValidate(root, baselineDir, quiet, scope) {
  const result = validateDataset(root, { baselineDir, scope });
  const { report } = result;
  print(report);
  const m = result.model;
  if (report.hasErrors()) {
    console.log(`\nvalidate: ${report.errors.length} error(es), ${report.warnings.length} aviso(s) en «${relRoot(root)}».`);
    return { code: 1, result };
  }
  if (!quiet) {
    console.log(`validate: correcto (${m.entities.size} entidades, ${m.bindings.size} bindings, ${m.hints.size} pistas, ${m.sourcesById.size} fuentes, ${m.creatures.size + m.places.size} documentos de World Data, ${m.candidates.size} candidatos, ${m.decisions.length} decisiones, ${m.ds.world.links.length} enlaces; ${report.warnings.length} aviso(s)) en «${relRoot(root)}».`);
  }
  return { code: 0, result };
}

function cmdQueue(root, args) {
  const result = validateDataset(root, {});
  for (const line of queueLines(result, { label: relRoot(root), flavor: args.flavor, all: args.all })) console.log(line);
  return 0;
}

function cmdExplain(root, args) {
  if (args.positional.length !== 1) {
    console.error('uso: node scripts/cli.js explain <id> (id de entidad npc:…, de candidato cand:… o de enlace link:…)');
    return 2;
  }
  const result = validateDataset(root, {});
  const r = explainLines(result, args.positional[0], { label: relRoot(root) });
  for (const line of r.lines) console.log(line);
  return r.found ? 0 : 1;
}

// El pack se genera con la validación de ámbito «publish»: NO lee ni valida Candidate Data.
function cmdGenerate(root, baselineDir, write, quiet) {
  const v = cmdValidate(root, baselineDir, true, 'publish');
  if (v.code !== 0) return { code: 1 };
  const { model } = v.result;
  const report = new Report();
  const built = [];
  for (const flavorId of Object.keys(model.flavors.flavors).sort()) {
    if (!model.flavors.flavors[flavorId].enabled) continue;
    built.push(buildFlavor(model, flavorId, report));
  }
  print(report);
  if (report.hasErrors()) {
    console.log(`\ngenerate: ${report.errors.length} error(es). No se ha escrito nada.`);
    return { code: 1 };
  }
  for (const b of built) {
    if (write) {
      const written = writeArtifacts(root, b);
      console.log(`generate: ${b.flavor}: ${b.pack.header.counts.entities} entidad(es), ${b.pack.header.counts.available} disponible(s), ${b.pack.header.counts.retired} lápida(s); content_revision ${b.pack.header.content_revision}`);
      for (const f of written) console.log(`  escrito  ${f}`);
    } else if (!quiet) {
      console.log(`generate (en memoria): ${b.flavor}: content_revision ${b.pack.header.content_revision}`);
    }
  }
  return { code: 0, built, model };
}

function cmdCheck(root, baselineDir) {
  const g = cmdGenerate(root, baselineDir, false, true);
  if (g.code !== 0) return 1;
  const report = new Report();
  for (const b of g.built) checkArtifacts(root, b, report);
  // artefactos de versiones que ya no están habilitadas
  const genDir = path.join(root, 'generated');
  if (fs.existsSync(genDir)) {
    const enabled = new Set(g.built.map((b) => b.flavor));
    for (const d of fs.readdirSync(genDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort(cmp)) {
      if (!enabled.has(d)) report.error('G-01', `generated/${d}`, '', 'artefactos de una versión no habilitada en editorial/flavors.yaml (bórrelos)');
    }
  }
  print(report);
  if (report.hasErrors()) {
    console.log(`\ncheck: ${report.errors.length} diferencia(s). Lo versionado no coincide con lo que regenera el pipeline.`);
    return 1;
  }
  for (const b of g.built) console.log(`check: ${b.flavor}: correcto (Pack.lua regenerado idéntico; huellas verificadas; content_revision ${b.pack.header.content_revision})`);
  return 0;
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.error || !COMMANDS.includes(args.command)) {
    console.error(args.error || `uso: node scripts/cli.js <${COMMANDS.join('|')}> [<id>] [--root <dir>] [--baseline-dir <dir>] [--flavor <id>] [--all]`);
    return 2;
  }
  const { root, baselineDir } = args;
  switch (args.command) {
    case 'normalize': return cmdNormalize(root);
    case 'candidates': return cmdCandidates(root);
    case 'validate': return cmdValidate(root, baselineDir, false).code;
    case 'queue': return cmdQueue(root, args);
    case 'explain': return cmdExplain(root, args);
    case 'generate': return cmdGenerate(root, baselineDir, true, false).code;
    case 'check': return cmdCheck(root, baselineDir);
    case 'pipeline': {
      for (const step of [() => cmdNormalize(root), () => cmdCandidates(root), () => cmdValidate(root, baselineDir, false).code, () => cmdGenerate(root, baselineDir, true, false).code, () => cmdCheck(root, baselineDir)]) {
        const code = step();
        if (code !== 0) return code;
      }
      return 0;
    }
    default: return 2;
  }
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));

module.exports = { main };
