# One-shot publication helper for the PhoneAura 0.4.15 tutorial.
# This branch commit intentionally triggers the merged publication workflow.
from pathlib import Path

INDEX_PATH = Path("index.html")
SITEMAP_PATH = Path("sitemap.xml")

CARD_START = "<!-- PHONEAURA_TUTORIAL_CARD_START -->"
CARD_END = "<!-- PHONEAURA_TUTORIAL_CARD_END -->"

PHONEAURA_CARD = f"""
      {CARD_START}
      <div class="content-card blog-post-card" style="overflow: hidden; padding: 0; border: 1px solid rgba(106,17,203,.24);">
        <a href="phoneaura-tweak-ios16.html" style="display: block; text-decoration: none; color: inherit;">
          <img src="assets/phoneaura/phoneaura-hero.svg"
               alt="PhoneAura 0.4.15 iOS 16 Phone app redesign concept"
               loading="lazy"
               width="1600"
               height="900"
               style="display: block; width: 100%; aspect-ratio: 16 / 9; object-fit: cover; border-bottom: 1px solid rgba(106,17,203,.18);">
        </a>
        <div style="padding: 1.35rem;">
          <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 12px;">
            <span style="width: 42px; height: 42px; display: grid; place-items: center; border-radius: 14px; color: white; font-size: 18px; font-weight: 900; background: linear-gradient(135deg,#7b2cff,#168dff); box-shadow: 0 10px 24px rgba(74,75,255,.28);">P</span>
            <div>
              <h3 style="margin: 0;">PhoneAura 0.4.15</h3>
              <p style="color: #666; font-size: .9rem; margin: 2px 0 0;">📱 Free iOS 16 Phone App Redesign</p>
            </div>
          </div>
          <p><strong>RootHide and rootless downloads included.</strong> Redesign Favorites, Recents, Contacts and Keypad with fixed saved-number suggestions, smart call filters and long-press Cut, Copy and Paste controls.</p>
          <div style="display: flex; gap: 10px; margin-top: 1rem; flex-wrap: wrap;">
            <a href="phoneaura-tweak-ios16.html" class="read-more blog-post-btn">
              Read Full Guide <i class="fas fa-arrow-right"></i>
            </a>
            <a href="sileo://source/https://zeshan0727.github.io/" class="youtube-link" style="background: linear-gradient(135deg,#168dff,#6a11cb);">
              <i class="fas fa-download"></i> Add Repo
            </a>
          </div>
        </div>
      </div>
      {CARD_END}
"""


def update_index() -> bool:
    original = INDEX_PATH.read_text(encoding="utf-8")
    updated = original.replace("https://www.nextsolution.app", "https://nextsolution.cc")
    updated = updated.replace("Latest Video Tutorials", "Latest Tutorials & Tweak Guides")
    updated = updated.replace(">60+</span>", ">61+</span>", 1)
    updated = updated.replace('id="current-year">2025</span>', 'id="current-year">2026</span>')

    if CARD_START not in updated:
        tutorial_start = updated.find('<section id="tutorials">')
        if tutorial_start == -1:
            raise RuntimeError("Could not find the Tutorials section in index.html")

        grid_marker = '<div class="content-grid">'
        grid_start = updated.find(grid_marker, tutorial_start)
        if grid_start == -1:
            raise RuntimeError("Could not find the Tutorials content grid in index.html")

        insertion_point = grid_start + len(grid_marker)
        updated = updated[:insertion_point] + "\n" + PHONEAURA_CARD + updated[insertion_point:]

    if updated == original:
        return False

    INDEX_PATH.write_text(updated, encoding="utf-8")
    return True


def update_sitemap() -> bool:
    original = SITEMAP_PATH.read_text(encoding="utf-8")
    updated = original.replace("https://www.nextsolution.app", "https://nextsolution.cc")

    phoneaura_url = "https://nextsolution.cc/phoneaura-tweak-ios16.html"
    if phoneaura_url not in updated:
        entry = """

  <!-- PhoneAura iOS 16 Tweak Guide -->
  <url>
    <loc>https://nextsolution.cc/phoneaura-tweak-ios16.html</loc>
    <lastmod>2026-07-30</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.9</priority>
  </url>
"""
        closing = "</urlset>"
        if closing not in updated:
            raise RuntimeError("Could not find closing urlset tag in sitemap.xml")
        updated = updated.replace(closing, entry + "\n" + closing)

    if updated == original:
        return False

    SITEMAP_PATH.write_text(updated, encoding="utf-8")
    return True


if __name__ == "__main__":
    index_changed = update_index()
    sitemap_changed = update_sitemap()
    print(f"index.html changed: {index_changed}")
    print(f"sitemap.xml changed: {sitemap_changed}")
