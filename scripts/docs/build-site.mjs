// Builds the documentation pages in site/ from site/data/model.json (see build-model.mjs) and the files in this folder.
// Run with: npm run docs:build
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { esc, short, code, codeList, table, cards, fill } from './lib/html.mjs';
import { erd } from './lib/erd.mjs';
import { objectDetail } from './lib/objects.mjs';
import { createSite } from './lib/layout.mjs';
import { DOMAIN_FOLDERS, TABS } from './content/navigation.mjs';

const projectRoot = new URL('../../', import.meta.url).pathname;
const siteDir = join(projectRoot, 'site');
const read = (file) => readFileSync(new URL(file, import.meta.url), 'utf8');

// ---- Data ----
const model = JSON.parse(readFileSync(join(siteDir, 'data/model.json'), 'utf8'));
const { objects, domains } = model;
const allObjects = Object.values(objects);

const withoutExtension = (files, ext) => files.filter((f) => f.endsWith(ext)).map((f) => f.replace(ext, ''));
const apexClasses = withoutExtension(readdirSync(join(projectRoot, 'force-app/main/default/classes')), '.cls').filter((c) => !c.endsWith('Test'));
const lwcBundles = readdirSync(join(projectRoot, 'force-app/main/default/lwc')).filter((f) => !f.includes('.'));
const startsWithAny = (name, prefixes) => prefixes.some((p) => name.startsWith(p));

// ---- Navigation ----
const objectUrl = (o) => `data-model/${DOMAIN_FOLDERS[o.domain]}/#${o.name}`;
const navigation = [
  { title: 'Home', url: '' },
  { title: 'Architecture', url: 'architecture/' },
  { title: 'Data model', url: 'data-model/', children: domains.map((d) => ({ title: d.title, url: `data-model/${DOMAIN_FOLDERS[d.key]}/` })) },
  { title: 'User interface', url: 'interface/', children: TABS.map((t) => ({ title: t.title, url: `interface/${t.slug}/` })) },
  { title: 'Security', url: 'security/' },
  { title: 'Develop and test', url: 'develop/' }
];
const { writePage, searchIndex } = createSite({ siteDir, navigation });
const home = [['Home', '']];

// ---- Home, Architecture, Security, Develop ----
const countOf = (kind) => allObjects.filter((o) => o.kind === kind).length;

writePage('', 'Home', fill(read('pages/home.html'), {
  objectCount: countOf('Custom object'),
  metadataCount: countOf('Custom metadata'),
  fieldCount: allObjects.reduce((total, o) => total + o.fields.length, 0),
  screenCount: TABS.length
}));

writePage('architecture/', 'Architecture', fill(read('pages/architecture.html'), {
  objectTotal: allObjects.length,
  apexCount: apexClasses.length,
  lwcCount: lwcBundles.length
}), home);

const sharingRows = allObjects.filter((o) => o.sharing).map((o) => [`<a href="../${objectUrl(o)}">${esc(o.label)}</a>`, esc(o.sharing)]);
writePage('security/', 'Security', fill(read('pages/security.html'), { sharingTable: table(['Object', 'Sharing'], sharingRows) }), home);

writePage('develop/', 'Develop and test', read('pages/develop.html'), home);

// ---- Data model: an overview and one page per group ----
const customObjectNames = allObjects.filter((o) => o.kind === 'Custom object').map((o) => o.name);
const groupCards = domains.map((d) => ({ href: `${DOMAIN_FOLDERS[d.key]}/`, title: d.title, text: d.summary }));

writePage('data-model/', 'Data model', `
<h1>Data model</h1>
<p class="lead">${allObjects.length} objects in ${domains.length} groups. Solid lines are master-detail (child deleted with its parent); dotted lines are lookups.</p>
${erd(customObjectNames, model)}
<h2>Groups</h2>
${cards(groupCards)}`, home);

for (const domain of domains) {
  const ownObjects = allObjects.filter((o) => o.domain === domain.key);

  for (const o of ownObjects) {
    searchIndex.push({ t: `${o.label} (${o.name})`, k: 'Object', u: objectUrl(o) });
    for (const f of o.fields) searchIndex.push({ t: `${f.label} (${f.name})`, k: `Field on ${o.label}`, u: objectUrl(o) });
  }

  const summaryRows = ownObjects.map((o) => [`<a href="#${o.name}">${esc(o.label)}</a>`, esc(o.description)]);
  writePage(`data-model/${DOMAIN_FOLDERS[domain.key]}/`, domain.title, `
<h1>${esc(domain.title)}</h1>
<p class="lead">${esc(domain.summary)}</p>
${erd(domain.objects, model)}
<h2>Objects</h2>
${table(['Object', 'Purpose'], summaryRows)}
<h2>Field reference</h2>
${ownObjects.map((o) => objectDetail(o, objects)).join('')}`, [...home, ['Data model', 'data-model/']]);
}

// ---- User interface: an overview and one page per screen ----
writePage('interface/', 'User interface', `
<h1>User interface</h1>
<p class="lead">The chat window for users and one tab per admin area.</p>
${cards(TABS.map((t) => ({ href: `${t.slug}/`, title: t.title, text: t.blurb })))}`, home);

const tabTemplate = read('templates/interface-tab.html');
for (const tab of TABS) {
  const components = lwcBundles.filter((b) => startsWithAny(b, tab.lwc));
  const classes = apexClasses.filter((c) => startsWithAny(c, tab.apex));
  const tabObjects = tab.objects.filter((name) => objects[name]);

  writePage(`interface/${tab.slug}/`, tab.title, fill(tabTemplate, {
    title: esc(tab.title),
    blurb: esc(tab.blurb),
    notes: tab.notes.map((n) => `<li>${n}</li>`).join(''),
    objects: tabObjects.map((n) => `<li><a href="../../${objectUrl(objects[n])}">${esc(objects[n].label)}</a> ${code(n)}</li>`).join(''),
    apex: codeList(classes),
    lwcCount: components.length,
    lwc: codeList(components)
  }), [...home, ['User interface', 'interface/']]);
}

writeFileSync(join(siteDir, 'data/search.json'), JSON.stringify(searchIndex));
console.log(`${searchIndex.length} search entries written`);
