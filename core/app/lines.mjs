// The link's events in words: the command line's lines and the desktop app's Activity list.
// eventLine(ev) → a line, or null for an event that needn't one.
const LINES = {
  hello: d => `The game said hello (addon ${d.ver}).`,
  msg: d => `Message in ${d.chat} (${d.bytes} bytes): asking ${d.status?.ai?.name || 'your AI'}…`,
  reply: d => `Reply out ${d.chat} (${d.chars} characters).`,
  'turn-error': d => `Error for ${d.chat}: ${d.kind}`,
  'msg-refused': d => `Refused a message: ${d.reason}`,
  state: d => `Character data in: ${d.part} (${d.bytes} bytes)`,
  'state-rejected': d => `Character data refused: ${d.part || '?'} ${d.reason}`,
  'state-wait-over': d => `Character data late for ${d.chat}: answering with what is there.`,
  wow: d => ({ running: 'WoW is running.', launched: 'WoW started.', absent: 'WoW isn\'t running.', exited: 'WoW closed.' }[d.state] || `WoW: ${d.state}`),
  // Not while WoW is simply closed: "its window wasn't found" said nothing new.
  'reading-error': d => (d.status?.wow === 'absent' || d.status?.wow === 'exited' ? null : `Screen reading: ${d.error}`),
  reading: d => (d.status?.reading ? 'Screen reading started.' : 'Screen reading stopped.'),
};

export function eventLine(ev) {
  const f = ev && LINES[ev.kind];
  if (!f) return null;
  try { return f(ev); } catch { return null; }
}
