'use strict';
// Condiciones de publicación por (entidad, versión) (Fase 16, 9.2). `available` es una CONCLUSIÓN derivada, nunca un campo escrito a mano.
//
//   1. la entidad está published (las retired van como lápida)       5. capacidades requeridas soportadas por el perfil de cliente
//   2. la versión está en applies_to                                  6. procedencia AUTORIZADA de todo dato técnico necesario
//   3. hay un Binding accepted (o la entidad no necesita datos técnicos)  7. ningún conflicto bloqueante abierto
//   4. cada TechRef existe en World Data de esa versión
const { checkField } = require('./eligibility');
const {
  PLACE_TYPES, materializeRules, interactionTypes, walkRequirement, normalizeName,
} = require('./rules');

const REASON_ORDER = [
  'not_applicable', 'no_binding', 'entity_absent', 'tech_ref_missing', 'blocked_by_conflict',
  'source_not_authorized_for_pack', 'capability_unavailable', 'capability_unverified',
];

function reasonRank(r) {
  const i = REASON_ORDER.indexOf(r.split(':')[0]);
  return i < 0 ? 99 : i;
}

function sortReasons(list) {
  return Array.from(new Set(list)).sort((a, b) => reasonRank(a) - reasonRank(b) || (a < b ? -1 : a > b ? 1 : 0));
}

function placeApis(model, entityId, flavor) {
  const b = model.bindings.get(`${entityId}|${flavor}`);
  if (!b || b.doc.status !== 'accepted' || !b.doc.places) return [];
  return Array.from(new Set(b.doc.places.map((p) => p.api))).sort();
}

// Capacidades LÓGICAS que necesita una entidad en una versión (Fase 16, 7.4). No son eventos del cliente.
function requiredCapabilities(model, entity, flavor, rules) {
  const caps = new Set();
  if (rules.method === 'interaction') for (const t of interactionTypes(rules.interaction)) caps.add(`interaction.${t}`);
  if (rules.method === 'place_enter') for (const api of placeApis(model, entity.id, flavor)) caps.add(`place.${api}`);
  walkRequirement(rules.requirements, (r) => {
    if (r.place_discovered) for (const api of placeApis(model, r.place_discovered.id, flavor)) caps.add(`place.${api}`);
  });
  return Array.from(caps).sort();
}

function shipEntity(model, entity, flavor) {
  const res = {
    entity: entity.id, flavor, available: false, reasons: [], details: [], omitted_optional: [], warnings: [], authorized_by: [],
    tech: [], attributes: {}, placeNames: [], rules: null, required_capabilities: [],
  };
  const reasons = [];
  const warnings = [];
  const authorizedBy = new Set();
  const blockedKeys = []; // sujetos del mundo que respaldan esta entidad (para la condición 7)

  if (!entity.applies_to.includes(flavor)) {
    res.reasons = ['not_applicable'];
    return res;
  }
  const mat = materializeRules(entity, flavor, model.entityDocs);
  if (!mat.rules) throw new Error(`reglas de descubrimiento no materializables para ${entity.id} (${mat.error}); data:validate debe haberlo detectado`);
  const rules = mat.rules;
  res.rules = rules;
  const needsTech = rules.method !== 'none';

  if (needsTech) {
    const binding = model.bindings.get(`${entity.id}|${flavor}`);
    const accepted = binding && binding.doc.status === 'accepted';
    if (!binding || ['proposed', 'rejected', 'superseded'].includes(binding.doc.status)) {
      reasons.push('no_binding');
    } else if (binding.doc.status === 'unavailable') {
      reasons.push('entity_absent');
    } else if (accepted) {
      const b = binding.doc;
      if (PLACE_TYPES.has(entity.type)) {
        if (!b.places) reasons.push('no_binding');
        for (const p of b.places || []) {
          const key = normalizeName(p.string);
          const place = model.places.get(`${flavor}|${key}`);
          const field = place && place.doc.texts[p.locale] && place.doc.texts[p.locale][p.api];
          if (!field) { reasons.push(`tech_ref_missing:place.${p.api}`); continue; }
          blockedKeys.push({ kind: 'name_only', key });
          if (field.resolved.value !== p.string) {
            if (field.resolved.status === 'conflict') continue; // se informa como conflicto
            reasons.push(`tech_ref_missing:place.${p.api}`);
            continue;
          }
          const el = checkField(field, model.sourcesById, model.authorized);
          if (el.eligible) {
            el.supportedBy.forEach((s) => authorizedBy.add(s));
            res.placeNames.push({ locale: p.locale, api: p.api, string: p.string, key });
          } else {
            reasons.push('source_not_authorized_for_pack');
            res.details.push({ datum: `texts.${p.locale}.${p.api}`, claims_from: el.blocked.map((x) => x.source), blocked_because: el.blocked.map((x) => x.why).join('; ') || 'sin afirmaciones autorizadas' });
          }
        }
      } else {
        if (!b.tech_refs) reasons.push('no_binding');
        (b.tech_refs || []).forEach((ref, i) => {
          const creature = model.creatures.get(`${flavor}|${ref.kind}|${ref.id}`);
          if (!creature) { reasons.push(`tech_ref_missing:${ref.kind}.${ref.id}`); return; }
          blockedKeys.push({ kind: ref.kind, id: ref.id });
          const exists = creature.doc.exists;
          if (exists.resolved.status === 'conflict') return; // se informa como conflicto
          if (exists.resolved.value === 'absent') { reasons.push('entity_absent'); return; }
          if (exists.resolved.value !== 'present') { reasons.push(`tech_ref_missing:${ref.kind}.${ref.id}`); return; }
          const el = checkField(exists, model.sourcesById, model.authorized);
          if (el.eligible) {
            el.supportedBy.forEach((s) => authorizedBy.add(s));
          } else {
            reasons.push('source_not_authorized_for_pack');
            res.details.push({ datum: 'exists', claims_from: el.blocked.map((x) => x.source), blocked_because: el.blocked.map((x) => x.why).join('; ') || 'sin afirmaciones autorizadas' });
          }
          // Atributos opcionales: solo el del primer TechRef (el principal). Un atributo no elegible se omite SIN bloquear.
          if (i === 0 && creature.doc.attributes && creature.doc.attributes.display_id) {
            const f = creature.doc.attributes.display_id;
            const ea = checkField(f, model.sourcesById, model.authorized);
            if (ea.eligible) {
              res.attributes.display_id = f.resolved.value;
              ea.supportedBy.forEach((s) => authorizedBy.add(s));
            } else if (!ea.noValue) {
              res.omitted_optional.push({ datum: 'attributes.display_id', claims_from: ea.blocked.map((x) => x.source), blocked_because: ea.blocked.map((x) => x.why).join('; ') || 'sin afirmaciones autorizadas' });
            }
          }
        });
        res.tech = (b.tech_refs || []).map((r) => ({ kind: r.kind, id: r.id })); // se vacía al final si la entidad no queda disponible
      }
    }
  }

  // 5. capacidades
  res.required_capabilities = requiredCapabilities(model, entity, flavor, rules);
  const profile = model.profiles.get(flavor);
  const policy = model.flavors.flavors[flavor].capability_policy;
  for (const cap of res.required_capabilities) {
    const status = profile && profile.doc.capabilities[cap] ? profile.doc.capabilities[cap].status : 'unverified';
    if (status === 'verified') continue;
    if (status === 'unverified') {
      if (policy === 'block') reasons.push(`capability_unverified:${cap}`);
      else warnings.push(`capability_unverified:${cap}`);
    } else {
      reasons.push(`capability_unavailable:${cap}`);
    }
  }

  // 7. conflictos bloqueantes abiertos que afectan a sus datos técnicos
  for (const c of model.conflicts) {
    if (c.scope !== 'world' || c.subject.flavor !== flavor) continue;
    if (!(c.status === 'open' || c.status === 'stale') || !c.blocks_publish) continue;
    const hit = blockedKeys.some((k) => k.kind === c.subject.kind && (k.id !== undefined ? k.id === c.subject.id : k.key === c.subject.key));
    if (hit) {
      reasons.push('blocked_by_conflict');
      res.details.push({ datum: `conflict:${c.id}`, claims_from: Array.from(new Set(c.claims.map((x) => x.provenance.source))).sort(), blocked_because: `conflicto ${c.status} (${c.class}, ${c.severity}) en ${c.field}` });
    }
  }

  res.reasons = sortReasons(reasons);
  res.warnings = sortReasons(warnings);
  res.available = res.reasons.length === 0;
  if (!res.available) { res.tech = []; res.attributes = {}; res.placeNames = []; }
  res.authorized_by = res.available ? Array.from(authorizedBy).sort() : [];
  const sortDetails = (a, b) => (a.datum < b.datum ? -1 : a.datum > b.datum ? 1 : 0);
  res.details.sort(sortDetails);
  res.omitted_optional.sort(sortDetails);
  return res;
}

module.exports = { shipEntity, requiredCapabilities, REASON_ORDER, sortReasons };
