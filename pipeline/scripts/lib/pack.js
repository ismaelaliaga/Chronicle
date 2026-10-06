'use strict';
// Generador del pack Lua por versión (Fase 16, 8). Lee un dataset YA validado, aplica la regla de ELEGIBILIDAD (procedencia autorizada)
// y produce artefactos deterministas: Pack.lua, pack-manifest.json y ship-report.json. Ningún artefacto lleva marcas de tiempo.
const fs = require('fs');
const path = require('path');
const { canonicalPretty, fingerprint, sha256Hex } = require('./canonical');
const { serialize } = require('./lua');
const { validateDoc } = require('./schemas');
const { shipEntity } = require('./ship');
const { cmp } = require('./report');

const GENERATOR_VERSION = '0.1.0';
const PACK_SCHEMA = 1;

const byId = (a, b) => cmp(a.id, b.id);

function worldFingerprint(model, flavor) {
  const sel = (arr, pick) => arr.filter(pick).sort((a, b) => cmp(a.file, b.file)).map((x) => x.doc);
  return fingerprint({
    sources: model.ds.sources.slice().sort((a, b) => cmp(a.file, b.file)).map((s) => s.doc),
    entities: sel(model.ds.world.entities, (x) => x.doc.ref.flavor === flavor),
    places: sel(model.ds.world.places, (x) => x.doc.ref.flavor === flavor),
    profiles: sel(model.ds.world.profiles, (x) => x.doc.flavor === flavor),
    observations: sel(model.ds.world.observations, (x) => x.doc.flavor === flavor),
    conflicts: sel(model.ds.world.conflicts, (x) => x.doc.subject.flavor === flavor),
  });
}

function editorialFingerprint(model, flavor) {
  const sel = (arr, pick) => arr.filter(pick).sort((a, b) => cmp(a.file, b.file)).map((x) => x.doc);
  const ed = model.ds.editorial;
  return fingerprint({
    flavor: model.flavors.flavors[flavor],
    editorial_locale: model.flavors.editorial_locale,
    entities: sel(ed.entities, (x) => x.doc.status === 'published' || x.doc.status === 'retired'),
    bindings: sel(ed.bindings, (x) => x.doc.flavor === flavor),
    hints: sel(ed.hints, (x) => x.doc.status === 'published'),
    texts: sel(ed.texts, () => true),
  });
}

// Construye el pack de una versión. Los errores de cierre de referencias (G-05) y de nombres ambiguos (G-10) se anotan en `report`.
function buildFlavor(model, flavorId, report) {
  const cfg = model.flavors.flavors[flavorId];
  const entities = Array.from(model.entityDocs.values()).sort(byId);
  const published = entities.filter((e) => e.status === 'published');
  const retired = entities.filter((e) => e.status === 'retired');

  const ships = new Map();
  for (const e of published) ships.set(e.id, shipEntity(model, e, flavorId));

  const inPack = published.filter((e) => e.applies_to.includes(flavorId));
  const inPackIds = new Set(inPack.map((e) => e.id));
  const retiredIds = new Set(retired.map((e) => e.id));
  const known = (id) => inPackIds.has(id) || retiredIds.has(id);

  const sec = { entities: {}, presence: {}, discovery: {}, hints: {}, texts: {}, names: {}, tombstones: {} };

  for (const e of inPack) {
    const entry = { type: e.type, status: 'published', importance: e.importance || 'standard' };
    if (e.categories && e.categories.length) entry.categories = e.categories.slice().sort();
    for (const rel of ['parent', 'located_in']) {
      if (e[rel]) {
        entry[rel] = e[rel];
        if (!known(e[rel])) report.error('G-05', `editorial/entities/${e.id.replace(':', '__')}.yaml`, `/${rel}`, `«${e[rel]}» no está en el pack de «${flavorId}» (no aplica a esa versión o no está publicada)`);
      }
    }
    if (e.related_to && e.related_to.length) {
      entry.related_to = e.related_to.slice().sort();
      for (const r of entry.related_to) {
        if (!known(r)) report.error('G-05', `editorial/entities/${e.id.replace(':', '__')}.yaml`, '/related_to', `«${r}» no está en el pack de «${flavorId}»`);
      }
    }
    sec.entities[e.id] = entry;

    const ship = ships.get(e.id);
    if (ship.available) {
      const presence = { available: true, tech: ship.tech.slice().sort((a, b) => cmp(a.kind, b.kind) || a.id - b.id) };
      if (Object.keys(ship.attributes).length) presence.attributes = ship.attributes;
      sec.presence[e.id] = presence;
      const rules = JSON.parse(JSON.stringify(ship.rules));
      if (ship.required_capabilities.length) rules.required_capabilities = ship.required_capabilities;
      sec.discovery[e.id] = rules;
      for (const pn of ship.placeNames) {
        sec.names[pn.locale] = sec.names[pn.locale] || {};
        sec.names[pn.locale][pn.api] = sec.names[pn.locale][pn.api] || {};
        const prev = sec.names[pn.locale][pn.api][pn.key];
        if (prev && prev !== e.id) report.error('G-10', 'pack', `/names/${pn.locale}/${pn.api}`, `la cadena «${pn.key}» identifica a «${prev}» y a «${e.id}» (ambigua)`);
        else sec.names[pn.locale][pn.api][pn.key] = e.id;
      }
    } else {
      sec.presence[e.id] = { available: false, reason: ship.reasons[0], tech: [] };
    }
  }

  // pistas publicadas cuya entidad objetivo está disponible en esta versión
  const includedHints = new Map();
  for (const h of Array.from(model.hintDocs.values()).sort(byId)) {
    if (h.status !== 'published' || !inPackIds.has(h.target) || !ships.get(h.target).available) continue;
    const appliesTo = h.applies_to || model.entityDocs.get(h.target).applies_to;
    if (!appliesTo.includes(flavorId)) continue;
    includedHints.set(h.id, h);
  }
  for (const h of includedHints.values()) {
    const entry = { target: h.target, kind: h.kind, necessity: h.necessity, tier: h.tier, text: h.text };
    if (h.reveals_when) entry.reveals_when = h.reveals_when;
    if (h.depends_on && h.depends_on.length) entry.depends_on = h.depends_on.slice().sort();
    if (h.related_to && h.related_to.length) entry.related_to = h.related_to.slice().sort();
    for (const d of entry.depends_on || []) {
      if (!includedHints.has(d)) report.error('G-05', 'pack', `/hints/${h.id}/depends_on`, `la pista «${h.id}» depende de «${d}», que no está en el pack de «${flavorId}»`);
    }
    sec.hints[h.id] = entry;
  }

  // textos del idioma editorial y demás idiomas configurados, solo de lo que está en el pack
  const textIds = new Set(Array.from(inPackIds).concat(Array.from(includedHints.keys())));
  for (const locale of cfg.locales.slice().sort()) {
    const byIdMap = model.texts.get(locale);
    if (!byIdMap) continue;
    const out = {};
    for (const id of Array.from(textIds).sort()) if (byIdMap.has(id)) out[id] = byIdMap.get(id).entry;
    if (Object.keys(out).length) sec.texts[locale] = out;
  }

  // lápidas: toda entidad retirada va en TODAS las versiones habilitadas (Fase 16, 10)
  for (const e of retired) {
    const t = { type: e.type, status: 'retired' };
    for (const rel of ['parent', 'located_in']) {
      if (e[rel]) {
        t[rel] = e[rel];
        if (!known(e[rel])) report.error('G-05', `editorial/entities/${e.id.replace(':', '__')}.yaml`, `/${rel}`, `la lápida de «${e.id}» referencia «${e[rel]}», que no está en el pack de «${flavorId}»`);
      }
    }
    if (e.retired && e.retired.superseded_by) t.superseded_by = e.retired.superseded_by;
    sec.tombstones[e.id] = t;
  }

  const counts = {
    entities: Object.keys(sec.entities).length,
    published: Object.keys(sec.entities).length,
    available: Object.keys(sec.discovery).length,
    retired: Object.keys(sec.tombstones).length,
    hints: Object.keys(sec.hints).length,
  };
  const client = { interface: cfg.interface.slice().sort((a, b) => a - b) };
  const features = { persist_hints: cfg.features.persist_hints, persist_interaction_progress: cfg.features.persist_interaction_progress };
  const locales = cfg.locales.slice().sort();

  // content_revision: huella de las ENTRADAS del pack (no de su procedencia): cambiar un dato no autorizado no la altera.
  const content_revision = fingerprint({ pack_schema: PACK_SCHEMA, flavor: flavorId, client, features, locales, counts, ...sec });
  const header = {
    pack_schema: PACK_SCHEMA,
    flavor: flavorId,
    client,
    content_revision,
    generated_from: { world: worldFingerprint(model, flavorId), editorial: editorialFingerprint(model, flavorId), generator: GENERATOR_VERSION },
    counts,
    features,
    locales,
  };
  const pack = Object.assign({ header }, sec);

  const comment = [
    `-- GENERADO por chronicle-pipeline ${GENERATOR_VERSION}. NO EDITAR A MANO: se regenera con \`npm run data:generate\` (carpeta pipeline/).`,
    `-- flavor: ${flavorId} | pack_schema: ${PACK_SCHEMA}`,
  ];
  if (cfg.notes) comment.push('-- ' + String(cfg.notes).replace(/\s+/g, ' ').replace(/[^\x20-\x7e]/g, '?'));
  const lua = comment.join('\n') + '\nChronicle = Chronicle or {}\n\nChronicle.Pack = ' + serialize(pack) + '\n';

  const authorizedSources = Array.from(model.authorized).sort();
  const shipReport = {
    schema: 'chronicle.report.ship/1',
    flavor: flavorId,
    policy: { capability_policy: cfg.capability_policy, authorized_sources: authorizedSources },
    entries: published.map((e) => {
      const s = ships.get(e.id);
      return { entity: e.id, flavor: flavorId, available: s.available, reasons: s.reasons, details: s.details, omitted_optional: s.omitted_optional, warnings: s.warnings, authorized_by: s.authorized_by };
    }),
  };
  const manifest = {
    schema: 'chronicle.pack.manifest/1',
    pack_schema: PACK_SCHEMA,
    flavor: flavorId,
    client,
    content_revision,
    generated_from: header.generated_from,
    counts,
    features,
    locales,
    files: [{ path: 'Pack.lua', sha256: sha256Hex(lua) }],
  };
  validateDoc('pack.manifest', manifest, report, `generated/${flavorId}/pack-manifest.json`, 'G-09');
  validateDoc('report.ship', shipReport, report, `generated/${flavorId}/ship-report.json`, 'G-09');
  return { flavor: flavorId, pack, lua, manifest, shipReport };
}

function artifactTexts(built) {
  return [
    { rel: `generated/${built.flavor}/Pack.lua`, text: built.lua },
    { rel: `generated/${built.flavor}/pack-manifest.json`, text: canonicalPretty(built.manifest) },
    { rel: `generated/${built.flavor}/ship-report.json`, text: canonicalPretty(built.shipReport) },
  ];
}

function writeArtifacts(root, built) {
  const written = [];
  for (const a of artifactTexts(built)) {
    const abs = path.join(root, a.rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    if (!fs.existsSync(abs) || fs.readFileSync(abs, 'utf8').replace(/\r\n/g, '\n') !== a.text) {
      fs.writeFileSync(abs, a.text, 'utf8');
      written.push(a.rel);
    }
  }
  return written;
}

// Para `data:check`: lo versionado debe ser byte a byte lo que se regenera, y las huellas del manifiesto deben ser verificables.
function checkArtifacts(root, built, report) {
  for (const a of artifactTexts(built)) {
    const abs = path.join(root, a.rel);
    if (!fs.existsSync(abs)) { report.error('G-01', a.rel, '', 'falta el artefacto generado (ejecute data:generate)'); continue; }
    if (fs.readFileSync(abs, 'utf8').replace(/\r\n/g, '\n') !== a.text) report.error('G-01', a.rel, '', 'no coincide con lo que regenera el pipeline (ejecute data:generate). Un artefacto generado no se edita a mano');
  }
  // verificación de huellas sobre lo que hay en disco
  const manifestPath = path.join(root, `generated/${built.flavor}/pack-manifest.json`);
  const luaPath = path.join(root, `generated/${built.flavor}/Pack.lua`);
  if (fs.existsSync(manifestPath) && fs.existsSync(luaPath)) {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const luaText = fs.readFileSync(luaPath, 'utf8').replace(/\r\n/g, '\n');
    const expected = manifest.files && manifest.files[0] && manifest.files[0].sha256;
    if (expected !== sha256Hex(luaText)) report.error('G-01', `generated/${built.flavor}/pack-manifest.json`, '/files/0/sha256', 'el sha256 del manifiesto no coincide con Pack.lua');
    if (manifest.content_revision !== built.pack.header.content_revision) report.error('G-01', `generated/${built.flavor}/pack-manifest.json`, '/content_revision', 'content_revision del manifiesto no coincide con el del pack regenerado');
  }
}

module.exports = { GENERATOR_VERSION, PACK_SCHEMA, buildFlavor, writeArtifacts, checkArtifacts, artifactTexts, worldFingerprint, editorialFingerprint };
