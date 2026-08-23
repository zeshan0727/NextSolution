/* Next Solution — live article/category renderer */
(function () {
  'use strict';

  var path = window.location.pathname || '/';
  var isHome = path === '/' || path === '/index.html';
  var isTutorials = path === '/tutorials/' || path === '/tutorials' || path === '/tutorials.html';
  if (!isHome && !isTutorials) return;

  var HOME_FALLBACK_IMAGE = '/nextsolution-iphone-customization-showcase.png';
  var TWEAKS_START = 'AUTO_ARTICLES_TUTORIALS_START';
  var TWEAKS_END = 'AUTO_ARTICLES_TUTORIALS_END';
  var JAILBREAK_START = 'AUTO_ARTICLES_JAILBREAK_START';
  var JAILBREAK_END = 'AUTO_ARTICLES_JAILBREAK_END';

  function text(value) {
    return String(value == null ? '' : value);
  }

  function categoryId(entry) {
    var category = entry && entry.category;
    return category && typeof category === 'object' ? text(category.id).trim().toLowerCase() : '';
  }

  function categoryLabel(entry) {
    var category = entry && entry.category;
    return category && typeof category === 'object' && category.label ? text(category.label) : 'Tweak';
  }

  function isJailbreak(entry) {
    return categoryId(entry) === 'jailbreak' || categoryLabel(entry).trim().toLowerCase() === 'jailbreak';
  }

  /*
   * IMPORTANT: published-articles.json stores the actual deployed path.
   * Do not rewrite .html pages to directory-style URLs; many automated
   * articles are intentionally published as root-level .html files.
   */
  function cleanHref(value) {
    var href = text(value).trim();
    if (!href) return '/';
    if (/^https?:\/\//i.test(href) || href.charAt(0) === '/' || href.charAt(0) === '#') return href;
    return '/' + href.replace(/^\/+/, '');
  }

  function cleanImage(value) {
    var image = text(value).trim();
    if (!image) return HOME_FALLBACK_IMAGE;
    if (/^https?:\/\//i.test(image) || image.charAt(0) === '/') return image;
    return '/' + image.replace(/^\/+/, '');
  }

  function timestamp(entry) {
    return Date.parse(text(entry.modified_at || entry.published_at || '')) || 0;
  }

  function orderedEntries(entries) {
    return entries.filter(function (entry) {
      return entry && typeof entry === 'object' && entry.href;
    }).sort(function (a, b) {
      return timestamp(b) - timestamp(a);
    });
  }

  function installHomePolish() {
    if (!isHome) return;

    var hero = document.querySelector('.editorial-hero');
    if (!hero) return;

    /* Remove the old phone-shaped artwork completely. */
    var stage = hero.querySelector('.hero-stage');
    if (stage) stage.remove();
    hero.classList.add('editorial-hero-clean');

    if (!document.getElementById('ns-home-polish')) {
      var style = document.createElement('style');
      style.id = 'ns-home-polish';
      style.textContent =
        '.editorial-hero.editorial-hero-clean{' +
          'min-height:0;' +
          'grid-template-columns:minmax(0,1fr);' +
          'padding:clamp(48px,7vw,86px);' +
          'background:radial-gradient(circle at 88% 18%,rgba(255,255,255,.88),transparent 30%),linear-gradient(120deg,#f8faff 0%,#e8edff 54%,#eee5ff 100%);' +
        '}' +
        '.editorial-hero.editorial-hero-clean .hero-copy{max-width:930px;}' +
        '.editorial-hero.editorial-hero-clean .hero-copy h1{max-width:900px;}' +
        '.editorial-hero.editorial-hero-clean .hero-copy>p{max-width:760px;}' +
        '@media(max-width:720px){' +
          '.editorial-hero.editorial-hero-clean{padding:38px 24px;border-radius:24px;margin-top:18px;}' +
          '.editorial-hero.editorial-hero-clean .hero-copy h1{font-size:clamp(2.65rem,13vw,4rem);}' +
        '}';
      document.head.appendChild(style);
    }
  }

  function createCard(entry, eager) {
    var article = document.createElement('article');
    article.className = 'content-card has-visual';
    article.setAttribute('data-runtime-entry', text(entry.href));

    var meta = document.createElement('div');
    meta.className = 'card-meta';

    var category = document.createElement('span');
    category.className = 'tag';
    category.textContent = categoryLabel(entry);
    meta.appendChild(category);

    var source = document.createElement('span');
    source.className = 'tag';
    source.textContent = text(entry.source_name || 'Next Solution');
    meta.appendChild(source);
    article.appendChild(meta);

    var href = cleanHref(entry.href);
    var link = document.createElement('a');
    link.className = 'card-media';
    link.href = href;
    link.setAttribute('aria-label', 'Open ' + text(entry.title || entry.name || 'article'));

    var image = document.createElement('img');
    image.src = cleanImage(entry.image);
    image.alt = text(entry.title || entry.name || 'Next Solution article');
    image.width = 1600;
    image.height = 900;
    image.loading = eager ? 'eager' : 'lazy';
    image.addEventListener('error', function () {
      if (image.src.indexOf(HOME_FALLBACK_IMAGE) === -1) image.src = HOME_FALLBACK_IMAGE;
    }, { once: true });
    link.appendChild(image);
    article.appendChild(link);

    var title = document.createElement('h3');
    title.textContent = text(entry.title || entry.name || 'Next Solution article');
    article.appendChild(title);

    var description = document.createElement('p');
    description.textContent = text(entry.description || 'Read the full article for details, compatibility notes, and source information.');
    article.appendChild(description);

    var read = document.createElement('a');
    read.className = 'card-link';
    read.href = href;
    read.textContent = 'Read article →';
    article.appendChild(read);

    return article;
  }

  function removeRuntimeCards(container) {
    if (!container) return;
    Array.prototype.forEach.call(container.querySelectorAll('[data-runtime-entry]'), function (node) {
      node.remove();
    });
  }

  function removeMarkerBlock(container, startLabel, endLabel) {
    if (!container) return;
    var nodes = Array.prototype.slice.call(container.childNodes);
    var removing = false;
    nodes.forEach(function (node) {
      if (node.nodeType === Node.COMMENT_NODE && text(node.nodeValue).indexOf(startLabel) !== -1) {
        removing = true;
        return;
      }
      if (node.nodeType === Node.COMMENT_NODE && text(node.nodeValue).indexOf(endLabel) !== -1) {
        removing = false;
        return;
      }
      if (removing) node.remove();
    });
  }

  function updateCategoryLabels() {
    Array.prototype.forEach.call(document.querySelectorAll('.nav-links a, .category-rail a, .category-list a'), function (link) {
      var label = link.textContent.trim();
      if (label === 'Cydia Tweaks' || label === 'Latest tweaks') link.textContent = 'Tweaks';
      if (label === 'Latest tweak information') link.textContent = 'Tweaks & tweak articles';
      if (label === 'Jailbreak tutorials' || label === 'Jailbreak guides') link.textContent = 'Jailbreak news & guides';
    });
  }

  function renderHome(entries) {
    var feed = document.querySelector('#latest .news-feed');
    if (!feed) return;
    feed.innerHTML = '';
    orderedEntries(entries).slice(0, 5).forEach(function (entry, index) {
      feed.appendChild(createCard(entry, index < 2));
    });
  }

  function renderTutorials(entries) {
    var ordered = orderedEntries(entries);
    var tweakEntries = ordered.filter(function (entry) { return !isJailbreak(entry); });
    var jailbreakEntries = ordered.filter(isJailbreak);

    var tweakGrid = document.querySelector('#verified-articles .archive-cards');
    if (tweakGrid) {
      removeRuntimeCards(tweakGrid);
      removeMarkerBlock(tweakGrid, TWEAKS_START, TWEAKS_END);
      var featured = tweakGrid.querySelector('.content-card.featured');
      var insertAfter = featured;
      tweakEntries.forEach(function (entry) {
        var card = createCard(entry, false);
        if (insertAfter && insertAfter.parentNode === tweakGrid) {
          insertAfter.insertAdjacentElement('afterend', card);
          insertAfter = card;
        } else {
          tweakGrid.appendChild(card);
          insertAfter = card;
        }
      });
    }

    var jailbreakGrid = document.querySelector('#jailbreak-guides .guide-card-grid');
    if (jailbreakGrid) {
      removeRuntimeCards(jailbreakGrid);
      removeMarkerBlock(jailbreakGrid, JAILBREAK_START, JAILBREAK_END);
      var firstStatic = jailbreakGrid.firstElementChild;
      jailbreakEntries.forEach(function (entry) {
        var card = createCard(entry, false);
        if (firstStatic) jailbreakGrid.insertBefore(card, firstStatic);
        else jailbreakGrid.appendChild(card);
      });
    }

    var tweakHeading = document.querySelector('#verified-articles h2');
    if (tweakHeading) tweakHeading.textContent = 'Tweaks & tweak articles';
    var jailbreakHeading = document.querySelector('#jailbreak-guides h2');
    if (jailbreakHeading) jailbreakHeading.textContent = 'Jailbreak news & guides';
  }

  function init() {
    installHomePolish();
    updateCategoryLabels();
    fetch('/automation/published-articles.json?ts=' + Date.now(), { cache: 'no-store' })
      .then(function (response) {
        if (!response.ok) throw new Error('article index request failed');
        return response.json();
      })
      .then(function (data) {
        var entries = data && Array.isArray(data.entries) ? data.entries : [];
        if (!entries.length) return;
        if (isHome) renderHome(entries);
        if (isTutorials) renderTutorials(entries);
      })
      .catch(function () {
        /* Keep the static HTML untouched if the live article index is unavailable. */
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
}());
