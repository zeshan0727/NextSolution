#!/usr/bin/env python3
from pathlib import Path
import re, sys

ROOT=Path(__file__).resolve().parents[2]
ARTICLE=ROOT/'wifidrophaptic-tweak-ios16.html'; INDEX=ROOT/'index.html'; TUTORIALS=ROOT/'tutorials.html'; SITEMAP=ROOT/'sitemap.xml'
HERO=ROOT/'assets/wifidrophaptic/wifidrophaptic-hero.svg'; PATH_ART=ROOT/'assets/wifidrophaptic/wifidrophaptic-path-concept.svg'
URL='https://nextsolution.cc/wifidrophaptic-tweak-ios16.html'; CLIENT='ca-pub-4770123899731214'
RS='<!-- WIFIDROPHAPTIC_RECENT_CARD_START -->'; RE='<!-- WIFIDROPHAPTIC_RECENT_CARD_END -->'
TS='<!-- WIFIDROPHAPTIC_TUTORIAL_CARD_START -->'; TE='<!-- WIFIDROPHAPTIC_TUTORIAL_CARD_END -->'
recent=f'''{RS}\n        <article class="card"><div class="icon"><i class="fas fa-wifi" aria-hidden="true"></i></div><h3>Wi-Fi Drop Haptic 1.0.0</h3><p>Feel one warning haptic when the active network path leaves Wi-Fi.</p><a class="more" href="wifidrophaptic-tweak-ios16.html">Read guide &amp; download <i class="fas fa-arrow-right"></i></a></article>\n        {RE}'''
tutorial=f'''{TS}\n      <article class="card featured"><a class="featured-media" href="wifidrophaptic-tweak-ios16.html" aria-label="Open the Wi-Fi Drop Haptic 1.0.0 guide"><img src="assets/wifidrophaptic/wifidrophaptic-hero.svg" alt="Wi-Fi Drop Haptic 1.0.0 network path concept" width="1600" height="900" loading="eager"></a><div class="featured-body"><div class="icon"><i class="fas fa-wifi" aria-hidden="true"></i></div><h3>Wi-Fi Drop Haptic 1.0.0</h3><div class="tags"><span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Free download</span></div><p>One warning haptic when the active iOS network path leaves Wi-Fi, with one clean Settings switch.</p><a href="wifidrophaptic-tweak-ios16.html">Read guide &amp; download</a></div></article>\n      {TE}'''
sitemap='  <url><loc>'+URL+'</loc><lastmod>2026-08-10</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>'

def read(p): return p.read_text(encoding='utf-8')
def write_if(p,t,changed):
    if read(p)!=t: p.write_text(t,encoding='utf-8'); changed.append(p)
def replace_or_insert(t,start,end,block,anchor):
    pat=re.compile(re.escape(start)+r'.*?'+re.escape(end),re.S)
    if pat.search(t): return pat.sub(block,t,count=1)
    if anchor not in t: raise SystemExit('Missing insertion anchor: '+anchor)
    return t.replace(anchor,anchor+'\n'+block,1)

def normalize():
    changed=[]
    i=read(INDEX); sec=i.find('<section class="section" id="tutorials">');
    if sec<0: raise SystemExit('Homepage Recent tutorials section missing')
    head=i[:sec]; tail=i[sec:]; anchor='<div class="grid">'; tail=replace_or_insert(tail,RS,RE,recent,anchor); write_if(INDEX,head+tail,changed)
    t=read(TUTORIALS); t=replace_or_insert(t,TS,TE,tutorial,'<section class="grid" aria-label="Tutorial guides">'); write_if(TUTORIALS,t,changed)
    s=read(SITEMAP); rows=[r for r in s.splitlines() if URL not in r]; s='\n'.join(rows); s=s.replace('</urlset>',sitemap+'\n</urlset>')+'\n'; write_if(SITEMAP,s,changed)
    return changed

def validate():
    a=read(ARTICLE); i=read(INDEX); t=read(TUTORIALS); s=read(SITEMAP)
    for p in (HERO,PATH_ART):
        if not p.is_file(): raise SystemExit('Missing asset '+str(p))
    checks=[(a,'Wi-Fi Drop Haptic 1.0.0'),(a,'href="./"'),(a,'href="tutorials.html" aria-current="page"'),(a,'href="videos.html"'),(a,'href="./#faq"'),(a,'WiFiDropHaptic_1.0.0_RootHide.deb'),(a,'WiFiDropHaptic_1.0.0_Rootless.deb'),(a,'https://nextsolution.cc/debfiles/'),(a,CLIENT),(a,'"@type":"TechArticle"'),(i,RS),(i,RE),(t,TS),(t,TE),(s,URL)]
    for text,n in checks:
        if n not in text: raise SystemExit('Validation missing: '+n)
    if a.count('pagead2.googlesyndication.com/pagead/js/adsbygoogle.js')!=1: raise SystemExit('AdSense loader must appear exactly once')
    if i.count(RS)!=1 or i.count(RE)!=1 or t.count(TS)!=1 or t.count(TE)!=1 or s.count(URL)!=1: raise SystemExit('Duplicate publication marker/URL')
    banned='zeshan0727'+'.github.io'
    if banned in a or banned in i or banned in t: raise SystemExit('Retired repository dependency found')

def main():
    check='--check' in sys.argv
    changed=[] if check else normalize(); validate()
    print('Wi-Fi Drop Haptic tutorial validation: PASS')
    for p in changed: print('Changed:',p.relative_to(ROOT))
if __name__=='__main__': main()
