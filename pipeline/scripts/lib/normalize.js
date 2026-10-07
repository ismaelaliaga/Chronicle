'use strict';
// Normalización de World Data (Fase 16, 5.4-5.5, y 6.3 «importar»): registros crudos con procedencia -> documentos canónicos
// (`world.entity`, `world.place`, `world.conflict`) con el valor resuelto de cada campo.
//
// Alcance: SOLO los campos del esquema (exists, names, subnames, attributes, relations, spawns, places, texts de lugares). No importa nada
// de forma masiva: la entrada son registros pequeños y controlados.
const fs = require('fs');
const path = require('path');
const { canonicalPretty } = require('./canonical');
const { resolveField, sortClaims } = require('./resolve');
const { validateDoc } = require('./schemas');
const { placeSlug, idToFileBase } = require('./loader');
const { cmp } = require('./report');
const { buildLinks, linkIdFor, linkFileBase } = require('./links');

// Directorios de World Data cuyo contenido escribe el normalizador (el resto son entradas: profile.json y observations/).
// `world/links/` (sin flavor: un enlace puede unir dos versiones) también es del normalizador.
const OWNED_DIRS = ['creature', 'place', 'conflicts'];
const LINKS_DIR = 'world/links';

function subjectKey(subject) {
  if (subject.kind === 'name_only') return `place/${placeSlug(subject.key)}`;
  if (subject.kind === 'area' || subject.kind === 'ui_map') return `place/${subject.kind}_${subject.id}`;
  return `${subject.kind}/${subject.id}`;
}

function isPlaceSubject(subject) {
  return subject.kind === 'name_only' || subject.kind === 'area' || subject.kind === 'ui_map';
}

// Inserta un campo `field` (ruta) en el documento.
function setField(doc, field, value) {
  const parts = field.split('.');
  if (parts[0] === 'exists' || parts[0] === 'spawns' || parts[0] === 'places') {
    doc[parts[0]] = value;
  } else if (parts[0] === 'names' || parts[0] === 'subnames' || parts[0] === 'attributes' || parts[0] === 'relations') {
    doc[parts[0]] = doc[parts[0]] || {};
    doc[parts[0]][parts[1]] = value;
  } else if (parts[0] === 'texts') {
    doc.texts = doc.texts || {};
    doc.texts[parts[1]] = doc.texts[parts[1]] || {};
    doc.texts[parts[1]][parts[2]] = value;
  }
}

// Devuelve { outputs: Map(rutaRelativa -> doc), conflicts: [...] }.
function buildWorld(ds, report) {
  const sourcesById = new Map(ds.sources.map((s) => [s.doc.id, s.doc]));
  const overrides = ds.editorial.overrides.map((o) => o.doc);
  const flavors = ds.flavors ? ds.flavors.doc.flavors : {};
  const groups = new Map(); // `${flavor}|${subjectKey}` -> { flavor, subject, fields: Map(field -> claims[]) }

  for (const { file, doc } of ds.records) {
    const source = sourcesById.get(doc.source);
    if (!source) {
      report.error('R-05', file, '/source', `fuente desconocida «${doc.source}» (no hay manifiesto en sources/)`);
      continue;
    }
    doc.records.forEach((rec, i) => {
      const at = `/records/${i}`;
      if (source.status === 'blocked') {
        report.error('R-04', file, at, `la fuente «${source.id}» está bloqueada`);
        return;
      }
      if (!source.applicable_flavors.includes(rec.flavor)) {
        report.error('R-03', file, `${at}/flavor`, `la fuente «${source.id}» no es aplicable al flavor «${rec.flavor}»`);
        return;
      }
      if (!flavors[rec.flavor]) {
        report.error('R-07', file, `${at}/flavor`, `el flavor «${rec.flavor}» no está en editorial/flavors.yaml`);
        return;
      }
      if (rec.subject.flavor !== rec.flavor) {
        report.error('R-08', file, `${at}/subject/flavor`, 'el flavor del sujeto no coincide con el del registro');
        return;
      }
      const place = isPlaceSubject(rec.subject);
      const isText = rec.field.startsWith('texts.');
      if (place !== isText) {
        report.error('R-09', file, `${at}/field`, isText ? 'los campos «texts.*» solo valen para lugares' : 'los lugares solo admiten campos «texts.*»');
        return;
      }
      const key = `${rec.flavor}|${subjectKey(rec.subject)}`;
      if (!groups.has(key)) groups.set(key, { flavor: rec.flavor, subject: rec.subject, fields: new Map() });
      const g = groups.get(key);
      if (!g.fields.has(rec.field)) g.fields.set(rec.field, []);
      g.fields.get(rec.field).push({
        value: rec.value,
        provenance: Object.assign({ source: doc.source }, rec.provenance),
        confidence: rec.confidence,
      });
    });
  }

  const outputs = new Map();
  const conflicts = [];
  const keys = Array.from(groups.keys()).sort(cmp);
  for (const key of keys) {
    const g = groups.get(key);
    const place = isPlaceSubject(g.subject);
    const relPath = `world/${g.flavor}/${subjectKey(g.subject)}.json`;
    const doc = place
      ? { schema: 'chronicle.world.place/1', ref: g.subject, identity_quality: g.subject.kind === 'name_only' ? 'name_only' : 'verified', texts: {} }
      : { schema: 'chronicle.world.entity/1', ref: g.subject };
    for (const field of Array.from(g.fields.keys()).sort(cmp)) {
      const ctx = { sourcesById, overrides, subject: g.subject, field, report, file: relPath };
      const r = resolveField(g.fields.get(field), ctx);
      setField(doc, field, { claims: r.claims, resolved: r.resolved });
      if (r.conflict) conflicts.push(r.conflict);
    }
    if (!place && !doc.exists) {
      report.error('R-06', relPath, '/exists', 'una entidad del mundo necesita al menos una afirmación de existencia (campo «exists»)');
      continue;
    }
    if (!validateDoc(place ? 'world.place' : 'world.entity', doc, report, relPath)) continue;
    outputs.set(relPath, doc);
  }
  conflicts.sort((a, b) => cmp(a.id, b.id));
  for (const c of conflicts) {
    const relPath = `world/${c.subject.flavor}/conflicts/${idToFileBase(c.id)}.json`;
    if (validateDoc('world.conflict', c, report, relPath)) outputs.set(relPath, c);
  }

  // enlaces de reconciliación propuestos (Fase 18). Una LinkDecision `reject` (different_from) impide que la pareja vuelva a proponerse.
  const creatureDocs = Array.from(outputs.values()).filter((d) => d.schema === 'chronicle.world.entity/1');
  const rejected = new Set((ds.editorial.linkDecisions || []).filter((d) => d.doc.decision === 'reject').map((d) => linkIdFor(d.doc.a, d.doc.b)));
  const links = buildLinks(creatureDocs, sourcesById, rejected);
  for (const l of links) {
    const relPath = `${LINKS_DIR}/${linkFileBase(l.id)}.json`;
    if (validateDoc('world.link', l, report, relPath)) outputs.set(relPath, l);
  }
  return { outputs, conflicts, links, creatureDocs };
}

// Archivos propiedad del normalizador que existen hoy en disco (rutas relativas).
function listOwnedFiles(root) {
  const found = [];
  const worldDir = path.join(root, 'world');
  if (!fs.existsSync(worldDir)) return found;
  const linksDir = path.join(worldDir, 'links');
  if (fs.existsSync(linksDir)) for (const f of fs.readdirSync(linksDir).sort(cmp)) found.push(`${LINKS_DIR}/${f}`);
  for (const flavor of fs.readdirSync(worldDir, { withFileTypes: true }).filter((e) => e.isDirectory() && e.name !== 'links').map((e) => e.name).sort(cmp)) {
    for (const d of OWNED_DIRS) {
      const dir = path.join(worldDir, flavor, d);
      if (!fs.existsSync(dir)) continue;
      for (const f of fs.readdirSync(dir).sort(cmp)) found.push(`world/${flavor}/${d}/${f}`);
    }
  }
  return found;
}

// Escribe los documentos normalizados y borra los ficheros propios que ya no corresponden. Devuelve { written, removed }.
function writeWorld(root, outputs) {
  const written = [];
  const removed = [];
  for (const [rel, doc] of Array.from(outputs.entries()).sort((a, b) => cmp(a[0], b[0]))) {
    const abs = path.join(root, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    const text = canonicalPretty(doc);
    if (!fs.existsSync(abs) || fs.readFileSync(abs, 'utf8').replace(/\r\n/g, '\n') !== text) {
      fs.writeFileSync(abs, text, 'utf8');
      written.push(rel);
    }
  }
  for (const rel of listOwnedFiles(root)) {
    if (!outputs.has(rel)) {
      fs.unlinkSync(path.join(root, rel));
      removed.push(rel);
    }
  }
  return { written, removed };
}

// Compara lo versionado con lo que produciría el normalizador (para `data:check`). Devuelve lista de diferencias.
function diffWorld(root, outputs) {
  const diffs = [];
  for (const [rel, doc] of Array.from(outputs.entries()).sort((a, b) => cmp(a[0], b[0]))) {
    const abs = path.join(root, rel);
    if (!fs.existsSync(abs)) diffs.push({ file: rel, why: 'falta (ejecute data:normalize)' });
    else if (fs.readFileSync(abs, 'utf8').replace(/\r\n/g, '\n') !== canonicalPretty(doc)) diffs.push({ file: rel, why: 'no coincide con la normalización de los registros (ejecute data:normalize)' });
  }
  for (const rel of listOwnedFiles(root)) {
    if (!outputs.has(rel)) diffs.push({ file: rel, why: 'fichero sobrante: ningún registro lo produce (ejecute data:normalize)' });
  }
  return diffs;
}

module.exports = { buildWorld, writeWorld, diffWorld, listOwnedFiles, subjectKey, sortClaims };
