'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseStrictYaml } = require('../scripts/lib/yaml-strict');
const { Report } = require('../scripts/lib/report');

function parse(text) {
  const report = new Report();
  const r = parseStrictYaml(text, 'x.yaml', report);
  return { ...r, report };
}
const codes = (report) => report.errors.map((e) => e.code);
const messages = (report) => report.errors.map((e) => e.message).join(' | ');

test('YAML estricto: un documento válido se lee y devuelve el valor', () => {
  const r = parse('a: 1\nb: [x, y]\nc:\n  d: "2026-10"\n');
  assert.equal(r.ok, true);
  assert.deepEqual(r.value, { a: 1, b: ['x', 'y'], c: { d: '2026-10' } });
  assert.equal(r.report.items.length, 0);
});

test('YAML estricto: rechaza anclas', () => {
  const r = parse('a: &x 1\nb: 2\n');
  assert.equal(r.ok, false);
  assert.match(messages(r.report), /ancla «&x»/);
});

test('YAML estricto: rechaza alias', () => {
  const r = parse('a: &x 1\nb: *x\n');
  assert.equal(r.ok, false);
  assert.match(messages(r.report), /alias «\*x»/);
});

test('YAML estricto: rechaza claves de fusión (<<)', () => {
  const r = parse('base: &b {k: 1}\nd:\n  <<: *b\n');
  assert.equal(r.ok, false);
  assert.match(messages(r.report), /clave de fusión/);
});

test('YAML estricto: rechaza etiquetas explícitas', () => {
  const r = parse('a: !!str 5\n');
  assert.equal(r.ok, false);
  assert.match(messages(r.report), /etiqueta explícita/);
});

test('YAML estricto: rechaza claves duplicadas', () => {
  const r = parse('a: 1\na: 2\n');
  assert.equal(r.ok, false);
  assert.deepEqual(codes(r.report), ['E-01']);
  assert.match(messages(r.report), /DUPLICATE_KEY/);
});

test('YAML estricto: exige un documento por fichero', () => {
  const r = parse('a: 1\n---\nb: 2\n');
  assert.equal(r.ok, false);
  assert.match(messages(r.report), /2 documentos/);
});

test('YAML estricto: rechaza BOM, tabuladores de sangrado y ficheros vacíos', () => {
  assert.match(messages(parse('\ufeffa: 1\n').report), /BOM/);
  assert.equal(parse('a:\n\tb: 1\n').ok, false);
  assert.match(messages(parse('a:\n\tb: 1\n').report), /tabuladores/);
  assert.match(messages(parse('').report), /vacío/);
  assert.match(messages(parse('# solo un comentario\n').report), /vacío/);
});

test('YAML estricto: rechaza valores vacíos implícitos y el nulo «~» (solo null explícito)', () => {
  assert.match(messages(parse('a:\nb: 1\n').report), /valor vacío implícito/);
  assert.match(messages(parse('a: ~\n').report), /nulo «~»/);
  const ok = parse('a: null\n');
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.value, { a: null });
});

test('YAML 1.2 core: solo true/false son booleanos y las fechas NO se convierten', () => {
  const r = parse('s: no\nt: yes\nb: true\nd: 2026-10-05\nv: "1.20"\n');
  assert.equal(r.ok, true);
  assert.equal(r.value.s, 'no');
  assert.equal(r.value.t, 'yes');
  assert.equal(r.value.b, true);
  assert.equal(r.value.d, '2026-10-05');
  assert.equal(r.value.v, '1.20');
});

test('YAML estricto: CRLF de la copia de trabajo se acepta (se normaliza a LF)', () => {
  const r = parse('a: 1\r\nb: 2\r\n');
  assert.equal(r.ok, true);
  assert.deepEqual(r.value, { a: 1, b: 2 });
});

test('YAML estricto: errores de sintaxis incluyen la línea y son deterministas', () => {
  const a = parse('a: [1, 2\nb: 3\n');
  const b = parse('a: [1, 2\nb: 3\n');
  assert.equal(a.ok, false);
  assert.deepEqual(a.report.format(), b.report.format());
  assert.match(a.report.format().join('\n'), /E-01/);
});
