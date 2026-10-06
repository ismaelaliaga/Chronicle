'use strict';
// Serializador Lua determinista y compatible con Lua 5.1 (sin goto, operadores de bits, //, ni escapes \x \z \u{}).
// Los caracteres no ASCII se escriben como escapes decimales de 3 dígitos por BYTE UTF-8 (\ddd).
const RESERVED = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);

function luaString(s) {
  let out = '"';
  for (const b of Buffer.from(String(s), 'utf8')) {
    if (b === 0x5c) out += '\\\\';
    else if (b === 0x22) out += '\\"';
    else if (b === 0x0a) out += '\\n';
    else if (b === 0x0d) out += '\\r';
    else if (b === 0x09) out += '\\t';
    else if (b < 0x20 || b >= 0x7f) out += '\\' + String(b).padStart(3, '0');
    else out += String.fromCharCode(b);
  }
  return out + '"';
}

function luaKey(k) {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && !RESERVED.has(k) ? k : `[${luaString(k)}]`;
}

function serialize(value, indent = 0) {
  const pad = (n) => ' '.repeat(n);
  if (value === null || value === undefined) throw new Error('el pack no admite null/undefined (Lua no distingue «ausente»)');
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    if (!Number.isInteger(value)) throw new Error(`el pack solo admite enteros (valor ${value})`);
    return String(value);
  }
  if (typeof value === 'string') return luaString(value);
  if (Array.isArray(value)) {
    if (value.length === 0) return '{}';
    return '{\n' + value.map((v) => pad(indent + 4) + serialize(v, indent + 4) + ',').join('\n') + '\n' + pad(indent) + '}';
  }
  const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort();
  if (keys.length === 0) return '{}';
  return '{\n' + keys.map((k) => pad(indent + 4) + luaKey(k) + ' = ' + serialize(value[k], indent + 4) + ',').join('\n') + '\n' + pad(indent) + '}';
}

module.exports = { serialize, luaString, luaKey };
