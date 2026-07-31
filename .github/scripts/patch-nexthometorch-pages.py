from pathlib import Path

index = Path("index.html")
text = index.read_text()
text = text.replace(
    "The newest Next Solution guides, with PhoneAura permanently pinned for quick access.",
    "The newest Next Solution guides, with PhoneAura and Next Home Torch permanently pinned for quick access.",
)
card = '''
        <!-- NEXTHOMETORCH_RECENT_CARD_START -->
        <article class="card">
          <div class="icon"><i class="fas fa-bolt" aria-hidden="true"></i></div>
          <h3>Next Home Torch 1.0.0 — Two-Finger Flashlight</h3>
          <p>Toggle the flashlight from empty Home Screen space with one simultaneous two-finger tap. RootHide and rootless builds for iOS 15+.</p>
          <a class="more" href="next-home-torch-ios15-ios16.html">Read guide &amp; download <i class="fas fa-arrow-right" aria-hidden="true"></i></a>
        </article>
        <!-- NEXTHOMETORCH_RECENT_CARD_END -->
'''
marker = "        <!-- PHONEAURA_RECENT_CARD_END -->\n"
if "NEXTHOMETORCH_RECENT_CARD_START" not in text:
    assert marker in text
    text = text.replace(marker, marker + card, 1)
index.write_text(text)

tutorials = Path("tutorials.html")
text = tutorials.read_text()
card = '''
      <article class="card">
        <div class="icon"><i class="fas fa-bolt" aria-hidden="true"></i></div>
        <h3>Next Home Torch 1.0.0</h3>
        <p>Use a two-finger tap on empty Home Screen wallpaper to toggle the flashlight. Includes direct RootHide and rootless downloads.</p>
        <a href="next-home-torch-ios15-ios16.html">Read guide &amp; download</a>
      </article>
'''
if 'href="next-home-torch-ios15-ios16.html"' not in text:
    start = text.index('<section class="grid" aria-label="Tutorial guides">')
    end = text.index("</section>", start)
    text = text[:end] + card + "\n" + text[end:]
tutorials.write_text(text)

sitemap = Path("sitemap.xml")
text = sitemap.read_text()
entry = '  <url><loc>https://nextsolution.cc/next-home-torch-ios15-ios16.html</loc><lastmod>2026-07-31</lastmod><changefreq>monthly</changefreq><priority>0.9</priority></url>\n'
if "next-home-torch-ios15-ios16.html" not in text:
    marker = '  <url><loc>https://nextsolution.cc/privacy.html</loc>'
    assert marker in text
    text = text.replace(marker, entry + marker, 1)
sitemap.write_text(text)
