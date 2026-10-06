'use strict';
// Serialización canónica y fingerprints. Ningún dato de tiempo de ejecución participa: el contenido que determina un fingerprint es una
// función pura de las entradas. Las marcas de tiempo que SON metadatos de entrada (fechas de obtención, de revisión...) se excluyen del fingerprint.
const crypto = require('crypto');

// Claves que son metadatos de tiempo de ENTRADA (Fase 16, 4.6): nunca determinan un fingerprint.
const TIME_KEYS = new Set(['retrieved_at', 'observed_at', 'created_at', 'reviewed_at', 'at', 'since']);

function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== undefined) out[key] = sortKeys(value[key]);
    }
    return out;
  }
  return value;
}

function stripTime(value) {
  if (Array.isArray(value)) return value.map(stripTime);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value)) {
      if (!TIME_KEYS.has(key)) out[key] = stripTime(value[key]);
    }
    return out;
  }
  return value;
}

// Fichero JSON canónico: claves ordenadas, sangría de 2 espacios, LF y salto de línea final.
function canonicalPretty(value) {
  return JSON.stringify(sortKeys(value), null, 2) + '\n';
}

// Forma compacta (para hashes).
function canonicalCompact(value) {
  return JSON.stringify(sortKeys(value));
}

function sha256Hex(text) {
  // Se normalizan los finales de línea: un CRLF introducido por la copia de trabajo no cambia ninguna huella.
  const normalized = Buffer.isBuffer(text) ? text : Buffer.from(String(text).replace(/\r\n/g, '\n'), 'utf8');
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

function fingerprint(value, options = {}) {
  const input = options.keepTime ? value : stripTime(value);
  return 'sha256:' + sha256Hex(canonicalCompact(input));
}

function deepEqual(a, b) {
  return canonicalCompact(a) === canonicalCompact(b);
}

module.exports = { TIME_KEYS, sortKeys, stripTime, canonicalPretty, canonicalCompact, sha256Hex, fingerprint, deepEqual };
