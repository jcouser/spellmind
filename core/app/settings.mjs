// The desktop app's AI settings (docs/milestone-3.md): what the window offers, and a change checked
// before it's saved to config.json. The game's chat window starts from these and can still pick its
// own thinking level and search for a question.
//
//   aiChoices(cfg) → { provider, name, models: [{ id, label }], model, efforts, effort, hasSearch, search }
//   applyAI(cfg, change) → { ok, cfg } | { ok: false, error }
import { loadManifests, effortLevels } from '../ai/providers/index.mjs';
import { pickAI } from './runner.mjs';

export function aiChoices(cfg = {}, manifests = loadManifests()) {
  const p = pickAI(cfg, {}, manifests);
  if (p.error) return { error: p.error };
  const { m, model, effort, search } = p;
  return {
    provider: m.id,
    name: m.name,
    card: m.display?.card || m.name,
    signIn: typeof m.auth?.signIn === 'string',
    models: m.models.list.map(x => ({ id: x.id, label: x.label || x.id })),
    model,
    efforts: effortLevels(m, model),
    effort,
    hasSearch: !!m.webSearch,
    search,
  };
}

export function applyAI(cfg = {}, change = {}, manifests = loadManifests()) {
  const now = aiChoices(cfg, manifests);
  if (now.error) return { ok: false, error: now.error };
  const next = { ...cfg };
  if (change.model !== undefined) {
    if (!now.models.some(x => x.id === change.model)) return { ok: false, error: 'unknown_model' };
    next.model = change.model;
  }
  if (change.effort !== undefined) {
    // The effort is checked against the model it will run with (a changed one too).
    const efforts = aiChoices(next, manifests).efforts;
    if (!efforts.includes(change.effort)) return { ok: false, error: 'unknown_effort' };
    next.effort = change.effort;
  } else if (next.effort && !aiChoices(next, manifests).efforts.includes(next.effort)) {
    delete next.effort; // the new model hasn't the old level: its default
  }
  if (change.search !== undefined) {
    if (typeof change.search !== 'boolean') return { ok: false, error: 'bad_search' };
    next.search = change.search ? 'on' : 'off';
  }
  return { ok: true, cfg: next };
}
