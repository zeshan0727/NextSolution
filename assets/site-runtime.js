/* Next Jailbreak — shared site runtime */
(function () {
  'use strict';

  if (!document.querySelector('script[data-ns-site-branding]')) {
    var brandingScript = document.createElement('script');
    brandingScript.src = '/assets/site-branding.js?v=20260823-2';
    brandingScript.defer = true;
    brandingScript.setAttribute('data-ns-site-branding', '1');
    document.head.appendChild(brandingScript);
  }

  if (!document.querySelector('script[data-ns-site-content]')) {
    var contentScript = document.createElement('script');
    contentScript.src = '/assets/site-content.js?v=20260825-1';
    contentScript.defer = true;
    contentScript.setAttribute('data-ns-site-content', '1');
    document.head.appendChild(contentScript);
  }
}());
