from pathlib import Path

TARGET = Path(__file__).with_name("fix_sms_draft_fields_and_message_decoding.py")
source = TARGET.read_text(encoding="utf-8")
start_marker = "# Fix the literal draft counter interpolation in the console as well.\n"
end_marker = "for path in [\"RootHideSMSQueue/control\"]:\n"
start = source.find(start_marker)
end = source.find(end_marker)
if start == -1 or end == -1 or end <= start:
    raise RuntimeError("Could not isolate the already-applied draft-counter edit.")
source = source[:start] + source[end:]
namespace = {"__file__": str(TARGET), "__name__": "__main__"}
exec(compile(source, str(TARGET), "exec"), namespace)
