'use strict';
// Herramientas de LECTURA del catálogo editorial (Fase 18): `data:queue` y `data:explain`. No escriben ningún fichero y no modifican el dataset.
//
// El score solo ORDENA la cola de revisión. Sin scoring el orden es técnico (por TechRef) y NO es una prioridad editorial.
const { cmp } = require('./report');
const { shipEntity } = require('./ship');
const { effectiveLinkStatus, linkIdFor, candidateSourceIds } = require('./links');
const { candidateId } = require('./candidates');

const NO_SCORING = 'sin scoring — orden técnico por TechRef';
const HYPOTHETICAL = 'evaluación técnica hipotética — no forma parte del Generated Pack';

const techKey = (r) => `${r.flavor}:${r.kind}:${r.id}`;
const sameRef = (x, y) => x.flavor === y.flavor && x.kind === y.kind && x.id === y.id;
const byTechRef = (a, b) => cmp(a.flavor, b.flavor) || cmp(a.kind, b.kind) || a.id - b.id;

function decisionOf(m, ref) {
  const hit = m.decisions.find((d) => sameRef(d.doc.subject, ref));
  return hit ? hit.doc : null;
}

function decisionReasons(d) {
  if (d.decision === 'accepted') return (d.inclusion_reasons || []).join(', ');
  if (d.decision === 'rejected') return (d.reject_reasons || []).join(', ');
  if (d.decision === 'deferred') return d.defer_reason;
  return '';
}

function decisionText(d) {
  if (!d) return '—';
  const r = decisionReasons(d);
  return `${d.decision}${r ? ` [${r}]` : ''} (policy_version ${d.policy_version})`;
}

// Entidades asociadas a un sujeto técnico: por decisión accepted (vínculo principal) y por Binding (referencias técnicas).
function entitiesFor(m, ref) {
  const out = new Map();
  const d = decisionOf(m, ref);
  if (d && d.decision === 'accepted' && m.entities.has(d.entity)) out.set(d.entity, 'decisión accepted');
  for (const { doc: b } of m.bindings.values()) {
    if (!(b.tech_refs || []).some((r) => sameRef(r, ref))) continue;
    if (!m.entities.has(b.entity)) continue;
    out.set(b.entity, out.has(b.entity) ? `${out.get(b.entity)} + binding` : 'binding');
  }
  return Array.from(out.entries()).sort((a, b) => cmp(a[0], b[0])).map(([id, via]) => ({ id, via, doc: m.entityDocs.get(id) }));
}

function entityText(e) {
  const ed = e.doc.editorial || {};
  return `${e.id} (origin: ${ed.origin || '—'}, status: ${e.doc.status}; vía ${e.via})`;
}

function profileOf(m, c) {
  if (!c.profile) return null;
  const p = m.candidateProfiles.get(`${c.profile.id}@${c.profile.version}`);
  return p ? p.doc : null;
}

const approvalLabel = (p) => (p ? ({ illustrative: 'ILUSTRATIVO — NO APROBADO', proposed: 'PROPUESTA — pendiente de aprobación', approved: 'APROBADO' }[p.approval] || p.approval) : 'perfil no encontrado');

// ----------------------------------------------------------------------------------------------- data:queue
function queueLines(result, options = {}) {
  const m = result.model;
  const label = options.label || '.';
  const lines = [];
  const all = Array.from(m.candidates.values()).map((x) => x.doc).filter((c) => !options.flavor || c.flavor === options.flavor);
  const isPending = (c) => {
    const d = decisionOf(m, c.subject);
    return !d || d.decision === 'shortlisted' || d.decision === 'deferred';
  };
  const shown = options.all ? all : all.filter(isPending);

  lines.push(`data:queue — dataset «${label}» (solo lectura: no escribe ningún fichero)`);
  lines.push(`Candidatos: ${shown.length} ${options.all ? 'en total' : 'pendientes de revisión'} (${all.length} en el dataset; ${all.length - all.filter(isPending).length} con decisión final)`);
  if (result.report.hasErrors()) lines.push(`AVISO: el dataset tiene ${result.report.errors.length} error(es) de validación; ejecute data:validate`);

  const line = (c, withRank) => {
    const dec = decisionOf(m, c.subject);
    const ents = entitiesFor(m, c.subject);
    const bootstrap = ents.some((e) => e.doc.editorial && e.doc.editorial.origin === 'bootstrap');
    const parts = [`  ${withRank && c.rank ? `#${c.rank} ` : ''}${c.id}`, `flavor=${c.flavor}`, `TechRef=${techKey(c.subject)}`];
    if (c.score) parts.push(`score=${c.score.total}`);
    parts.push(`decisión=${decisionText(dec)}`);
    parts.push(`entidad=${ents.length ? ents.map(entityText).join('; ') : '—'}`);
    if (bootstrap) parts.push('[bootstrap_entity: pendiente de revisión editorial]');
    return parts.join('  ');
  };

  const scored = shown.filter((c) => c.profile && c.score && c.rank);
  const unscored = shown.filter((c) => !scored.includes(c));
  const groups = new Map();
  for (const c of scored) {
    const k = `${c.profile.id}@${c.profile.version}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(c);
  }
  for (const k of Array.from(groups.keys()).sort(cmp)) {
    const list = groups.get(k).sort((a, b) => a.rank - b.rank || cmp(a.id, b.id));
    lines.push('');
    lines.push(`== Con scoring: perfil «${k}» [${approvalLabel(profileOf(m, list[0]))}] — orden por rank ==`);
    lines.push('   (el score ORDENA la revisión; no acepta, rechaza ni publica nada)');
    for (const c of list) lines.push(line(c, true));
  }
  if (unscored.length || groups.size === 0) {
    lines.push('');
    lines.push(`== ${NO_SCORING} ==`);
    lines.push('   (este orden NO es una prioridad editorial: solo ordena por referencia técnica)');
    for (const c of unscored.sort((a, b) => byTechRef(a.subject, b.subject))) lines.push(line(c, false));
    if (unscored.length === 0) lines.push('  (ningún candidato)');
  }
  return lines;
}

// ----------------------------------------------------------------------------------------------- data:explain
function fieldSummary(path, field) {
  const claims = (field.claims || []).map((c) => `${c.provenance.source} (${c.confidence})`).join(', ');
  const r = field.resolved;
  const value = r.status === 'conflict' ? `CONFLICTO (${r.conflict})` : JSON.stringify(r.value);
  return `${path} = ${value}  [${r.status}/${r.rule}]  ← ${claims}`;
}

function worldLines(doc, file, allowed) {
  const out = [];
  out.push(`World Data: ${file}`);
  const add = (path, field) => {
    const research = (field.claims || []).every((c) => !allowed.has(c.provenance.source));
    out.push(`    ${fieldSummary(path, field)}${research ? '  [solo investigación: ninguna fuente con candidate_generation]' : ''}`);
  };
  if (doc.exists) add('exists', doc.exists);
  for (const g of ['names', 'subnames', 'attributes', 'relations']) for (const k of Object.keys(doc[g] || {}).sort(cmp)) add(`${g}.${k}`, doc[g][k]);
  for (const k of ['spawns', 'places']) if (doc[k]) add(k, doc[k]);
  return out;
}

function sourceIdsOf(doc) {
  const ids = new Set();
  const visit = (v) => {
    if (Array.isArray(v)) return v.forEach(visit);
    if (!v || typeof v !== 'object') return;
    if (v.provenance && v.provenance.source) ids.add(v.provenance.source);
    Object.values(v).forEach(visit);
  };
  visit(doc);
  return Array.from(ids).sort(cmp);
}

function candidateBlock(m, c, allowedSources, lines, implicated) {
  const ref = c.subject;
  const creature = m.creatures.get(`${ref.flavor}|${ref.kind}|${ref.id}`);
  lines.push(`[1] Candidate ${c.id}  (sujeto ${techKey(ref)}; un Candidate NO es un TechRef ni una Entity)`);
  if (creature) worldLines(creature.doc, creature.file, allowedSources).forEach((l, i) => lines.push(i === 0 ? `[2] ${l}` : l));
  else lines.push('[2] World Data: (no encontrado)');

  const srcIds = creature ? sourceIdsOf(creature.doc) : [];
  srcIds.forEach((s) => implicated.add(s));
  lines.push('[3] Fuentes con datos sobre este sujeto:');
  for (const id of srcIds) {
    const s = m.sourcesById.get(id);
    if (!s) { lines.push(`    ${id}: SIN MANIFIESTO`); continue; }
    lines.push(`    ${id}  status=${s.status}  research=${s.usage.research}  candidate_generation=${s.usage.candidate_generation}  generated_data=${s.usage.generated_data}`);
  }
  lines.push(`[4] candidate_generation: origina este candidato → ${c.sources.map((s) => s.source).join(', ') || '—'}; el resto de fuentes solo aporta investigación`);

  const es = c.evidence_summary;
  lines.push(`[5] Evidencias: orígenes independientes=${es.independent_origins}  client_verified=${es.client_verified}  conflictos abiertos=${es.open_conflicts}`);
  for (const lid of c.links || []) {
    const link = m.ds.world.links.find((l) => l.doc.id === lid);
    if (!link) { lines.push(`    enlace ${lid}: no encontrado`); continue; }
    const dec = m.linkDecisions.find((x) => linkIdFor(x.doc.a, x.doc.b) === lid);
    const eff = effectiveLinkStatus(link.doc, dec && dec.doc);
    lines.push(`    enlace ${lid} (${link.doc.relation}) ${techKey(link.doc.a)} ↔ ${techKey(link.doc.b)}: propuesta=${link.doc.status}; efectivo=${eff.status}${eff.stale ? ' (decisión desfasada)' : ''}${dec ? ` [decisión humana: ${dec.doc.decision}]` : ''}; evidencia: ${link.doc.evidence.map((e) => `${e.kind}=${e.value}`).join('; ')}`);
    lines.push('      (matched NO significa inclusión editorial)');
  }
  const conflicts = m.conflicts.filter((x) => sameRef(x.subject, ref));
  lines.push(`[6] Conflictos: ${conflicts.length ? conflicts.map((x) => `${x.id} ${x.field} (${x.status})`).join('; ') : 'ninguno'}`);
  lines.push(`[7] Investigación: status=${c.research.status}; lagunas de datos: ${(c.data_gaps || []).join(', ') || 'ninguna'}`);
  const prof = profileOf(m, c);
  lines.push(c.profile ? `[8] Score: ${c.score.total} (rank ${c.rank}) con el perfil «${c.profile.id}» v${c.profile.version} [${approvalLabel(prof)}]` : '[8] Score: sin scoring (candidato sin puntuar)');
  const d = decisionOf(m, ref);
  lines.push(`[9] CandidateDecision: ${d ? `${d.decision} (por ${d.by}, ${d.at})` : 'ninguna (pendiente de revisión editorial)'}`);
  lines.push(`[10] Motivos: ${d ? decisionReasons(d) || '—' : '—'}`);
  lines.push(`[11] policy_version: ${d ? d.policy_version : '—'}`);
}

function shipLines(m, entity, lines) {
  const e = entity.doc;
  {
    for (const f of e.applies_to) {
      const cfg = m.flavors && m.flavors.flavors[f];
      if (!cfg) { lines.push(`    ${f}: flavor no configurado`); continue; }
      let res;
      try {
        res = shipEntity(m, e, f);
      } catch (err) {
        lines.push(`    ${f}: no evaluable (${err.message})`);
        continue;
      }
      const official = e.status === 'published' && cfg.enabled;
      const tag = official ? 'ship-report (evaluación del generador)' : HYPOTHETICAL;
      lines.push(`    ${f}: ${tag}`);
      lines.push(`      resultado: ${res.available ? 'available' : res.reasons.join(', ')}`);
      for (const dd of res.details) lines.push(`      · ${dd.datum}: ${dd.blocked_because} (claims de: ${dd.claims_from.join(', ')})`);
      if (res.available) lines.push(`      autorizada por: ${res.authorized_by.join(', ') || '—'}`);
    }
  }
}

function explainLines(result, id, options = {}) {
  const m = result.model;
  const lines = [];
  const allowedSources = candidateSourceIds(m.sourcesById);
  lines.push(`data:explain ${id} — dataset «${options.label || '.'}» (solo lectura: no escribe ningún fichero)`);
  if (result.report.hasErrors()) lines.push(`AVISO: el dataset tiene ${result.report.errors.length} error(es) de validación; ejecute data:validate`);

  const implicated = new Set();
  let candidates = [];
  let entities = [];

  if (id.startsWith('cand:')) {
    const c = m.candidates.get(id);
    if (!c) { lines.push(`No existe el candidato «${id}».`); return { lines, found: false }; }
    candidates = [c.doc];
    entities = entitiesFor(m, c.doc.subject);
  } else if (id.startsWith('link:')) {
    const link = m.ds.world.links.find((l) => l.doc.id === id);
    if (!link) { lines.push(`No existe el enlace «${id}» (puede haber sido rechazado o ya no tener evidencia).`); return { lines, found: false }; }
    const dec = m.linkDecisions.find((x) => linkIdFor(x.doc.a, x.doc.b) === id);
    const eff = effectiveLinkStatus(link.doc, dec && dec.doc);
    lines.push(`Enlace ${id} (${link.doc.relation}): ${techKey(link.doc.a)} ↔ ${techKey(link.doc.b)}`);
    lines.push(`  propuesta de la máquina: ${link.doc.status}; estado efectivo: ${eff.status}${eff.stale ? ' (decisión desfasada)' : ''}`);
    link.doc.evidence.forEach((e) => lines.push(`  evidencia ${e.kind} = ${e.value}  (fuentes: ${e.sources.join(', ')})`));
    lines.push(dec ? `  decisión humana: ${dec.doc.decision} por ${dec.doc.by} (${dec.doc.at}): ${dec.doc.reason}` : '  decisión humana: ninguna');
    lines.push('  (matched NO significa inclusión editorial: un enlace nunca crea una Entity)');
    return { lines, found: true };
  } else if (m.entities.has(id)) {
    const e = { id, doc: m.entityDocs.get(id), via: 'consulta' };
    entities = [e];
    const refs = new Map();
    for (const d of m.decisions) if (d.doc.decision === 'accepted' && d.doc.entity === id) refs.set(techKey(d.doc.subject), d.doc.subject);
    for (const { doc: b } of m.bindings.values()) if (b.entity === id) (b.tech_refs || []).forEach((r) => refs.set(techKey(r), r));
    for (const r of Array.from(refs.values()).sort(byTechRef)) {
      const c = m.candidates.get(candidateId(r));
      if (c) candidates.push(c.doc);
    }
  } else {
    lines.push(`No existe «${id}» como entidad, candidato ni enlace.`);
    return { lines, found: false };
  }

  lines.push('');
  lines.push(`=== Candidatos relacionados: ${candidates.length} ===`);
  if (candidates.length === 0) lines.push('[1]–[11] Sin candidato: no hay Candidate Data asociado (el catálogo editorial no depende de él para existir).');
  for (const c of candidates.sort((a, b) => byTechRef(a.subject, b.subject))) {
    candidateBlock(m, c, allowedSources, lines, implicated);
    lines.push('');
  }

  lines.push(`=== Entidad: ${entities.length ? entities.length : 'ninguna'} ===`);
  if (entities.length === 0) lines.push('[12]–[16] Ninguna Entity asociada: el candidato aún no ha dado lugar a una entidad editorial (la crea una persona tras una decisión accepted).');
  for (const e of entities) {
    const ed = e.doc.editorial || {};
    lines.push(`[12] Entity ${e.id} (tipo ${e.doc.type}; asociada vía ${e.via})`);
    lines.push(`[13] Entity.editorial.origin: ${ed.origin || '(sin origin)'}`);
    lines.push(`[14] Entity.status (dimensión EDITORIAL): ${e.doc.status}   (published ≠ generated: ver [16])`);
    lines.push('[15] Binding por flavor:');
    const bs = Array.from(m.bindings.values()).filter((b) => b.doc.entity === e.id).sort((a, b) => cmp(a.doc.flavor, b.doc.flavor));
    if (bs.length === 0) lines.push('    ninguno');
    for (const b of bs) lines.push(`    ${b.doc.flavor}: ${b.doc.status}${(b.doc.tech_refs || []).length ? ` → ${b.doc.tech_refs.map(techKey).join(', ')}` : ''}${b.doc.places ? ` → ${b.doc.places.length} cadena(s) de lugar` : ''} (un Binding no autoriza datos)`);
    lines.push('[16] Estado técnico (dimensión TÉCNICA, árbitro: ship):');
    if (e.doc.status === 'retired') lines.push('    retirada: el pack la conserva como lápida; no se evalúa');
    else shipLines(m, e, lines);
    for (const b of bs) for (const s of sourceIdsOf(b.doc)) implicated.add(s);
    lines.push('');
  }
  lines.push(`[17] Fuentes implicadas: ${Array.from(implicated).sort(cmp).join(', ') || '—'}`);
  return { lines, found: true };
}

module.exports = { queueLines, explainLines, entitiesFor, decisionOf, NO_SCORING, HYPOTHETICAL };
