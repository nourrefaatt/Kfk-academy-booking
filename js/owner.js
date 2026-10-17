// Owner: dashboard, accounts, settings
import { sb, rpc, q, state } from './api.js';
import { t } from './i18n.js';
import { h, clear, toast, toastErr, confirmBox, formDialog, formFields, readForm, fmtDate, fmtMoney, fmtNum,
  fmtDateTime, cairoDate, cairoToISO, ageYears, empty } from './ui.js';
import { memberFields } from './member.js';

const pct = (a, b) => (b ? Math.round(((a - b) / b) * 100) : null);
function change(cur, prev) {
  const p = pct(Number(cur), Number(prev));
  if (p == null) return h('small.muted', '—');
  return h('small', { class: p >= 0 ? 'up' : 'down' }, `${p >= 0 ? '▲' : '▼'} ${Math.abs(p)}% `, t('vs_last_month'));
}
const rate = (a, b) => (b ? `${Math.round((a / b) * 100)}%` : '—');

// ---------- Dashboard ----------
export async function renderDashboard(box) {
  let month = cairoDate().slice(0, 7);
  const body = h('div');
  const input = h('input', { type: 'month', value: month, onchange: () => { month = input.value; load(); } });
  box.append(h('div.section-head', h('h2', t('tab_dashboard')), h('label.inline', input)), body);

  async function load() {
    clear(body).append(h('p.muted', t('loading')));
    const s = await rpc('owner_stats', { p_month: `${month}-01` });
    clear(body);
    const marked = Number(s.attended) + Number(s.no_show);
    body.append(h('div.stats.big',
      h('div.stat', h('small', t('revenue')), h('strong', fmtMoney(s.revenue)), change(s.revenue, s.revenue_prev)),
      h('div.stat', h('small', `${t('revenue')} · ${t('adults')}`), h('strong', fmtMoney(s.revenue_adults)),
        change(s.revenue_adults, s.revenue_prev_adults)),
      h('div.stat', h('small', `${t('revenue')} · ${t('kids')}`), h('strong', fmtMoney(s.revenue_kids)),
        change(s.revenue_kids, s.revenue_prev_kids)),
      h('div.stat', h('small', t('pending_tx')), h('strong', fmtNum(s.pending_count)), h('small.muted', fmtMoney(s.pending_amount))),
      h('div.stat', h('small', t('total_bookings')), h('strong', fmtNum(s.bookings_month)),
        h('small.muted', `${fmtNum(s.bookings_total)} ${t('all_time')}`)),
      h('div.stat', h('small', t('active_packages')), h('strong', fmtNum(s.active_packages))),
      h('div.stat', h('small', t('active_members')), h('strong', fmtNum(Number(s.active_adults) + Number(s.active_kids))),
        h('small.muted', `${t('adults')} ${s.active_adults} · ${t('kids')} ${s.active_kids}`)),
      h('div.stat', h('small', t('retention')), h('strong', rate(s.retention_kept, s.retention_base)),
        h('small.muted', `${s.retention_kept}/${s.retention_base} · ${t('retention_hint')}`)),
      h('div.stat', h('small', t('attendance_rate')), h('strong', rate(s.attended, marked))),
      h('div.stat', h('small', t('no_show_rate')), h('strong', rate(s.no_show, marked)))));
    body.append(h('p.muted.small', t('test_payments_note')));

    // Revenue by month: one bar series (total), adults/kids as numbers
    const rows = s.revenue_by_month || [];
    body.append(h('h2', t('revenue_by_month')));
    if (!rows.length) body.append(empty('—'));
    else {
      const max = Math.max(...rows.map((r) => Number(r.adults) + Number(r.kids)), 1);
      body.append(h('div.table-wrap', h('table.bars',
        h('thead', h('tr', h('th', t('month')), h('th', t('total')), h('th', t('adults')), h('th', t('kids')))),
        h('tbody', rows.map((r) => {
          const total = Number(r.adults) + Number(r.kids);
          return h('tr', { title: `${fmtMoney(total)}` },
            h('td', fmtDate(r.month + 'T12:00:00Z', { month: 'short', year: 'numeric' })),
            h('td.bar-cell', h('div.bar-wrap', h('div.bar-track', h('span.bar', { style: `width:${Math.max(2, (total / max) * 100)}%` })),
              h('span', fmtMoney(total)))),
            h('td', fmtMoney(r.adults)), h('td', fmtMoney(r.kids)));
        })))));
    }

    body.append(h('div.two-col',
      h('div', h('h2', t('popular')), s.popular_classes.length ? h('ol.plain', s.popular_classes.map((c) =>
        h('li', h('strong', c.name), h('small.muted', ` · ${t(c.audience)} · ${c.bookings}`)))) : empty('—')),
      h('div', h('h2', t('cancelled_by_coach'), ' ', h('span.count', s.cancelled_by_coach.length)),
        s.cancelled_by_coach.length ? h('ul.plain', s.cancelled_by_coach.map((c) =>
          h('li', h('strong', c.name), h('small.muted', ` · ${fmtDateTime(c.starts_at)}${c.reason ? ' · ' + c.reason : ''}`))))
          : empty('—'))));
  }
  load();
}

// ---------- Accounts ----------
export async function renderAccounts(box, refresh) {
  const [profiles, members] = await Promise.all([
    q(sb.from('profiles').select('*').order('created_at', { ascending: false })),
    q(sb.from('members').select('*').order('full_name')),
  ]);
  const search = h('input', { type: 'search', placeholder: t('search'), oninput: () => draw() });
  const list = h('div');
  box.append(h('div.section-head', h('h2', t('tab_accounts')), h('label.inline', search)),
    h('p.muted', t('make_coach_hint')), list);

  function draw() {
    clear(list);
    const term = search.value.toLowerCase();
    for (const p of profiles) {
      const mine = members.filter((m) => m.account_id === p.id);
      const hay = [p.full_name, p.email, p.phone, ...mine.map((m) => m.full_name)].join(' ').toLowerCase();
      if (term && !hay.includes(term)) continue;
      list.append(accountCard(p, mine, refresh));
    }
  }
  draw();
}

function accountCard(p, mine, refresh) {
  const details = h('div.members');
  let open = false;
  const roleSel = h('select', { 'aria-label': t('role'), disabled: p.id === state.user.id, onchange: async () => {
    try { await rpc('set_role', { p_user: p.id, p_role: roleSel.value }); toast(t('saved')); }
    catch (e) { toastErr(e); roleSel.value = p.role; }
  } }, ['client', 'parent', 'coach', 'owner'].map((r) => h('option', { value: r, selected: r === p.role }, t('role_' + r))));
  return h('article.card',
    h('header',
      h('button.link', { onclick: async () => {
        open = !open; clear(details);
        if (open) await drawMembers(details, mine, refresh);
      } }, h('strong', p.full_name || p.email), ' ', h('small.muted', [p.email, p.phone].filter(Boolean).join(' · ')),
        mine.length ? h('span.count', mine.length) : null),
      h('div.row', roleSel,
        h('button.btn.ghost.sm', { onclick: () => editAccount(p, mine, refresh) }, t('edit')),
        p.id === state.user.id ? null : h('button.btn.ghost.sm', { onclick: async () => {
          try { await rpc('set_account_active', { p_user: p.id, p_active: !p.active }); refresh(); } catch (e) { toastErr(e); }
        } }, p.active ? t('deactivate') : t('activate')),
        p.active ? null : h('span.pill.grey', t('inactive')))),
    details);
}

// Change an account's name / phone (and the matching adult member's name)
export async function editAccount(p, mine, refresh) {
  const v = await formDialog(`${t('edit')}: ${p.full_name || p.email}`, [
    { name: 'full_name', label: t('full_name'), value: p.full_name, required: true },
    { name: 'phone', label: t('phone'), type: 'tel', value: p.phone },
  ]);
  if (!v) return;
  try {
    await q(sb.from('profiles').update({ full_name: v.full_name, phone: v.phone || null }).eq('id', p.id));
    const adult = (mine || []).find((m) => m.kind === 'adult');
    if (adult) await q(sb.from('members').update({ full_name: v.full_name, phone: v.phone || null }).eq('id', adult.id));
    if (p.id === state.user.id) Object.assign(state.profile, v);
    toast(t('saved'));
    if (p.id === state.user.id) location.reload(); else refresh();
  } catch (e) { toastErr(e); }
}

async function drawMembers(box, mine, refresh) {
  if (!mine.length) { box.append(h('p.muted', '—')); return; }
  for (const m of mine) {
    let bal = null;
    try { bal = await rpc('member_balance', { p_member: m.id }); } catch {}
    const age = ageYears(m.date_of_birth);
    box.append(h('div.member-row',
      h('div', h('strong', m.full_name), ' ',
        h('small.muted', [t('kind_' + m.kind), age != null ? `${age}y` : null,
          bal ? `${t('sessions_left')}: ${bal.sessions_left}` : null,
          bal && (Number(bal.private_left) || bal.in_private_group) ? `${t('private_left')}: ${bal.private_left}` : null,
          bal?.next_expiry ? `${t('expires')}: ${fmtDate(bal.next_expiry)}` : null].filter(Boolean).join(' · ')),
        m.kind === 'child' && age != null && age >= 13 ? h('span.pill.warn', t('turned_13')) : null,
        m.active ? null : h('span.pill.grey', t('inactive'))),
      h('div.row',
        h('button.btn.ghost.sm', { onclick: async () => {
          const v = await formDialog(`${t('edit')}: ${m.full_name}`, memberFields(m));
          if (!v) return;
          if (!v.date_of_birth) v.date_of_birth = null;
          try { await q(sb.from('members').update(v).eq('id', m.id)); toast(t('saved')); refresh(); } catch (e) { toastErr(e); }
        } }, t('edit')),
        h('button.btn.ghost.sm', { onclick: () => adjust(m, refresh) }, t('adjust_balance')),
        h('button.btn.ghost.sm', { onclick: async () => {
          try { await rpc('set_member_active', { p_member: m.id, p_active: !m.active }); refresh(); } catch (e) { toastErr(e); }
        } }, m.active ? t('deactivate') : t('activate')),
        h('button.btn.danger.sm', { onclick: async () => {
          if (!(await confirmBox(t('delete_member_confirm'), t('delete'), true))) return;
          try { await rpc('delete_member', { p_member: m.id }); refresh(); } catch (e) { toastErr(e); }
        } }, t('delete')))));
  }
}

async function adjust(m, refresh) {
  const v = await formDialog(`${t('adjust_balance')}: ${m.full_name}`, [
    { name: 'sessions', label: t('add_sessions'), type: 'number', value: 0 },
    { name: 'expires', label: t('new_expiry'), type: 'date' },
    { name: 'weekly', label: t('weekly_limit'), type: 'number', min: 1 },
    { name: 'note', label: t('note') },
    { name: 'private', label: t('adjust_private'), type: 'checkbox', value: false },
  ]);
  if (!v) return;
  try {
    await rpc('adjust_balance_kind', { p_member: m.id, p_sessions: Number(v.sessions || 0),
      p_expires_at: v.expires ? cairoToISO(v.expires, '23:59') : null,
      p_weekly_limit: v.weekly ? Number(v.weekly) : null, p_note: v.note || null, p_private: !!v.private });
    toast(t('saved')); refresh();
  } catch (e) { toastErr(e); }
}

// ---------- Settings ----------
export async function renderSettings(box, refresh) {
  const st = state.settings;
  const form = formFields([
    { name: 'bookings_locked', label: t('lock_bookings'), type: 'checkbox', value: st.bookings_locked },
    { name: 'payments_locked', label: t('lock_payments'), type: 'checkbox', value: st.payments_locked },
    { name: 'online_test_mode', label: t('online_test'), type: 'checkbox', value: st.online_test_mode },
  ]);
  box.append(h('h2', t('tab_settings')), form, h('button.btn.primary', { onclick: async () => {
    const v = readForm(form);
    try {
      await rpc('save_settings', { p_bookings_locked: v.bookings_locked, p_payments_locked: v.payments_locked,
        p_online_test_mode: v.online_test_mode });
      Object.assign(st, v); toast(t('saved'));
    } catch (e) { toastErr(e); }
  } }, t('save')));

  box.append(h('h2', t('prices')));
  const all = await q(sb.from('packages').select('*').order('audience').order('sort'));
  for (const p of all) {
    const input = h('input', { type: 'number', min: 0, value: p.price_egp, 'aria-label': p.name_en });
    box.append(h('div.member-row',
      h('div', h('strong', `${t(p.audience)} · ${document.documentElement.lang === 'ar' ? p.name_ar : p.name_en}`),
        h('small.muted', ` · ${t('sessions_n', { n: p.sessions })}`,
          p.weekly_limit ? ` · ${t('per_week', { n: p.weekly_limit })}` : '',
          p.validity_days ? ` · ${t('valid_days', { n: p.validity_days })}` : '')),
      h('div.row', input, h('span', t('egp')), h('button.btn.ghost.sm', { onclick: async () => {
        try { await rpc('save_package_price', { p_code: p.code, p_price: Number(input.value) }); toast(t('saved')); }
        catch (e) { toastErr(e); }
      } }, t('save')))));
  }
}
