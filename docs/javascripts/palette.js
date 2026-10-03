/* Follow the device preference until the reader chooses a palette. */
(() => {
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  let choice;
  try { choice = localStorage.getItem('keri-palette'); } catch (_) { /* Storage is optional. */ }
  const isDark = () => choice === 'dark' || (choice !== 'light' && system.matches);
  const apply = () => {
    const dark = isDark();
    document.documentElement.dataset.keriPalette = dark ? 'dark' : 'light';
    document.getElementById('keri-dark-palette').media = dark ? 'all' : 'not all';
    document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
    const button = document.getElementById('keri-palette-toggle');
    if (button) {
      button.textContent = dark ? 'Light mode' : 'Dark mode';
      button.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode');
      button.hidden = false;
    }
  };
  apply();
  system.addEventListener('change', apply);
  document.addEventListener('DOMContentLoaded', () => {
    apply();
    document.getElementById('keri-palette-toggle').addEventListener('click', () => {
      choice = isDark() ? 'light' : 'dark';
      try { localStorage.setItem('keri-palette', choice); } catch (_) { /* Storage is optional. */ }
      apply();
    });
    const navigation = document.getElementById('keri-navigation');
    if (navigation) {
      const wide = window.matchMedia('(min-width: 70em)');
      navigation.open = wide.matches;
      wide.addEventListener('change', () => { navigation.open = wide.matches; });
    }
  });
})();
