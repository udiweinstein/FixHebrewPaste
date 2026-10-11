(() => {
  'use strict';

  // ---- Configuration -------------------------------------------------------
  const HEB = /[\u0590-\u05FF\uFB1D-\uFB4F]/g;          // Hebrew letters
  const LAT = /[A-Za-z\u00C0-\u024F]/g;                  // Latin letters
  const RTL_RATIO = 0.3;      // ≥30% of letters Hebrew → right-to-left
  const WEAK_MAX_LEN = 30;    // short Latin-only lines (e.g. "TL;DR:") follow their neighbours
  const DEBOUNCE_MS = 120;

  const BLOCKS = 'p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th,dt,dd,summary,figcaption,div';
  const CONTAINERS = 'ul,ol,table,dl';
  const ALL = BLOCKS + ',' + CONTAINERS;
  const SKIP = 'pre,code,kbd,samp,.katex,math,svg,textarea,input,[contenteditable=""],[contenteditable="true"],[contenteditable="plaintext-only"]';
  const ATTR = 'data-rtlfix';
  const ORIG = 'data-rtlfix-orig';

  let enabled = false;
  let observer = null;
  let timer = null;
  const queue = new Set();

  // ---- Direction detection -------------------------------------------------
  function count(text) {
    return {
      h: (text.match(HEB) || []).length,
      l: (text.match(LAT) || []).length,
    };
  }

  // For <div>s, only look at their own text nodes, so wrapper divs that contain
  // the whole page are not flipped. Other block elements use their full text.
  function ownText(el) {
    if (el.tagName !== 'DIV') return el.textContent || '';
    let t = '';
    for (const n of el.childNodes) {
      if (n.nodeType === Node.TEXT_NODE) t += n.nodeValue;
      else if (n.nodeType === Node.ELEMENT_NODE && isInline(n)) t += n.textContent;
    }
    return t;
  }

  const INLINE = new Set(['SPAN', 'B', 'STRONG', 'I', 'EM', 'A', 'U', 'S', 'MARK', 'SMALL', 'SUB', 'SUP', 'BR', 'CODE', 'ABBR', 'CITE', 'Q']);
  function isInline(el) { return INLINE.has(el.tagName); }

  function classify(el) {
    if (el.closest(SKIP)) return 'skip';
    const text = ownText(el);
    const { h, l } = count(text);
    if (h === 0 && l === 0) return 'neutral';
    if (h / (h + l) >= RTL_RATIO) return 'rtl';
    if (h === 0 && text.trim().length <= WEAK_MAX_LEN) return 'weak';
    return 'ltr';
  }

  function setRtl(el) {
    if (el.getAttribute(ATTR) === 'rtl') return;
    if (!el.hasAttribute(ORIG)) el.setAttribute(ORIG, el.getAttribute('dir') ?? '');
    el.setAttribute('dir', 'rtl');
    el.setAttribute(ATTR, 'rtl');
  }

  function unset(el) {
    if (!el.hasAttribute(ATTR)) return;
    const orig = el.getAttribute(ORIG);
    if (orig) el.setAttribute('dir', orig); else el.removeAttribute('dir');
    el.removeAttribute(ATTR);
    el.removeAttribute(ORIG);
  }

  function neighbourIsRtl(el) {
    const p = el.previousElementSibling, n = el.nextElementSibling;
    return (p && p.getAttribute(ATTR) === 'rtl') || (n && n.getAttribute(ATTR) === 'rtl');
  }

  function processElements(list) {
    const weak = [];
    for (const el of list) {
      const c = classify(el);
      if (c === 'rtl') setRtl(el);
      else if (c === 'weak') weak.push(el);
      else if (c === 'ltr') unset(el);
      // 'neutral' / 'skip': leave as is
    }
    // Second pass: short Latin-only lines adopt the direction of their neighbours
    for (const el of weak) {
      if (neighbourIsRtl(el)) setRtl(el); else unset(el);
    }
  }

  function collect(root) {
    const set = new Set();
    if (root.nodeType !== Node.ELEMENT_NODE) root = root.parentElement;
    if (!root) return set;
    // The element itself and its ancestors (a streamed word changes the paragraph's ratio)
    for (let a = root; a && a !== document.documentElement; a = a.parentElement) {
      if (a.matches(ALL)) set.add(a);
    }
    // Everything inside it
    root.querySelectorAll(ALL).forEach((e) => set.add(e));
    return set;
  }

  function flush() {
    timer = null;
    if (!enabled) { queue.clear(); return; }
    const els = new Set();
    for (const r of queue) if (r.isConnected) collect(r).forEach((e) => els.add(e));
    queue.clear();
    processElements(els);
  }

  function schedule(node) {
    queue.add(node);
    if (!timer) timer = setTimeout(flush, DEBOUNCE_MS);
  }

  // ---- Editable areas: let the browser pick direction per line ------------
  function fixEditables(root = document) {
    root.querySelectorAll('textarea, [contenteditable="true"], [contenteditable=""], [role="textbox"]').forEach((el) => {
      if (!el.hasAttribute('dir')) { el.setAttribute('dir', 'auto'); el.setAttribute('data-rtlfix-edit', ''); }
    });
  }

  // ---- Start / stop --------------------------------------------------------
  function start() {
    if (enabled) return;
    enabled = true;
    fixEditables();
    schedule(document.body);
    observer = new MutationObserver((muts) => {
      for (const m of muts) {
        schedule(m.target);
        if (m.type === 'childList') {
          m.addedNodes.forEach((n) => { if (n.nodeType === Node.ELEMENT_NODE) fixEditables(n.parentElement || document); });
        }
      }
    });
    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  function stop() {
    enabled = false;
    if (observer) observer.disconnect();
    observer = null;
    document.querySelectorAll('[' + ATTR + ']').forEach(unset);
    document.querySelectorAll('[data-rtlfix-edit]').forEach((el) => {
      el.removeAttribute('dir'); el.removeAttribute('data-rtlfix-edit');
    });
  }

  // ---- Settings ------------------------------------------------------------
  const host = location.hostname;
  function apply(s) {
    const on = s.enabled !== false && !(s.disabledSites || []).includes(host);
    on ? start() : stop();
  }

  chrome.storage.sync.get({ enabled: true, disabledSites: [] }, apply);
  chrome.storage.onChanged.addListener((_, area) => {
    if (area === 'sync') chrome.storage.sync.get({ enabled: true, disabledSites: [] }, apply);
  });
})();
