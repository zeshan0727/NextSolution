#!/usr/bin/env python3
from pathlib import Path

ROOT=Path('.')
article=ROOT/'clean-home-labels-tweak-ios16.html'
index=ROOT/'index.html'; tutorials=ROOT/'tutorials.html'; sitemap=ROOT/'sitemap.xml'
legacy='zeshan0727'+'.github.io'
client='ca-pub-4770123899731214'
html=article.read_text()
assert html.count('pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client='+client)==1
assert legacy not in html and 'raw.githubusercontent.com/zeshan0727/' not in html
for required in ['href="./">Home</a>','href="tutorials.html" aria-current="page">Tutorials</a>','href="videos.html">Videos</a>','href="./#faq">FAQ</a>','TechArticle','CleanHomeLabels_1.0.0_RootHide.deb','CleanHomeLabels_1.0.0_Rootless.deb']:
    assert required in html, required
home_card='''<!-- CLEAN_HOME_LABELS_RECENT_CARD_START -->\n            <article class="content-card featured">\n              <div class="card-meta"><span class="tag">Next Solution release</span><span class="tag">Home Screen</span></div>\n              <div class="card-icon" aria-hidden="true">CH</div>\n              <h3>Clean Home Labels 1.0.0 — Hide Icon Names</h3>\n              <p>Hide SpringBoard app icon names for a cleaner layout while keeping icons and badges intact.</p>\n              <a class="card-link" href="clean-home-labels-tweak-ios16.html">Read guide and download →</a>\n            </article>\n            <!-- CLEAN_HOME_LABELS_RECENT_CARD_END -->\n\n            '''
tutorial_card='''<!-- CLEAN_HOME_LABELS_TUTORIAL_CARD_START -->\n          <article class="featured-guide">\n            <a class="featured-media" href="clean-home-labels-tweak-ios16.html" aria-label="Open the Clean Home Labels 1.0.0 guide"><img src="assets/clean-home-labels/clean-home-labels-hero.svg" alt="Clean Home Labels icon-name hiding concept" width="1600" height="900" loading="eager"></a>\n            <div class="featured-body"><div class="tags"><span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Next Solution release</span></div><div class="card-icon" aria-hidden="true">CH</div><h3>Clean Home Labels 1.0.0</h3><p>Hide Home Screen app icon names while preserving icons and badges.</p><a class="button button-primary" href="clean-home-labels-tweak-ios16.html">Read guide and download</a></div>\n          </article>\n          <!-- CLEAN_HOME_LABELS_TUTORIAL_CARD_END -->\n\n          '''
def replace_marker(path,start,end,block,anchor):
    text=path.read_text()
    if start in text:
        a=text.index(start); b=text.index(end,a)+len(end)
        text=text[:a]+block.strip()+text[b:]
    else:
        assert anchor in text, f'anchor missing in {path}'
        text=text.replace(anchor,block+anchor,1)
    path.write_text(text)
replace_marker(index,'<!-- CLEAN_HOME_LABELS_RECENT_CARD_START -->','<!-- CLEAN_HOME_LABELS_RECENT_CARD_END -->',home_card,'<!-- NEXT_HOME_LOCK_RECENT_CARD_START -->')
replace_marker(tutorials,'<!-- CLEAN_HOME_LABELS_TUTORIAL_CARD_START -->','<!-- CLEAN_HOME_LABELS_TUTORIAL_CARD_END -->',tutorial_card,'<!-- NEXT_HOME_LOCK_TUTORIAL_CARD_START -->')
sm=sitemap.read_text(); entry='''  <url>\n    <loc>https://nextsolution.cc/clean-home-labels-tweak-ios16.html</loc>\n    <lastmod>2026-08-13</lastmod>\n    <changefreq>monthly</changefreq>\n    <priority>0.9</priority>\n  </url>\n'''
if 'clean-home-labels-tweak-ios16.html' not in sm: sm=sm.replace('</urlset>',entry+'</urlset>')
sitemap.write_text(sm)
assert index.read_text().count('CLEAN_HOME_LABELS_RECENT_CARD_START')==1
assert tutorials.read_text().count('CLEAN_HOME_LABELS_TUTORIAL_CARD_START')==1
assert sitemap.read_text().count('clean-home-labels-tweak-ios16.html')==1
for p in [article,index,tutorials,sitemap]: assert legacy not in p.read_text()
print('Clean Home Labels tutorial publication checks PASS')
