'use strict';
// Elegibilidad de un dato de World Data para entrar en un pack generado (Fase 16, 5.2 «Autorización para el pack ≠ confianza»).
//
// Un valor resuelto es ELEGIBLE si su `resolved.value` coincide con el valor de al menos una claim cuya fuente tiene `usage.generated_data === true`.
//   - La confianza (`client_verified`) NO sustituye a la autorización.
//   - Un Binding NO concede elegibilidad (esta función ni lo mira).
//   - Un override `set_value` (valor escrito por una persona sin una claim que lo respalde) tampoco es elegible por sí solo.
//   - Un dato no elegible sigue siendo World Data válido (investigación, contraste, candidatos); simplemente no viaja al pack.
const { deepEqual } = require('./canonical');

function authorizedSourceIds(sourcesById) {
  const ids = [];
  for (const [id, s] of sourcesById) if (s.usage.generated_data === true && s.status === 'active') ids.push(id);
  return new Set(ids.sort());
}

function whyNotAuthorized(source) {
  if (!source) return 'fuente desconocida';
  if (source.status === 'blocked') return 'status = blocked';
  if (source.status === 'research_only') return 'status = research_only';
  if (source.usage.generated_data !== true) return 'usage.generated_data = false';
  return 'no autorizada';
}

// field: { claims, resolved } (de world.entity / world.place).
function checkField(field, sourcesById, authorized) {
  if (!field || !field.resolved || field.resolved.value === null || field.resolved.value === undefined) {
    return { eligible: false, supportedBy: [], blocked: [], noValue: true };
  }
  const matching = field.claims.filter((c) => deepEqual(c.value, field.resolved.value));
  const supportedBy = Array.from(new Set(matching.map((c) => c.provenance.source).filter((s) => authorized.has(s)))).sort();
  const blockedSources = Array.from(new Set(matching.map((c) => c.provenance.source).filter((s) => !authorized.has(s)))).sort();
  return {
    eligible: supportedBy.length > 0,
    supportedBy,
    blocked: blockedSources.map((s) => ({ source: s, why: whyNotAuthorized(sourcesById.get(s)) })),
    noValue: false,
  };
}

module.exports = { authorizedSourceIds, checkField, whyNotAuthorized };
