'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { canonicalPretty, canonicalCompact, fingerprint, sha256Hex, stripTime, deepEqual } = require('../scripts/lib/canonical');
const { serialize, luaString } = require('../scripts/lib/lua');

test('JSON canónico: las claves salen ordenadas, 2 espacios, LF y salto final, sea cual sea el orden de entrada', () => {
  const a = canonicalPretty({ b: 1, a: { d: [3, 2, 1], c: 'x' } });
  const b = canonicalPretty({ a: { c: 'x', d: [3, 2, 1] }, b: 1 });
  assert.equal(a, b);
  assert.equal(a, '{\n  "a": {\n    "c": "x",\n    "d": [\n      3,\n      2,\n      1\n    ]\n  },\n  "b": 1\n}\n');
  assert.ok(!a.includes('\r'));
});

test('fingerprint: formato sha256:<64 hex>, estable ante el orden de claves y distinto si cambia un valor', () => {
  const f = fingerprint({ a: 1, b: [1, 2] });
  assert.match(f, /^sha256:[a-f0-9]{64}$/);
  assert.equal(f, fingerprint({ b: [1, 2], a: 1 }));
  assert.notEqual(f, fingerprint({ a: 2, b: [1, 2] }));
  assert.notEqual(f, fingerprint({ a: 1, b: [2, 1] })); // el orden de una lista SÍ importa
});

test('fingerprint: los metadatos de TIEMPO de entrada no determinan la huella (la fecha de ejecución tampoco existe)', () => {
  const base = { provenance: { source: 's', retrieved_at: '2026-10-04' }, observed_at: '2026-10', editorial: { reviewed_at: '2026-10' }, v: 1 };
  const moved = { provenance: { source: 's', retrieved_at: '2030-01-01' }, observed_at: '2031-02', editorial: { reviewed_at: '2032-03' }, v: 1 };
  assert.equal(fingerprint(base), fingerprint(moved));
  assert.notEqual(fingerprint(base), fingerprint({ ...base, v: 2 }));
  assert.notEqual(fingerprint(base, { keepTime: true }), fingerprint(moved, { keepTime: true }));
  assert.deepEqual(stripTime(base), { provenance: { source: 's' }, editorial: {}, v: 1 });
});

test('sha256Hex: un CRLF de la copia de trabajo no cambia la huella; el contenido real sí', () => {
  assert.equal(sha256Hex('a\nb\n'), sha256Hex('a\r\nb\r\n'));
  assert.notEqual(sha256Hex('a\nb\n'), sha256Hex('a\nc\n'));
  assert.equal(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'); // vector conocido de SHA-256
});

test('deepEqual compara por contenido canónico', () => {
  assert.equal(deepEqual({ a: [1, { b: 2 }] }, { a: [1, { b: 2 }] }), true);
  assert.equal(deepEqual({ a: 1 }, { a: '1' }), false);
});

test('Lua: serialización determinista (claves ordenadas, 4 espacios) y compatible con 5.1', () => {
  const lua = serialize({ z: 1, a: { 'npc:x': true, list: [1, 2], vacio: {} }, 'fin': 'x' });
  assert.equal(lua, serialize({ 'fin': 'x', a: { vacio: {}, list: [1, 2], 'npc:x': true }, z: 1 }));
  assert.match(lua, /\["npc:x"\] = true/);
  assert.match(lua, /vacio = \{\}/);
  assert.doesNotMatch(lua, /\bgoto\b|\\x|\\z|\\u\{/);
});

test('Lua: las palabras reservadas y claves no identificador van entre corchetes', () => {
  const lua = serialize({ ['end']: 1, ['if']: 2, normal: 3, 'con-guion': 4 });
  assert.match(lua, /\["end"\] = 1/);
  assert.match(lua, /\["if"\] = 2/);
  assert.match(lua, /normal = 3/);
  assert.match(lua, /\["con-guion"\] = 4/);
});

test('Lua: cadenas con comillas, barra, saltos y no ASCII usan escapes decimales \\ddd (nunca \\x, \\z ni \\u)', () => {
  assert.equal(luaString('a"b\\c\nd\te'), '"a\\"b\\\\c\\nd\\te"');
  assert.equal(luaString('ñ'), '"\\195\\177"'); // bytes UTF-8 en decimal de 3 dígitos
  assert.equal(luaString('é1'), '"\\195\\1691"'); // 3 dígitos fijos: el «1» siguiente no se confunde con el escape
  assert.equal(luaString('\u0001'), '"\\001"');
});

test('Lua: no se admiten null, undefined ni números no enteros (Lua no distingue «ausente»)', () => {
  assert.throws(() => serialize({ a: null }), /null/);
  assert.throws(() => serialize({ a: 1.5 }), /enteros/);
  assert.doesNotThrow(() => serialize({ a: undefined }));
  assert.equal(serialize({ a: undefined }), '{}');
});
