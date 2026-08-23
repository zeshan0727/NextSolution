/* Next Solution — site-wide branding cleanup */
(function () {
  'use strict';

  function replaceText(root) {
    if (!root) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        var parent = node.parentElement;
        if (!parent || /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE)$/i.test(parent.tagName)) return NodeFilter.FILTER_REJECT;
        return node.nodeValue && node.nodeValue.indexOf('Zeeshan Barvi') !== -1
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(function (node) {
      node.nodeValue = node.nodeValue.replace(/Zeeshan Barvi/g, 'Next Solution');
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

    Array.prototype.forEach.call(document.querySelectorAll('[content]'), function (node) {
      var value = node.getAttribute('content');
      if (value && value.indexOf('Zeeshan Barvi') !== -1) {
        node.setAttribute('content', value.replace(/Zeeshan Barvi/g, 'Next Solution'));
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', cleanBranding, { once: true });
  } else {
    cleanBranding();
  }
}());
