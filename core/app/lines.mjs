// The link's events in words: the command line's lines and the desktop app's Activity list.
// eventLine(ev) → a line, or null for an event that needn't one.
// Plain words, not byte counts (the audit: "Message in c3f9a1e (412 bytes)" was for developers).
const LINES = {
  hello: d => `The game said hello (addon ${d.ver}).`,
  msg: d => `Question received: asking ${d.status?.ai?.name || 'your AI'}…`,
  reply: () => 'Answer sent to the game.',
  // The words the player saw in game (userLine), else the kind.
  'turn-error': d => (d.text ? `Answer failed: ${d.text}` : `Answer failed (${d.what}).`),
  'ai-not-ready': () => "Your AI isn't set up yet: sign in or paste a key under Your AI.",
  'msg-refused': d => `A question wasn't sent: ${d.reason}`,
  // Character data comes every few seconds while playing: not a line each (it buried the rest).
  state: () => null,
  'state-rejected': d => `Some character data (${d.part || '?'}) was refused: ${d.reason}`,
  'state-wait-over': () => 'Character data came late: answered with what was there.',
  wow: d => ({ running: 'WoW is running.', launched: 'WoW started.', absent: 'WoW isn\'t running.', exited: 'WoW closed.' }[d.state] || `WoW: ${d.state}`),
  // Not while WoW is simply closed: "its window wasn't found" said nothing new.
  'reading-error': d => (d.status?.wow === 'absent' || d.status?.wow === 'exited' ? null : `Screen reading: ${d.error}`),
  // What's read, said plainly (the audit: "Screen reading started" alarmed without saying).
  reading: d => (d.status?.reading ? "Watching WoW's window for Spellmind's signal strip (nothing else is read)." : 'Stopped watching WoW\'s window.'),
};

export function eventLine(ev) {
  const f = ev && LINES[ev.kind];
  if (!f) return null;
  try { return f(ev); } catch { return null; }
}
