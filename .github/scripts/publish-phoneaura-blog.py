from pathlib import Path
import re

INDEX_PATH = Path("index.html")
TUTORIALS_PATH = Path("tutorials.html")
ARTICLE_PATH = Path("phoneaura-tweak-ios16.html")
SITEMAP_PATH = Path("sitemap.xml")

RECENT_CARD_START = "<!-- PHONEAURA_RECENT_CARD_START -->"
RECENT_CARD_END = "<!-- PHONEAURA_RECENT_CARD_END -->"
TABS_CSS_START = "/* PHONEAURA_SHARED_TABS_START */"
TABS_CSS_END = "/* PHONEAURA_SHARED_TABS_END */"

PHONEAURA_RECENT_CARD = f"""
        {RECENT_CARD_START}
        <article class="card">
          <div class="icon"><i class="fas fa-phone-volume" aria-hidden="true"></i></div>
          <h3>PhoneAura 0.4.16 — Stable Phone App Redesign</h3>
          <p>Emergency stability hotfix with redesigned Favorites, Recents, Contacts and a fixed smart Keypad for RootHide and rootless jailbreaks.</p>
          <a class="more" href="phoneaura-tweak-ios16.html">Read guide &amp; download <i class="fas fa-arrow-right" aria-hidden="true"></i></a>
        </article>
        {RECENT_CARD_END}
"""

SHARED_TABS_CSS = f"""
    {TABS_CSS_START}
    .header-links {{
      flex-wrap: nowrap;
      overflow-x: auto;
      overscroll-behavior-x: contain;
      scrollbar-width: none;
      -webkit-overflow-scrolling: touch;
    }}
    .header-links::-webkit-scrollbar {{ display: none; }}
    .header-links a {{ flex: 0 0 auto; white-space: nowrap; }}
    .header-links a[aria-current="page"] {{
      color: #fff;
      background: rgba(255,255,255,.14);
    }}
    @media (max-width: 650px) {{
      .site-header-inner {{
        min-height: 0;
        align-items: stretch;
        flex-direction: column;
        padding: 10px 0;
      }}
      .header-links {{ width: 100%; }}
      .header-links a:not(:last-child) {{ display: block; }}
    }}
    {TABS_CSS_END}
"""


def remove_marked_block(text: str, start: str, end: str) -> str:
    pattern = re.compile(rf"\s*{re.escape(start)}.*?{re.escape(end)}\s*", re.S)
    return pattern.sub("\n", text)


def update_index() -> bool:
    original = INDEX_PATH.read_text(encoding="utf-8")
    updated = original.replace(
        '<div class="heading"><h2>Popular tutorials</h2><p>Guides covering the most requested jailbreak and iPhone customization topics.</p></div>',
        '<div class="heading"><h2>Recent tutorials</h2><p>The newest Next Jailbreak guides, with PhoneAura permanently pinned for quick access.</p></div>',
    )

    updated = remove_marked_block(updated, RECENT_CARD_START, RECENT_CARD_END)
    section_start = updated.find('<section class="section" id="tutorials">')
    if section_start == -1:
        raise RuntimeError("Could not find the main-page tutorials section")

    grid_marker = '<div class="grid">'
    grid_start = updated.find(grid_marker, section_start)
    if grid_start == -1:
        raise RuntimeError("Could not find the main-page tutorials grid")

    insertion_point = grid_start + len(grid_marker)
    updated = updated[:insertion_point] + "\n" + PHONEAURA_RECENT_CARD + updated[insertion_point:]

    if updated == original:
        return False
    INDEX_PATH.write_text(updated, encoding="utf-8")
    return True


def update_tutorials() -> bool:
    original = TUTORIALS_PATH.read_text(encoding="utf-8")
    updated = original.replace("PhoneAura 0.4.15", "PhoneAura 0.4.16")
    updated = updated.replace(
        "Includes fixed saved-number suggestions, smart call filters, Number Options, direct DEB downloads and long-press Cut, Copy and Paste controls.",
        "Includes fixed saved-number suggestions, smart call filters, Number Options, direct DEB downloads and the 0.4.16 emergency stability rollback.",
    )
    updated = updated.replace(
        "PhoneAura 0.4.16 — Complete Phone App Redesign",
        "PhoneAura 0.4.16 — Stable Phone App Redesign",
    )

    if updated == original:
        return False
    TUTORIALS_PATH.write_text(updated, encoding="utf-8")
    return True


def update_article() -> bool:
    original = ARTICLE_PATH.read_text(encoding="utf-8")
    updated = original.replace("0.4.15", "0.4.16")

    old_nav = '''      <nav class="header-links" aria-label="Article navigation">
        <a href="./#tutorials">Tutorials</a>
        <a href="videos">Videos</a>
        <a href="downloads">Downloads</a>
        <a href="#download">Get PhoneAura</a>
      </nav>'''
    new_nav = '''      <nav class="header-links" aria-label="Primary navigation">
        <a href="./">Home</a>
        <a href="tutorials.html" aria-current="page">Tutorials</a>
        <a href="videos.html">Videos</a>
        <a href="./#faq">FAQ</a>
      </nav>'''
    if old_nav in updated:
        updated = updated.replace(old_nav, new_nav)
    elif new_nav not in updated:
        raise RuntimeError("Could not find the PhoneAura article navigation")

    updated = remove_marked_block(updated, TABS_CSS_START, TABS_CSS_END)
    updated = updated.replace("  </style>", SHARED_TABS_CSS + "  </style>", 1)

    replacements = {
        "Redesign Favorites, Recents, Contacts and Keypad on iOS 16 with fixed suggestions, smart filters and long-press phone-number editing.":
            "Redesign Favorites, Recents, Contacts and Keypad on iOS 16 with fixed suggestions, smart filters and the 0.4.16 emergency stability hotfix.",
        "Modern Favorites, smart Recents, redesigned Contacts, a stable keypad and native long-press number editing for jailbroken iOS 16.":
            "Modern Favorites, smart Recents, redesigned Contacts and a stable keypad for jailbroken iOS 16.",
        "Use the native iOS edit menu for Cut, Copy and Paste where appropriate, including Paste to Keypad.":
            "Version 0.4.16 removes the unsafe global edit-menu hooks from 0.4.15 and restores the stable number-display behavior used in 0.4.14.",
        "Long-Press Number Editing": "Stable Number Handling",
        "PhoneAura Keypad with fixed contact suggestion card and long-press edit menu":
            "PhoneAura Keypad with fixed contact suggestion card and stable number display",
        "Keypad concept: fixed suggestion space, preserved Number Options, Next Jailbreak shortcut and native phone-number editing.":
            "Keypad concept: fixed suggestion space, preserved Number Options, Next Jailbreak shortcut and a stable number display.",
        "            <li>Long press the displayed number to open the editing menu.</li>\n": "",
        "Read more jailbreak tutorials on <a href=\"./#tutorials\">Next Jailbreak</a>":
            "Read more jailbreak tutorials on <a href=\"tutorials.html\">Next Jailbreak</a>",
    }
    for old, new in replacements.items():
        updated = updated.replace(old, new)

    stability_section = '''
      <section class="section" id="number-menu">
        <div class="section-heading">
          <span class="kicker">PhoneAura 0.4.16 hotfix</span>
          <h2>Phone app crash fixed</h2>
          <p>Version 0.4.15 attached edit-menu interactions by globally modifying UILabel behavior inside the Phone process. On affected devices this caused MobilePhone to crash during launch or while views were updating.</p>
        </div>

        <div class="glass-card prose-card">
          <ul>
            <li>The global long-press phone-number editing hooks have been removed.</li>
            <li>The tweak now uses the proven 0.4.14 runtime file set.</li>
            <li>Favorites, Recents, Contacts, Keypad, fixed suggestions, Number Options and the Next Jailbreak shortcut remain available.</li>
            <li>RootHide and rootless builds were compiled separately as version 0.4.16.</li>
          </ul>
          <div class="warning"><strong>Remove 0.4.15 immediately.</strong> Refresh the Next Jailbreak repository and upgrade to 0.4.16 before reopening the Phone app.</div>
        </div>
      </section>

'''
    number_menu_pattern = re.compile(
        r'\s*<section class="section" id="number-menu">.*?</section>\s*(?=<section class="section" id="compatibility">)',
        re.S,
    )
    if number_menu_pattern.search(updated):
        updated = number_menu_pattern.sub("\n" + stability_section, updated, count=1)
    elif "Phone app crash fixed" not in updated:
        raise RuntimeError("Could not replace the old long-press editing section")

    old_test = '''          <h3>Recommended first test</h3>
          <ol>
            <li>Open Keypad and type at least two digits.</li>
            <li>Confirm the suggestion area stays visible and the keypad does not move.</li>
            <li>Long press the typed number and test Copy or Paste.</li>
            <li>Open Contacts or Recents and long press a displayed number.</li>
            <li>Check Favorites, Recents filters and the upper Next Jailbreak logo.</li>
          </ol>'''
    new_test = '''          <h3>Recommended first test</h3>
          <ol>
            <li>Confirm Settings → PhoneAura shows version 0.4.16.</li>
            <li>Respring, fully close the Phone app and reopen it.</li>
            <li>Open Keypad and type at least two digits.</li>
            <li>Confirm the suggestion area stays visible and the keypad does not move.</li>
            <li>Check Favorites, Recents filters, Contacts, Number Options and the upper Next Jailbreak logo.</li>
          </ol>'''
    if old_test in updated:
        updated = updated.replace(old_test, new_test)

    old_faq = '''          <details>
            <summary>Why is Cut disabled on saved numbers?</summary>
            <p>Saved contacts and call-history numbers are read-only in this menu. Disabling Cut protects stored data while still allowing Copy and Paste to Keypad.</p>
          </details>'''
    new_faq = '''          <details>
            <summary>Why was long-press number editing removed?</summary>
            <p>The 0.4.15 implementation modified UILabel behavior globally and caused the Phone app to crash on affected devices. Version 0.4.16 removes that code and restores the stable 0.4.14 runtime.</p>
          </details>'''
    if old_faq in updated:
        updated = updated.replace(old_faq, new_faq)

    if updated == original:
        return False
    ARTICLE_PATH.write_text(updated, encoding="utf-8")
    return True


def update_sitemap() -> bool:
    original = SITEMAP_PATH.read_text(encoding="utf-8")
    updated = original.replace(
        "<lastmod>2026-07-30</lastmod>",
        "<lastmod>2026-07-30</lastmod>",
    )
    if updated == original:
        return False
    SITEMAP_PATH.write_text(updated, encoding="utf-8")
    return True


if __name__ == "__main__":
    results = {
        "index.html": update_index(),
        "tutorials.html": update_tutorials(),
        "phoneaura-tweak-ios16.html": update_article(),
        "sitemap.xml": update_sitemap(),
    }
    for path, changed in results.items():
        print(f"{path} changed: {changed}")
