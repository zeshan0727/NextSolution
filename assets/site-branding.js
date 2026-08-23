/* Next Solution — site-wide branding cleanup */
(function () {
  'use strict';

  var PERSONAL_NAME = /\b(?:Muhammad\s+)?Zeeshan(?:\s+Barvi)?\b/g;

  function replaceName(value) {
    return String(value || '').replace(PERSONAL_NAME, 'NextSolution');
  }

  function replaceText(root) {
    if (!root) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        var parent = node.parentElement;
        if (!parent || /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE)$/i.test(parent.tagName)) return NodeFilter.FILTER_REJECT;
        return /\b(?:Muhammad\s+)?Zeeshan(?:\s+Barvi)?\b/.test(node.nodeValue || '')
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(function (node) {
      node.nodeValue = replaceName(node.nodeValue);
    });
  }

  function cleanBranding() {
    Array.prototype.forEach.call(document.querySelectorAll('.topline-status'), function (node) {
      var value = (node.textContent || '').trim().toLowerCase();
      if (value.indexOf('direct link') !== -1 || value.indexOf('original source') !== -1) {
        node.remove();
      }
    });

    replaceText(document.body);

    Array.prototype.forEach.call(document.querySelectorAll('[content], [title], [aria-label], [alt]'), function (node) {
      ['content', 'title', 'aria-label', 'alt'].forEach(function (attr) {
        var value = node.getAttribute(attr);
        if (value && /\b(?:Muhammad\s+)?Zeeshan(?:\s+Barvi)?\b/.test(value)) {
          node.setAttribute(attr, replaceName(value));
        }
      });
    });

    Array.prototype.forEach.call(document.querySelectorAll('script[type="application/ld+json"]'), function (node) {
      if (node.textContent && /\b(?:Muhammad\s+)?Zeeshan(?:\s+Barvi)?\b/.test(node.textContent)) {
        node.textContent = replaceName(node.textContent);
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', cleanBranding, { once: true });
  } else {
    cleanBranding();
  }
}());
