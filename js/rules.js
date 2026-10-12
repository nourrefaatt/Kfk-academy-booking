// Rules & guidelines shown in every portal. Prices come from the live package list.
import { state } from './api.js';
import { t, getLang } from './i18n.js';
import { h, fmtMoney } from './ui.js';

export function renderRules(box) {
  const ar = getLang() === 'ar';
  const pk = (state.packages || []).slice().sort((a, b) => a.audience.localeCompare(b.audience) || a.sort - b.sort);
  box.append(
    h('h2', t('tab_rules')),
    h('div.no-refunds', { role: 'note' }, h('strong', t('rule_no_refunds_title')), h('p', t('rule_no_refunds'))),
    h('h3', t('packages')),
    h('ul.rules', pk.map((p) => h('li',
      h('strong', `${t(p.audience)} · ${ar ? p.name_ar : p.name_en}: `), fmtMoney(p.price_egp),
      p.weekly_limit ? ` · ${t('per_week', { n: p.weekly_limit })}` : '',
      p.validity_days ? ` · ${t('valid_days', { n: p.validity_days })}` : ''))),
    ...[
      ['rules_h_accounts', ['rule_ages']],
      ['rules_h_payments', ['rule_expiry', 'rule_cash', 'rule_reset', 'rule_early', 'rule_no_refunds_short']],
      ['rules_h_booking', ['rule_week', 'rule_one_day', 'rule_limit', 'rule_dropin', 'rule_after']],
      ['rules_h_cancel', ['rule_cancel', 'rule_noshow', 'rule_waitlist', 'rule_coach_cancel']],
    ].map(([head, items]) => h('section', h('h3', t(head)), h('ul.rules', items.map((k) => h('li', t(k))))))
  );
}
