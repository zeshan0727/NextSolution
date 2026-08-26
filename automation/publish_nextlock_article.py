from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, needle: str, replacement: str):
    text = path.read_text()
    if replacement.strip() in text:
        return False
    if needle not in text:
        raise SystemExit(f"Marker not found in {path}: {needle[:80]}")
    path.write_text(text.replace(needle, replacement, 1))
    return True

index = ROOT / "index.html"
tutorials = ROOT / "tutorials.html"
feed = ROOT / "feed.xml"
sitemap = ROOT / "sitemap.xml"

# Home structured data: newest original release first.
if '"url": "https://nextjailbreak.com/nextlock-tweak.html"' not in index.read_text():
    replace_once(
        index,
        '    "blogPost": [\n',
        '    "blogPost": [\n'
        '      {"@type": "BlogPosting", "headline": "NextLock 1.0.1 — Customize Lock Screen Time, Date & Icons", "url": "https://nextjailbreak.com/nextlock-tweak.html", "datePublished": "2026-08-16", "dateModified": "2026-08-16"},\n'
    )

# Home Recent / Latest articles card.
if 'NEXTLOCK_RECENT_CARD_START' not in index.read_text():
    card = '''          <!-- NEXTLOCK_RECENT_CARD_START -->
            <article class="content-card has-visual featured">
              <a class="card-media" href="nextlock-tweak.html" aria-label="Read the NextLock 1.0.1 feature guide"><img src="assets/articles/nextlock/nextlock-hero.jpg" alt="NextLock time font, date and custom icon Lock Screen showcase" width="360" height="240" loading="eager"></a>
              <div class="card-meta"><span class="tag">Next Jailbreak release</span><span class="tag">Lock Screen</span><span class="tag">iOS 15+</span></div>
              <h3>NextLock 1.0.1 — Lock Screen, Your Way</h3>
              <p>Change time and date fonts, size, color, position and shadows, then add 30+ icons or your own transparent sticker-style photo.</p>
              <a class="card-link" href="nextlock-tweak.html">See features and install →</a>
            </article>
          <!-- NEXTLOCK_RECENT_CARD_END -->
'''
    replace_once(index, '          <div class="news-feed">\n', '          <div class="news-feed">\n' + card)

# Original Releases: put NextLock first.
if 'NEXTLOCK_TUTORIAL_CARD_START' not in tutorials.read_text():
    release = '''          <!-- NEXTLOCK_TUTORIAL_CARD_START -->
          <article class="featured-guide">
            <a class="featured-media" href="nextlock-tweak.html" aria-label="Open the NextLock 1.0.1 guide"><img src="assets/articles/nextlock/nextlock-hero.jpg" alt="NextLock Lock Screen customization showcase" width="360" height="240" loading="eager"></a>
            <div class="featured-body">
              <div class="tags"><span class="tag">iOS 15+</span><span class="tag">RootHide</span><span class="tag">Rootless</span><span class="tag">Next Jailbreak release</span></div>
              <div class="card-icon" aria-hidden="true">NL</div>
              <h3>NextLock 1.0.1</h3>
              <p>Customize Lock Screen time and date fonts, colors, size, position and shadows, then add built-in icons or transparent sticker-style custom photos.</p>
              <a class="button button-primary" href="nextlock-tweak.html">Read guide and download</a>
            </div>
          </article>
          <!-- NEXTLOCK_TUTORIAL_CARD_END -->
'''
    replace_once(tutorials, '        <div class="content-grid releases-grid">\n', '        <div class="content-grid releases-grid">\n' + release)

# RSS: newest item first after channel metadata.
if 'https://nextjailbreak.com/nextlock-tweak.html' not in feed.read_text():
    item = '''    <item>
      <title>NextLock 1.0.1 — Customize Lock Screen Time, Date &amp; Icons</title>
      <link>https://nextjailbreak.com/nextlock-tweak.html</link>
      <guid isPermaLink="true">https://nextjailbreak.com/nextlock-tweak.html</guid>
      <pubDate>Sun, 16 Aug 2026 12:58:00 GMT</pubDate>
      <description>NextLock by Next Jailbreak adds 27 fonts, independent time and date styling, position controls, shadows, 30+ icons and transparent sticker-style custom photos for Rootless and RootHide jailbreaks.</description>
      <category>Lock Screen</category>
    </item>
'''
    replace_once(feed, '    <language>en</language>\n', '    <language>en</language>\n' + item)

# Sitemap: add article and refresh important landing-page dates.
st = sitemap.read_text()
st = st.replace('<loc>https://nextjailbreak.com/</loc>\n    <lastmod>2026-08-13</lastmod>', '<loc>https://nextjailbreak.com/</loc>\n    <lastmod>2026-08-16</lastmod>')
st = st.replace('<loc>https://nextjailbreak.com/tutorials.html</loc>\n    <lastmod>2026-08-13</lastmod>', '<loc>https://nextjailbreak.com/tutorials.html</loc>\n    <lastmod>2026-08-16</lastmod>')
if 'https://nextjailbreak.com/nextlock-tweak.html' not in st:
    marker = '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    entry = '''  <url>
    <loc>https://nextjailbreak.com/nextlock-tweak.html</loc>
    <lastmod>2026-08-16</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.9</priority>
  </url>
'''
    if marker not in st:
        raise SystemExit('Sitemap root marker not found')
    st = st.replace(marker, marker + entry, 1)
sitemap.write_text(st)

for p in (index, tutorials, feed, sitemap):
    print(f"updated {p.name}")
