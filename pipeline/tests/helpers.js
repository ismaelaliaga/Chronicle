'use strict';
// Utilidades de las pruebas del pipeline: copiar un dataset a un directorio temporal, mutar ficheros y ejecutar la CLI.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const PIPELINE_DIR = path.resolve(__dirname, '..');
const FIXTURE_ROOT = path.join(PIPELINE_DIR, 'fixtures', 'authorized');
const REAL_ROOT = PIPELINE_DIR;
const DATA_DIRS = ['sources', 'world', 'editorial', 'candidates', 'generated'];

function mkTmp(label = 'chronicle-pipeline-') {
  return fs.mkdtempSync(path.join(os.tmpdir(), label));
}

// Copia solo los directorios de DATOS de un dataset (nunca node_modules ni fixtures anidados).
function copyDataset(srcRoot) {
  const dst = mkTmp();
  for (const d of DATA_DIRS) {
    const from = path.join(srcRoot, d);
    if (fs.existsSync(from)) fs.cpSync(from, path.join(dst, d), { recursive: true });
  }
  return dst;
}

function read(root, rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function write(root, rel, text) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, text, 'utf8');
}

// Aplica una sustitución exacta a un fichero (falla si el texto buscado no existe: la prueba no puede pasar «por casualidad»).
function edit(root, rel, search, replacement) {
  const text = read(root, rel);
  if (!text.includes(search)) throw new Error(`edit: «${search}» no está en ${rel}`);
  write(root, rel, text.replace(search, replacement));
}

function cli(args, cwd = PIPELINE_DIR) {
  const r = spawnSync(process.execPath, [path.join(PIPELINE_DIR, 'scripts', 'cli.js'), ...args], { cwd, encoding: 'utf8' });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

function rm(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

module.exports = { PIPELINE_DIR, FIXTURE_ROOT, REAL_ROOT, mkTmp, copyDataset, read, write, edit, cli, rm };
