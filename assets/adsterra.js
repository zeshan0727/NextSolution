/* Next Solution — Adsterra responsive ad manager */
(function () {
  'use strict';

  var path = window.location.pathname || '/';

  // Do not monetize repository depictions, legal/support pages, or app-internal pages.
  var blockedPrefixes = ['/depictions/', '/applications/', '/DailyLedger/', '/DailyTweaks/', '/Diagnostics/', '/ModuleGlassPreview/', '/NextPDF/', '/NextPost/'];
  var blockedExact = ['/privacy/', '/privacy.html', '/terms/', '/terms.html', '/next-ledger-support.html'];
  if (blockedExact.indexOf(path) !== -1 || blockedPrefixes.some(function (prefix) { return path.indexOf(prefix) === 0; })) {
    return;
  }

  function makeSlot(className, label) {
    var slot = document.createElement('div');
    slot.className = 'ns-ad-slot ' + className;
    slot.setAttribute('aria-label', label || 'Advertisement');
    return slot;
  }

  function loadIframeAd(slot, key, width, height) {
    if (!slot || slot.dataset.loaded === '1') return;
    slot.dataset.loaded = '1';

    var config = document.createElement('script');
    config.text = "atOptions={key:'" + key + "',format:'iframe',height:" + height + ",width:" + width + ",params:{}};";
    slot.appendChild(config);

    var loader = document.createElement('script');
    loader.src = 'https://www.highperformanceformat.com/' + key + '/invoke.js';
    loader.async = false;
    slot.appendChild(loader);
  }

  function loadNative(slot) {
    if (!slot || slot.dataset.loaded === '1') return;
    slot.dataset.loaded = '1';

    var loader = document.createElement('script');
    loader.async = true;
    loader.setAttribute('data-cfasync', 'false');
    loader.src = 'https://pl30907500.effectivecpmnetwork.com/21b153a5ca3aac7a8e6450883186791d/invoke.js';
    slot.appendChild(loader);

    var container = document.createElement('div');
    container.id = 'container-21b153a5ca3aac7a8e6450883186791d';
    slot.appendChild(container);
  }

  function loadSocialBar() {
    if (document.querySelector('script[data-ns-socialbar]')) return;
    var script = document.createElement('script');
    script.src = 'https://pl30907501.effectivecpmnetwork.com/15/63/c9/1563c9d278f2eaf1059657eaee10be16.js';
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
