/* Next Jailbreak — Google AdSense site-wide loader (legacy filename kept for existing pages) */
(function () {
  'use strict';

  // Keep shared branding and homepage/category content behavior unchanged.
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

  // Google AdSense account verification for legacy/static pages using this shared loader.
  var accountMeta = document.querySelector('meta[name="google-adsense-account"]');
  if (!accountMeta) {
    accountMeta = document.createElement('meta');
    accountMeta.name = 'google-adsense-account';
    document.head.appendChild(accountMeta);
  }
  accountMeta.content = 'ca-pub-4770123899731214';

  // Google AdSense only. Do not load Monetag, Adsterra, pop-under, push, or other ad-network scripts here.
  var adsenseSelector = 'script[src*="pagead2.googlesyndication.com/pagead/js/adsbygoogle.js"]';
  if (!document.querySelector(adsenseSelector)) {
    var adsense = document.createElement('script');
    adsense.async = true;
    adsense.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-4770123899731214';
    adsense.crossOrigin = 'anonymous';
    adsense.setAttribute('data-ns-adsense', '1');
    document.head.appendChild(adsense);
  }
}());
