// Panels for one trainee (an adult client, or a parent's child)
import { sb, rpc, q, state } from './api.js';
import { t } from './i18n.js';
import { h, formFields, readForm, toast, toastErr, confirmBox, formDialog, fmtDate, fmtTime, fmtDateTime,
  fmtMoney, cairoDate, empty } from './ui.js';

export function weekStart(dateStr = cairoDate()) {
  const d = new Date(dateStr + 'T12:00:00Z');
  const back = (d.getUTCDay() + 1) % 7;           // Saturday-based week
  d.setUTCDate(d.getUTCDate() - back);
  return d.toISOString().slice(0, 10);
}
export function addDays(dateStr, n) {
  const d = new Date(dateStr + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
export function placeOf(cls) {
  const name = cls?.location || state.settings?.location_name || '';
  const s = state.settings;
  if (s?.location_lat && s?.location_lng && (!cls?.location || cls.location === s.location_name)) {
    return h('a', { href: `https://maps.google.com/?q=${s.location_lat},${s.location_lng}`, target: '_blank',
      rel: 'noopener' }, name);
  }
  return name;
}
const audienceOf = (m) => (m.kind === 'child' ? 'kids' : 'adults');

// ---------- Book a class ----------
export async function renderBook(box, member, refresh) {
  const ws = weekStart(); const we = addDays(ws, 6);
  const [sessions, counts, mine, waits] = await Promise.all([
    q(sb.from('sessions').select('*, classes!inner(*)').gte('session_date', ws).lte('session_date', we)
      .eq('classes.audience', audienceOf(member)).eq('classes.active', true).order('starts_at')),
    rpc('session_counts', { p_from: ws, p_to: we }),
    q(sb.from('bookings').select('id, session_id, status').eq('member_id', member.id)
      .in('status', ['booked', 'attended', 'no_show', 'late_cancel'])),
    q(sb.from('waitlist').select('session_id').eq('member_id', member.id)),
  ]);
  const bal = await rpc('member_balance', { p_member: member.id });
  const countOf = Object.fromEntries(counts.map((c) => [c.session_id, c]));
  const booked = new Map(mine.map((b) => [b.session_id, b]));
  const waiting = new Set(waits.map((w) => w.session_id));

  box.append(balanceStrip(bal),
    h('div.section-head', h('h2', t('this_week')), h('p.muted', t('week_note'))));
  if (state.settings.bookings_locked) box.append(h('p.notice', t('bookings_closed')));

  const visible = sessions.filter((s) => !s.classes.locked);
  if (!visible.length) { box.append(empty(t('no_classes'))); return; }

  let lastDay = '';
  const list = h('div.session-list');
  for (const s of visible) {
    if (s.session_date !== lastDay) {
      lastDay = s.session_date;
      list.append(h('h3.day', fmtDate(s.starts_at, { weekday: 'long', day: 'numeric', month: 'long' })));
    }
    const c = countOf[s.id] || { booked: 0, waiting: 0 };
    const ended = new Date(s.ends_at) <= new Date();
    const isFull = s.capacity != null && c.booked >= s.capacity;
    let action;
    if (s.status === 'cancelled') action = h('span.pill.grey', t('cancelled'));
    else if (booked.has(s.id)) action = h('span.pill.ok', t('booked'));
    else if (ended) action = h('span.pill.grey', t('class_ended'));
    else if (waiting.has(s.id)) action = h('button.btn.ghost.sm', { onclick: async () => {
      try { await rpc('leave_waitlist', { p_member: member.id, p_session: s.id }); refresh(); }
      catch (e) { toastErr(e); } } }, t('leave_waitlist'));
    else action = h('button.btn.primary.sm', { onclick: async (e) => {
      e.target.disabled = true;
      try {
        const r = await rpc('book_session', { p_member: member.id, p_session: s.id });
        toast(r === 'waitlisted' ? t('waitlisted_ok') : t('booked_ok'));
        refresh();
      } catch (err) { toastErr(err); e.target.disabled = false; }
    } }, isFull ? t('join_waitlist') : t('book'));

    const spots = s.capacity == null ? t('unlimited')
      : isFull ? t('full') : t('spots_left', { n: s.capacity - c.booked });
    list.append(h('article.session', { class: s.status === 'cancelled' ? 'is-cancelled' : '' },
      h('div.when', h('strong', fmtTime(s.starts_at)), h('small', `${Math.round((new Date(s.ends_at) - new Date(s.starts_at)) / 60000)}′`)),
      h('div.what', h('strong', s.classes.name), h('small', placeOf(s.classes), ' · ', spots,
        waiting.has(s.id) ? ` · ${t('on_waitlist')}` : '')),
      h('div.act', action)));
  }
  box.append(list);
}

export function balanceStrip(bal) {
  const left = Number(bal.sessions_left || 0);
  return h('div.stats',
    h('div.stat', h('small', t('sessions_left')), h('strong', left)),
    h('div.stat', h('small', t('expires')), h('strong', bal.next_expiry ? fmtDate(bal.next_expiry) : (left ? t('no_expiry') : '—'))),
    h('div.stat', h('small', t('this_week_used')),
      h('strong', bal.weekly_limit ? `${bal.used_this_week} / ${bal.weekly_limit}` : bal.used_this_week)),
    left ? null : h('p.notice.full', t('no_balance')));
}

// ---------- My bookings ----------
export async function renderBookings(box, member, refresh) {
  const rows = await q(sb.from('bookings').select('*, sessions(*, classes(*))').eq('member_id', member.id)
    .order('created_at', { ascending: false }).limit(100));
  const waits = await q(sb.from('waitlist').select('*, sessions(*, classes(*))').eq('member_id', member.id));
  const now = new Date();
  const upcoming = rows.filter((b) => b.status === 'booked' && new Date(b.sessions.ends_at) > now)
    .sort((a, b) => new Date(a.sessions.starts_at) - new Date(b.sessions.starts_at));
  const past = rows.filter((b) => !upcoming.includes(b));

  box.append(h('h2', t('upcoming'), ' ', h('span.count', upcoming.length)));
  if (!upcoming.length && !waits.length) box.append(empty(t('no_bookings')));
  const list = h('div.session-list');
  for (const b of upcoming) {
    const s = b.sessions;
    const late = new Date(s.starts_at) - now < 3 * 3600 * 1000;
    list.append(h('article.session',
      h('div.when', h('strong', fmtDate(s.starts_at)), h('small', fmtTime(s.starts_at))),
      h('div.what', h('strong', s.classes.name), h('small', t('place'), ': ', placeOf(s.classes))),
      h('div.act', new Date(s.starts_at) > now ? h('button.btn.ghost.sm', { onclick: async () => {
        if (!(await confirmBox(late ? t('cancel_late') : t('cancel_free'), t('cancel_booking'), late))) return;
        try {
          const r = await rpc('cancel_booking', { p_booking: b.id });
          toast(r === 'late_cancel' ? t('late_cancel_ok') : t('cancelled_ok'));
          refresh();
        } catch (e) { toastErr(e); }
      } }, t('cancel_booking')) : null)));
  }
  for (const w of waits) {
    const s = w.sessions;
    list.append(h('article.session.waiting',
      h('div.when', h('strong', fmtDate(s.starts_at)), h('small', fmtTime(s.starts_at))),
      h('div.what', h('strong', s.classes.name), h('small', t('on_waitlist'))),
      h('div.act', h('button.btn.ghost.sm', { onclick: async () => {
        try { await rpc('leave_waitlist', { p_member: member.id, p_session: s.id }); refresh(); }
        catch (e) { toastErr(e); } } }, t('leave_waitlist')))));
  }
  box.append(list);

  if (past.length) {
    box.append(h('h2', t('past')));
    box.append(h('div.table-wrap', h('table',
      h('thead', h('tr', h('th', t('date')), h('th', t('class_name')), h('th', ''))),
      h('tbody', past.map((b) => h('tr',
        h('td', fmtDateTime(b.sessions.starts_at)), h('td', b.sessions.classes.name),
        h('td', h('span.pill', { class: statusClass(b.status) }, t('status_' + b.status)))))))));
  }
}
export function statusClass(s) {
  return { booked: 'ok', attended: 'ok', cancelled: 'grey', cancelled_by_coach: 'grey',
    late_cancel: 'warn', no_show: 'warn' }[s] || '';
}

// ---------- Balance & payments ----------
export async function renderBalance(box, member, refresh) {
  const [bal, pays] = await Promise.all([
    rpc('member_balance', { p_member: member.id }),
    q(sb.from('payments').select('*, packages(name_en, name_ar)').eq('member_id', member.id)
      .order('created_at', { ascending: false })),
  ]);
  box.append(balanceStrip(bal));
  const pending = pays.find((p) => p.status === 'pending');
  if (pending) box.append(h('p.notice', t('cash_pending')));
  if (state.settings.payments_locked) box.append(h('p.notice', t('payments_closed')));

  box.append(h('h2', t('packages')));
  const pk = state.packages.filter((p) => p.audience === audienceOf(member));
  const grid = h('div.package-grid');
  for (const p of pk) {
    const lang = document.documentElement.lang;
    const hasLeft = Number(bal.sessions_left) > 0;
    grid.append(h('article.package',
      h('h3', lang === 'ar' ? p.name_ar : p.name_en),
      h('div.price', fmtMoney(p.price_egp)),
      h('ul',
        h('li', p.sessions === 1 ? t('one_session') : t('sessions_n', { n: p.sessions })),
        p.weekly_limit ? h('li', t('per_week', { n: p.weekly_limit })) : null,
        p.validity_days ? h('li', t('valid_days', { n: p.validity_days })) : null),
      !p.is_drop_in && hasLeft ? h('small.muted', t('early_recharge_note')) : null,
      h('div.package-actions',
        h('button.btn.primary', { disabled: !!pending || state.settings.payments_locked,
          onclick: () => buy(member, p, 'online', refresh) },
          t('pay_online'), state.settings.online_test_mode ? h('small.tag', t('test_mode')) : null),
        h('button.btn.ghost', { disabled: !!pending || state.settings.payments_locked,
          onclick: () => buy(member, p, 'cash', refresh) }, t('pay_cash')))));
  }
  box.append(grid);

  box.append(h('h2', t('payment_history')));
  if (!pays.length) { box.append(empty(t('no_payments'))); return; }
  box.append(h('div.table-wrap', h('table',
    h('thead', h('tr', h('th', t('invoice')), h('th', t('date')), h('th', t('packages')), h('th', t('total')), h('th', ''))),
    h('tbody', pays.map((p) => h('tr',
      h('td', '#' + p.invoice_no), h('td', fmtDate(p.created_at, { day: 'numeric', month: 'short', year: 'numeric' })),
      h('td', (document.documentElement.lang === 'ar' ? p.packages?.name_ar : p.packages?.name_en) || p.package_code,
        ' · ', t('method_' + p.method), p.test_mode ? ` (${t('test_mode')})` : ''),
      h('td', fmtMoney(p.amount_egp)),
      h('td', h('span.pill', { class: { paid: 'ok', pending: 'warn', rejected: 'grey' }[p.status] }, t('pay_' + p.status)),
        p.note ? h('small.muted', ' ' + p.note) : null)))))));
}

async function buy(member, pkg, method, refresh) {
  if (method === 'online' && !state.settings.online_test_mode) { toast(t('online_unavailable'), 'err'); return; }
  const label = `${document.documentElement.lang === 'ar' ? pkg.name_ar : pkg.name_en} — ${fmtMoney(pkg.price_egp)}`;
  const msg = method === 'online'
    ? `${label}\n${t('pay_online')}${state.settings.online_test_mode ? ` (${t('test_mode')})` : ''}`
    : `${label}\n${t('pay_cash')}`;
  if (!(await confirmBox(msg, method === 'online' ? t('pay_online') : t('pay_cash')))) return;
  try {
    const r = await rpc('purchase', { p_member: member.id, p_package: pkg.code, p_method: method });
    toast(r.status === 'paid' ? t('paid_ok') : t('cash_pending'));
    refresh();
  } catch (e) { toastErr(e); }
}

// ---------- Profile ----------
export function memberFields(m, withDob = true) {
  return [
    { name: 'full_name', label: t('full_name'), value: m.full_name, required: true },
    withDob ? { name: 'date_of_birth', label: t('dob'), type: 'date', value: m.date_of_birth } : null,
    m.kind === 'adult' ? { name: 'phone', label: t('phone'), type: 'tel', value: m.phone } : null,
    { name: 'emergency_contact', label: t('emergency'), value: m.emergency_contact },
    { name: 'medical_notes', label: t('medical'), type: 'textarea', value: m.medical_notes },
    { name: 'experience', label: t('experience'), type: 'textarea', value: m.experience },
  ].filter(Boolean);
}
export async function renderProfile(box, member, refresh) {
  const form = formFields(memberFields(member));
  box.append(h('h2', t('tab_profile')), form,
    h('button.btn.primary', { onclick: async () => {
      if (!form.reportValidity()) return;
      const v = readForm(form);
      if (!v.date_of_birth) v.date_of_birth = null;
      try {
        await q(sb.from('members').update(v).eq('id', member.id));
        if (member.kind === 'adult') {
          await q(sb.from('profiles').update({ full_name: v.full_name, phone: v.phone || null }).eq('id', state.user.id));
        }
        Object.assign(member, v);
        toast(t('profile_saved'));
        refresh && refresh();
      } catch (e) { toastErr(e); }
    } }, t('save')));
}

// ---------- Notifications ----------
export async function renderNotifications(box, onRead) {
  const rows = await q(sb.from('notifications').select('*').eq('account_id', state.user.id)
    .order('created_at', { ascending: false }).limit(100));
  const unread = rows.filter((r) => !r.read_at);
  box.append(h('div.section-head', h('h2', t('tab_notifications')),
    unread.length ? h('button.btn.ghost.sm', { onclick: async () => {
      try {
        await q(sb.from('notifications').update({ read_at: new Date().toISOString() })
          .eq('account_id', state.user.id).is('read_at', null));
        onRead && onRead();
      } catch (e) { toastErr(e); }
    } }, t('mark_read')) : null));
  if (!rows.length) { box.append(empty(t('no_notifications'))); return; }
  box.append(h('div.notes', rows.map((n) => h('article.note', { class: n.read_at ? '' : 'unread' },
    h('div', h('strong', n.title), h('small.muted', fmtDateTime(n.created_at))),
    n.body ? h('p', n.body) : null))));
}
