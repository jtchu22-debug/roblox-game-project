"""
Starfall Ranch: S6-ART-03 Editable Observatory UI Icon Generator
Location: tools/art/generate_ui_icons.py

Generates 16 editable 256x256 SVG vector icons for Navigation, Meteors, Tools, and Upgrades
using the Starfall Ranch Observatory palette, plus `tools/art/icons/manifest.json`.
"""

import json
import os

PALETTE = {
    "bg": "#181626",
    "cream": "#F5EBDC",
    "brass": "#D2A452",
    "teal": "#55C3B9",
    "cyan": "#41D2FF",
    "gold": "#FFCD2D",
    "violet": "#C46EFF",
    "coral": "#FF7850",
    "mint": "#5FD791",
    "slate": "#2E2A48",
}

SVG_WRAPPER = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <rect x="12" y="12" width="232" height="232" rx="44" fill="{bg}" stroke="{border}" stroke-width="10"/>
  {body}
</svg>
"""

ICONS = {
    "nav/Hub": (
        PALETTE["violet"],
        '<circle cx="128" cy="128" r="56" fill="none" stroke="#D2A452" stroke-width="12"/>'
        '<path d="M128 52 L144 112 L204 128 L144 144 L128 204 L112 144 L52 128 L112 112 Z" fill="#C46EFF"/>'
        '<circle cx="128" cy="128" r="18" fill="#FFCD2D"/>',
    ),
    "nav/Ranch": (
        PALETTE["mint"],
        '<path d="M52 124 L128 60 L204 124 L184 124 L184 192 L72 192 L72 124 Z" fill="#F5EBDC" stroke="#D2A452" stroke-width="8"/>'
        '<rect x="106" y="132" width="44" height="60" rx="8" fill="#5FD791"/>',
    ),
    "nav/Bag": (
        PALETTE["cyan"],
        '<path d="M88 84 C88 56 168 56 168 84" fill="none" stroke="#D2A452" stroke-width="12" stroke-linecap="round"/>'
        '<rect x="60" y="84" width="136" height="114" rx="24" fill="#2E2A48" stroke="#41D2FF" stroke-width="10"/>'
        '<circle cx="128" cy="138" r="22" fill="#FFCD2D"/>',
    ),
    "nav/Guide": (
        PALETTE["gold"],
        '<rect x="64" y="54" width="128" height="148" rx="16" fill="#2E2A48" stroke="#FFCD2D" stroke-width="10"/>'
        '<line x1="92" y1="54" x2="92" y2="202" stroke="#D2A452" stroke-width="10"/>'
        '<circle cx="144" cy="124" r="24" fill="#55C3B9"/>',
    ),
    "nav/Shop": (
        PALETTE["brass"],
        '<polygon points="62,92 194,92 178,194 78,194" fill="#D2A452" stroke="#F5EBDC" stroke-width="8"/>'
        '<path d="M128 112 L140 136 L166 140 L146 158 L152 184 L128 170 L104 184 L110 158 L90 140 L116 136 Z" fill="#FFCD2D"/>',
    ),
    "nav/Settings": (
        PALETTE["cream"],
        '<circle cx="128" cy="128" r="48" fill="none" stroke="#F5EBDC" stroke-width="18" stroke-dasharray="22 14"/>'
        '<circle cx="128" cy="128" r="22" fill="#55C3B9"/>',
    ),
    "meteors/Ember": (
        PALETTE["coral"],
        '<polygon points="128,44 194,116 172,198 84,198 62,116" fill="#91555F" stroke="#FF7850" stroke-width="8"/>'
        '<polygon points="128,74 162,138 128,176 94,138" fill="#FF913C"/>',
    ),
    "meteors/Frost": (
        PALETTE["cyan"],
        '<polygon points="128,42 188,104 168,196 88,196 68,104" fill="#5F87B9" stroke="#41D2FF" stroke-width="8"/>'
        '<polygon points="128,68 156,128 128,178 100,128" fill="#7DF0FF"/>',
    ),
    "meteors/Astral": (
        PALETTE["violet"],
        '<ellipse cx="128" cy="132" rx="78" ry="30" fill="none" stroke="#FFCD2D" stroke-width="10" transform="rotate(-22 128 132)"/>'
        '<circle cx="128" cy="132" r="44" fill="#5A4B87" stroke="#C46EFF" stroke-width="8"/>'
        '<circle cx="128" cy="132" r="18" fill="#FFD250"/>',
    ),
    "tools/StarterCracker": (
        PALETTE["teal"],
        '<rect x="118" y="96" width="20" height="114" rx="8" fill="#8E5C36"/>'
        '<rect x="74" y="56" width="108" height="48" rx="14" fill="#EEE4D0" stroke="#C68048" stroke-width="8"/>'
        '<rect x="114" y="68" width="28" height="24" rx="6" fill="#55C3B9"/>',
    ),
    "tools/FrostCracker": (
        PALETTE["cyan"],
        '<rect x="118" y="102" width="20" height="108" rx="8" fill="#B9985C"/>'
        '<path d="M84 52 L110 52 L116 106 L84 106 Z M146 52 L172 52 L172 106 L140 106 Z" fill="#4E76A8"/>'
        '<polygon points="128,46 146,104 110,104" fill="#5FE8FF"/>',
    ),
    "tools/AstralCracker": (
        PALETTE["violet"],
        '<rect x="118" y="112" width="20" height="98" rx="8" fill="#CDA44E"/>'
        '<path d="M78 102 A52 52 0 1 1 178 102" fill="none" stroke="#D7AE52" stroke-width="16" stroke-linecap="round"/>'
        '<polygon points="128,62 150,86 128,110 106,86" fill="#C46EFF"/>',
    ),
    "upgrades/PenSlot": (
        PALETTE["mint"],
        '<rect x="58" y="72" width="140" height="116" rx="16" fill="none" stroke="#F5EBDC" stroke-width="12"/>'
        '<line x1="128" y1="98" x2="128" y2="162" stroke="#5FD791" stroke-width="14" stroke-linecap="round"/>'
        '<line x1="96" y1="130" x2="160" y2="130" stroke="#5FD791" stroke-width="14" stroke-linecap="round"/>',
    ),
    "upgrades/Incubator": (
        PALETTE["cyan"],
        '<path d="M74 146 C74 74 182 74 182 146 Z" fill="#41D2FF" fill-opacity="0.35" stroke="#D2A452" stroke-width="10"/>'
        '<rect x="62" y="146" width="132" height="44" rx="14" fill="#F5EBDC"/>'
        '<circle cx="128" cy="122" r="20" fill="#FF7850"/>',
    ),
    "upgrades/BagCap": (
        PALETTE["gold"],
        '<rect x="64" y="74" width="128" height="120" rx="22" fill="#2E2A48" stroke="#FFCD2D" stroke-width="10"/>'
        '<text x="128" y="150" text-anchor="middle" font-family="Arial, sans-serif" font-weight="bold" font-size="56" fill="#F5EBDC">20</text>',
    ),
    "upgrades/FrostLure": (
        PALETTE["cyan"],
        '<circle cx="128" cy="128" r="54" fill="none" stroke="#41D2FF" stroke-width="10"/>'
        '<path d="M128 60 L128 196 M60 128 L196 128 M80 80 L176 176 M176 80 L80 176" stroke="#7DF0FF" stroke-width="10" stroke-linecap="round"/>',
    ),
}


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    icons_dir = os.path.join(script_dir, "icons")
    manifest = {}

    for rel_key, (border, body) in ICONS.items():
        out_path = os.path.join(icons_dir, f"{rel_key}.svg")
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        svg = SVG_WRAPPER.format(bg=PALETTE["bg"], border=border, body=body)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(svg)
        manifest[rel_key] = f"tools/art/icons/{rel_key}.svg"

    manifest_path = os.path.join(icons_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"[ArtIcons] Generated {len(manifest)} editable SVG icons -> {manifest_path}")


if __name__ == "__main__":
    main()
