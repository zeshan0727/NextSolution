from __future__ import annotations

import plistlib
import re
from pathlib import Path

ROOT = Path("projects/NextMedia")
SRC = ROOT / "NextMedia"


def swift_files():
    return list(SRC.rglob("*.swift"))


def replace_if_changed(path: Path, source: str) -> None:
    old = path.read_text()
    if old != source:
        path.write_text(source)


def update_version() -> None:
    plist_path = SRC / "Info.plist"
    if plist_path.exists():
        with plist_path.open("rb") as handle:
            data = plistlib.load(handle)
        data["CFBundleShortVersionString"] = "1.3.0"
        data["CFBundleVersion"] = "4"
        with plist_path.open("wb") as handle:
            plistlib.dump(data, handle, sort_keys=False)


def disable_automatic_download_prompts() -> None:
    # Keep media collection and the floating manual button, but never assign an
    # automatically detected item to the alert/confirmation-dialog selection.
    for path in swift_files():
        if path.name not in {"BrowserSession.swift", "BrowserView.swift", "BrowserWebView.swift"}:
            continue
        source = path.read_text()
        lines = source.splitlines()
        changed = False
        output: list[str] = []
        for line in lines:
            stripped = line.strip()
            # The 1.1 implementation used a pending detected-media property to
            # trigger the repeated alert. Preserve the property for ABI/source
            # compatibility, but stop automatic assignments to it.
            if ("pending" in stripped.lower() or "prompt" in stripped.lower()) and re.search(r"\b(?:self\.)?[A-Za-z_][A-Za-z0-9_]*(?:pending|Pending|prompt|Prompt)[A-Za-z0-9_]*\s*=\s*", stripped):
                if "= nil" not in stripped and not stripped.startswith("@") and not stripped.startswith("var ") and not stripped.startswith("let "):
                    indent = line[: len(line) - len(line.lstrip())]
                    output.append(indent + "// Next Media 1.3: automatic media prompt disabled; use the floating download button.")
                    changed = True
                    continue
            output.append(line)
        if changed:
            replace_if_changed(path, "\n".join(output) + "\n")


def find_detected_media_url_property() -> str:
    candidates = list(SRC.rglob("DetectedMedia.swift"))
    for path in candidates:
        source = path.read_text()
        match = re.search(r"(?:let|var)\s+(\w+)\s*:\s*URL\b", source)
        if match:
            return match.group(1)
    return "url"


def add_quality_helpers() -> None:
    url_property = find_detected_media_url_property()
    helper = SRC / "Models" / "DetectedMedia+Quality.swift"
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_text(f'''import Foundation

extension DetectedMedia {{
    /// Best-effort quality inferred from direct media URL metadata. This does
    /// not decipher protected URLs; it only labels resources already exposed
    /// to the browser.
    var nextMediaQualityHeight: Int {{
        let value = {url_property}.absoluteString.lowercased()
        let patterns = [
            #"(?:height|quality|res|resolution)[=/_%:-](2160|1440|1080|720|480|360|240|144)"#,
            #"(?:^|[^0-9])(2160|1440|1080|720|480|360|240|144)p(?:[^0-9]|$)"#
        ]
        for pattern in patterns {{
            if let expression = try? NSRegularExpression(pattern: pattern),
               let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
               let range = Range(match.range(at: 1), in: value),
               let number = Int(value[range]) {{
                return number
            }}
        }}

        // Common YouTube itags, but only when the signed direct resource URL
        // is already visible to WKWebView. No signature extraction is done.
        let itagMap: [Int: Int] = [
            17: 144, 18: 360, 22: 720,
            160: 144, 133: 240, 134: 360, 135: 480,
            136: 720, 137: 1080, 264: 1440, 266: 2160,
            278: 144, 242: 240, 243: 360, 244: 480,
            247: 720, 248: 1080, 271: 1440, 313: 2160
        ]
        if let components = URLComponents(url: {url_property}, resolvingAgainstBaseURL: false),
           let raw = components.queryItems?.first(where: {{ $0.name == "itag" }})?.value,
           let itag = Int(raw), let height = itagMap[itag] {{
            return height
        }}
        return 0
    }}

    var nextMediaQualityLabel: String {{
        let height = nextMediaQualityHeight
        return height > 0 ? "\\(height)p" : "Quality not reported"
    }}
}}
''')

    # Sort candidates highest first after each append, without changing the
    # existing detection and download APIs.
    for path in swift_files():
        if path.name != "BrowserSession.swift":
            continue
        source = path.read_text()
        if "nextMediaQualityHeight" in source:
            continue
        pattern = re.compile(r"^(\s*)(\w+)\.append\(([^\n]+)\)\s*$", re.MULTILINE)
        def repl(match: re.Match[str]) -> str:
            collection = match.group(2)
            if "detect" not in collection.lower() and "media" not in collection.lower():
                return match.group(0)
            indent = match.group(1)
            return match.group(0) + f"\n{indent}{collection}.sort {{ $0.nextMediaQualityHeight > $1.nextMediaQualityHeight }}"
        updated = pattern.sub(repl, source)
        replace_if_changed(path, updated)


def add_file_size_helpers_and_labels() -> None:
    model_types: list[tuple[str, str]] = []
    for path in swift_files():
        source = path.read_text()
        for match in re.finditer(r"(?:struct|class)\s+(\w+)[^{]*\{", source):
            type_name = match.group(1)
            tail = source[match.end():]
            # Stop at a conservative distance; media models are compact.
            sample = tail[:6000]
            if not re.search(r"(?:let|var)\s+title\s*:\s*String", sample):
                continue
            url_match = re.search(r"(?:let|var)\s+(\w+)\s*:\s*URL\b", sample)
            if url_match:
                model_types.append((type_name, url_match.group(1)))

    # Deduplicate while retaining order.
    seen: set[str] = set()
    model_types = [(t, u) for t, u in model_types if not (t in seen or seen.add(t))]
    helper = SRC / "Models" / "MediaFileSize+Formatting.swift"
    blocks = ["import Foundation", ""]
    for type_name, url_property in model_types:
        blocks.append(f'''extension {type_name} {{
    var nextMediaFileSizeText: String {{
        let fileURL = {url_property}
        guard fileURL.isFileURL else {{ return "Remote file" }}
        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
           let bytes = values.fileSize {{
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }}
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let bytes = attributes[.size] as? NSNumber {{
            return ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file)
        }}
        return "Size unavailable"
    }}
}}
''')
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_text("\n".join(blocks))

    # Add a compact size label to visible file/download/library rows. The
    # insertion is limited to files whose names describe file-list screens.
    for path in swift_files():
        lower_name = path.name.lower()
        if not any(word in lower_name for word in ("download", "library", "file")):
            continue
        source = path.read_text()
        if "nextMediaFileSizeText" in source:
            continue
        lines = source.splitlines()
        output: list[str] = []
        inserted_vars: set[str] = set()
        for line in lines:
            output.append(line)
            match = re.search(r"Text\(\s*(\w+)\.title\s*\)", line)
            if not match:
                continue
            variable = match.group(1)
            # Confirm that this view accesses a URL-bearing media model.
            if not re.search(rf"\b{re.escape(variable)}\.(?:url|fileURL|localURL)\b", source):
                continue
            if variable in inserted_vars:
                continue
            indent = line[: len(line) - len(line.lstrip())]
            output.append(indent + f'Text({variable}.nextMediaFileSizeText)')
            output.append(indent + "    .font(.caption2)")
            output.append(indent + "    .foregroundStyle(.secondary)")
            inserted_vars.add(variable)
        if inserted_vars:
            replace_if_changed(path, "\n".join(output) + "\n")


def add_quality_labels_to_detected_list() -> None:
    candidates = list(SRC.rglob("DetectedMediaListView.swift"))
    for path in candidates:
        source = path.read_text()
        if "nextMediaQualityLabel" in source:
            continue
        lines = source.splitlines()
        output: list[str] = []
        inserted = False
        for line in lines:
            output.append(line)
            if inserted:
                continue
            match = re.search(r"Text\(\s*(\w+)\.(?:title|displayName|name)\s*\)", line)
            if match:
                variable = match.group(1)
                indent = line[: len(line) - len(line.lstrip())]
                output.append(indent + f'Text({variable}.nextMediaQualityLabel)')
                output.append(indent + "    .font(.caption)")
                output.append(indent + "    .foregroundStyle(.secondary)")
                inserted = True
        if inserted:
            replace_if_changed(path, "\n".join(output) + "\n")


def add_hd_preference() -> None:
    # Add a setting. It defaults on and affects browser playback only; the
    # detected download list still includes only direct resources the page has
    # actually exposed.
    for path in swift_files():
        if path.name != "SettingsView.swift":
            continue
        source = path.read_text()
        if "nextMediaPrefer1080p" not in source:
            source = re.sub(
                r"(struct\s+SettingsView\s*:\s*View\s*\{)",
                r'\1\n    @AppStorage("nextMediaPrefer1080p") private var nextMediaPrefer1080p = true',
                source,
                count=1,
            )
            lines = source.splitlines()
            output: list[str] = []
            inserted = False
            for line in lines:
                if not inserted and ("Clear Browser" in line or "Browser Data" in line or "YouTube" in line):
                    indent = line[: len(line) - len(line.lstrip())]
                    output.append(indent + 'Toggle("Prefer 1080p browser playback", isOn: $nextMediaPrefer1080p)')
                    output.append(indent + 'Text("The browser asks compatible players for 1080p. Download choices still depend on the direct streams exposed by the page.")')
                    output.append(indent + '    .font(.caption)')
                    output.append(indent + '    .foregroundStyle(.secondary)')
                    inserted = True
                output.append(line)
            source = "\n".join(output) + "\n"
            replace_if_changed(path, source)

    # Inject a small non-invasive YouTube player quality preference into the
    # WKWebView. YouTube may ignore it based on bandwidth/device conditions.
    for path in swift_files():
        if path.name != "BrowserWebView.swift":
            continue
        source = path.read_text()
        if "nextMediaPrefer1080p" in source:
            continue
        config_match = re.search(r"(?:let|var)\s+(\w+)\s*=\s*WKWebViewConfiguration\(\)", source)
        if not config_match:
            continue
        config = config_match.group(1)
        insertion = f'''
        if UserDefaults.standard.object(forKey: "nextMediaPrefer1080p") as? Bool ?? true {{
            let nextMediaHDSource = #"""
            (() => {{
              const apply = () => {{
                try {{
                  const player = document.getElementById('movie_player');
                  if (player && typeof player.setPlaybackQualityRange === 'function') {{
                    player.setPlaybackQualityRange('hd1080');
                  }}
                  if (player && typeof player.setPlaybackQuality === 'function') {{
                    player.setPlaybackQuality('hd1080');
                  }}
                }} catch (_) {{}}
              }};
              document.addEventListener('play', apply, true);
              new MutationObserver(apply).observe(document.documentElement, {{childList:true, subtree:true}});
              setInterval(apply, 2500);
              apply();
            }})();
            """#
            {config}.userContentController.addUserScript(
                WKUserScript(source: nextMediaHDSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            )
        }}
'''
        pos = source.find("\n", config_match.end())
        if pos == -1:
            pos = config_match.end()
        source = source[: pos + 1] + insertion + source[pos + 1 :]
        replace_if_changed(path, source)


def add_manual_only_note() -> None:
    for path in swift_files():
        if path.name != "BrowserView.swift":
            continue
        source = path.read_text()
        if "Media is collected silently" in source:
            continue
        # Add a small accessibility/help label near an existing detected-media
        # button without relying on its exact visual implementation.
        source = source.replace(
            '.accessibilityLabel("Detected media")',
            '.accessibilityLabel("Detected media. Media is collected silently; open this button to choose a download.")'
        )
        replace_if_changed(path, source)


def main() -> None:
    update_version()
    disable_automatic_download_prompts()
    add_quality_helpers()
    add_file_size_helpers_and_labels()
    add_quality_labels_to_detected_list()
    add_hd_preference()
    add_manual_only_note()


if __name__ == "__main__":
    main()
