from pathlib import Path
import base64
import zlib

root = Path(__file__).resolve().parents[1]
blob_dir = root / "scripts" / "erp_1_3_72_patcher_blob"
blob = "".join(
    (blob_dir / f"chunk{i:02d}.txt").read_text(encoding="utf-8").strip()
    for i in range(3)
)
source = zlib.decompress(base64.b64decode(blob)).decode("utf-8")
out = root / "scripts" / "add_erp_accounting_center_1_3_72.py"
out.write_text(source, encoding="utf-8")
print("Materialized ERP 1.3.72 patcher.")
