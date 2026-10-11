import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Call a database function; throws on error
export async function rpc(name, args = {}) {
  const { data, error } = await sb.rpc(name, args);
  if (error) throw error;
  return data;
}
// Run a query builder; throws on error
export async function q(builder) {
  const { data, error } = await builder;
  if (error) throw error;
  return data;
}

export const state = { user: null, profile: null, settings: null, packages: [] };

export async function loadBasics() {
  const [profile, settings, packages] = await Promise.all([
    q(sb.from('profiles').select('*').eq('id', state.user.id).single()),
    q(sb.from('settings').select('*').single()),
    q(sb.from('packages').select('*').eq('active', true).order('sort')),
  ]);
  Object.assign(state, { profile, settings, packages });
  try { await rpc('run_due_jobs'); } catch (e) { console.warn(e); }
}

export async function unreadCount() {
  const { count } = await sb.from('notifications').select('id', { count: 'exact', head: true })
    .eq('account_id', state.user.id).is('read_at', null);
  return count || 0;
}
