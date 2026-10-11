const globalBox = document.getElementById('global');
const siteBox = document.getElementById('site');
const hostEl = document.getElementById('host');

chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
  let host = '';
  try { host = new URL(tab.url).hostname; } catch (e) {}
  hostEl.textContent = host || '—';
  if (!host) siteBox.disabled = true;

  chrome.storage.sync.get({ enabled: true, disabledSites: [] }, (s) => {
    globalBox.checked = s.enabled !== false;
    siteBox.checked = !s.disabledSites.includes(host);
    siteBox.disabled = !host || !globalBox.checked;
  });

  globalBox.addEventListener('change', () => {
    chrome.storage.sync.set({ enabled: globalBox.checked });
    siteBox.disabled = !host || !globalBox.checked;
  });

  siteBox.addEventListener('change', () => {
    chrome.storage.sync.get({ disabledSites: [] }, (s) => {
      const list = new Set(s.disabledSites);
      siteBox.checked ? list.delete(host) : list.add(host);
      chrome.storage.sync.set({ disabledSites: [...list] });
    });
  });
});
