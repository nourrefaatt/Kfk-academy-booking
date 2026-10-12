// Coach portal (the owner gets all of this too)
import { sb, rpc, q, state } from './api.js';
import { t } from './i18n.js';
import { h, clear, toast, toastErr, confirmBox, formDialog, modal, formFields, readForm, fmtDate, fmtTime,
  fmtDateTime, fmtMoney, cairoDate, cairoToISO, cairoTimeHM, ageYears, empty } from './ui.js';
import { statusClass } from './member.js';

const LIVE = ['booked', 'attended', 'no_show', 'late_cancel'];

// ---------- Day ----------
export async function renderDay(box) {
  let day = cairoDate();
  try { day = sessionStorage.getItem('kfk_day') || day; } catch {}
  const body = h('div');
  const input = h('input', { type: 'date', value: day, onchange: () => {
    day = input.value; try { sessionStorage.setItem('kfk_day', day); } catch {} load();
  } });
  box.append(h('div.section-head', h('h2', t('tab_day')), h('label.inline', input)), body);

  async function load() {
    clear(body).append(h('p.muted', t('loading')));
    try { await rpc('ensure_sessions'); } catch {}
    const sessions = await q(sb.from('sessions').select('*, classes(*)').eq('session_date', day).order('starts_at'));
    const ids = sessions.map((s) => s.id);
    const [bookings, waits] = ids.length ? await Promise.all([
      q(sb.from('bookings').select('*, members(id, full_name, kind, phone, medical_notes, date_of_birth, account_id)')
        .in('session_id', ids).in('status', [...LIVE, 'cancelled', 'cancelled_by_coach'])),
      q(sb.from('waitlist').select('*, members(full_name)').in('session_id', ids).order('created_at')),
    ]) : [[], []];
    clear(body);
    const live = sessions.filter((s) => s.status === 'scheduled');
    const now = new Date();
    const attendees = bookings.filter((b) => LIVE.includes(b.status) && b.status !== 'late_cancel').length;
    body.append(h('div.stats',
      h('div.stat', h('small', t('classes_today')), h('strong', live.length)),
      h('div.stat', h('small', t('classes_left')), h('strong', live.filter((s) => new Date(s.starts_at) > now).length)),
      h('div.stat', h('small', t('attendees')), h('strong', attendees))));
    if (!sessions.length) { body.append(empty(t('no_classes'))); return; }
    for (const s of sessions) body.append(sessionCard(s, bookings.filter((b) => b.session_id === s.id),
      waits.filter((w) => w.session_id === s.id), load));
  }
  load();
}

function sessionCard(s, bookings, waits, reload) {
  const live = bookings.filter((b) => LIVE.includes(b.status));
  const cancelled = s.status === 'cancelled';
  const cap = s.capacity == null ? '∞' : s.capacity;
  const card = h('article.card.class-card', { class: cancelled ? 'is-cancelled' : '' },
    h('header',
      h('div', h('h3', s.classes.name, s.classes.locked ? h('span.pill.grey', t('locked')) : null),
        h('small.muted', `${fmtTime(s.starts_at)}–${fmtTime(s.ends_at)} · ${t(s.classes.audience)} · `,
          `${live.length} / ${cap}`, waits.length ? ` · ${t('waitlist')}: ${waits.length}` : '')),
      cancelled ? h('span.pill.grey', t('cancelled')) : h('div.row',
        h('button.btn.ghost.sm', { onclick: () => editSession(s, reload) }, t('edit')),
        h('button.btn.danger.sm', { onclick: () => cancelSession(s, reload) }, t('cancel_class')))));
  if (cancelled) {
    card.append(h('p.muted', s.cancel_reason ? `${t('reason')}: ${s.cancel_reason}` : ''));
    return card;
  }
  if (!live.length) card.append(h('p.muted', t('no_bookings')));
  const list = h('ul.attendance');
  for (const b of live.sort((a, z) => a.members.full_name.localeCompare(z.members.full_name))) {
    const m = b.members;
    const age = ageYears(m.date_of_birth);
    list.append(h('li', { class: b.status },
      h('div', h('strong', m.full_name),
        h('small.muted', [age != null ? `${age}y` : null, m.phone, m.medical_notes ? `⚕ ${m.medical_notes}` : null]
          .filter(Boolean).join(' · '))),
      b.status === 'late_cancel' ? h('span.pill.warn', t('status_late_cancel')) : h('div.row',
        h('button.btn.sm', { class: b.status === 'attended' ? 'primary' : 'ghost',
          'aria-pressed': b.status === 'attended' ? 'true' : 'false',
          onclick: () => mark(b.id, true, reload) }, '✓ ', t('came')),
        h('button.btn.sm', { class: b.status === 'no_show' ? 'danger' : 'ghost',
          'aria-pressed': b.status === 'no_show' ? 'true' : 'false',
          onclick: () => mark(b.id, false, reload) }, '✕ ', t('no_show')))));
  }
  card.append(list);
  if (waits.length) card.append(h('p.muted', `${t('waitlist')}: `, waits.map((w) => w.members.full_name).join(', ')));
  return card;
}
async function mark(id, attended, reload) {
  try { await rpc('set_attendance', { p_booking: id, p_attended: attended }); reload(); } catch (e) { toastErr(e); }
}
async function cancelSession(s, reload) {
  const v = await formDialog(`${t('cancel_class')}: ${s.classes.name} — ${fmtDateTime(s.starts_at)}`,
    [{ name: 'reason', label: t('cancel_reason'), type: 'textarea' }], t('cancel_class'));
  if (!v) return;
  if (!(await confirmBox(t('cancel_class_confirm'), t('cancel_class'), true))) return;
  try {
    const n = await rpc('cancel_session', { p_session: s.id, p_reason: v.reason || null });
    toast(t('class_cancelled_ok', { n })); reload();
  } catch (e) { toastErr(e); }
}
async function editSession(s, reload) {
  const v = await formDialog(`${t('edit_session')}: ${s.classes.name}`, [
    { name: 'date', label: t('date'), type: 'date', value: s.session_date, required: true },
    { name: 'time', label: t('start'), type: 'time', value: cairoTimeHM(s.starts_at), required: true },
    { name: 'duration', label: t('duration_min'), type: 'number', min: 5,
      value: Math.round((new Date(s.ends_at) - new Date(s.starts_at)) / 60000), required: true },
    { name: 'capacity', label: t('capacity'), type: 'number', min: 1, value: s.capacity ?? '', hint: t('capacity_hint') },
  ]);
  if (!v) return;
  try {
    await rpc('update_session', { p_session: s.id, p_start: cairoToISO(v.date, v.time),
      p_duration: Number(v.duration), p_capacity: v.capacity ? Number(v.capacity) : null });
    toast(t('saved')); reload();
  } catch (e) { toastErr(e); }
}

// ---------- Weekly classes ----------
const WEEK_ORDER = [6, 0, 1, 2, 3, 4, 5]; // Saturday first
export async function renderClasses(box, refresh) {
  const [classes, coaches] = await Promise.all([
    q(sb.from('classes').select('*, profiles(full_name)').eq('active', true).order('start_time')),
    q(sb.from('profiles').select('id, full_name, role').in('role', ['coach', 'owner']).eq('active', true)),
  ]);
  box.append(h('div.section-head', h('h2', t('weekly_classes')),
    h('button.btn.primary', { onclick: () => editClass(null, coaches, refresh) }, '+ ', t('new_class'))));
  if (!classes.length) { box.append(empty(t('no_class_templates'))); return; }
  for (const d of WEEK_ORDER) {
    const list = classes.filter((c) => c.weekday === d);
    if (!list.length) continue;
    box.append(h('h3.day', t('days')[d]));
    for (const c of list) {
      box.append(h('article.card.row-card',
        h('div', h('strong', c.name, c.locked ? h('span.pill.grey', t('locked')) : null),
          h('small.muted', `${c.start_time.slice(0, 5)} · ${c.duration_min}′ · ${t(c.audience)} · ${t('capacity')}: `,
            c.capacity ?? '∞', c.profiles?.full_name ? ` · ${c.profiles.full_name}` : '',
            c.location ? ` · ${c.location}` : '')),
        h('div.row',
          h('button.btn.ghost.sm', { onclick: () => editClass(c, coaches, refresh) }, t('edit')),
          h('button.btn.ghost.sm', { onclick: async () => {
            try { await rpc('set_class_locked', { p_id: c.id, p_locked: !c.locked }); refresh(); } catch (e) { toastErr(e); }
          } }, c.locked ? t('unlock') : t('lock')),
          h('button.btn.danger.sm', { onclick: async () => {
            if (!(await confirmBox(t('remove_class_confirm'), t('remove'), true))) return;
            try { await rpc('remove_class', { p_id: c.id }); refresh(); } catch (e) { toastErr(e); }
          } }, t('remove')))));
    }
  }
}
async function editClass(c, coaches, refresh) {
  const v = await formDialog(c ? `${t('edit')}: ${c.name}` : t('new_class'), [
    { name: 'name', label: t('class_name'), value: c?.name, required: true },
    { name: 'audience', label: t('audience'), type: 'select', value: c?.audience || 'adults',
      options: [['adults', t('adults')], ['kids', t('kids')]] },
    c ? { name: 'weekday', label: t('weekday'), type: 'select', value: c.weekday,
      options: WEEK_ORDER.map((d) => [d, t('days')[d]]) }
      : { name: 'day', label: t('days_multi'), type: 'days', value: [],
      options: WEEK_ORDER.map((d) => [d, t('days')[d]]) },
    { name: 'start', label: t('time'), type: 'time', value: c?.start_time?.slice(0, 5), required: true },
    { name: 'duration', label: t('duration_min'), type: 'number', min: 5, value: c?.duration_min, required: true },
    { name: 'capacity', label: t('capacity'), type: 'number', min: 1, value: c?.capacity ?? '', hint: t('capacity_hint') },
    { name: 'coach', label: t('coach'), type: 'select', value: c?.coach_id || '',
      options: [['', '—'], ...coaches.map((p) => [p.id, p.full_name || p.id.slice(0, 8)])] },
    { name: 'location', label: t('location'), value: c?.location ?? state.settings.location_name },
  ]);
  if (!v) return;
  // New class: one separate class per selected day (each can be edited on its own later)
  const days = c ? [Number(v.weekday)] : WEEK_ORDER.filter((d) => v[`day_${d}`]);
  if (!days.length) { toast(t('pick_a_day'), 'err'); return; }
  let made = 0;
  try {
    for (const d of days) {
      await rpc('save_class', { p_id: c?.id || null, p_name: v.name, p_audience: v.audience,
        p_weekday: d, p_start: v.start, p_duration: Number(v.duration),
        p_capacity: v.capacity ? Number(v.capacity) : null, p_coach: v.coach || null, p_location: v.location || null });
      made++;
    }
    toast(c ? t('saved') : t('classes_created', { n: made })); refresh();
  } catch (e) { toastErr(e); if (made) refresh(); }
}

// ---------- Cash payments ----------
export async function renderPayments(box, refresh) {
  const rows = await q(sb.from('payments').select('*, members(full_name, kind, profiles(full_name, phone)), packages(name_en, name_ar, audience)')
    .order('created_at', { ascending: false }).limit(60));
  const pending = rows.filter((p) => p.status === 'pending' && p.method === 'cash');
  box.append(h('h2', t('pay_pending'), ' ', h('span.count', pending.length)));
  if (!pending.length) box.append(empty(t('no_pending')));
  for (const p of pending) {
    box.append(h('article.card.row-card',
      h('div', h('strong', p.members.full_name),
        h('small.muted', `${p.members.kind === 'child' ? `${t('kind_child')} · ${p.members.profiles?.full_name} · ` : ''}`,
          `${pkgName(p)} · ${fmtMoney(p.amount_egp)} · #${p.invoice_no} · ${fmtDateTime(p.created_at)}`,
          p.members.profiles?.phone ? ` · ${p.members.profiles.phone}` : '')),
      h('div.row',
        h('button.btn.primary.sm', { onclick: async () => {
          try { await rpc('decide_payment', { p_payment: p.id, p_approve: true, p_note: null }); toast(t('saved')); refresh(); }
          catch (e) { toastErr(e); } } }, t('approve')),
        h('button.btn.ghost.sm', { onclick: async () => {
          const v = await formDialog(t('reject'), [{ name: 'note', label: t('reject_reason'), type: 'textarea' }], t('reject'));
          if (!v) return;
          try { await rpc('decide_payment', { p_payment: p.id, p_approve: false, p_note: v.note || null }); refresh(); }
          catch (e) { toastErr(e); } } }, t('reject')))));
  }
  const done = rows.filter((p) => p.status !== 'pending');
  if (done.length) {
    box.append(h('h2', t('payment_history')));
    box.append(h('div.table-wrap', h('table',
      h('thead', h('tr', h('th', t('invoice')), h('th', t('date')), h('th', t('member')), h('th', t('packages')),
        h('th', t('total')), h('th', ''))),
      h('tbody', done.map((p) => h('tr', h('td', '#' + p.invoice_no), h('td', fmtDate(p.created_at)),
        h('td', p.members.full_name), h('td', pkgName(p), ' · ', t('method_' + p.method), p.test_mode ? ` (${t('test_mode')})` : ''),
        h('td', fmtMoney(p.amount_egp)),
        h('td', h('span.pill', { class: p.status === 'paid' ? 'ok' : 'grey' }, t('pay_' + p.status)))))))));
  }
}
const pkgName = (p) => (document.documentElement.lang === 'ar' ? p.packages?.name_ar : p.packages?.name_en) || p.package_code;

// ---------- Expiring soon ----------
export async function renderExpiring(box) {
  const rows = await rpc('expiring_soon');
  box.append(h('h2', t('tab_expiring')));
  if (!rows.length) { box.append(empty(t('nobody_expiring'))); return; }
  box.append(h('div.table-wrap', h('table',
    h('thead', h('tr', h('th', t('member')), h('th', t('account')), h('th', t('left')), h('th', t('expires')), h('th', ''))),
    h('tbody', rows.map((r) => h('tr',
      h('td', r.member_name, r.kind === 'child' ? h('small.muted', ` (${t('kind_child')})`) : ''),
      h('td', r.account_name), h('td', r.sessions_left), h('td', fmtDateTime(r.expires_at)),
      h('td', h('button.btn.ghost.sm', { onclick: async (e) => {
        try { await rpc('notify_expiring', { p_member: r.member_id }); toast(t('notified')); e.target.disabled = true; }
        catch (err) { toastErr(err); } } }, t('notify')))))))));
}

// ---------- Announcements ----------
export async function renderAnnounce(box) {
  const form = formFields([
    { name: 'audience', label: t('send_to'), type: 'select', value: 'all',
      options: [['all', t('aud_all')], ['clients', t('aud_clients')], ['parents', t('aud_parents')]] },
    { name: 'title', label: t('title'), required: true },
    { name: 'body', label: t('message'), type: 'textarea', required: true },
  ]);
  box.append(h('h2', t('tab_announce')), form, h('button.btn.primary', { onclick: async () => {
    if (!form.reportValidity()) return;
    const v = readForm(form);
    try { const n = await rpc('send_announcement', { p_title: v.title, p_body: v.body, p_audience: v.audience }); toast(t('announce_sent', { n })); form.reset(); }
    catch (e) { toastErr(e); }
  } }, t('send')));
}

// ---------- My profile (coach / owner) ----------
export async function renderMyProfile(box) {
  const [mine] = await q(sb.from('members').select('*').eq('account_id', state.user.id).eq('kind', 'adult').limit(1));
  const form = formFields([
    { name: 'full_name', label: t('full_name'), value: state.profile.full_name, required: true },
    { name: 'phone', label: t('phone'), type: 'tel', value: state.profile.phone },
  ]);
  box.append(h('h2', t('tab_profile')), h('p.muted', state.profile.email), form,
    h('button.btn.primary', { onclick: async () => {
      if (!form.reportValidity()) return;
      const v = readForm(form);
      try {
        await q(sb.from('profiles').update({ full_name: v.full_name, phone: v.phone || null }).eq('id', state.user.id));
        if (mine) await q(sb.from('members').update({ full_name: v.full_name, phone: v.phone || null }).eq('id', mine.id));
        toast(t('profile_saved'));
        setTimeout(() => location.reload(), 600);
      } catch (e) { toastErr(e); }
    } }, t('save')));
}

// ---------- Cancelled classes by month ----------
export async function renderCancelled(box) {
  let month = cairoDate().slice(0, 7);
  const body = h('div');
  const input = h('input', { type: 'month', value: month, onchange: () => { month = input.value; load(); } });
  box.append(h('div.section-head', h('h2', t('tab_cancelled')), h('label.inline', input)), body);
  async function load() {
    clear(body);
    const [y, m] = month.split('-').map(Number);
    const from = `${month}-01`;
    const to = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
    const rows = await q(sb.from('sessions').select('*, classes(name, audience), canceller:profiles!cancelled_by(full_name)')
      .eq('status', 'cancelled').gte('session_date', from).lte('session_date', to).order('starts_at'));
    body.append(h('p', h('strong', rows.length), ' ', t('cancelled_by_coach')));
    if (!rows.length) return;
    body.append(h('div.table-wrap', h('table',
      h('thead', h('tr', h('th', t('date')), h('th', t('class_name')), h('th', t('reason')), h('th', t('coach')))),
      h('tbody', rows.map((s) => h('tr', h('td', fmtDateTime(s.starts_at)), h('td', s.classes.name, ` (${t(s.classes.audience)})`),
        h('td', s.cancel_reason || '—'), h('td', s.canceller?.full_name || '—')))))));
  }
  load();
}

export { statusClass };
