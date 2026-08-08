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

def remove_marked(text, start, end):
    pattern=re.compile(r'^[ \t]*<!-- '+re.escape(start)+r' -->.*?^[ \t]*<!-- '+re.escape(end)+r' -->\n?', re.M|re.S)
    return pattern.sub('', text)

changed=[]

p=Path('index.html'); text=remove_marked(p.read_text(),f'{SLUG}_RECENT_CARD_START',f'{SLUG}_RECENT_CARD_END')
anchor='<!-- NEXT_HOME_LOCK_RECENT_CARD_START -->'
pos=text.find(anchor)
if pos < 0: raise SystemExit('Recent tutorials anchor missing')
line_start=text.rfind('\n',0,pos)+1
text=text[:line_start]+recent+text[line_start:]
p.write_text(text); changed.append(str(p))

p=Path('tutorials.html'); text=remove_marked(p.read_text(),f'{SLUG}_TUTORIAL_CARD_START',f'{SLUG}_TUTORIAL_CARD_END')
anchor='<!-- NEXT_HOME_LOCK_TUTORIAL_CARD_START -->'
pos=text.find(anchor)
if pos < 0: raise SystemExit('Tutorial grid anchor missing')
line_start=text.rfind('\n',0,pos)+1
text=text[:line_start]+tutorial_card+text[line_start:]
p.write_text(text); changed.append(str(p))

p=Path('sitemap.xml'); text=p.read_text()
entry=f'  <url><loc>https://nextsolution.cc/{ARTICLE}</loc><lastmod>2026-08-08</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>\n'
text=re.sub(r'^[ \t]*<url><loc>https://nextsolution\.cc/'+re.escape(ARTICLE)+r'</loc>.*?</url>\n?', '', text, flags=re.M)
anchor='<url><loc>https://nextsolution.cc/privacy.html</loc>'
pos=text.find(anchor)
if pos < 0: raise SystemExit('Sitemap anchor missing')
line_start=text.rfind('\n',0,pos)+1
text=text[:line_start]+entry+text[line_start:]
p.write_text(text); changed.append(str(p))

article=Path(ARTICLE).read_text(); packages=Path('Packages').read_text()
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
