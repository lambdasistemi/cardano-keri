/* Per-section play/pause for the recorded narration; one passage plays at a time. */
document.addEventListener('DOMContentLoaded', async () => {
  const meta = document.querySelector('meta[name="narration-page"]');
  if (!meta || !meta.content.endsWith('.md')) return;
  const base = new URL('audio/', document.querySelector('script[src*="narration.js"]').src.replace(/javascripts\/narration\.js.*$/, ''));
  const page = 'docs-' + meta.content.slice(0, -3).replace(/\//g, '-');
  let manifest;
  try { manifest = await (await fetch(new URL('manifest.json', base))).json(); } catch (_) { return; }
  const sections = {};
  for (const [name, clip] of Object.entries(manifest.clips)) {
    if (name.startsWith(page + '/')) (sections[clip.section] ||= []).push({ name, ...clip });
  }
  const audio = new Audio();
  let current = null;
  const stop = () => {
    audio.pause();
    if (current) { current.button.textContent = '▶ Listen'; current.button.setAttribute('aria-pressed', 'false'); }
    current = null;
  };
  const speed = Number((() => { try { return localStorage.getItem('keri-narration-speed'); } catch (_) { return null; } })() || 1);
  audio.playbackRate = speed;
  const play = (state) => {
    const clip = state.clips[state.i];
    audio.src = new URL('clips/' + clip.name + '.mp3', base);
    audio.playbackRate = speed;
    audio.play().catch(() => { state.button.textContent = 'Could not play'; });
  };
  audio.addEventListener('ended', () => {
    if (!current) return;
    const state = current;
    const pause = state.clips[state.i].pause_ms || 0;
    state.i += 1;
    if (state.i >= state.clips.length) { stop(); return; }
    setTimeout(() => { if (current === state) play(state); }, pause);
  });
  audio.addEventListener('error', () => { if (current) current.button.textContent = 'Could not load'; });
  const controls = document.createElement('div');
  controls.className = 'narration-speed';
  controls.innerHTML = '<label>Narration speed <select aria-label="Narration speed"></select></label>';
  const select = controls.querySelector('select');
  for (const v of [0.75, 1, 1.25, 1.5, 2]) {
    const o = document.createElement('option');
    o.value = v; o.textContent = v + '×'; o.selected = v === speed; select.append(o);
  }
  select.addEventListener('change', () => {
    audio.playbackRate = Number(select.value);
    try { localStorage.setItem('keri-narration-speed', select.value); } catch (_) { /* optional */ }
  });
  let any = false;
  for (const [id, clips] of Object.entries(sections)) {
    const heading = document.getElementById(id);
    if (!heading) continue;
    clips.sort((a, b) => a.index - b.index);
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'narration-play';
    button.textContent = '▶ Listen';
    button.setAttribute('aria-pressed', 'false');
    button.setAttribute('aria-label', 'Listen to this section: ' + heading.textContent.replace('¶', '').trim());
    const state = { button, clips, i: 0 };
    button.addEventListener('click', () => {
      if (current === state) {
        if (audio.paused) { audio.play(); button.textContent = '⏸ Pause'; }
        else { audio.pause(); button.textContent = '▶ Resume'; }
        return;
      }
      stop();
      current = state; state.i = 0;
      button.textContent = '⏸ Pause'; button.setAttribute('aria-pressed', 'true');
      play(state);
    });
    heading.after(button);
    any = true;
  }
  if (any) document.getElementById('terminal-mkdocs-main-content')?.prepend(controls);
});
