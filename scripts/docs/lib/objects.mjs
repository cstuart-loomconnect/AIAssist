// The collapsible "field reference" block for one object.
import { esc, short, code, codeList, table } from './html.mjs';

const kindLabel = (type) => (type === 'MasterDetail' ? 'master-detail' : 'lookup');

function fieldNotes(field) {
  return [
    field.required && 'required',
    field.unique && 'unique',
    field.externalId && 'external ID',
    field.values.length && `values: ${field.values.map(esc).join(', ')}`,
    field.description && esc(field.description)
  ]
    .filter(Boolean)
    .join(' · ');
}

export function objectDetail(object, objects) {
  const relationships = object.fields
    .filter((f) => f.referenceTo)
    .map((f) => `${esc(f.label)} → ${esc(objects[f.referenceTo]?.label ?? f.referenceTo)} (${kindLabel(f.type)})`);

  const fieldRows = object.fields.map((f) => [
    esc(f.label),
    code(f.name),
    esc(f.type) + (f.referenceTo ? ` → ${esc(short(f.referenceTo))}` : ''),
    fieldNotes(f)
  ]);

  return `
<details class="obj" id="${object.name}">
  <summary>
    <b>${esc(object.label)}</b> ${code(object.name)}
    <span class="badge">${object.kind}</span>
    ${object.sharing ? `<span class="badge">${esc(object.sharing)}</span>` : ''}
    ${object.hasTrigger ? '<span class="badge">trigger</span>' : ''}
    <span class="muted">${object.fields.length} fields</span>
  </summary>
  <div class="body">
    <p>${esc(object.description)}</p>
    ${relationships.length ? `<p><b>Relationships:</b> ${relationships.join('; ')}</p>` : ''}
    ${object.validationRules.length ? `<p><b>Validation rules:</b> ${codeList(object.validationRules)}</p>` : ''}
    ${table(['Field', 'API name', 'Type', 'Notes'], fieldRows)}
  </div>
</details>`;
}
