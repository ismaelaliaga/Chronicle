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
const { REJECT_REASONS, TECHNICAL_SHIP_REASONS } = require('./rules');
const { linkIdFor, refKey, candidateSourceIds } = require('./links');
const { buildCandidates, candidateId } = require('./candidates');

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

    // D-08 (regla EDITORIAL, no técnica): una entidad creada por la infraestructura bootstrap no ha sido revisada editorialmente
    if (e.editorial && e.editorial.origin === 'bootstrap' && (e.status === 'review' || e.status === 'published')) {
      report.error('D-08', file, '/status', `una entidad con editorial.origin «bootstrap» no puede estar en «${e.status}»: nació de la infraestructura y no hay decisión editorial de incluirla (resuélvase con una CandidateDecision accepted o retírese)`);
    }

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

// ----------------------------------------------------------------------------------------------- Catálogo editorial (Fase 18): decisiones, origen y enlaces
// Solo lee capas editoriales y World Data (NO Candidate Data): también se ejecuta al generar el pack.
function checkCatalog(m, report, world) {
  const entities = Array.from(m.entities.entries()).sort((a, b) => cmp(a[0], b[0]));
  const subjectKey = (r) => `${r.flavor}|${r.kind}|${r.id}`;
  const decisions = m.decisions.slice().sort((a, b) => cmp(a.file, b.file));
  const technical = new Set(TECHNICAL_SHIP_REASONS);
  const approved = new Set(REJECT_REASONS);

  // por sujeto: una sola decisión (el historial append-only queda fuera de alcance)
  const bySubject = new Map();
  for (const d of decisions) {
    const k = subjectKey(d.doc.subject);
    if (bySubject.has(k)) report.error('D-09', d.file, '/subject', `ya hay una decisión para ${d.doc.subject.kind}:${d.doc.subject.id} de «${d.doc.subject.flavor}» (${bySubject.get(k).file}); solo se admite una decisión vigente por sujeto`);
    else bySubject.set(k, d);
  }

  for (const d of decisions) {
    const { file, doc } = d;
    if (!m.creatures.has(subjectKey(doc.subject))) report.error('D-10', file, '/subject', `el sujeto ${doc.subject.kind}:${doc.subject.id} no existe en World Data de «${doc.subject.flavor}»`);
    if (doc.subject.kind !== 'creature') report.error('D-10', file, '/subject/kind', 'una decisión sobre un NPC se toma sobre una criatura (kind «creature»)');

    // D-04: los motivos de rechazo son EDITORIALES; los motivos técnicos del ship-report nunca lo son
    (doc.reject_reasons || []).forEach((r, i) => {
      if (technical.has(r)) report.error('D-04', file, `/reject_reasons/${i}`, `«${r}» es un motivo técnico del ship-report: la falta de datos o la imposibilidad técnica de publicar NO es un motivo editorial de rechazo (use deferred, o no decida)`);
      else if (!approved.has(r)) report.error('D-04', file, `/reject_reasons/${i}`, `«${r}» no es un motivo de rechazo aprobado (${REJECT_REASONS.join(', ')})`);
    });
    if (doc.duplicate_of) {
      if (!(doc.reject_reasons || []).includes('duplicate_of')) report.error('D-04', file, '/duplicate_of', '«duplicate_of» solo se admite con el motivo de rechazo «duplicate_of»');
      if (refKey(doc.duplicate_of) === refKey(doc.subject)) report.error('D-04', file, '/duplicate_of', 'una referencia no puede ser duplicada de sí misma');
      else if (!m.creatures.has(subjectKey(doc.duplicate_of))) report.error('D-04', file, '/duplicate_of', `${doc.duplicate_of.kind}:${doc.duplicate_of.id} no existe en World Data de «${doc.duplicate_of.flavor}»`);
    }

    if (doc.decision !== 'accepted') continue;
    const target = m.entities.get(doc.entity);
    if (!target) { report.error('E-12', file, '/entity', `la entidad «${doc.entity}» no existe`); continue; }
    // D-03: la decisión accepted apunta a una Entity existente con origin candidate, y su flavor está en applies_to
    const origin = target.doc.editorial && target.doc.editorial.origin;
    if (origin !== 'candidate') report.error('D-03', file, '/entity', `«${doc.entity}» tiene editorial.origin «${origin || '(sin origin)'}»: una decisión accepted solo da lugar a entidades con origin «candidate»`);
    if (!target.doc.applies_to.includes(doc.subject.flavor)) report.error('D-03', file, '/subject/flavor', `el flavor «${doc.subject.flavor}» de la decisión no está en applies_to de «${doc.entity}»`);
  }

  // D-05: un mismo TechRef no puede estar accepted hacia dos Entities
  const acceptedBySubject = new Map();
  for (const d of decisions.filter((x) => x.doc.decision === 'accepted')) {
    const k = subjectKey(d.doc.subject);
    if (!acceptedBySubject.has(k)) acceptedBySubject.set(k, new Map());
    acceptedBySubject.get(k).set(d.doc.entity, d.file);
  }
  for (const [k, ents] of Array.from(acceptedBySubject.entries()).sort((a, b) => cmp(a[0], b[0]))) {
    if (ents.size > 1) {
      const list = Array.from(ents.keys()).sort(cmp);
      report.error('D-05', ents.get(list[1]), '/entity', `el TechRef ${k.split('|').slice(1).join(':')} de «${k.split('|')[0]}» está accepted hacia ${list.length} entidades distintas (${list.join(', ')})`);
    }
  }

  // D-01 (origin candidate => decisión accepted) y D-06 (el binding coincide con alguna decisión; solo AVISO)
  for (const [id, { file, doc: e }] of entities) {
    if (!(e.editorial && e.editorial.origin === 'candidate')) continue;
    const mine = decisions.filter((x) => x.doc.decision === 'accepted' && x.doc.entity === id);
    if (mine.length === 0) {
      report.error('D-01', file, '/editorial/origin', `«${id}» tiene origin «candidate» pero no existe ninguna CandidateDecision accepted que apunte a ella`);
      continue;
    }
    for (const [, { file: bfile, doc: b }] of m.bindings) {
      if (b.entity !== id || b.status !== 'accepted' || !b.tech_refs) continue;
      const hit = b.tech_refs.some((r) => mine.some((x) => refKey(x.doc.subject) === refKey(r)));
      if (!hit) report.warn('D-06', bfile, '/tech_refs', `ningún TechRef del binding coincide con el sujeto de las decisiones accepted de «${id}» (${mine.map((x) => refKey(x.doc.subject)).join(', ')})`);
    }
  }

  // decisiones de reconciliación (humanas)
  const links = new Map((world.links || []).map((l) => [l.id, l]));
  const seen = new Map();
  for (const { file, doc } of m.linkDecisions.slice().sort((a, b) => cmp(a.file, b.file))) {
    const id = linkIdFor(doc.a, doc.b);
    if (refKey(doc.a) > refKey(doc.b)) report.error('L-03', file, '/a', 'a y b deben ir en orden canónico (a < b por flavor:kind:id)');
    if (refKey(doc.a) === refKey(doc.b)) report.error('L-03', file, '/b', 'a y b no pueden ser la misma referencia');
    for (const side of ['a', 'b']) {
      if (doc[side].kind !== 'creature') report.error('L-02', file, `/${side}/kind`, 'se reconcilian criaturas (kind «creature»)');
      else if (!m.creatures.has(subjectKey(doc[side]))) report.error('L-02', file, `/${side}`, `${doc[side].kind}:${doc[side].id} no existe en World Data de «${doc[side].flavor}»`);
    }
    if (seen.has(id)) report.error('L-06', file, '', `ya hay una decisión para este enlace (${seen.get(id)})`);
    else seen.set(id, file);
    if (doc.decision === 'confirm') {
      const link = links.get(id);
      if (!link) report.warn('L-05', file, '', 'la confirmación no corresponde a ningún enlace propuesto actualmente (la evidencia ya no existe)');
      else if (link.fingerprint !== doc.evidence_fingerprint) report.warn('L-04', file, '/evidence_fingerprint', 'decisión desfasada: la evidencia del enlace cambió desde que se confirmó; la confirmación NO se aplica hasta revisarla');
    }
  }
}

// ----------------------------------------------------------------------------------------------- Candidate Data
// Candidate Data es una capa de PREPARACIÓN editorial: el generador del pack no la lee ni depende de que sea válida.
function checkCandidates(m, report, world) {
  const signalIds = new Set(m.ds.candidates.signals.map((s) => s.doc.id));
  const profiles = new Map(Array.from(m.candidateProfiles.entries()).map(([k, v]) => [k, v.doc]));
  for (const p of m.ds.candidates.profiles) {
    p.doc.signals.forEach((s, i) => { if (!signalIds.has(s.id)) report.error('C-02', p.file, `/signals/${i}/id`, `la señal «${s.id}» no tiene definición en candidates/signals`); });
    p.doc.flavors.forEach((f, i) => { if (!m.flavors || !m.flavors.flavors[f]) report.error('C-02', p.file, `/flavors/${i}`, `el flavor «${f}» no está en editorial/flavors.yaml`); });
    // C-05: no existe todavía ningún mecanismo de aprobación; ningún perfil puede declararse «approved»
    if (p.doc.approval === 'approved') report.error('C-05', p.file, '/approval', 'ningún perfil de scoring puede ser «approved» todavía (no hay calibración ni política aprobada); use «illustrative» o «proposed»');
  }

  const allowed = candidateSourceIds(m.sourcesById);
  const scoredIds = new Set();
  for (const { file, doc: c } of m.ds.candidates.records) {
    if (c.profile) {
      scoredIds.add(c.id);
      const prof = profiles.get(`${c.profile.id}@${c.profile.version}`);
      if (!prof) report.error('C-02', file, '/profile', `el perfil «${c.profile.id}» versión ${c.profile.version} no existe`);
      const sum = c.signals.reduce((a, s) => a + s.contribution, 0);
      if (Math.abs(sum - c.score.total) > 1e-9) report.error('C-01', file, '/score/total', `score.total (${c.score.total}) debe ser la suma de contribuciones (${sum})`);
      c.signals.forEach((s, i) => {
        if (Math.abs(s.weight * s.normalized - s.contribution) > 1e-9) report.error('C-01', file, `/signals/${i}/contribution`, `contribution (${s.contribution}) debe ser weight × normalized (${s.weight * s.normalized})`);
        if (prof && !prof.signals.some((x) => x.id === s.id)) report.error('C-02', file, `/signals/${i}/id`, `la señal «${s.id}» no está en el perfil`);
      });
    }
    if (c.id !== candidateId(c.subject)) report.error('C-03', file, '/id', `el id debe derivarse del sujeto: «${candidateId(c.subject)}»`);
    if (c.flavor !== c.subject.flavor) report.error('C-03', file, '/flavor', 'el flavor del candidato debe coincidir con el de su sujeto');
    if (!m.creatures.has(`${c.subject.flavor}|${c.subject.kind}|${c.subject.id}`)) report.error('C-03', file, '/subject', `el sujeto ${c.subject.kind}:${c.subject.id} no existe en World Data de «${c.subject.flavor}»`);
    // D-02: solo las fuentes con usage.candidate_generation = true pueden originar un candidato
    c.sources.forEach((s, i) => {
      const src = m.sourcesById.get(s.source);
      if (!src) report.error('D-02', file, `/sources/${i}/source`, `la fuente «${s.source}» no tiene manifiesto`);
      else if (!allowed.has(s.source)) report.error('D-02', file, `/sources/${i}/source`, `la fuente «${s.source}» no tiene usage.candidate_generation = true: no puede originar candidatos (sus datos solo sirven como investigación)`);
      else if (src.origin_group !== s.origin_group) report.error('D-02', file, `/sources/${i}/origin_group`, `origin_group «${s.origin_group}» no coincide con el de la fuente («${src.origin_group}»)`);
    });
    (c.links || []).forEach((l, i) => { if (!(world.links || []).some((x) => x.id === l)) report.error('L-07', file, `/links/${i}`, `el enlace «${l}» no existe entre los enlaces propuestos actuales`); });
  }

  // C-04: los candidatos SIN PUNTUAR los produce la máquina: deben coincidir con lo que se regenera (los puntuados son entrada y no se reescriben)
  const generated = buildCandidates({ creatureDocs: world.creatureDocs, conflicts: world.conflicts, sourcesById: m.sourcesById, links: world.links, scoredIds });
  const genById = new Map(generated.map((g) => [g.id, g]));
  for (const g of generated) {
    const rec = m.candidates.get(g.id);
    if (!rec) report.error('C-04', `candidates/records/${g.id.replace(/:/g, '__')}.json`, '', 'falta el candidato (ejecute data:candidates)');
    else if (canonicalCompact(rec.doc) !== canonicalCompact(g)) report.error('C-04', rec.file, '', 'no coincide con lo que regenera data:candidates (ejecute data:candidates)');
  }
  for (const { file, doc: c } of m.ds.candidates.records) {
    if (!c.profile && !genById.has(c.id)) report.error('C-04', file, '', 'fichero sobrante: ninguna fuente con candidate_generation lo respalda (ejecute data:candidates)');
  }

  // D-07 / D-11: la decisión se compara con el candidato ACTUAL (los candidatos se regeneran; la decisión histórica no se invalida)
  for (const { file, doc: d } of m.decisions.slice().sort((a, b) => cmp(a.file, b.file))) {
    const cand = m.candidates.get(candidateId(d.subject));
    if (!cand) report.warn('D-11', file, '/subject', `no existe un candidato actual para ${d.subject.kind}:${d.subject.id} de «${d.subject.flavor}»`);
    else if (cand.doc.inputs_fingerprint !== d.evidence_fingerprint) report.warn('D-07', file, '/evidence_fingerprint', 'la evidencia del candidato ha cambiado desde que se tomó la decisión (la decisión sigue vigente; revísela si procede)');
  }
}

// ----------------------------------------------------------------------------------------------- transiciones respecto a una línea base
function checkBaseline(m, baselineDir, report) {
  const baseReport = new Report();
  const base = loadDataset(baselineDir, baseReport, { skipCandidates: true });
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
// options.scope = 'publish': validación para GENERAR el pack. No carga ni valida Candidate Data (el generador no depende de ella).
function validateDataset(root, options = {}) {
  const report = new Report();
  const publishScope = options.scope === 'publish';
  const ds = loadDataset(root, report, { skipCandidates: publishScope });
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
  checkCatalog(m, report, world);
  if (!publishScope) checkCandidates(m, report, world);
  if (options.baselineDir) checkBaseline(m, path.resolve(options.baselineDir), report);

  return { report, ds, model: m, world };
}

module.exports = { validateDataset, namesOfTarget };
