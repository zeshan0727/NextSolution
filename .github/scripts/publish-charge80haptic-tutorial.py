#!/usr/bin/env python3
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
INDEX=ROOT/'index.html'; TUTORIALS=ROOT/'tutorials.html'; SITEMAP=ROOT/'sitemap.xml'; ARTICLE=ROOT/'charge80haptic-tweak-ios16.html'
HERO=ROOT/'assets/charge80haptic/charge80haptic-hero.svg'; SETTINGS=ROOT/'assets/charge80haptic/charge80haptic-settings.svg'
VERSION='1.0.0'; CLIENT='ca-pub-4770123899731214'; URL='https://nextsolution.cc/charge80haptic-tweak-ios16.html'
RH='https://nextsolution.cc/debfiles/Charge80Haptic_1.0.0_RootHide.deb'; RL='https://nextsolution.cc/debfiles/Charge80Haptic_1.0.0_Rootless.deb'
RS='<!-- CHARGE80HAPTIC_RECENT_CARD_START -->'; RE='<!-- CHARGE80HAPTIC_RECENT_CARD_END -->'; TS='<!-- CHARGE80HAPTIC_TUTORIAL_CARD_START -->'; TE='<!-- CHARGE80HAPTIC_TUTORIAL_CARD_END -->'
RECENT=f'''{RS}\n        <article class="card"><div class="icon"><i class="fas fa-battery-three-quarters" aria-hidden="true"></i></div><h3>Charge 80 Haptic 1.0.0 — Charging Cue</h3><p>Get one success haptic when a charging iPhone crosses 80%, without changing Apple's charging policy.</p><a class="more" href="charge80haptic-tweak-ios16.html">Read guide &amp; download <i class="fas fa-arrow-right" aria-hidden="true"></i></a></article>\n        {RE}'''
TCARD=f'''{TS}\n      <article class="card featured"><a class="featured-media" href="charge80haptic-tweak-ios16.html" aria-label="Open the Charge 80 Haptic 1.0.0 guide"><img src="assets/charge80haptic/charge80haptic-hero.svg" alt="Charge 80 Haptic 1.0.0 charging concept" width="1600" height="900" loading="eager"></a><div class="featured-body"><div class="icon"><i class="fas fa-battery-three-quarters" aria-hidden="true"></i></div><h3>Charge 80 Haptic 1.0.0 — 80% Charging Alert</h3><div class="tags"><span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Free download</span></div><p>One success haptic when charging crosses 80%. It does not stop charging or modify system battery policy.</p><a href="charge80haptic-tweak-ios16.html">Read guide &amp; download</a></div></article>\n      {TE}'''

def read(p): return p.read_text(encoding='utf-8')
def write_if(p,t):
    old=read(p)
    if old!=t: p.write_text(t,encoding='utf-8'); print('changed:',p.relative_to(ROOT))
def strip_block(t,s,e): return re.sub(r'\s*'+re.escape(s)+r'.*?'+re.escape(e)+r'\s*','\n',t,flags=re.S)

def update_index():
    t=strip_block(read(INDEX),RS,RE); sec=t.find('<section class="section" id="tutorials">'); assert sec>=0
    g=t.find('<div class="grid">',sec); assert g>=0; pos=g+len('<div class="grid">'); t=t[:pos]+'\n        '+RECENT+t[pos:]; write_if(INDEX,t)
def update_tutorials():
    t=strip_block(read(TUTORIALS),TS,TE); marker='<section class="grid" aria-label="Tutorial guides">'; pos=t.find(marker); assert pos>=0; pos+=len(marker); t=t[:pos]+'\n      '+TCARD+t[pos:]; write_if(TUTORIALS,t)
def update_sitemap():
    t=read(SITEMAP); rows=[r for r in t.splitlines() if URL not in r]; t='\n'.join(rows)
    entry='  <url><loc>'+URL+'</loc><lastmod>2026-08-09</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>'
    t=t.replace('</urlset>',entry+'\n</urlset>')+'\n'; write_if(SITEMAP,t)
def validate():
    a=read(ARTICLE); i=read(INDEX); tu=read(TUTORIALS); sm=read(SITEMAP)
    for p in (HERO,SETTINGS): assert p.is_file(),p
    for n in ['href="./"','href="tutorials.html" aria-current="page"','href="videos.html"','href="./#faq"',RH,RL,'"@type":"TechArticle"',CLIENT,'Charge 80 Haptic 1.0.0']: assert n in a,n
    assert a.count('pagead2.googlesyndication.com/pagead/js/adsbygoogle.js')==1
    assert 'zeshan0727.github.io' not in a and 'raw.githubusercontent.com/zeshan0727/zeshan0727.github.io' not in a
    assert i.count(RS)==1 and i.count(RE)==1 and tu.count(TS)==1 and tu.count(TE)==1 and sm.count(URL)==1
    assert 'https://nextsolution.cc/' in a
    print('Charge 80 Haptic tutorial validation: PASS')

if __name__=='__main__': update_index(); update_tutorials(); update_sitemap(); validate()
