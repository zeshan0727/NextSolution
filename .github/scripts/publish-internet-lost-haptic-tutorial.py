#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[2]
ARTICLE=ROOT/'internet-lost-haptic-tweak-ios16.html'; INDEX=ROOT/'index.html'; TUTORIALS=ROOT/'tutorials.html'; SITEMAP=ROOT/'sitemap.xml'
HERO=ROOT/'assets/internetlosthaptic/internetlosthaptic-hero.svg'; FLOW=ROOT/'assets/internetlosthaptic/internetlosthaptic-flow-concept.svg'
URL='https://nextsolution.cc/internet-lost-haptic-tweak-ios16.html'; CLIENT='ca-pub-4770123899731214'
RS='<!-- INTERNET_LOST_HAPTIC_RECENT_CARD_START -->'; RE='<!-- INTERNET_LOST_HAPTIC_RECENT_CARD_END -->'; TS='<!-- INTERNET_LOST_HAPTIC_TUTORIAL_CARD_START -->'; TE='<!-- INTERNET_LOST_HAPTIC_TUTORIAL_CARD_END -->'
recent=f'''{RS}\n        <article class="card"><div class="icon"><i class="fas fa-wifi" aria-hidden="true"></i></div><h3>Internet Lost Haptic 1.0.0</h3><p>Get one warning haptic when a usable network path becomes unavailable.</p><a class="more" href="internet-lost-haptic-tweak-ios16.html">Read guide &amp; download <i class="fas fa-arrow-right"></i></a></article>\n        {RE}'''
tutorial=f'''{TS}\n      <article class="card featured"><a class="featured-media" href="internet-lost-haptic-tweak-ios16.html" aria-label="Open the Internet Lost Haptic 1.0.0 guide"><img src="assets/internetlosthaptic/internetlosthaptic-hero.svg" alt="Internet Lost Haptic 1.0.0 concept" width="1600" height="900" loading="eager"></a><div class="featured-body"><div class="icon"><i class="fas fa-wifi" aria-hidden="true"></i></div><h3>Internet Lost Haptic 1.0.0</h3><div class="tags"><span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Free download</span></div><p>One warning haptic only when iOS changes from a usable network path to unavailable, with ordinary Wi-Fi-to-cellular handoff rejected.</p><a href="internet-lost-haptic-tweak-ios16.html">Read guide &amp; download</a></div></article>\n      {TE}'''
sitemap='  <url><loc>'+URL+'</loc><lastmod>2026-08-12</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>'
def read(p): return p.read_text(encoding='utf-8')
def write_if(p,t,c):
    if read(p)!=t: p.write_text(t,encoding='utf-8'); c.append(p)
def replace_or_insert(t,s,e,b,a):
    pat=re.compile(re.escape(s)+r'.*?'+re.escape(e),re.S)
    if pat.search(t): return pat.sub(b,t,count=1)
    if a not in t: raise SystemExit('Missing insertion anchor: '+a)
    return t.replace(a,a+'\n'+b,1)
def normalize():
    c=[]; i=read(INDEX); sec=i.find('<section class="section" id="tutorials">')
    if sec<0: raise SystemExit('Homepage Recent tutorials section missing')
    head,tail=i[:sec],i[sec:]; tail=replace_or_insert(tail,RS,RE,recent,'<div class="grid">'); write_if(INDEX,head+tail,c)
    t=read(TUTORIALS); t=replace_or_insert(t,TS,TE,tutorial,'<section class="grid" aria-label="Tutorial guides">'); write_if(TUTORIALS,t,c)
    s=read(SITEMAP); s='\n'.join(r for r in s.splitlines() if URL not in r); s=s.replace('</urlset>',sitemap+'\n</urlset>')+'\n'; write_if(SITEMAP,s,c); return c
def validate():
    a,i,t,s=map(read,(ARTICLE,INDEX,TUTORIALS,SITEMAP))
    for p in (HERO,FLOW):
        if not p.is_file(): raise SystemExit('Missing asset '+str(p))
    need=[(a,'Internet Lost Haptic 1.0.0'),(a,'href="./"'),(a,'href="tutorials.html" aria-current="page"'),(a,'href="videos.html"'),(a,'href="./#faq"'),(a,'InternetLostHaptic_1.0.0_RootHide.deb'),(a,'InternetLostHaptic_1.0.0_Rootless.deb'),(a,CLIENT),(a,'"@type":"TechArticle"'),(i,RS),(i,RE),(t,TS),(t,TE),(s,URL)]
    for text,n in need:
        if n not in text: raise SystemExit('Validation missing: '+n)
    if a.count('pagead2.googlesyndication.com/pagead/js/adsbygoogle.js')!=1: raise SystemExit('AdSense loader must appear exactly once')
    if i.count(RS)!=1 or i.count(RE)!=1 or t.count(TS)!=1 or t.count(TE)!=1 or s.count(URL)!=1: raise SystemExit('Duplicate publication marker/URL')
    banned='zeshan0727'+'.github.io'
    if banned in a or banned in i or banned in t or banned in s: raise SystemExit('Retired repository dependency found')
def main():
    check='--check' in sys.argv; changed=[] if check else normalize(); validate(); print('Internet Lost Haptic tutorial validation: PASS')
    for p in changed: print('Changed:',p.relative_to(ROOT))
if __name__=='__main__': main()
