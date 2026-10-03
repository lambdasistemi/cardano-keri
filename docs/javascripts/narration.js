/* Per-section narration: a speaker icon at each heading; one passage plays at a time. */
document.addEventListener('DOMContentLoaded', async () => {
  const meta = document.querySelector('meta[name="narration-page"]');
  if (!meta || !meta.content.endsWith('.md')) return;
  const root = document.querySelector('script[src*="narration.js"]').src.replace(/javascripts\/narration\.js.*$/, '');
  const audioBase = new URL('audio/', root);
  const page = 'docs/' + meta.content;
  let sections;
  try {
    const index = await (await fetch(new URL('index.json', audioBase), { cache: 'no-cache' })).json();
    sections = index[page];
  } catch (_) { return; }
  if (!sections) return;

  const SPEAKER = '<svg viewBox="0 0 24 24" width="1.1em" height="1.1em" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/><path d="M19 6a8.5 8.5 0 0 1 0 12"/></svg>';
  const PAUSE = '<svg viewBox="0 0 24 24" width="1.1em" height="1.1em" fill="currentColor" aria-hidden="true"><rect x="6" y="5" width="4" height="14"/><rect x="14" y="5" width="4" height="14"/></svg>';

  const audio = new Audio();
  let current = null;
  const show = (state, playing) => {
    state.button.innerHTML = playing ? PAUSE : SPEAKER;
    state.button.setAttribute('aria-label', (playing ? 'Pause: ' : 'Listen to this section: ') + state.title);
    state.button.setAttribute('aria-pressed', playing ? 'true' : 'false');
  };
  const stop = () => {
    audio.pause();
    if (current) show(current, false);
    current = null;
  };
  const stored = () => { try { return Number(localStorage.getItem('keri-narration-speed')) || 1; } catch (_) { return 1; } };
  audio.playbackRate = stored();
  const play = (state) => {
    const clip = state.clips[state.i];
    audio.src = new URL('clips/' + clip.name + '.mp3?v=' + clip.v, audioBase);
    audio.playbackRate = stored();
    audio.play().catch(() => { state.button.title = 'This recording could not be played'; show(state, false); });
  };
  audio.addEventListener('ended', () => {
    if (!current) return;
    const state = current;
    const pause = state.clips[state.i].pause_ms || 0;
    state.i += 1;
    if (state.i >= state.clips.length) { stop(); return; }
    setTimeout(() => { if (current === state) play(state); }, pause);
  });
  audio.addEventListener('error', () => { if (current) { current.button.title = 'This recording could not be loaded'; stop(); } });

  let any = false;
  for (const [id, clips] of Object.entries(sections)) {
    const heading = document.getElementById(id);
    if (!heading) continue;
    const state = { title: heading.textContent.replace('¶', '').trim(), clips, i: 0 };
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'narration-play';
    state.button = button;
    show(state, false);
    button.addEventListener('click', () => {
      if (current === state) {
        if (audio.paused) { audio.play(); show(state, true); } else { audio.pause(); show(state, false); }
        return;
      }
      stop();
      current = state; state.i = 0;
      show(state, true);
      play(state);
    });
    heading.append(button);
    any = true;
  }
  if (!any) return;
  const select = document.createElement('select');
  select.className = 'narration-speed';
  select.setAttribute('aria-label', 'Narration speed');
  const speed = stored();
  for (const v of [0.75, 1, 1.25, 1.5, 2]) {
    const o = document.createElement('option');
    o.value = v; o.textContent = v + '×'; o.selected = v === speed; select.append(o);
  }
  select.addEventListener('change', () => {
    audio.playbackRate = Number(select.value);
    try { localStorage.setItem('keri-narration-speed', select.value); } catch (_) { /* optional */ }
  });
  document.getElementById('terminal-mkdocs-main-content')?.prepend(select);
});
