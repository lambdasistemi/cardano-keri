/* Render Mermaid fences client side, one diagram at a time, following the chosen palette. */
(() => {
  const s = document.createElement('script');
  s.src = 'https://cdn.jsdelivr.net/npm/mermaid@10.9.3/dist/mermaid.min.js';
  s.onload = () => {
    const nodes = [...document.querySelectorAll('pre.mermaid')];
    if (!nodes.length) return;
    nodes.forEach(n => { n.dataset.source = n.textContent; });
    const render = async () => {
      const dark = document.documentElement.dataset.keriPalette === 'dark';
      mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'loose' });
      for (const [i, n] of nodes.entries()) {
        try {
          const { svg } = await mermaid.render(`keri-diagram-${i}-${Date.now()}`, n.dataset.source);
          n.innerHTML = svg;
          const el = n.querySelector('svg');
          const v = el.viewBox.baseVal;
          if (v && v.width) el.style.width = v.width + 'px';
        } catch (e) {
          n.textContent = n.dataset.source;
          console.error('Diagram ' + i + ' could not be rendered:', e.message || e);
        }
      }
    };
    render();
    document.getElementById('keri-palette-toggle')?.addEventListener('click', () => setTimeout(render, 0));
  };
  document.head.append(s);
})();
