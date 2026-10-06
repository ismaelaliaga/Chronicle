'use strict';
// Carga y ejecución de los JSON Schema (2020-12) del pipeline. Errores deterministas y legibles.
const fs = require('fs');
const path = require('path');
const Ajv2020 = require('ajv/dist/2020');

const SCHEMA_DIR = path.join(__dirname, '..', '..', 'schemas');
const BASE = 'https://chronicle.local/schemas/';

let ajv = null;

function getAjv() {
  if (ajv) return ajv;
  // Modo estricto de Ajv (palabras clave desconocidas, etc.). Solo se relaja `strictRequired`: el patrón if/then exige nombrar propiedades en `required`
  // dentro de `then` sin repetirlas en `properties`.
  ajv = new Ajv2020({ strict: true, strictRequired: false, strictTypes: false, allErrors: true });
  const files = fs.readdirSync(SCHEMA_DIR).filter((f) => f.endsWith('.json')).sort();
  for (const f of files) ajv.addSchema(JSON.parse(fs.readFileSync(path.join(SCHEMA_DIR, f), 'utf8')));
  return ajv;
}

function listSchemas() {
  return fs.readdirSync(SCHEMA_DIR).filter((f) => f.endsWith('.json')).map((f) => f.replace(/\.json$/, '')).sort();
}

function getValidator(name) {
  const fn = getAjv().getSchema(BASE + name + '.json');
  if (!fn) throw new Error(`esquema desconocido: ${name}`);
  return fn;
}

function describe(err) {
  const p = err.params || {};
  switch (err.keyword) {
    case 'required': return `falta la propiedad «${p.missingProperty}»`;
    case 'additionalProperties': return `propiedad no permitida «${p.additionalProperty}»`;
    case 'enum': return `valor no permitido (permitidos: ${(p.allowedValues || []).join(', ')})`;
    case 'const': return `debe valer ${JSON.stringify(p.allowedValue)}`;
    case 'pattern': return `no cumple el patrón ${p.pattern}`;
    case 'type': return `debe ser de tipo ${Array.isArray(p.type) ? p.type.join('|') : p.type}`;
    case 'minItems': return `debe tener al menos ${p.limit} elemento(s)`;
    case 'minLength': return 'no puede estar vacío';
    case 'minProperties': return `debe tener al menos ${p.limit} propiedad(es)`;
    case 'uniqueItems': return 'tiene elementos repetidos';
    case 'oneOf': return 'no coincide exactamente con una de las formas permitidas';
    case 'not': return 'contiene algo que este caso no permite';
    default: return err.message;
  }
}

// Valida `doc` contra el esquema `name`. Anota los errores en `report` con el código dado (por defecto SCHEMA).
function validateDoc(name, doc, report, file, code = 'SCHEMA') {
  const validate = getValidator(name);
  if (validate(doc)) return true;
  const seen = new Set();
  const rows = [];
  for (const err of validate.errors || []) {
    if (err.keyword === 'if') continue; // «must match then schema»: el error de fondo ya se informa
    const at = err.instancePath || '/';
    const msg = describe(err);
    const key = at + '|' + msg;
    if (seen.has(key)) continue;
    seen.add(key);
    rows.push({ at, msg });
  }
  rows.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : a.msg < b.msg ? -1 : a.msg > b.msg ? 1 : 0));
  for (const r of rows) report.error(code, file, r.at, `${name}: ${r.msg}`);
  return false;
}

module.exports = { SCHEMA_DIR, getValidator, listSchemas, validateDoc };
