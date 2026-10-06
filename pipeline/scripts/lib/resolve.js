'use strict';
// Reconciliación de afirmaciones (claims) de un campo de World Data (Fase 16, 5.4). Nunca se «elige» en silencio:
// si no hay una regla que decida, el campo queda en conflicto con valor null y se crea un registro de conflicto.
const { canonicalCompact, deepEqual, fingerprint, sha256Hex, stripTime } = require('./canonical');

const CONFIDENCE_RANK = { client_verified: 4, source_confirmed: 3, source_reported: 2, inferred: 1 };

// Orden determinista de las claims de un campo.
function sortClaims(claims) {
  return claims.slice().sort((a, b) => {
    const ka = a.provenance.source + '\u0000' + canonicalCompact(a.value) + '\u0000' + canonicalCompact(stripTime(a.provenance));
    const kb = b.provenance.source + '\u0000' + canonicalCompact(b.value) + '\u0000' + canonicalCompact(stripTime(b.provenance));
    return ka < kb ? -1 : ka > kb ? 1 : 0;
  });
}

function classOf(field, claims) {
  const verified = claims.filter((c) => c.confidence === 'client_verified');
  const distinct = new Set(verified.map((c) => canonicalCompact(c.value)));
  if (distinct.size > 1) return 'drift'; // dos observaciones de cliente que no coinciden: decisión humana, nunca «gana la más reciente»
  if (field === 'exists') return 'existence';
  if (field === 'spawns' || field === 'places') return 'location';
  if (field.startsWith('texts.')) return 'name_locale';
  return 'identity';
}

const SEVERITY = { identity: 'high', existence: 'high', location: 'medium', name_locale: 'medium', drift: 'medium', duplicate_tech: 'blocking' };

// Resuelve sin overrides. Devuelve { resolved } o { conflict: true }.
function resolveBasic(claims, sourcesById) {
  if (claims.length === 1) return { value: claims[0].value, status: 'resolved', rule: 'single_claim' };
  const distinct = new Set(claims.map((c) => canonicalCompact(c.value)));
  if (distinct.size === 1) return { value: claims[0].value, status: 'resolved', rule: 'agreement' };
  // Discrepancia: precedencia por trust_tier SOLO si la confianza de la ganadora es estrictamente mayor que la de todas las demás.
  const tier = (c) => sourcesById.get(c.provenance.source).trust_tier;
  const minTier = Math.min(...claims.map(tier));
  const top = claims.filter((c) => tier(c) === minTier);
  const topValues = new Set(top.map((c) => canonicalCompact(c.value)));
  if (topValues.size === 1) {
    const topRank = Math.max(...top.map((c) => CONFIDENCE_RANK[c.confidence]));
    const others = claims.filter((c) => canonicalCompact(c.value) !== canonicalCompact(top[0].value));
    if (others.every((c) => topRank > CONFIDENCE_RANK[c.confidence])) {
      return { value: top[0].value, status: 'resolved', rule: 'tier_precedence' };
    }
  }
  return null;
}

function claimMatches(claim, p) {
  return claim.provenance.source === p.source && claim.provenance.source_version === p.source_version && claim.provenance.method === p.method;
}

// Resuelve un campo. `ctx` = { sourcesById, overrides, subject, field, report, file }.
// Devuelve { resolved, conflict|null, claims } (claims ordenadas).
function resolveField(rawClaims, ctx) {
  const claims = sortClaims(rawClaims);
  const basic = resolveBasic(claims, ctx.sourcesById);
  if (basic) return { resolved: basic, conflict: null, claims };

  const cls = classOf(ctx.field, claims);
  const claimsFp = fingerprint(claims.map((c) => ({ value: c.value, provenance: c.provenance, confidence: c.confidence })));
  const idHex = sha256Hex(canonicalCompact({ class: cls, subject: ctx.subject, field: ctx.field, claims: claimsFp })).slice(0, 16);
  const conflictId = 'conf:' + idHex;
  const severity = SEVERITY[cls];
  const conflict = {
    schema: 'chronicle.world.conflict/1',
    id: conflictId,
    scope: 'world',
    class: cls,
    severity,
    status: 'open',
    subject: ctx.subject,
    field: ctx.field,
    claims: claims.map((c) => ({ value: c.value, provenance: c.provenance, confidence: c.confidence })),
    fingerprint: claimsFp,
    blocks_publish: severity === 'blocking' || severity === 'high',
  };
  const unresolved = { value: null, status: 'conflict', rule: 'none', conflict: conflictId };

  // Override aplicable: por id de conflicto o por (sujeto, campo).
  const ov = (ctx.overrides || []).find((o) => (o.target.conflict && o.target.conflict === conflictId)
    || (o.target.subject && o.target.field === ctx.field && deepEqual(o.target.subject, ctx.subject)));
  if (!ov) return { resolved: unresolved, conflict, claims };

  if (ov.bound_to_fingerprint !== claimsFp) {
    // Las fuentes han cambiado desde la decisión: el override ya no es válido y el conflicto VUELVE a abrirse.
    conflict.status = 'stale';
    ctx.report.warn('W-OVERRIDE-STALE', ctx.file, '', `el override «${ov.id}» está atado a otra huella (${ov.bound_to_fingerprint}); las fuentes han cambiado (huella actual ${claimsFp}). El conflicto se reabre.`);
    return { resolved: unresolved, conflict, claims };
  }

  let value;
  let found = true;
  if ('set_value' in ov.decision) {
    value = ov.decision.set_value;
  } else if (ov.decision.prefer_claim) {
    const c = claims.find((x) => claimMatches(x, ov.decision.prefer_claim));
    if (c) value = c.value; else found = false;
  } else {
    const rest = claims.filter((x) => !claimMatches(x, ov.decision.reject_claim));
    if (rest.length === claims.length || rest.length === 0) found = false;
    else {
      const again = resolveBasic(rest, ctx.sourcesById);
      if (again) value = again.value; else found = false;
    }
  }
  if (!found) {
    ctx.report.error('W-OVERRIDE-INVALID', ctx.file, '', `el override «${ov.id}» no se puede aplicar: la afirmación indicada no existe o no resuelve el conflicto`);
    return { resolved: unresolved, conflict, claims };
  }
  conflict.status = 'overridden';
  conflict.blocks_publish = false;
  conflict.resolution = { kind: 'override', override: ov.id, reason: ov.reason, by: ov.author };
  return { resolved: { value, status: 'overridden', rule: 'override', override: ov.id }, conflict, claims };
}

module.exports = { CONFIDENCE_RANK, SEVERITY, sortClaims, resolveField, resolveBasic };
