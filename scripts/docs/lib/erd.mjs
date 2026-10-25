// Draws an entity relationship diagram (Mermaid syntax) for a list of objects.
import { short } from './html.mjs';

// Shows only the key fields so the diagram stays readable.
function entity(object) {
  const keyFields = object.fields.filter((f) => f.referenceTo || f.required || f.unique || f.externalId).slice(0, 6);
  const lines = keyFields.map((f) => {
    const mark = f.referenceTo ? ' FK' : f.unique || f.externalId ? ' UK' : '';
    return `    string ${short(f.name)}${mark}`;
  });
  return `  ${short(object.name)} {\n${lines.join('\n') || '    string Name'}\n  }`;
}

// Master-detail is a solid line, lookup is dotted.
function relationshipLine(r) {
  const line = r.type === 'MasterDetail' ? '||--o{' : '|o..o{';
  return `  ${short(r.to)} ${line} ${short(r.from)} : "${short(r.field)}"`;
}

export function erd(objectNames, { objects, relationships }) {
  const names = new Set(objectNames.filter((n) => objects[n]));
  const links = relationships.filter((r) => names.has(r.from) && names.has(r.to));
  const linked = new Set(links.flatMap((r) => [r.from, r.to]));
  const shown = [...names].filter((n) => linked.has(n));
  if (!shown.length) return '';

  const diagram = ['erDiagram', ...links.map(relationshipLine), ...shown.map((n) => entity(objects[n]))].join('\n');
  return `<div class="diagram"><pre class="mermaid">${diagram}</pre></div>`;
}
