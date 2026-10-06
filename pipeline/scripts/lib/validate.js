'use strict';
// Validación del pipeline (`data:validate`): contratos, referencias, IDs, bindings, procedencia, reglas de publicación, pistas y estados.
// Los códigos siguen el catálogo de la Fase 16 (W-xx World, C-xx Candidate, E-xx Editorial) más R/S/P/X para fuentes, registros, configuración y cruces.
// Salida determinista: ver Report.sorted().
const path = require('path');
const { Report, cmp } = require('./report');
const { loadDataset } = require('./loader');
const { buildModel } = require('./model');
const { buildWorld, diffWorld } = require('./normalize');
const {
  PLACE_TYPES, TYPE_RULES, MAX_SLUG, typeOf, slugOf, checkTransition, normalizeName,
  effectiveRules, walkRequirement, requirementRefs, usesInteractionAll, materializeRules, findCoordinates, findNameLeak,
} = require('./rules');
const { canonicalCompact } = require('./canonical');

// ----------------------------------------------------------------------------------------------- configuración y fuentes
function checkConfig(m, report) {
  if (!m.flavors) return;
  const file = m.ds.flavors.file;
  for (const [id, f] of Object.entries(m.flavors.flavors)) {
    if (f.enabled && !f.locales.includes(m.flavors.editorial_locale)) {
      report.error('P-02', file, `/flavors/${id}/locales`, `el flavor habilitado «${id}» debe incluir el idioma editorial «${m.flavors.editorial_locale}»`);
    }
  }
  for (const s of m.ds.sources) {
    s.doc.applicable_flavors.forEach((f, i) => {
      if (!m.flavors.flavors[f]) report.error('S-04', s.file, `/applicable_flavors/${i}`, `el flavor «${f}» no está en editorial/flavors.yaml`);
    });
  }
}

// ----------------------------------------------------------------------------------------------- World Data
function checkWorld(m, report) {
  const { ds } = m;
  for (const p of ds.world.places) {
    if (p.doc.ref.kind === 'name_only' && p.doc.ref.key !== normalizeName(p.doc.ref.key)) {
      report.error('W-13', p.file, '/ref/key', `la clave de un lugar «name_only» debe estar normalizada (recortada, en minúsculas): «${normalizeName(p.doc.ref.key)}»`);
    }
  }
  // Toda afirmación remite a una fuente conocida y aplicable (procedencia trazable).
  const checkClaims = (file, doc) => {
    const visit = (v, at) => {
      if (Array.isArray(v)) return v.forEach((x, i) => visit(x, `${at}/${i}`));
      if (!v || typeof v !== 'object') return;
      if (v.provenance && v.provenance.source) {
        const s = m.sourcesById.get(v.provenance.source);
        if (!s) report.error('W-02', file, at, `la fuente «${v.provenance.source}» no tiene manifiesto`);
        else if (s.status === 'blocked') report.error('W-02', file, at, `la fuente «${s.id}» está bloqueada`);
      }
      for (const k of Object.keys(v)) visit(v[k], `${at}/${k}`);
    };
    visit(doc, '');
  };
  for (const e of ds.world.entities) checkClaims(e.file, e.doc);
  for (const p of ds.world.places) checkClaims(p.file, p.doc);
  for (const c of ds.world.conflicts) checkClaims(c.file, c.doc);
  // Evidencias de capacidades verified: observaciones existentes del mismo flavor.
  for (const p of ds.world.profiles) {
    for (const [cap, v] of Object.entries(p.doc.capabilities)) {
      v.evidence.forEach((id, i) => {
        const o = m.observations.get(id);
        if (!o) report.error('W-11', p.file, `/capabilities/${cap}/evidence/${i}`, `la observación «${id}» no existe`);
        else if (o.doc.flavor !== p.doc.flavor) report.error('W-11', p.file, `/capabilities/${cap}/evidence/${i}`, `la observación «${id}» es de otro flavor`);
      });
    }
    if (!m.flavors || !m.flavors.flavors[p.doc.flavor]) report.error('W-12', p.file, '/flavor', `el flavor «${p.doc.flavor}» no está en editorial/flavors.yaml`);
  }
}

// ----------------------------------------------------------------------------------------------- Editorial: entidades
function checkEntities(m, report) {
  const flavors = m.flavors ? m.flavors.flavors : {};
  const editorialLocale = m.flavors ? m.flavors.editorial_locale : null;
  const vocab = new Set();
  for (const v of m.ds.editorial.vocab) v.doc.categories.forEach((c) => vocab.add(c));

  for (const [id, { file, doc: e }] of Array.from(m.entities.entries()).sort((a, b) => cmp(a[0], b[0]))) {
    if (typeOf(id) !== e.type) report.error('E-02', file, '/type', `el tipo «${e.type}» no coincide con el prefijo del ID «${typeOf(id)}»`);
    if (slugOf(id).length > MAX_SLUG) report.error('E-02', file, '/id', `el slug supera ${MAX_SLUG} caracteres`);

    // relaciones (E-03): existencia y tipos, igual que Schema.lua
    const rules = TYPE_RULES[e.type] || {};
    for (const rel of ['parent', 'located_in']) {
      const target = e[rel];
      if (target === undefined) {
        if (rel === 'parent' && rules.parent && rules.parent.required) report.error('E-03', file, `/${rel}`, `«${e.type}» exige «parent»`);
        continue;
      }
      if (!rules[rel]) { report.error('E-03', file, `/${rel}`, `«${e.type}» no admite «${rel}»`); continue; }
      const t = m.entities.get(target);
      if (!t) { report.error('E-03', file, `/${rel}`, `«${target}» no existe`); continue; }
      if (!rules[rel].types.includes(t.doc.type)) report.error('E-03', file, `/${rel}`, `«${target}» es de tipo «${t.doc.type}»; se admiten: ${rules[rel].types.join(', ')}`);
    }
    (e.related_to || []).forEach((r, i) => {
      if (!m.entities.has(r)) report.error('E-03', file, `/related_to/${i}`, `«${r}» no existe`);
      if (r === id) report.error('E-03', file, `/related_to/${i}`, 'una entidad no puede relacionarse consigo misma');
    });
    // un publicado solo referencia entidades publicadas o retiradas (el pack debe poder resolver sus referencias)
    if (e.status === 'published') {
      for (const [rel, t] of [['parent', e.parent], ['located_in', e.located_in]].filter((x) => x[1])) {
        const te = m.entities.get(t);
        if (te && !['published', 'retired'].includes(te.doc.status)) report.error('E-03', file, `/${rel}`, `«${t}» está en estado «${te.doc.status}»: un publicado solo puede referenciar publicados o retirados`);
      }
      (e.related_to || []).forEach((r, i) => {
        const te = m.entities.get(r);
        if (te && !['published', 'retired'].includes(te.doc.status)) report.error('E-03', file, `/related_to/${i}`, `«${r}» está en estado «${te.doc.status}»: un publicado solo puede referenciar publicados o retirados`);
      });
    }

    // applies_to y flavors
    e.applies_to.forEach((f, i) => { if (!flavors[f]) report.error('E-14', file, `/applies_to/${i}`, `el flavor «${f}» no está en editorial/flavors.yaml`); });
    for (const f of Object.keys(e.flavors || {})) {
      if (!flavors[f]) report.error('E-15', file, `/flavors/${f}`, `el flavor «${f}» no está en editorial/flavors.yaml`);
      else if (!e.applies_to.includes(f)) report.error('E-15', file, `/flavors/${f}`, `hay una anulación para «${f}» pero la entidad no aplica a ese flavor`);
    }

    // categorías
    (e.categories || []).forEach((c, i) => { if (!vocab.has(c)) report.error('E-16', file, `/categories/${i}`, `la categoría «${c}» no está en ningún vocabulario (editorial/vocab)`); });

    // estado
    if (e.status === 'published') {
      const t = editorialLocale && m.texts.get(editorialLocale) && m.texts.get(editorialLocale).get(id);
      if (!t || !t.entry.title) report.error('E-04', file, '/status', `un publicado necesita «title» en el idioma editorial ${editorialLocale} (editorial/text)`);
    }
    if (e.status === 'retired' && e.retired && e.retired.superseded_by && !m.entities.has(e.retired.superseded_by)) {
      report.error('E-05', file, '/retired/superseded_by', `«${e.retired.superseded_by}» no existe`);
    }

    checkDiscovery(m, report, file, e);
  }

  // ciclos en la jerarquía parent
  for (const [id, { file }] of m.entities) {
    const seen = new Set([id]);
    let cur = m.entityDocs.get(id) && m.entityDocs.get(id).parent;
    while (cur) {
      if (seen.has(cur)) { report.error('E-03', file, '/parent', `ciclo en la jerarquía de «parent» (pasa por «${cur}»)`); break; }
      seen.add(cur);
      cur = m.entityDocs.get(cur) && m.entityDocs.get(cur).parent;
    }
  }
}

// ----------------------------------------------------------------------------------------------- Editorial: reglas de descubrimiento
function checkDiscovery(m, report, file, e) {
  const flavors = m.flavors ? m.flavors.flavors : {};
  const variants = [];
  if (e.discovery) variants.push({ rules: e.discovery, at: '/discovery', flavors: e.applies_to.filter((f) => !(e.flavors && e.flavors[f] && e.flavors[f].discovery)) });
  for (const f of Object.keys(e.flavors || {})) if (e.flavors[f].discovery) variants.push({ rules: e.flavors[f].discovery, at: `/flavors/${f}/discovery`, flavors: [f] });

  for (const v of variants) {
    const { rules, at } = v;
    const isPlace = PLACE_TYPES.has(e.type);
    if (isPlace && rules.method === 'interaction') report.error('E-06', file, `${at}/method`, `«${e.type}» es un lugar: se descubre entrando (place_enter), no por interacción`);
    if (!isPlace && rules.method === 'place_enter') report.error('E-06', file, `${at}/method`, `«${e.type}» no es un lugar: «place_enter» no es válido`);
    const refs = requirementRefs(rules.requirements);
    refs.places.forEach((id) => {
      const t = m.entities.get(id);
      if (!t) report.error('E-06', file, `${at}/requirements`, `place_discovered: «${id}» no existe`);
      else if (!PLACE_TYPES.has(t.doc.type)) report.error('E-06', file, `${at}/requirements`, `place_discovered: «${id}» no es un lugar`);
    });
    refs.entities.forEach((id) => {
      const t = m.entities.get(id);
      if (!t) report.error('E-06', file, `${at}/requirements`, `entity_discovered: «${id}» no existe`);
      else if (PLACE_TYPES.has(t.doc.type)) report.error('E-06', file, `${at}/requirements`, `entity_discovered: «${id}» es un lugar (use place_discovered)`);
    });
    // características RESERVADAS (Fase 16, 7.4): solo con su `feature` habilitada en esa versión
    for (const f of v.flavors) {
      const feat = flavors[f] && flavors[f].features;
      if (!feat) continue;
      if (usesInteractionAll(rules.interaction) && !feat.persist_interaction_progress) {
        report.error('E-06', file, `${at}/interaction`, `«all» en interacciones está RESERVADO: exige progreso persistido (features.persist_interaction_progress) y no está habilitado en «${f}»`);
      }
      if (refs.hints.length > 0 && !feat.persist_hints) {
        report.error('E-06', file, `${at}/requirements`, `«hint_seen» está RESERVADO: exige persistir pistas (features.persist_hints) y no está habilitado en «${f}»`);
      }
    }
    // el requisito por defecto debe poder materializarse
    if (rules.method === 'interaction' && !rules.requirements) {
      for (const f of v.flavors) {
        if (!materializeRules(e, f, m.entityDocs).rules) report.error('E-06', file, `${at}`, `sin «requirements» y sin zona/ciudad ancestro por located_in: no se puede materializar el requisito por defecto`);
      }
    }
  }
  if (!e.discovery && !(PLACE_TYPES.has(e.type))) {
    // npc/lore sin reglas base: lo exige el esquema; aquí solo se cubre el caso de reglas solo por versión
  }
}

// ciclos entre entidades por entity_discovered
function checkDiscoveryCycles(m, report) {
  const edges = new Map();
  for (const [id, { doc: e }] of m.entities) {
    const deps = new Set();
    const rulesList = [e.discovery].concat(Object.values(e.flavors || {}).map((x) => x.discovery)).filter(Boolean);
    rulesList.forEach((r) => requirementRefs(r.requirements).entities.forEach((d) => deps.add(d)));
    edges.set(id, Array.from(deps).filter((d) => m.entities.has(d)).sort());
  }
  const state = new Map();
  const stack = [];
  const dfs = (id) => {
    state.set(id, 1);
    stack.push(id);
    for (const d of edges.get(id) || []) {
      if (state.get(d) === 1) {
        report.error('E-06', m.entities.get(id).file, '/discovery', `ciclo de dependencias entre entidades: ${stack.slice(stack.indexOf(d)).concat(d).join(' -> ')}`);
      } else if (!state.has(d)) dfs(d);
    }
    stack.pop();
    state.set(id, 2);
  };
  for (const id of Array.from(edges.keys()).sort()) if (!state.has(id)) dfs(id);
}

// ----------------------------------------------------------------------------------------------- Editorial: bindings
function checkBindings(m, report) {
  const flavors = m.flavors ? m.flavors.flavors : {};
  const techOwners = new Map(); // `${flavor}|${kind}|${id}` -> binding file
  for (const [key, { file, doc: b }] of Array.from(m.bindings.entries()).sort((a, b2) => cmp(a[0], b2[0]))) {
    const e = m.entities.get(b.entity);
    if (!e) { report.error('E-09', file, '/entity', `la entidad «${b.entity}» no existe`); continue; }
    if (!flavors[b.flavor]) { report.error('E-09', file, '/flavor', `el flavor «${b.flavor}» no está en editorial/flavors.yaml`); continue; }
    if (!e.doc.applies_to.includes(b.flavor)) report.warn('E-09', file, '/flavor', `la entidad no aplica a «${b.flavor}» (applies_to): el binding se ignora`);
    (b.tech_refs || []).forEach((r, i) => { if (r.flavor !== b.flavor) report.error('E-09', file, `/tech_refs/${i}/flavor`, `el flavor del TechRef («${r.flavor}») no coincide con el del binding («${b.flavor}»)`); });
    (b.evidence || []).forEach((o, i) => { if (!m.observations.has(o)) report.error('E-09', file, `/evidence/${i}`, `la observación «${o}» no existe`); });
    (b.places || []).forEach((p, i) => {
      (p.evidence || []).forEach((o, j) => { if (!m.observations.has(o)) report.error('E-09', file, `/places/${i}/evidence/${j}`, `la observación «${o}» no existe`); });
      if (!flavors[b.flavor].locales.includes(p.locale)) report.error('E-09', file, `/places/${i}/locale`, `el idioma «${p.locale}» no está entre los de «${b.flavor}»`);
    });
    if (b.status !== 'accepted') continue;
    const isPlace = PLACE_TYPES.has(e.doc.type);
    if (isPlace && !b.places) report.error('E-09', file, '/places', `«${e.doc.type}» exige «places» en un binding accepted`);
    if (!isPlace && !b.tech_refs) report.error('E-09', file, '/tech_refs', `«${e.doc.type}» exige «tech_refs» en un binding accepted`);
    if (!isPlace && e.doc.type === 'npc') (b.tech_refs || []).forEach((r, i) => { if (r.kind !== 'creature') report.error('E-09', file, `/tech_refs/${i}/kind`, 'un npc se vincula a una criatura (kind «creature»)'); });
    // duplicate_binding: un TechRef en un solo binding accepted por flavor
    (b.tech_refs || []).forEach((r, i) => {
      const k = `${b.flavor}|${r.kind}|${r.id}`;
      if (techOwners.has(k)) report.error('E-09', file, `/tech_refs/${i}`, `duplicate_binding: el TechRef ${r.kind}:${r.id} ya está vinculado en ${techOwners.get(k)}`);
      else techOwners.set(k, file);
      // X-01: el TechRef debe existir en World Data
      if (!m.creatures.has(`${b.flavor}|${r.kind}|${r.id}`)) report.error('X-01', file, `/tech_refs/${i}`, `binding_unavailable: ${r.kind}:${r.id} no existe en World Data de «${b.flavor}»`);
    });
    // X-02: las cadenas de lugar deben estar respaldadas por World Data
    (b.places || []).forEach((p, i) => {
      const place = m.places.get(`${b.flavor}|${normalizeName(p.string)}`);
      const field = place && place.doc.texts[p.locale] && place.doc.texts[p.locale][p.api];
      if (!field) report.error('X-02', file, `/places/${i}`, `la cadena «${p.string}» (${p.locale}/${p.api}) no tiene respaldo en World Data de «${b.flavor}»`);
    });
  }
}

// ----------------------------------------------------------------------------------------------- Editorial: pistas
function namesOfTarget(m, targetId) {
  const names = new Set();
  for (const [locale, byId] of m.texts) {
    const t = byId.get(targetId);
    if (t && t.entry.title) names.add(t.entry.title);
  }
  for (const [, { doc: b }] of m.bindings) {
    if (b.entity !== targetId) continue;
    (b.places || []).forEach((p) => names.add(p.string));
    (b.tech_refs || []).forEach((r) => {
      const c = m.creatures.get(`${b.flavor}|${r.kind}|${r.id}`);
      if (c && c.doc.names) for (const f of Object.values(c.doc.names)) if (f.resolved.value) names.add(f.resolved.value);
    });
  }
  return Array.from(names).sort();
}

function checkHints(m, report) {
  const editorialLocale = m.flavors ? m.flavors.editorial_locale : null;
  const flavors = m.flavors ? m.flavors.flavors : {};
  for (const [id, { file, doc: h }] of Array.from(m.hints.entries()).sort((a, b) => cmp(a[0], b[0]))) {
    const target = m.entities.get(h.target);
    if (!target) report.error('E-08', file, '/target', `la entidad objetivo «${h.target}» no existe`);
    else if (h.status === 'published' && target.doc.status === 'retired') report.error('E-08', file, '/target', `una pista publicada no puede apuntar a «${h.target}», que está retirada`);
    (h.applies_to || []).forEach((f, i) => {
      if (!flavors[f]) report.error('E-08', file, `/applies_to/${i}`, `el flavor «${f}» no está en editorial/flavors.yaml`);
      else if (target && !target.doc.applies_to.includes(f)) report.warn('E-08', file, `/applies_to/${i}`, `la entidad objetivo no aplica a «${f}»`);
    });
    (h.related_to || []).forEach((r, i) => { if (!m.entities.has(r)) report.error('E-08', file, `/related_to/${i}`, `«${r}» no existe`); });
    (h.depends_on || []).forEach((d, i) => {
      if (!m.hints.has(d)) report.error('E-08', file, `/depends_on/${i}`, `la dependencia «${d}» no existe`);
      if (d === id) report.error('E-08', file, `/depends_on/${i}`, 'una pista no puede depender de sí misma');
    });
    const refs = requirementRefs(h.reveals_when);
    if (refs.hints.length > 0) report.error('E-08', file, '/reveals_when', '«hint_seen» no se admite en «reveals_when» (esquema inicial)');
    refs.places.forEach((p) => { if (!m.entities.has(p)) report.error('E-08', file, '/reveals_when', `place_discovered: «${p}» no existe`); });
    refs.entities.forEach((p) => { if (!m.entities.has(p)) report.error('E-08', file, '/reveals_when', `entity_discovered: «${p}» no existe`); });
    // texto de la pista
    const text = editorialLocale && m.texts.get(editorialLocale) && m.texts.get(editorialLocale).get(h.text);
    if (h.status === 'published' && !text) report.error('E-13', file, '/text', `falta el texto «${h.text}» en el idioma editorial ${editorialLocale}`);
    // lint: coordenadas y nombre de la entidad objetivo (en todos los idiomas con texto)
    const leakNames = target ? namesOfTarget(m, h.target) : [];
    for (const [locale, byId] of m.texts) {
      const t = byId.get(h.text);
      if (!t) continue;
      const body = Object.values(t.entry).join('\n');
      const coords = findCoordinates(body);
      if (coords.length) report.error('E-08', t.file, `/entries/${h.text}`, `lint de pista «${id}» (${locale}): contiene coordenadas o instrucciones tipo GPS (${coords.join(', ')})`);
      const leaks = findNameLeak(body, leakNames);
      if (leaks.length) report.error('E-08', t.file, `/entries/${h.text}`, `lint de pista «${id}» (${locale}): revela el nombre de la entidad objetivo (${leaks.join(', ')})`);
    }
  }
  // ciclos en depends_on (grafo global)
  const state = new Map();
  const stack = [];
  const dfs = (id) => {
    state.set(id, 1);
    stack.push(id);
    for (const d of (m.hintDocs.get(id).depends_on || []).filter((x) => m.hintDocs.has(x)).sort()) {
      if (state.get(d) === 1) report.error('E-08', m.hints.get(id).file, '/depends_on', `ciclo de dependencias entre pistas: ${stack.slice(stack.indexOf(d)).concat(d).join(' -> ')}`);
      else if (!state.has(d)) dfs(d);
    }
    stack.pop();
    state.set(id, 2);
  };
  for (const id of Array.from(m.hintDocs.keys()).sort()) if (!state.has(id)) dfs(id);

  // requires_hint: puerta de calidad editorial (Fase 16, 7.5; «auto» => true si importance = major)
  for (const [id, { file, doc: e }] of m.entities) {
    if (e.status !== 'published') continue;
    const required = e.requires_hint === true || ((e.requires_hint === undefined || e.requires_hint === 'auto') && e.importance === 'major');
    if (!required) continue;
    const has = Array.from(m.hintDocs.values()).some((h) => h.target === id && h.status === 'published');
    if (!has) report.error('E-07', file, '/requires_hint', `«${id}» exige al menos una pista publicada (requires_hint resuelto a true) y no tiene ninguna`);
  }
}

// ----------------------------------------------------------------------------------------------- Editorial: textos, decisiones, overrides
function checkTextsAndDecisions(m, report, worldConflicts) {
  for (const t of m.ds.editorial.texts) {
    for (const id of Object.keys(t.doc.entries)) {
      if (id.startsWith('hint:') ? !m.hints.has(id) : !m.entities.has(id)) report.error('E-13', t.file, `/entries/${id}`, `«${id}» no existe`);
    }
  }
  for (const d of m.ds.editorial.decisions) {
    if (d.doc.entity && !m.entities.has(d.doc.entity)) report.error('E-12', d.file, '/entity', `la entidad «${d.doc.entity}» no existe`);
  }
  // overrides sin conflicto asociado
  const ids = new Set(worldConflicts.map((c) => c.id));
  const keys = worldConflicts.map((c) => canonicalCompact({ subject: c.subject, field: c.field }));
  for (const o of m.ds.editorial.overrides) {
    const t = o.doc.target;
    const hit = t.conflict ? ids.has(t.conflict) : keys.includes(canonicalCompact({ subject: t.subject, field: t.field }));
    if (!hit) report.warn('W-OVERRIDE-ORPHAN', o.file, '/target', 'el override no corresponde a ningún conflicto actual (¿ya resuelto por las fuentes?)');
  }
}

// ----------------------------------------------------------------------------------------------- Candidate Data
function checkCandidates(m, report) {
  const signalIds = new Set(m.ds.candidates.signals.map((s) => s.doc.id));
  const profiles = new Map(m.ds.candidates.profiles.map((p) => [`${p.doc.id}@${p.doc.version}`, p.doc]));
  for (const p of m.ds.candidates.profiles) {
    p.doc.signals.forEach((s, i) => { if (!signalIds.has(s.id)) report.error('C-02', p.file, `/signals/${i}/id`, `la señal «${s.id}» no tiene definición en candidates/signals`); });
    p.doc.flavors.forEach((f, i) => { if (!m.flavors || !m.flavors.flavors[f]) report.error('C-02', p.file, `/flavors/${i}`, `el flavor «${f}» no está en editorial/flavors.yaml`); });
  }
  for (const { file, doc: c } of m.ds.candidates.records) {
    const prof = profiles.get(`${c.profile.id}@${c.profile.version}`);
    if (!prof) report.error('C-02', file, '/profile', `el perfil «${c.profile.id}» versión ${c.profile.version} no existe`);
    const sum = c.signals.reduce((a, s) => a + s.contribution, 0);
    if (Math.abs(sum - c.score.total) > 1e-9) report.error('C-01', file, '/score/total', `score.total (${c.score.total}) debe ser la suma de contribuciones (${sum})`);
    c.signals.forEach((s, i) => {
      if (Math.abs(s.weight * s.normalized - s.contribution) > 1e-9) report.error('C-01', file, `/signals/${i}/contribution`, `contribution (${s.contribution}) debe ser weight × normalized (${s.weight * s.normalized})`);
      if (prof && !prof.signals.some((x) => x.id === s.id)) report.error('C-02', file, `/signals/${i}/id`, `la señal «${s.id}» no está en el perfil`);
    });
    if (!m.creatures.has(`${c.subject.flavor}|${c.subject.kind}|${c.subject.id}`)) report.error('C-03', file, '/subject', `el sujeto ${c.subject.kind}:${c.subject.id} no existe en World Data de «${c.subject.flavor}»`);
  }
}

// ----------------------------------------------------------------------------------------------- transiciones respecto a una línea base
function checkBaseline(m, baselineDir, report) {
  const baseReport = new Report();
  const base = loadDataset(baselineDir, baseReport);
  const prev = new Map(base.editorial.entities.map((e) => [e.doc.id, e.doc.status]));
  for (const [id, { file, doc }] of m.entities) {
    if (prev.has(id) && !checkTransition(prev.get(id), doc.status)) {
      report.error('E-11', file, '/status', `transición no permitida «${prev.get(id)}» -> «${doc.status}»`);
    }
  }
  for (const [id, status] of prev) {
    if (!m.entities.has(id)) report.error('E-05', 'editorial/entities', '', `la entidad «${id}» (${status}) ha desaparecido: nunca se borra un ID, se marca «retired»`);
  }
}

// ----------------------------------------------------------------------------------------------- orquestación
function validateDataset(root, options = {}) {
  const report = new Report();
  const ds = loadDataset(root, report);
  const m = buildModel(ds, report);
  checkConfig(m, report);
  checkWorld(m, report);

  // La normalización de los registros crudos debe coincidir con lo versionado (W-06) y sus propios errores se informan aquí.
  const world = buildWorld(ds, report);
  for (const d of diffWorld(root, world.outputs)) report.error('W-06', d.file, '', d.why);

  checkEntities(m, report);
  checkDiscoveryCycles(m, report);
  checkBindings(m, report);
  checkHints(m, report);
  checkTextsAndDecisions(m, report, world.conflicts);
  checkCandidates(m, report);
  if (options.baselineDir) checkBaseline(m, path.resolve(options.baselineDir), report);

  return { report, ds, model: m, world };
}

module.exports = { validateDataset, namesOfTarget };
