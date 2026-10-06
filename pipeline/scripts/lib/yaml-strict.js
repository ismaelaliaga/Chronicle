'use strict';
// Lector YAML 1.2 de subconjunto estricto (Fase 16, 3.3). Solo para datos escritos o revisados por personas.
// Es una dependencia de DESARROLLO del pipeline: ningún parser YAML forma parte del addon.
//
// Se rechaza: anclas, alias, claves de fusión (<<), etiquetas explícitas, claves duplicadas, más de un documento por fichero, BOM,
// tabuladores de sangrado, valores vacíos implícitos y el nulo «~». Los tipos reales los fija después el esquema JSON (un valor mal tipado
// falla aunque el YAML sea válido). Esquema YAML «core» de 1.2: solo true/false son booleanos y las fechas NO se convierten.
const YAML = require('yaml');

function lineOf(node, doc) {
  try {
    if (node && node.range && doc) {
      return doc.contents && typeof doc.contents === 'object' ? offsetToLine(doc, node.range[0]) : null;
    }
  } catch (e) {
    return null;
  }
  return null;
}

function offsetToLine(doc, offset) {
  const src = doc.__source || '';
  let line = 1;
  for (let i = 0; i < offset && i < src.length; i++) if (src[i] === '\n') line++;
  return line;
}

// Devuelve { value, ok }. Los problemas se anotan en `report` con el código E-01.
function parseStrictYaml(text, file, report) {
  const source = String(text).replace(/\r\n/g, '\n');
  const fail = (at, message) => report.error('E-01', file, at, message);

  if (source.charCodeAt(0) === 0xfeff) fail('', 'el fichero empieza por BOM (se exige UTF-8 sin BOM)');
  if (/\t/.test(source.split('\n').map((l) => l.match(/^[ \t]*/)[0]).join('\n'))) fail('', 'hay tabuladores de sangrado (se usa solo espacio)');

  const docs = YAML.parseAllDocuments(source, { version: '1.2', schema: 'core', uniqueKeys: true, merge: false, prettyErrors: true });
  if (docs.length === 0 || (docs.length === 1 && docs[0].contents === null)) {
    fail('', 'el fichero está vacío');
    return { ok: false, value: undefined };
  }
  if (docs.length > 1) fail('', `el fichero contiene ${docs.length} documentos YAML (se exige uno por fichero)`);

  let ok = !report.items.some((i) => i.file === file && i.code === 'E-01');
  const doc = docs[0];
  doc.__source = source;

  for (const err of doc.errors) {
    const line = err.linePos && err.linePos[0] ? `línea ${err.linePos[0].line}` : '';
    fail(line, `YAML no válido (${err.code}): ${err.message.split('\n')[0]}`);
    ok = false;
  }
  for (const warn of doc.warnings) {
    const line = warn.linePos && warn.linePos[0] ? `línea ${warn.linePos[0].line}` : '';
    fail(line, `aviso de YAML tratado como error (${warn.code}): ${warn.message.split('\n')[0]}`);
    ok = false;
  }

  const at = (node) => {
    const l = lineOf(node, doc);
    return l ? `línea ${l}` : '';
  };

  function walk(node) {
    if (node === null || node === undefined) return;
    if (YAML.isAlias(node)) {
      fail(at(node), `alias «*${node.source}» no permitido`);
      ok = false;
      return;
    }
    if (node.anchor) {
      fail(at(node), `ancla «&${node.anchor}» no permitida`);
      ok = false;
    }
    if (node.tag) {
      fail(at(node), `etiqueta explícita «${node.tag}» no permitida`);
      ok = false;
    }
    if (YAML.isMap(node)) {
      for (const pair of node.items) {
        if (YAML.isScalar(pair.key) && pair.key.value === '<<') {
          fail(at(pair.key), 'clave de fusión «<<» no permitida');
          ok = false;
        }
        walk(pair.key);
        walk(pair.value);
      }
    } else if (YAML.isSeq(node)) {
      for (const item of node.items) walk(item);
    } else if (YAML.isScalar(node)) {
      if (node.value === null && node.type === 'PLAIN' && node.source !== 'null') {
        fail(at(node), node.source === '' ? 'valor vacío implícito (escriba null o comillas)' : `nulo «${node.source}» no permitido (escriba null)`);
        ok = false;
      }
    }
  }
  walk(doc.contents);

  if (!ok) return { ok: false, value: undefined };
  return { ok: true, value: doc.toJS() };
}

module.exports = { parseStrictYaml };
