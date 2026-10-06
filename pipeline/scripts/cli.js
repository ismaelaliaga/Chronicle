#!/usr/bin/env node
'use strict';
// CLI del pipeline de datos. Uso: node scripts/cli.js <normalize|validate|generate|check|pipeline> [--root <dir>] [--baseline-dir <dir>]
// Códigos de salida: 0 correcto, 1 errores de validación o diferencias, 2 uso incorrecto.
const fs = require('fs');
const path = require('path');
const { Report } = require('./lib/report');
const { loadDataset } = require('./lib/loader');
const { buildWorld, writeWorld } = require('./lib/normalize');
const { validateDataset } = require('./lib/validate');
const { buildFlavor, writeArtifacts, checkArtifacts } = require('./lib/pack');

const DEFAULT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const args = { command: argv[0], root: DEFAULT_ROOT, baselineDir: null };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--root') args.root = path.resolve(argv[++i] || '');
    else if (argv[i] === '--baseline-dir') args.baselineDir = argv[++i];
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

function cmdValidate(root, baselineDir, quiet) {
  const result = validateDataset(root, { baselineDir });
  const { report } = result;
  print(report);
  const m = result.model;
  if (report.hasErrors()) {
    console.log(`\nvalidate: ${report.errors.length} error(es), ${report.warnings.length} aviso(s) en «${relRoot(root)}».`);
    return { code: 1, result };
  }
  if (!quiet) {
    console.log(`validate: correcto (${m.entities.size} entidades, ${m.bindings.size} bindings, ${m.hints.size} pistas, ${m.sourcesById.size} fuentes, ${m.creatures.size + m.places.size} documentos de World Data; ${report.warnings.length} aviso(s)) en «${relRoot(root)}».`);
  }
  return { code: 0, result };
}

function cmdGenerate(root, baselineDir, write, quiet) {
  const v = cmdValidate(root, baselineDir, true);
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
    for (const d of fs.readdirSync(genDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()) {
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
  if (args.error || !['normalize', 'validate', 'generate', 'check', 'pipeline'].includes(args.command)) {
    console.error(args.error || `uso: node scripts/cli.js <normalize|validate|generate|check|pipeline> [--root <dir>] [--baseline-dir <dir>]`);
    return 2;
  }
  const { root, baselineDir } = args;
  switch (args.command) {
    case 'normalize': return cmdNormalize(root);
    case 'validate': return cmdValidate(root, baselineDir, false).code;
    case 'generate': return cmdGenerate(root, baselineDir, true, false).code;
    case 'check': return cmdCheck(root, baselineDir);
    case 'pipeline': {
      for (const step of [() => cmdNormalize(root), () => cmdValidate(root, baselineDir, false).code, () => cmdGenerate(root, baselineDir, true, false).code, () => cmdCheck(root, baselineDir)]) {
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
