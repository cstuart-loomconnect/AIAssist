// Wraps page content in the shared header, sidebar and footer links, and writes it to site/<url>/index.html.
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { esc, fill } from './html.mjs';

const layout = readFileSync(new URL('../templates/layout.html', import.meta.url), 'utf8');

export function createSite({ siteDir, navigation }) {
  const flat = navigation.flatMap((item) => [item, ...(item.children ?? [])]);
  const searchIndex = [];

  const link = (rel, item, extra = '') => `<a href="${rel}${item.url}" ${extra}>${esc(item.title)}</a>`;

  function sidebar(url, rel) {
    return navigation
      .map((item) => {
        const open = item.children && (url === item.url || url.startsWith(item.url));
        const current = (i) => (url === i.url ? 'current' : '');
        const children = open ? item.children.map((c) => link(rel, c, `class="sub ${current(c)}"`)).join('') : '';
        return link(rel, item, `class="${current(item)}"`) + children;
      })
      .join('');
  }

  function pager(url, rel) {
    const i = flat.findIndex((item) => item.url === url);
    if (i < 0) return '';
    const previous = flat[i - 1] ? `<a href="${rel}${flat[i - 1].url}">← ${esc(flat[i - 1].title)}</a>` : '<span></span>';
    const next = flat[i + 1] ? `<a href="${rel}${flat[i + 1].url}">${esc(flat[i + 1].title)} →</a>` : '';
    return `<div class="pager">${previous}${next}</div>`;
  }

  function writePage(url, title, body, breadcrumbs = []) {
    const rel = '../'.repeat(url.split('/').filter(Boolean).length);
    const crumbs = breadcrumbs.length
      ? `<div class="crumbs">${breadcrumbs.map(([text, to]) => `<a href="${rel}${to}">${esc(text)}</a>`).join(' / ')}</div>`
      : '';
    mkdirSync(join(siteDir, url), { recursive: true });
    writeFileSync(
      join(siteDir, url, 'index.html'),
      fill(layout, { title: esc(title), rel, nav: sidebar(url, rel), crumbs, body, pager: pager(url, rel) })
    );
    searchIndex.push({ t: title, k: 'Page', u: url });
  }

  return { writePage, searchIndex };
}
