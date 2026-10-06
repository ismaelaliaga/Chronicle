'use strict';
// Informe de errores y avisos del pipeline. Determinista: el orden de salida no depende del orden en que se detectan los problemas.

function cmp(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

class Report {
  constructor() {
    this.items = [];
  }

  add(severity, code, file, at, message) {
    this.items.push({ severity, code, file: file || '', at: at || '', message });
  }

  error(code, file, at, message) {
    this.add('error', code, file, at, message);
  }

  warn(code, file, at, message) {
    this.add('warning', code, file, at, message);
  }

  merge(other) {
    for (const item of other.items) this.items.push(item);
  }

  get errors() {
    return this.items.filter((i) => i.severity === 'error');
  }

  get warnings() {
    return this.items.filter((i) => i.severity === 'warning');
  }

  hasErrors() {
    return this.items.some((i) => i.severity === 'error');
  }

  // Errores primero; después por fichero, posición, código y mensaje (comparación de cadenas simple: no depende de la configuración regional).
  sorted() {
    return this.items.slice().sort((a, b) =>
      cmp(a.severity === 'error' ? 0 : 1, b.severity === 'error' ? 0 : 1) ||
      cmp(a.file, b.file) || cmp(a.at, b.at) || cmp(a.code, b.code) || cmp(a.message, b.message));
  }

  format() {
    const seen = new Set();
    const lines = [];
    for (const i of this.sorted()) {
      const line = `${i.severity === 'error' ? 'ERROR' : 'AVISO'} [${i.code}] ${i.file}${i.at ? ' ' + i.at : ''}: ${i.message}`;
      if (!seen.has(line)) {
        seen.add(line);
        lines.push(line);
      }
    }
    return lines;
  }
}

module.exports = { Report, cmp };
