#!/usr/bin/env python3
from pathlib import Path
import re

SLUG='THERMAL_WARNING_HAPTIC'
VERSION='1.0.0'
ARTICLE='thermal-warning-haptic-tweak-ios16.html'
ROOT_HIDE='ThermalWarningHaptic_1.0.0_RootHide.deb'
ROOTLESS='ThermalWarningHaptic_1.0.0_Rootless.deb'
ADS='https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-4770123899731214'

recent=f'''        <!-- {SLUG}_RECENT_CARD_START -->
        <article class="card">
          <div class="icon"><i class="fas fa-temperature-high" aria-hidden="true"></i></div>
          <h3>Thermal Warning Haptic {VERSION}</h3>
          <p>Get one warning haptic when iOS newly enters a serious or critical thermal state. Built for RootHide and rootless jailbreaks.</p>
          <a class="more" href="{ARTICLE}">Read guide &amp; download <i class="fas fa-arrow-right" aria-hidden="true"></i></a>
        </article>
        <!-- {SLUG}_RECENT_CARD_END -->

'''

tutorial_card=f'''      <!-- {SLUG}_TUTORIAL_CARD_START -->
      <article class="card featured">
        <a class="featured-media" href="{ARTICLE}" aria-label="Open the Thermal Warning Haptic {VERSION} guide">
          <img src="assets/thermal-warning-haptic/thermal-warning-haptic-hero.svg" alt="Thermal Warning Haptic {VERSION} thermal transition concept" width="1600" height="900" loading="eager">
        </a>
        <div class="featured-body">
          <div class="icon"><i class="fas fa-temperature-high" aria-hidden="true"></i></div>
          <h3>Thermal Warning Haptic {VERSION} — Serious Heat Alert</h3>
          <div class="tags" aria-label="Thermal Warning Haptic compatibility">
            <span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Free download</span>
          </div>
          <p>One focused haptic when the system newly enters a serious or critical thermal state, with one clean enable switch.</p>
          <a href="{ARTICLE}">Read guide &amp; download</a>
        </div>
      </article>
      <!-- {SLUG}_TUTORIAL_CARD_END -->

'''

def replace_marked(text, start, end, block):
    pattern=re.compile(r'\s*<!-- '+re.escape(start)+r' -->.*?<!-- '+re.escape(end)+r' -->\s*', re.S)
    text=pattern.sub('\n', text)
    return text, block

changed=[]

p=Path('index.html'); text=p.read_text()
text,_=replace_marked(text,f'{SLUG}_RECENT_CARD_START',f'{SLUG}_RECENT_CARD_END',recent)
anchor='        <!-- NEXT_HOME_LOCK_RECENT_CARD_START -->'
if anchor not in text: raise SystemExit('Recent tutorials anchor missing')
text=text.replace(anchor,recent+anchor,1)
p.write_text(text); changed.append(str(p))

p=Path('tutorials.html'); text=p.read_text()
text,_=replace_marked(text,f'{SLUG}_TUTORIAL_CARD_START',f'{SLUG}_TUTORIAL_CARD_END',tutorial_card)
anchor='      <!-- NEXT_HOME_LOCK_TUTORIAL_CARD_START -->'
if anchor not in text: raise SystemExit('Tutorial grid anchor missing')
text=text.replace(anchor,tutorial_card+anchor,1)
p.write_text(text); changed.append(str(p))

p=Path('sitemap.xml'); text=p.read_text()
entry=f'  <url><loc>https://nextsolution.cc/{ARTICLE}</loc><lastmod>2026-08-08</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>\n'
text=re.sub(r'\s*<url><loc>https://nextsolution\.cc/'+re.escape(ARTICLE)+r'</loc>.*?</url>\s*','\n',text)
anchor='  <url><loc>https://nextsolution.cc/privacy.html</loc>'
if anchor not in text: raise SystemExit('Sitemap anchor missing')
text=text.replace(anchor,entry+anchor,1)
p.write_text(text); changed.append(str(p))

article=Path(ARTICLE).read_text()
packages=Path('Packages').read_text()
assert article.count(ADS)==1, 'tutorial must contain exactly one verified AdSense publisher script'
assert 'ca-pub-4770123899731214' in article
assert 'zeshan0727.github.io' not in article
assert f'https://nextsolution.cc/debfiles/{ROOT_HIDE}' in article
assert f'https://nextsolution.cc/debfiles/{ROOTLESS}' in article
assert f'Filename: ./debfiles/{ROOT_HIDE}' in packages
assert f'Filename: ./debfiles/{ROOTLESS}' in packages
assert packages.count('Package: com.nextsolution.thermalwarninghaptic')==2
assert 'aria-current="page">Tutorials</a>' in article
assert all(x in article for x in ['>Home</a>','>Tutorials</a>','>Videos</a>','>FAQ</a>'])
assert '"@type":"TechArticle"' in article
assert Path('assets/thermal-warning-haptic/thermal-warning-haptic-hero.svg').exists()
assert Path('assets/thermal-warning-haptic/thermal-warning-haptic-settings.svg').exists()

print('Updated:', ', '.join(changed))
print('Validated exact live package filenames, navigation, TechArticle, assets, and existing AdSense publisher script.')
