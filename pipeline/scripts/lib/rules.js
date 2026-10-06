'use strict';
// Reglas de dominio del modelo editorial (Fase 16, 7). Son funciones puras; no leen ficheros.

const PLACE_TYPES = new Set(['continent', 'zone', 'city', 'subzone']);
const ENTITY_TYPES = ['continent', 'zone', 'city', 'subzone', 'npc', 'lore'];

// Relaciones permitidas por tipo. Espejo de Chronicle/Data/Schema.lua (DEFAULT_TYPES) [HECHO en la Fase 16: «igual que hoy»].
const TYPE_RULES = {
  continent: {},
  zone: { parent: { types: ['continent'], required: true } },
  city: { parent: { types: ['continent'], required: true }, located_in: { types: ['zone'] } },
  subzone: { parent: { types: ['zone', 'city'], required: true } },
  npc: { located_in: { types: ['subzone', 'zone', 'city'] } },
  lore: { located_in: { types: ['continent', 'zone', 'city', 'subzone'] } },
};

const MAX_SLUG = 64;

function typeOf(id) {
  return id.split(':')[0];
}

function slugOf(id) {
  return id.slice(id.indexOf(':') + 1);
}

// Transiciones de estado de una entidad (Fase 16, 7.2). Mismo estado = permitido.
const TRANSITIONS = {
  accepted: ['drafting', 'retired'],
  drafting: ['review', 'retired'],
  review: ['published', 'drafting', 'retired'],
  published: ['drafting', 'retired'],
  retired: ['review'],
};

function checkTransition(prev, next) {
  if (prev === next) return true;
  return Array.isArray(TRANSITIONS[prev]) && TRANSITIONS[prev].includes(next);
}

// Nombre normalizado igual que Chronicle.Resolver (recorta, colapsa espacios, minúsculas ASCII y mayúsculas acentuadas del español).
const UPPER_TO_LOWER = [['Á', 'á'], ['É', 'é'], ['Í', 'í'], ['Ó', 'ó'], ['Ú', 'ú'], ['Ñ', 'ñ'], ['Ü', 'ü']];
function normalizeName(text) {
  let t = String(text).replace(/^[ \t\n\v\f\r]+/, '').replace(/[ \t\n\v\f\r]+$/, '').replace(/[ \t\n\v\f\r]+/g, ' ');
  t = t.replace(/[A-Z]/g, (c) => c.toLowerCase());
  for (const [up, low] of UPPER_TO_LOWER) t = t.split(up).join(low);
  return t;
}

// ---- reglas de descubrimiento
function implicitRules(type) {
  if (type === 'zone' || type === 'city' || type === 'subzone') return { method: 'place_enter' };
  if (type === 'continent') return { method: 'none' };
  return null; // npc y lore exigen reglas explícitas
}

// Reglas efectivas de una entidad para una versión: la anulación por versión SUSTITUYE por completo a la base (no se fusionan).
function effectiveRules(entity, flavor) {
  const override = entity.flavors && entity.flavors[flavor] && entity.flavors[flavor].discovery;
  if (override) return override;
  return entity.discovery || implicitRules(entity.type);
}

function walkRequirement(req, visit) {
  if (!req) return;
  if (req.all) req.all.forEach((r) => walkRequirement(r, visit));
  else if (req.any) req.any.forEach((r) => walkRequirement(r, visit));
  else visit(req);
}

function walkInteraction(spec, visit, depth = 0) {
  if (!spec) return;
  if (spec.all) {
    visit({ kind: 'all', depth });
    spec.all.forEach((s) => walkInteraction(s, visit, depth + 1));
  } else if (spec.any) {
    spec.any.forEach((s) => walkInteraction(s, visit, depth + 1));
  } else {
    visit({ kind: 'type', type: spec.type, depth });
  }
}

function interactionTypes(spec) {
  const out = new Set();
  walkInteraction(spec, (n) => { if (n.kind === 'type') out.add(n.type); });
  return Array.from(out).sort();
}

function usesInteractionAll(spec) {
  let found = false;
  walkInteraction(spec, (n) => { if (n.kind === 'all') found = true; });
  return found;
}

function requirementRefs(req) {
  const places = [];
  const entities = [];
  const hints = [];
  walkRequirement(req, (r) => {
    if (r.place_discovered) places.push(r.place_discovered.id);
    if (r.entity_discovered) entities.push(r.entity_discovered.id);
    if (r.hint_seen) hints.push(r.hint_seen.id);
  });
  return { places, entities, hints };
}

// Zona o ciudad ancestro de una entidad (por located_in y parent). Devuelve el ID o null.
function ancestorZone(entity, entitiesById) {
  let cur = entity.located_in;
  for (let i = 0; i < 16 && cur; i++) {
    const e = entitiesById.get(cur);
    if (!e) return null;
    if (e.type === 'zone' || e.type === 'city') return cur;
    if (e.type === 'subzone') cur = e.parent;
    else if (e.type === 'continent') return null;
    else cur = e.located_in;
  }
  return null;
}

// Regla materializada para el pack (Fase 16, 7.4): si falta `requirements` en una interacción, se expande a la zona ancestro (derived: true).
function materializeRules(entity, flavor, entitiesById) {
  const base = effectiveRules(entity, flavor);
  if (!base) return { rules: null, error: 'no_rules' };
  const rules = JSON.parse(JSON.stringify(base));
  if (rules.method === 'interaction' && !rules.requirements) {
    const zone = ancestorZone(entity, entitiesById);
    if (!zone) return { rules: null, error: 'no_zone_ancestor' };
    rules.requirements = { place_discovered: { id: zone, strict: false, derived: true } };
  }
  return { rules };
}

// ---- lint de pistas (Fase 16, 7.5). Patrones documentados en docs/fase17_data_pipeline.md.
const COORDINATE_PATTERNS = [
  { id: 'pair', re: /(?<![\w.])\d{1,3}(?:[.,]\d{1,2})?\s*[,;/]\s*\d{1,3}(?:[.,]\d{1,2})?(?![\w.])/ },
  { id: 'xy', re: /\b[xy]\s*[:=]\s*\d/i },
  { id: 'way', re: /\/way\b|\btomtom\b/i },
  { id: 'word', re: /\bcoordenadas?\b/i },
  { id: 'gps', re: /\b(?:ve|ir|camina|avanza|sigue|dirígete|dirigete)\b[^.]{0,40}\b(?:al|hacia el|hacia la)\s+(?:norte|sur|este|oeste)\b[^.]{0,30}\d/i },
];

function findCoordinates(text) {
  const hits = [];
  for (const p of COORDINATE_PATTERNS) if (p.re.test(text)) hits.push(p.id);
  return hits;
}

// ¿El texto contiene alguno de los nombres (como palabra completa, sin distinguir mayúsculas ni acentos de mayúscula)?
function findNameLeak(text, names) {
  const hay = normalizeName(text);
  const leaks = [];
  for (const name of names) {
    const n = normalizeName(name);
    if (n.length < 3) continue;
    const escaped = n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp(`(^|[^\\p{L}\\p{N}])${escaped}($|[^\\p{L}\\p{N}])`, 'u');
    if (re.test(hay)) leaks.push(name);
  }
  return Array.from(new Set(leaks)).sort();
}

module.exports = {
  PLACE_TYPES, ENTITY_TYPES, TYPE_RULES, MAX_SLUG, TRANSITIONS,
  typeOf, slugOf, checkTransition, normalizeName,
  implicitRules, effectiveRules, walkRequirement, walkInteraction, interactionTypes, usesInteractionAll, requirementRefs,
  ancestorZone, materializeRules, findCoordinates, findNameLeak, COORDINATE_PATTERNS,
};
