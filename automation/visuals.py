"""Deterministic concept artwork for reader-facing tweak articles."""

from __future__ import annotations

import html
import re
import textwrap
from typing import Any


PALETTES = {
    "home-screen": ("#172554", "#2563EB", "#67E8F9"),
    "lock-screen": ("#2E1065", "#7C3AED", "#F0ABFC"),
    "control-center": ("#083344", "#0F766E", "#5EEAD4"),
    "notifications": ("#4C0519", "#E11D48", "#FDA4AF"),
    "messages-phone": ("#052E16", "#16A34A", "#86EFAC"),
    "media": ("#3B0764", "#C026D3", "#F5D0FE"),
    "productivity": ("#1E293B", "#475569", "#FDE68A"),
    "privacy-security": ("#172554", "#1D4ED8", "#93C5FD"),
    "visual-customization": ("#4C1D95", "#DB2777", "#FDE68A"),
    "system-utilities": ("#111827", "#334155", "#38BDF8"),
}


def visual_relative_path(candidate: dict[str, Any]) -> str:
    slug = str(candidate.get("slug", "")).strip()
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,118}[a-z0-9])?", slug):
        raise ValueError("candidate slug is unsafe for an article visual")
    return f"assets/articles/{slug}-hero.svg"


def visual_alt(candidate: dict[str, Any]) -> str:
    category = candidate.get("category", {})
    label = category.get("label", "jailbreak tweak") if isinstance(category, dict) else "jailbreak tweak"
    return f"Concept artwork for {candidate.get('name', 'this tweak')}, a {label.lower()} package"


def _wrapped_title(value: Any) -> list[str]:
    text = re.sub(r"\s+", " ", str(value)).strip()
    lines = textwrap.wrap(text, width=23, break_long_words=False, break_on_hyphens=False)
    return (lines or ["Jailbreak tweak"])[:3]


def _motif(category_id: str) -> str:
    if category_id == "lock-screen":
        return """
          <text x="982" y="244" text-anchor="middle" fill="#FFFFFF" font-family="Arial, sans-serif" font-size="42" font-weight="800">9:41</text>
          <rect x="862" y="308" width="240" height="238" rx="34" fill="#FFFFFF" fill-opacity=".12"/>
          <circle cx="982" cy="369" r="34" fill="#FFFFFF" fill-opacity=".25"/>
          <path d="M910 440h144M926 476h112M944 512h76" stroke="#FFFFFF" stroke-width="16" stroke-linecap="round" opacity=".78"/>
        """
    if category_id == "messages-phone":
        return """
          <circle cx="982" cy="319" r="76" fill="#FFFFFF" fill-opacity=".16"/>
          <circle cx="982" cy="304" r="25" fill="#FFFFFF" fill-opacity=".75"/>
          <path d="M936 363c16-31 76-31 92 0" fill="#FFFFFF" fill-opacity=".75"/>
          <rect x="858" y="433" width="248" height="84" rx="42" fill="#FFFFFF" fill-opacity=".12"/>
          <circle cx="906" cy="475" r="24" fill="#EF4444"/><circle cx="982" cy="475" r="24" fill="#FFFFFF" fill-opacity=".24"/><circle cx="1058" cy="475" r="24" fill="#22C55E"/>
        """
    if category_id == "home-screen":
        icons = []
        colors = ("#60A5FA", "#A78BFA", "#2DD4BF", "#FB7185", "#FBBF24", "#38BDF8")
        for row in range(3):
            for col in range(3):
                x = 876 + col * 88
                y = 278 + row * 88
                icons.append(f'<rect x="{x}" y="{y}" width="64" height="64" rx="18" fill="{colors[(row * 3 + col) % len(colors)]}"/>')
        return "\n".join(icons) + '<rect x="876" y="558" width="240" height="70" rx="28" fill="#FFFFFF" fill-opacity=".16"/>'
    if category_id == "media":
        return """
          <rect x="862" y="264" width="240" height="240" rx="46" fill="#FFFFFF" fill-opacity=".15"/>
          <circle cx="982" cy="384" r="78" fill="#FFFFFF" fill-opacity=".18"/>
          <path d="M962 346v92c0 23-42 26-42 2 0-19 28-25 42-16V365l72-17v70c0 23-42 26-42 2 0-19 28-25 42-16v-84z" fill="#FFFFFF"/>
          <path d="M886 558h192" stroke="#FFFFFF" stroke-width="14" stroke-linecap="round" opacity=".7"/>
        """
    if category_id == "privacy-security":
        return """
          <path d="M982 252 1090 292v94c0 105-66 176-108 197-42-21-108-92-108-197v-94z" fill="#FFFFFF" fill-opacity=".14" stroke="#FFFFFF" stroke-width="8"/>
          <path d="m934 405 32 32 66-76" fill="none" stroke="#FFFFFF" stroke-width="19" stroke-linecap="round" stroke-linejoin="round"/>
        """
    return """
      <rect x="860" y="280" width="244" height="82" rx="26" fill="#FFFFFF" fill-opacity=".14"/>
      <rect x="860" y="384" width="244" height="82" rx="26" fill="#FFFFFF" fill-opacity=".14"/>
      <rect x="860" y="488" width="244" height="82" rx="26" fill="#FFFFFF" fill-opacity=".14"/>
      <circle cx="906" cy="321" r="18" fill="#FFFFFF"/><circle cx="906" cy="425" r="18" fill="#FFFFFF"/><circle cx="906" cy="529" r="18" fill="#FFFFFF"/>
      <path d="M950 321h110M950 425h110M950 529h110" stroke="#FFFFFF" stroke-width="13" stroke-linecap="round" opacity=".7"/>
    """


def render_article_visual(candidate: dict[str, Any], article: dict[str, Any]) -> str:
    esc = lambda value: html.escape(str(value), quote=True)
    category = candidate.get("category", {})
    category_id = str(category.get("id", "system-utilities")) if isinstance(category, dict) else "system-utilities"
    category_label = str(category.get("label", "Jailbreak Tweak")) if isinstance(category, dict) else "Jailbreak Tweak"
    dark, mid, accent = PALETTES.get(category_id, PALETTES["system-utilities"])
    lines = _wrapped_title(candidate.get("name"))
    title_svg = "".join(
        f'<text x="112" y="{335 + index * 78}" fill="#FFFFFF" font-family="Arial, sans-serif" font-size="68" font-weight="800">{esc(line)}</text>'
        for index, line in enumerate(lines)
    )
    feature = ""
    features = article.get("what_it_does", [])
    if isinstance(features, list) and features:
        feature = re.sub(r"\s+", " ", str(features[0])).strip()
    if not feature:
        feature = re.sub(r"\s+", " ", str(candidate.get("description", "Package information and compatibility guide"))).strip()
    feature_lines = textwrap.wrap(feature, width=58, break_long_words=False, break_on_hyphens=False)[:2]
    feature_svg = "".join(
        f'<text x="116" y="{650 + index * 32}" fill="#CBD5E1" font-family="Arial, sans-serif" font-size="23">{esc(line)}</text>'
        for index, line in enumerate(feature_lines)
    )
    motif_svg = _motif(category_id).strip()
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" role="img" aria-labelledby="title desc">
  <title id="title">{esc(candidate.get('name'))} {esc(candidate.get('version'))}</title>
  <desc id="desc">{esc(visual_alt(candidate))}</desc>
  <defs>
    <linearGradient id="background" x1="80" y1="55" x2="1510" y2="845" gradientUnits="userSpaceOnUse"><stop stop-color="{dark}"/><stop offset="1" stop-color="{mid}"/></linearGradient>
    <radialGradient id="glow" cx="0" cy="0" r="1" gradientTransform="translate(1280 130) rotate(132) scale(680 560)" gradientUnits="userSpaceOnUse"><stop stop-color="{accent}" stop-opacity=".7"/><stop offset="1" stop-color="{accent}" stop-opacity="0"/></radialGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="28" stdDeviation="28" flood-color="#000000" flood-opacity=".28"/></filter>
  </defs>
  <rect width="1600" height="900" rx="56" fill="url(#background)"/>
  <rect width="1600" height="900" rx="56" fill="url(#glow)"/>
  <circle cx="1440" cy="760" r="215" fill="#FFFFFF" fill-opacity=".05"/>
  <g>
    <rect x="112" y="104" width="276" height="46" rx="23" fill="#FFFFFF" fill-opacity=".12" stroke="#FFFFFF" stroke-opacity=".18"/>
    <text x="250" y="135" text-anchor="middle" fill="{accent}" font-family="Arial, sans-serif" font-size="19" font-weight="800" letter-spacing="2">{esc(category_label.upper())}</text>
    <text x="112" y="226" fill="#FFFFFF" fill-opacity=".68" font-family="Arial, sans-serif" font-size="25" font-weight="700">VERSION {esc(candidate.get('version'))}</text>
    {title_svg}
    {feature_svg}
    <g transform="translate(112 760)">
      <rect width="50" height="50" rx="14" fill="#FFFFFF"/>
      <path d="M13 37V13l19 24V13" fill="none" stroke="{mid}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="m32 13 9 12-9 12" fill="none" stroke="{dark}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
      <text x="70" y="34" fill="#FFFFFF" font-family="Arial, sans-serif" font-size="24" font-weight="800">NEXT JAILBREAK</text>
    </g>
  </g>
  <g filter="url(#shadow)">
    <rect x="798" y="118" width="380" height="664" rx="70" fill="#070A10"/>
    <rect x="817" y="137" width="342" height="626" rx="54" fill="#0F172A"/>
    <rect x="923" y="152" width="130" height="28" rx="14" fill="#04060A"/>
    {motif_svg}
    <rect x="920" y="727" width="136" height="7" rx="4" fill="#FFFFFF" fill-opacity=".65"/>
  </g>
  <g filter="url(#shadow)" transform="rotate(6 1310 580)">
    <rect x="1180" y="475" width="276" height="204" rx="36" fill="#FFFFFF"/>
    <text x="1212" y="527" fill="{mid}" font-family="Arial, sans-serif" font-size="18" font-weight="800">SOURCE GUIDE</text>
    <text x="1212" y="574" fill="#0F172A" font-family="Arial, sans-serif" font-size="27" font-weight="800">Features</text>
    <text x="1212" y="609" fill="#475569" font-family="Arial, sans-serif" font-size="21">Compatibility</text>
    <text x="1212" y="644" fill="#475569" font-family="Arial, sans-serif" font-size="21">Install checks</text>
  </g>
</svg>
"""
