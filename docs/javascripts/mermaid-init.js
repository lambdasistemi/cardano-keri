/* Render Mermaid fences client side, one diagram at a time, following the chosen palette.
   A left-to-right flowchart wider than the reading column is drawn top to bottom instead. */
(() => {
  const s = document.createElement('script');
  s.src = 'https://cdn.jsdelivr.net/npm/mermaid@10.9.3/dist/mermaid.min.js';
  s.onload = () => {
    mermaid.initialize({ startOnLoad: false });
    const nodes = [...document.querySelectorAll('pre.mermaid')];
    if (!nodes.length) return;
    nodes.forEach(n => { n.dataset.source = n.textContent; });
    // Long labels do not wrap by themselves: break them at word boundaries, keeping any breaks already there.
    const breakLines = (text, limit) => text.split(/<br\/>/).map(part => {
      const lines = [];
      let line = '';
      for (const word of part.split(/\s+/)) {
        if (line && (line + ' ' + word).length > limit) { lines.push(line); line = word; } else { line = line ? line + ' ' + word : word; }
      }
      lines.push(line);
      return lines.join('<br/>');
    }).join('<br/>');
    const wrapLabels = source => source.split('\n').map(line => /^\s*subgraph\b/.test(line) ? line : line
      .replace(/\|"([^"|\n]{34,})"\|/g, (_, text) => '|"' + breakLines(text, 30) + '"|')
      .replace(/\["([^"\n]{44,})"\]/g, (_, text) => '["' + breakLines(text, 38) + '"]')).join('\n');
    const LEFT_TO_RIGHT = /^(\s*(?:flowchart|graph)\s+)(LR|RL)\b/m;
    const draw = async (id, source, n) => {
      const { svg } = await mermaid.render(id, source);
      n.innerHTML = svg;
      const el = n.querySelector('svg');
      const v = el.viewBox.baseVal;
      if (v && v.width) el.style.width = v.width + 'px';
      return el.getBoundingClientRect().width;
    };
    const render = async () => {
      const dark = document.documentElement.dataset.keriPalette === 'dark';
      mermaid.initialize({
        startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'loose',
        sequence: { wrap: true, width: 150, actorMargin: 24, messageMargin: 28, useMaxWidth: false },
        flowchart: { wrappingWidth: 140, htmlLabels: true, useMaxWidth: false, subGraphTitleMargin: { top: 6, bottom: 12 } },
        state: { useMaxWidth: false },
      });
      for (const [i, n] of nodes.entries()) {
        const source = /^\s*(flowchart|graph)\b/m.test(n.dataset.source) ? wrapLabels(n.dataset.source) : n.dataset.source;
        delete n.dataset.rendered;
        try {
          const width = await draw(`keri-diagram-${i}-${Date.now()}`, source, n);
          if (width > n.clientWidth && LEFT_TO_RIGHT.test(source)) {
            const narrower = await draw(`keri-diagram-${i}-tb-${Date.now()}`, source.replace(LEFT_TO_RIGHT, '$1TB'), n);
            if (narrower >= width) await draw(`keri-diagram-${i}-lr-${Date.now()}`, source, n);
          }
        } catch (e) {
          n.textContent = source;
          console.error('Diagram ' + i + ' could not be rendered:', e.message || e);
        }
        n.dataset.rendered = 'true';
      }
    };
    render();
    document.getElementById('keri-palette-toggle')?.addEventListener('click', () => setTimeout(render, 0));
  };
  document.head.append(s);
})();
