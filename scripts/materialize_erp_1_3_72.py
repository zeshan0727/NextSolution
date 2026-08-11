from pathlib import Path
import base64
import json
import zlib

root = Path(__file__).resolve().parents[1]
blob_dir = root / "scripts" / "erp_1_3_72_blob"
blob = "".join(
    (blob_dir / f"chunk{i:02d}.txt").read_text(encoding="utf-8").strip()
    for i in range(6)
)
data = json.loads(zlib.decompress(base64.b64decode(blob)).decode("utf-8"))
out = root / "scripts" / "erp_1_3_72"
out.mkdir(parents=True, exist_ok=True)
for name, content in data.items():
    (out / name).write_text(content, encoding="utf-8")
print(f"Materialized {len(data)} ERP 1.3.72 Swift templates.")
