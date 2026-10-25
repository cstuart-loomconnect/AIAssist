// Shared behaviour: theme toggle, mobile menu, site search, ERD rendering. Each page sets <body data-root="../">.
const root = document.body.dataset.root;
const html = document.documentElement;
try { if (localStorage.theme) html.dataset.theme = localStorage.theme; } catch {}
const isDark = () => html.dataset.theme === 'dark' || (!html.dataset.theme && matchMedia('(prefers-color-scheme: dark)').matches);
document.getElementById('theme').onclick = () => {
  html.dataset.theme = isDark() ? 'light' : 'dark';
  try { localStorage.theme = html.dataset.theme; } catch {}
  location.reload();
};
document.getElementById('menu').onclick = () => document.getElementById('nav').classList.toggle('open');

const box = document.getElementById('search');
const results = document.getElementById('results');
let index;
box.addEventListener('input', async () => {
  const q = box.value.trim().toLowerCase();
  results.hidden = q.length < 2;
  if (q.length < 2) return;
  index ??= await (await fetch(root + 'data/search.json')).json();
  const hits = index.filter((e) => e.t.toLowerCase().includes(q)).slice(0, 12);
  results.innerHTML = hits.length
    ? hits.map((e) => `<a href="${root}${e.u}">${e.t}<br><small>${e.k}</small></a>`).join('')
    : '<a>No matches</a>';
});
document.addEventListener('click', (e) => { if (!e.target.closest('#search,#results')) results.hidden = true; });

if (document.querySelector('pre.mermaid')) {
  const { default: mermaid } = await import('https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs');
  mermaid.initialize({ startOnLoad: false, theme: isDark() ? 'dark' : 'neutral', er: { useMaxWidth: false } });
  await mermaid.run({ querySelector: 'pre.mermaid' });
}
