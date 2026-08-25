/* Next Jailbreak — Adsterra responsive ad manager */
(function () {
  'use strict';

  // Apply shared branding cleanup on every page before the content renderer.
  if (!document.querySelector('script[data-ns-site-branding]')) {
    var brandingScript = document.createElement('script');
    brandingScript.src = '/assets/site-branding.js?v=20260823-2';
    brandingScript.defer = true;
    brandingScript.setAttribute('data-ns-site-branding', '1');
    document.head.appendChild(brandingScript);
  }

  // Keep the homepage/category renderer separate from ad logic while loading it site-wide.
  if (!document.querySelector('script[data-ns-site-content]')) {
    var contentScript = document.createElement('script');
    contentScript.src = '/assets/site-content.js?v=20260825-1';
    contentScript.defer = true;
    contentScript.setAttribute('data-ns-site-content', '1');
    document.head.appendChild(contentScript);
  }

  var path = window.location.pathname || '/';

  // Do not monetize repository depictions, legal/support pages, or app-internal pages.
  var blockedPrefixes = ['/depictions/', '/applications/', '/DailyLedger/', '/DailyTweaks/', '/Diagnostics/', '/ModuleGlassPreview/', '/NextPDF/', '/NextPost/'];
  var blockedExact = ['/privacy/', '/privacy.html', '/terms/', '/terms.html', '/next-ledger-support.html'];
  if (blockedExact.indexOf(path) !== -1 || blockedPrefixes.some(function (prefix) { return path.indexOf(prefix) === 0; })) {
    return;
  }

  function addStyles() {
    if (document.getElementById('ns-ad-styles')) return;
    var style = document.createElement('style');
    style.id = 'ns-ad-styles';
    style.textContent =
      '.ns-ad-slot{width:100%;margin:28px auto;display:flex;justify-content:center;align-items:center;overflow:hidden;clear:both}' +
      '.ns-ad-slot iframe{display:block;border:0;max-width:100%;background:transparent}' +
      '.ns-ad-lead{min-height:90px;padding:10px 0}' +
      '.ns-ad-article-rect{min-height:250px;margin:34px auto}' +
      '.ns-ad-native{min-height:280px;margin:38px auto 18px}' +
      '.ns-ad-home-native{margin-top:44px}' +
      '@media(max-width:767px){.ns-ad-slot{margin:22px auto}.ns-ad-lead{min-height:50px;padding:6px 0}.ns-ad-native{min-height:300px}.ns-ad-article-rect{margin:28px auto}}';
    document.head.appendChild(style);
  }

  function makeSlot(className, label) {
    var slot = document.createElement('div');
    slot.className = 'ns-ad-slot ' + className;
    slot.setAttribute('aria-label', label || 'Advertisement');
    return slot;
  }

  function makeAdFrame(width, height, html, title) {
    var frame = document.createElement('iframe');
    frame.width = String(width);
    frame.height = String(height);
    frame.title = title || 'Advertisement';
    frame.scrolling = 'no';
    frame.loading = 'lazy';
    frame.setAttribute('referrerpolicy', 'no-referrer-when-downgrade');
    frame.setAttribute('sandbox', 'allow-scripts allow-popups allow-popups-to-escape-sandbox allow-top-navigation-by-user-activation');
    frame.srcdoc = '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;padding:0;background:transparent;overflow:hidden;display:flex;justify-content:center;align-items:flex-start}</style></head><body>' + html + '</body></html>';
    return frame;
  }

  function loadIframeAd(slot, key, width, height) {
    if (!slot || slot.dataset.loaded === '1') return;
    slot.dataset.loaded = '1';
    var html = '<script>atOptions={key:\'' + key + '\',format:\'iframe\',height:' + height + ',width:' + width + ',params:{}};<\/script>' +
      '<script src="https://www.highperformanceformat.com/' + key + '/invoke.js"><\/script>';
    slot.appendChild(makeAdFrame(width, height, html, 'Advertisement'));
  }

  function loadNative(slot) {
    if (!slot || slot.dataset.loaded === '1') return;
    slot.dataset.loaded = '1';
    var html = '<script async data-cfasync="false" src="https://pl30907500.effectivecpmnetwork.com/21b153a5ca3aac7a8e6450883186791d/invoke.js"><\/script>' +
      '<div id="container-21b153a5ca3aac7a8e6450883186791d"></div>';
    var frame = makeAdFrame(900, 320, html, 'Sponsored content');
    frame.style.width = '100%';
    frame.style.maxWidth = '900px';
    slot.appendChild(frame);
  }

  function loadSocialBar() {
    if (document.querySelector('script[data-ns-socialbar]')) return;
    var script = document.createElement('script');
    script.src = 'https://pl30907501.effectivecpmnetwork.com/15/63/c9/1563c9d278f2eaf1059657eaee10be16.js';
    script.async = true;
    script.setAttribute('data-ns-socialbar', '1');
    document.body.appendChild(script);
  }

  function insertResponsiveLeadAd(anchor) {
    if (!anchor || document.querySelector('.ns-ad-lead')) return;
    var slot = makeSlot('ns-ad-lead', 'Advertisement');
    anchor.insertAdjacentElement('afterend', slot);

    if (window.matchMedia('(max-width: 767px)').matches) {
      loadIframeAd(slot, 'ae585eccd50df0d5784c540ecab43e36', 320, 50);
    } else {
      loadIframeAd(slot, '9d4c7529548de4fe22f557d120b16061', 728, 90);
    }
  }

  function insertArticleAds() {
    var main = document.querySelector('.article-main');
    var content = document.querySelector('.article-content');
    if (!main || !content) return false;

    var hero = main.querySelector('.article-hero');
    insertResponsiveLeadAd(hero || main.querySelector('article > figure'));

    if (!document.querySelector('.ns-ad-article-rect')) {
      var children = Array.prototype.slice.call(content.children);
      var target = children.find(function (node, idx) {
        if (idx < 3) return false;
        return /^(P|UL|OL|DIV|H2)$/i.test(node.tagName);
      });
      if (target) {
        var rect = makeSlot('ns-ad-article-rect', 'Advertisement');
        target.insertAdjacentElement('afterend', rect);
        loadIframeAd(rect, '4058727155a733baa2ecc2ab9b3754aa', 300, 250);
      }
    }

    if (!document.querySelector('.ns-ad-native')) {
      var nativeSlot = makeSlot('ns-ad-native', 'Sponsored');
      content.appendChild(nativeSlot);
      loadNative(nativeSlot);
    }

    return true;
  }

  function insertHomeAds() {
    var main = document.querySelector('main');
    if (!main) return;

    var hero = main.querySelector('.editorial-hero');
    insertResponsiveLeadAd(hero);

    var latest = document.querySelector('#latest .container');
    if (latest && !document.querySelector('.ns-ad-native')) {
      var nativeSlot = makeSlot('ns-ad-native ns-ad-home-native', 'Sponsored');
      latest.appendChild(nativeSlot);
      loadNative(nativeSlot);
    }
  }

  function init() {
    if (!document.body || !document.querySelector('main')) return;
    addStyles();

    var isArticle = insertArticleAds();
    if (!isArticle) insertHomeAds();

    // One site-wide Social Bar unit on monetized pages.
    loadSocialBar();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
}());
