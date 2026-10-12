// Private messages between coaches/owner and client/parent accounts
import { sb, rpc, q, state } from './api.js';
import { t } from './i18n.js';
import { h, clear, toastErr, fmtDateTime, empty } from './ui.js';

// One conversation. isStaff = the coach/owner is viewing it.
export async function renderThread(box, account, isStaff, onRead) {
  const list = h('div.thread', { 'aria-live': 'polite' });
  const input = h('textarea', { rows: 2, placeholder: t('write_message'), 'aria-label': t('write_message') });
  const send = h('button.btn.primary', { onclick: submit }, t('send'));
  const form = h('div.composer', input, send);
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) submit(); });
  box.append(list, form);

  let lastCount = -1;
  async function load() {
    const rows = await q(sb.from('messages').select('*').eq('account_id', account.id).order('created_at').limit(500));
    if (rows.length === lastCount) return;
    lastCount = rows.length;
    clear(list);
    if (!rows.length) list.append(empty(isStaff ? t('no_messages_staff') : t('no_messages')));
    for (const m of rows) {
      const mine = isStaff ? m.from_staff : !m.from_staff;
      list.append(h('div.bubble', { class: mine ? 'mine' : 'theirs' },
        h('small.who', m.from_staff ? t('coach_label') : (isStaff ? account.full_name : t('you'))),
        h('p', m.body), h('small.muted', fmtDateTime(m.created_at))));
    }
    list.scrollTop = list.scrollHeight;
    try { await rpc('mark_messages_read', { p_account: account.id }); onRead && onRead(); } catch {}
  }
  async function submit() {
    const body = input.value.trim();
    if (!body) return;
    send.disabled = true;
    try { await rpc('send_message', { p_account: account.id, p_body: body }); input.value = ''; await load(); }
    catch (e) { toastErr(e); }
    send.disabled = false; input.focus();
  }
  await load();
  // Check for new messages every 15 seconds while this conversation is open
  const timer = setInterval(() => { if (!box.isConnected) clearInterval(timer); else load().catch(() => {}); }, 15000);
}

// Client / parent: their own conversation with the coach
export async function renderMyMessages(box, onRead) {
  box.append(h('h2', t('tab_messages')), h('p.muted', t('messages_hint')));
  const holder = h('div'); box.append(holder);
  await renderThread(holder, { id: state.user.id, full_name: state.profile.full_name }, false, onRead);
}

// Coach / owner: inbox of all conversations + start a new one
export async function renderInbox(box) {
  const [threads, accounts] = await Promise.all([
    rpc('message_threads'),
    q(sb.from('profiles').select('id, full_name, email, role').in('role', ['client', 'parent']).eq('active', true)
      .order('full_name')),
  ]);
  const side = h('div.inbox-list');
  const main = h('div.inbox-main', empty(t('pick_conversation')));
  const picker = h('select', { 'aria-label': t('new_message') },
    h('option', { value: '' }, `+ ${t('new_message')}…`),
    accounts.map((a) => h('option', { value: a.id }, `${a.full_name || a.email} · ${t('role_' + a.role)}`)));
  picker.addEventListener('change', () => {
    const a = accounts.find((x) => x.id === picker.value);
    if (a) open(a);
  });
  box.append(h('div.section-head', h('h2', t('tab_messages')), h('label.inline', picker)),
    h('div.inbox', side, main));

  function open(a) {
    for (const b of side.querySelectorAll('button')) b.setAttribute('aria-pressed', b.dataset.id === a.id ? 'true' : 'false');
    clear(main).append(h('h3', a.full_name || a.email, h('small.muted', ` · ${t('role_' + a.role)}`)));
    const holder = h('div'); main.append(holder);
    renderThread(holder, a, true, () => {
      const badge = side.querySelector(`button[data-id="${a.id}"] .badge`);
      if (badge) badge.remove();
    }).catch(toastErr);
  }
  if (!threads.length) side.append(h('p.muted.small', t('no_conversations')));
  for (const th of threads) {
    const a = { id: th.account_id, full_name: th.full_name, email: th.email, role: th.role };
    side.append(h('button.thread-item', { 'data-id': th.account_id, 'aria-pressed': 'false', onclick: () => open(a) },
      h('strong', th.full_name || th.email, th.unread ? h('span.badge', th.unread) : null),
      h('small.muted', `${th.last_from_staff ? t('you') + ': ' : ''}${(th.last_body || '').slice(0, 60)}`),
      h('small.muted', fmtDateTime(th.last_at))));
  }
}
