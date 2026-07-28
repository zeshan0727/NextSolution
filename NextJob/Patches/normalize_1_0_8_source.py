from pathlib import Path

path = Path("NextJob/Services/EmailDeliveryService.swift")
text = path.read_text(encoding="utf-8")
legacy = 'NextJob-iOS/1.0.6'
current = 'NextJob-iOS/1.0.7'

if legacy in text:
    text = text.replace(legacy, current)

if text.count(current) < 2:
    raise RuntimeError("Could not normalize both Next Job Gmail user-agent paths for 1.0.8")

path.write_text(text, encoding="utf-8")
print("Next Job 1.0.8 source normalization applied.")
