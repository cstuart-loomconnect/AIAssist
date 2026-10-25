// Small helpers that turn data into HTML strings.

export const esc = (text) =>
  String(text ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

// 'AIAgent__c' -> 'AIAgent'
export const short = (apiName) => apiName.replace(/__(c|mdt|e)$/, '');

export const code = (text) => `<code>${esc(text)}</code>`;

export const codeList = (names) => names.map(code).join(' ');

export function table(headings, rows) {
  const head = headings.map((h) => `<th>${h}</th>`).join('');
  const body = rows.map((row) => `<tr>${row.map((cell) => `<td>${cell}</td>`).join('')}</tr>`).join('');
  return `<div class="table-wrap"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

export function cards(items) {
  const html = items
    .map((c) => `<a class="card" href="${c.href}"><b>${esc(c.title)}</b><span>${esc(c.text)}</span></a>`)
    .join('');
  return `<div class="cards">${html}</div>`;
}

// Replaces {{name}} in a template with values[name].
export const fill = (template, values) => template.replace(/\{\{(\w+)\}\}/g, (_, name) => values[name] ?? '');
