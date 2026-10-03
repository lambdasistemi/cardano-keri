/* Render Mermaid fences client side, following the chosen palette. */
(() => {
  const s = document.createElement('script');
  s.src = 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js';
  s.onload = () => {
    const nodes = [...document.querySelectorAll('pre.mermaid, .mermaid')];
    if (!nodes.length) return;
    nodes.forEach(n => { n.dataset.source = n.textContent; });
    const render = async () => {
      const dark = document.documentElement.dataset.keriPalette === 'dark';
      mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'loose' });
      nodes.forEach(n => { n.removeAttribute('data-processed'); n.textContent = n.dataset.source; });
      await mermaid.run({ nodes });
      nodes.forEach(n => { const v = n.querySelector("svg")?.viewBox.baseVal; if (v && v.width) { n.querySelector("svg").style.width = v.width + "px"; } });
    };
    render();
    document.getElementById('keri-palette-toggle')?.addEventListener('click', () => setTimeout(render, 0));
  };
  document.head.append(s);
})();
