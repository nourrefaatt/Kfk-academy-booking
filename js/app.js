import { sb, rpc, q, state, loadBasics, unreadCount } from './api.js';
import { t, tErr, getLang, setLang } from './i18n.js';
import { h, clear, toast, toastErr, tabs, formFields, readForm, formDialog, ageYears, cairoDate, empty } from './ui.js';
import { renderBook, renderBookings, renderBalance, renderProfile, renderNotifications } from './member.js';
import { renderDay, renderClasses, renderPayments, renderExpiring, renderAnnounce, renderCancelled } from './staff.js';
import { renderDashboard, renderAccounts, renderSettings } from './owner.js';
import { renderMyMessages, renderInbox } from './messages.js';
import { renderRules } from './rules.js';

const app = document.getElementById('app');

function langButton() {
  return h('button.btn.ghost.sm.lang', { onclick: () => { setLang(getLang() === 'ar' ? 'en' : 'ar'); start(); } },
    getLang() === 'ar' ? 'English' : 'العربية');
}

// ---------------- Auth screens ----------------
function authScreen(mode = 'login') {
  clear(app);
  const card = h('div.auth-card');
  app.append(h('main.auth',
    h('div.auth-brand',
      h('img', { src: 'assets/brand/logo-full-stacked-on-dark.png', alt: 'KFK Muay Thai & MMA', width: 320 }),
      h('p', t('tagline'))),
    card));
  const tabsRow = h('div.seg',
    h('button', { 'aria-pressed': mode === 'login' ? 'true' : 'false', onclick: () => authScreen('login') }, t('login')),
    h('button', { 'aria-pressed': mode === 'signup' ? 'true' : 'false', onclick: () => authScreen('signup') }, t('signup')));
  card.append(h('div.auth-top', tabsRow, langButton()));
  if (mode === 'login') loginForm(card);
  else if (mode === 'signup') signupForm(card);
  else if (mode === 'forgot') forgotForm(card);
  else if (mode === 'recover') recoverForm(card);
}

function loginForm(card) {
  const form = formFields([
    { name: 'email', label: t('email'), type: 'email', required: true, autocomplete: 'email' },
    { name: 'password', label: t('password'), type: 'password', required: true, autocomplete: 'current-password' },
  ]);
  const btn = h('button.btn.primary.wide', { type: 'submit' }, t('login'));
  form.append(btn, h('button.link', { type: 'button', onclick: () => authScreen('forgot') }, t('forgot')));
  form.addEventListener('submit', async () => {
    const v = readForm(form); btn.disabled = true;
    const { error } = await sb.auth.signInWithPassword({ email: v.email, password: v.password });
    btn.disabled = false;
    if (error) toastErr(error);
  });
  card.append(form);
}

function signupForm(card) {
  let type = 'client';
  const typeSel = h('div.seg.choice',
    h('button', { type: 'button', 'aria-pressed': 'true', onclick: () => pick('client') }, t('type_client')),
    h('button', { type: 'button', 'aria-pressed': 'false', onclick: () => pick('parent') }, t('type_parent')));
  const holder = h('div');
  function pick(v) {
    type = v;
    typeSel.children[0].setAttribute('aria-pressed', v === 'client' ? 'true' : 'false');
    typeSel.children[1].setAttribute('aria-pressed', v === 'parent' ? 'true' : 'false');
    draw();
  }
  function draw() {
    clear(holder);
    const base = [
      { name: 'full_name', label: t('full_name'), required: true, autocomplete: 'name' },
      { name: 'email', label: t('email'), type: 'email', required: true, autocomplete: 'email' },
      { name: 'password', label: t('password'), type: 'password', required: true, hint: t('password_hint'),
        autocomplete: 'new-password' },
      { name: 'phone', label: t('phone'), type: 'tel', required: true, autocomplete: 'tel' },
    ];
    const extra = type === 'client' ? [
      { name: 'date_of_birth', label: t('dob'), type: 'date', required: true, max: cairoDate() },
      { name: 'emergency_contact', label: t('emergency'), required: true },
      { name: 'medical_notes', label: t('medical'), type: 'textarea' },
      { name: 'experience', label: t('experience'), type: 'textarea' },
    ] : [];
    const form = formFields([...base, ...extra]);
    const btn = h('button.btn.primary.wide', { type: 'submit' }, t('signup'));
    form.append(btn);
    form.addEventListener('submit', async () => {
      const v = readForm(form);
      if (v.password.length < 8) { toast(t('password_hint'), 'err'); return; }
      if (type === 'client' && ageYears(v.date_of_birth) < 13) { toast(t('too_young'), 'err'); return; }
      btn.disabled = true;
      const { email, password, ...meta } = v;
      const { data, error } = await sb.auth.signUp({ email, password, options: {
        data: { ...meta, role: type, locale: getLang() }, emailRedirectTo: location.origin + location.pathname } });
      btn.disabled = false;
      if (error) { toastErr(error); return; }
      if (!data.session) { authScreen('login'); toast(t('check_email')); }
    });
    holder.append(form);
  }
  card.append(h('p.label', t('account_type')), typeSel, holder);
  draw();
}

function forgotForm(card) {
  const form = formFields([{ name: 'email', label: t('email'), type: 'email', required: true }]);
  form.append(h('button.btn.primary.wide', { type: 'submit' }, t('send_reset')));
  form.addEventListener('submit', async () => {
    const { error } = await sb.auth.resetPasswordForEmail(readForm(form).email,
      { redirectTo: location.origin + location.pathname });
    if (error) toastErr(error); else toast(t('reset_sent'));
  });
  card.append(form);
}

function recoverForm(card) {
  const form = formFields([{ name: 'password', label: t('new_password'), type: 'password', required: true,
    hint: t('password_hint'), autocomplete: 'new-password' }]);
  form.append(h('button.btn.primary.wide', { type: 'submit' }, t('save_password')));
  form.addEventListener('submit', async () => {
    const pw = readForm(form).password;
    if (pw.length < 8) { toast(t('password_hint'), 'err'); return; }
    const { error } = await sb.auth.updateUser({ password: pw });
    if (error) toastErr(error); else { toast(t('saved')); recovering = false; start(); }
  });
  card.append(form);
}

// ---------------- Signed-in shell ----------------
async function shell() {
  clear(app).append(h('p.center.muted', t('loading')));
  await loadBasics();
  const p = state.profile;
  if (p.locale !== getLang()) { sb.from('profiles').update({ locale: getLang() }).eq('id', p.id).then(() => {}); }
  if (!p.active) {
    clear(app).append(h('main.auth', h('div.auth-card', h('p', t('inactive')),
      h('button.btn.primary', { onclick: () => sb.auth.signOut() }, t('logout')))));
    return;
  }
  const bell = h('button.icon-btn.bell', { 'aria-label': t('tab_notifications'), onclick: () => openNotifications() },
    '🔔', h('span.badge.hidden'));
  const header = h('header.top',
    h('img.logo', { src: 'assets/brand/logo-full-horizontal.png', alt: 'KFK Muay Thai & MMA' }),
    h('div.who', h('strong', p.full_name || p.email), h('small', t('role_' + p.role))),
    h('div.row', bell, langButton(), h('button.btn.ghost.sm', { onclick: () => sb.auth.signOut() }, t('logout'))));
  const main = h('main.container');
  clear(app).append(header, main);
  refreshBell(bell);

  if (p.role === 'client') await clientPortal(main, () => refreshBell(bell));
  else if (p.role === 'parent') await parentPortal(main, () => refreshBell(bell));
  else staffPortal(main, p.role === 'owner');
}

async function refreshBell(bell) {
  try {
    const n = await unreadCount();
    const b = bell.querySelector('.badge');
    b.textContent = n; b.classList.toggle('hidden', !n);
  } catch {}
}
function openNotifications() {
  const box = h('div');
  import('./ui.js').then(({ modal }) => {
    renderNotifications(box, () => { start(); }).then(() => modal(t('tab_notifications'), box));
  });
}

function memberTabs(container, member, onChange) {
  const ctl = tabs(container, [
    { key: 'book', label: t('tab_book'), render: (b) => renderBook(b, member, () => ctl.reload()) },
    { key: 'bookings', label: t('tab_bookings'), render: (b) => renderBookings(b, member, () => ctl.reload()) },
    { key: 'balance', label: t('tab_balance'), render: (b) => renderBalance(b, member, () => ctl.reload()) },
    { key: 'profile', label: t('tab_profile'), render: (b) => renderProfile(b, member, onChange) },
    { key: 'notes', label: t('tab_notifications'), render: (b) => renderNotifications(b, () => { onChange(); ctl.reload(); }) },
    { key: 'messages', label: t('tab_messages'), render: (b) => renderMyMessages(b, onChange) },
    { key: 'rules', label: t('tab_rules'), render: (b) => renderRules(b) },
  ]);
  return ctl;
}

async function clientPortal(main, onChange) {
  const [member] = await q(sb.from('members').select('*').eq('account_id', state.user.id).eq('kind', 'adult').limit(1));
  if (!member) { main.append(empty('—')); return; }
  memberTabs(main, member, onChange);
}

async function parentPortal(main, onChange) {
  const kids = await q(sb.from('members').select('*').eq('account_id', state.user.id).eq('kind', 'child').order('created_at'));
  let selected = null;
  try { selected = sessionStorage.getItem('kfk_child'); } catch {}
  if (!kids.find((k) => k.id === selected)) selected = kids[0]?.id;
  const chips = h('div.chips');
  const body = h('div');
  main.append(h('div.section-head', h('h2', t('my_kids')), h('button.btn.primary.sm', { onclick: addChild }, '+ ', t('add_child'))),
    chips, body);
  function draw() {
    clear(chips); clear(body);
    for (const k of kids) {
      const age = ageYears(k.date_of_birth);
      chips.append(h('button.chip', { 'aria-pressed': k.id === selected ? 'true' : 'false', onclick: () => {
        selected = k.id; try { sessionStorage.setItem('kfk_child', k.id); } catch {} draw();
      } }, k.full_name, age != null ? h('small', ` ${age}`) : null));
    }
    const kid = kids.find((k) => k.id === selected);
    if (!kid) { body.append(empty(t('no_kids'))); return; }
    if (ageYears(kid.date_of_birth) >= 13) body.append(h('p.notice', t('turned_13')));
    memberTabs(body, kid, onChange);
  }
  async function addChild() {
    const v = await formDialog(t('add_child'), [
      { name: 'full_name', label: t('full_name'), required: true },
      { name: 'dob', label: t('dob'), type: 'date', required: true, max: cairoDate(), hint: t('child_under_13') },
      { name: 'emergency', label: t('emergency'), required: true },
      { name: 'medical', label: t('medical'), type: 'textarea' },
      { name: 'experience', label: t('experience'), type: 'textarea' },
    ], t('add_child'));
    if (!v) return;
    if (ageYears(v.dob) >= 13) { toast(t('child_under_13'), 'err'); return; }
    try {
      const id = await rpc('add_child', { p_full_name: v.full_name, p_dob: v.dob, p_emergency: v.emergency,
        p_medical: v.medical || null, p_experience: v.experience || null });
      const [kid] = await q(sb.from('members').select('*').eq('id', id));
      kids.push(kid); selected = id; toast(t('child_added')); draw();
    } catch (e) { toastErr(e); }
  }
  draw();
}

function staffPortal(main, isOwner) {
  const items = [];
  if (isOwner) items.push({ key: 'dash', label: t('tab_dashboard'), render: renderDashboard });
  items.push(
    { key: 'day', label: t('tab_day'), render: renderDay },
    { key: 'classes', label: t('tab_classes'), render: (b) => renderClasses(b, () => ctl.reload()) },
    { key: 'payments', label: t('tab_payments'), render: (b) => renderPayments(b, () => ctl.reload()) },
    { key: 'expiring', label: t('tab_expiring'), render: renderExpiring },
    { key: 'messages', label: t('tab_messages'), render: renderInbox },
    { key: 'announce', label: t('tab_announce'), render: renderAnnounce },
    { key: 'cancelled', label: t('tab_cancelled'), render: renderCancelled },
  );
  if (isOwner) items.push(
    { key: 'accounts', label: t('tab_accounts'), render: (b) => renderAccounts(b, () => ctl.reload()) },
    { key: 'settings', label: t('tab_settings'), render: (b) => renderSettings(b, () => ctl.reload()) });
  items.push({ key: 'rules', label: t('tab_rules'), render: (b) => renderRules(b) });
  const ctl = tabs(main, items);
}

// ---------------- Boot ----------------
let recovering = false;
async function start() {
  setLang(getLang());
  if (recovering) { authScreen('recover'); return; }
  const { data } = await sb.auth.getSession();
  state.user = data.session?.user || null;
  if (!state.user) { authScreen('login'); return; }
  try { await shell(); }
  catch (e) {
    console.error(e);
    clear(app).append(h('main.auth', h('div.auth-card', h('p.error', tErr(e)),
      h('button.btn.primary', { onclick: () => sb.auth.signOut() }, t('logout')))));
  }
}

let lastUser;
sb.auth.onAuthStateChange((event, session) => {
  if (event === 'PASSWORD_RECOVERY') { recovering = true; start(); return; }
  const uid = session?.user?.id || null;
  if (event === 'SIGNED_OUT' || (uid !== lastUser && event !== 'INITIAL_SESSION' && event !== 'TOKEN_REFRESHED')) {
    lastUser = uid; start();
  }
  if (event === 'INITIAL_SESSION') lastUser = uid;
});
start();
