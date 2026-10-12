import { t, tErr, getLang } from './i18n.js';
import { TIME_ZONE } from './config.js';

// h('div.card#id', {onclick, ...attrs}, ...children)
export function h(tag, attrs, ...children) {
  if (attrs == null || typeof attrs !== 'object' || attrs instanceof Node || Array.isArray(attrs)) {
    children.unshift(attrs); attrs = {};
  }
  const [name, ...rest] = tag.split(/(?=[.#])/);
  const el = document.createElement(name || 'div');
  for (const part of rest) {
    if (part[0] === '.') el.classList.add(part.slice(1));
    else if (part[0] === '#') el.id = part.slice(1);
  }
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className += ' ' + v;
    else if (k === 'value') el.value = v;
    else if (k === 'checked') el.checked = !!v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

export function clear(el) { while (el.firstChild) el.firstChild.remove(); return el; }

// ---- Toasts ----
export function toast(msg, kind = 'ok') {
  const box = document.getElementById('toasts');
  const el = h('div.toast', { class: kind, role: 'status' }, msg);
  box.append(el);
  setTimeout(() => el.classList.add('out'), 4200);
  setTimeout(() => el.remove(), 4700);
}
export function toastErr(err) { console.error(err); toast(tErr(err), 'err'); }

// ---- Dialogs ----
export function modal(title, body, actions = []) {
  return new Promise((resolve) => {
    const close = (v) => { overlay.remove(); resolve(v); };
    const overlay = h('div.overlay', { onclick: (e) => { if (e.target === overlay) close(null); } },
      h('div.dialog', { role: 'dialog', 'aria-modal': 'true' },
        h('div.dialog-head', h('h3', title),
          h('button.icon-btn', { 'aria-label': t('close'), onclick: () => close(null) }, '×')),
        h('div.dialog-body', body),
        actions.length ? h('div.dialog-actions', actions.map((a) =>
          h('button.btn', { class: a.kind || '', onclick: async () => {
            const v = a.value ? await a.value() : true;
            if (v !== undefined && v !== false) close(v);
          } }, a.label))) : null));
    overlay.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(null); });
    document.body.append(overlay);
    const first = overlay.querySelector('input,select,textarea,button.btn');
    if (first) first.focus();
  });
}
export function confirmBox(message, okLabel = t('confirm'), danger = false) {
  return modal(t('confirm'), message instanceof Node ? message : h('p', message), [
    { label: t('back'), kind: 'ghost', value: () => null },
    { label: okLabel, kind: danger ? 'danger' : 'primary', value: () => true },
  ]).then((v) => v === true);
}

// Build a simple form. fields: [{name, label, type, value, options, required, hint, min, max}]
export function formFields(fields) {
  const form = h('form.form', { onsubmit: (e) => e.preventDefault() });
  for (const f of fields) {
    let input;
    if (f.type === 'select') {
      input = h('select', { name: f.name, required: f.required },
        f.options.map(([v, l]) => h('option', { value: v, selected: String(v) === String(f.value ?? '') }, l)));
    } else if (f.type === 'textarea') {
      input = h('textarea', { name: f.name, rows: 3, required: f.required }, f.value ?? '');
    } else if (f.type === 'days') {
      const group = h('fieldset.days', h('legend', f.label),
        f.options.map(([v, l]) => h('label.check', h('input', { type: 'checkbox', name: `${f.name}_${v}`,
          checked: (f.value || []).includes(v) }), h('span', l))));
      form.append(group);
      continue;
    } else if (f.type === 'checkbox') {
      input = h('input', { type: 'checkbox', name: f.name, checked: !!f.value });
      form.append(h('label.check', input, h('span', f.label)));
      continue;
    } else {
      input = h('input', { name: f.name, type: f.type || 'text', value: f.value ?? '', required: f.required,
        min: f.min, max: f.max, step: f.step, autocomplete: f.autocomplete, placeholder: f.placeholder });
    }
    form.append(h('label.field', h('span', f.label), input, f.hint ? h('small', f.hint) : null));
  }
  return form;
}
export function readForm(form) {
  const out = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    out[el.name] = el.type === 'checkbox' ? el.checked : el.value.trim();
  }
  return out;
}
export function formDialog(title, fields, okLabel = t('save')) {
  const form = formFields(fields);
  return modal(title, form, [
    { label: t('back'), kind: 'ghost', value: () => null },
    { label: okLabel, kind: 'primary', value: () => {
      if (!form.reportValidity()) return false;
      return readForm(form);
    } },
  ]);
}

// ---- Dates in Cairo time ----
const loc = () => (getLang() === 'ar' ? 'ar-EG' : 'en-GB');
export function fmtDate(d, opts = { weekday: 'short', day: 'numeric', month: 'short' }) {
  if (!d) return '';
  return new Intl.DateTimeFormat(loc(), { timeZone: TIME_ZONE, ...opts }).format(new Date(d));
}
export function fmtTime(d) {
  return new Intl.DateTimeFormat(getLang() === 'ar' ? 'ar-EG' : 'en-US',
    { timeZone: TIME_ZONE, hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(d));
}
export function fmtDateTime(d) { return d ? `${fmtDate(d)} · ${fmtTime(d)}` : ''; }
export function fmtMoney(n) {
  return `${new Intl.NumberFormat(loc(), { maximumFractionDigits: 0 }).format(Number(n || 0))} ${t('egp')}`;
}
export function fmtNum(n) { return new Intl.NumberFormat(loc()).format(Number(n || 0)); }
// Cairo calendar date (YYYY-MM-DD) of a timestamp
export function cairoDate(d = new Date()) {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' })
    .formatToParts(new Date(d));
  const g = (k) => p.find((x) => x.type === k).value;
  return `${g('year')}-${g('month')}-${g('day')}`;
}
// Convert a Cairo local date + time ("2026-10-13", "18:00") to an ISO timestamp
export function cairoToISO(dateStr, timeStr) {
  const guess = new Date(`${dateStr}T${timeStr}:00Z`);
  const asCairo = new Date(guess.toLocaleString('en-US', { timeZone: TIME_ZONE }));
  const asUTC = new Date(guess.toLocaleString('en-US', { timeZone: 'UTC' }));
  return new Date(guess.getTime() - (asCairo - asUTC)).toISOString();
}
export function cairoTimeHM(d) {
  return new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, hour: '2-digit', minute: '2-digit', hour12: false })
    .format(new Date(d));
}
export function ageYears(dob) {
  if (!dob) return null;
  const today = cairoDate();
  const [y, m, d] = dob.split('-').map(Number);
  const [ty, tm, td] = today.split('-').map(Number);
  return ty - y - (tm < m || (tm === m && td < d) ? 1 : 0);
}

// Tabs: [{key, label, render(container)}]
export function tabs(container, items, initial) {
  const bar = h('nav.tabs', { role: 'tablist' });
  const panel = h('section.panel');
  let current = null;
  const show = async (key) => {
    current = key;
    for (const b of bar.children) b.setAttribute('aria-selected', b.dataset.key === key ? 'true' : 'false');
    clear(panel).append(h('p.muted', t('loading')));
    const item = items.find((i) => i.key === key);
    const box = h('div');
    try { await item.render(box); clear(panel).append(box); }
    catch (e) { clear(panel).append(h('p.error', tErr(e))); console.error(e); }
    try { sessionStorage.setItem('kfk_tab', key); } catch {}
  };
  for (const i of items) {
    bar.append(h('button.tab', { role: 'tab', 'data-key': i.key, onclick: () => show(i.key) },
      i.label, i.badge ? h('span.badge', i.badge) : null));
  }
  container.append(bar, panel);
  let start = initial || items[0].key;
  try { const saved = sessionStorage.getItem('kfk_tab'); if (items.some((i) => i.key === saved)) start = saved; } catch {}
  show(start);
  return { reload: () => show(current), show };
}

export function empty(msg) { return h('p.empty', msg); }
