from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")

old = '''        @{\n            @"name": @"incoming Fawran transfer",\n            @"sms": @"Current Acc xxx364001 credited with QAR 1,000.00 for Fawran instant payment ref zeeshan,MOHAMED ASHFAAQ MOHAMED AZW withM-33510982 at 16:09, 03-Aug-26 Current Acc Bal: QAR 2,596.69",\n            @"kind": @"incomingTransfer", @"ending": @"364001", @"amount": @"1000"\n        }\n    ];\n'''
new = '''        @{\n            @"name": @"incoming Fawran transfer",\n            @"sms": @"Current Acc xxx364001 credited with QAR 1,000.00 for Fawran instant payment ref zeeshan,MOHAMED ASHFAAQ MOHAMED AZW withM-33510982 at 16:09, 03-Aug-26 Current Acc Bal: QAR 2,596.69",\n            @"kind": @"incomingTransfer", @"ending": @"364001", @"amount": @"1000"\n        },\n        @{\n            @"name": @"unrecognized transfer review fallback",\n            @"sms": @"Transfer notification QAR 825.50 sent to beneficiary TEST PERSON reference X992 at 18:42, 07-Aug-26 account balance QAR 1,900.00",\n            @"kind": @"reviewTransfer", @"ending": @"", @"amount": @"825.50", @"reviewFallback": @YES\n        }\n    ];\n'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one Fawran self-test tail, found {count}")
text = text.replace(old, new, 1)

old = '''        NSDictionary *parsed = ParseTransaction(test[@"sms"], NSDate.date);\n'''
new = '''        NSDictionary *parsed = ParseTransaction(test[@"sms"], NSDate.date);\n        if (!parsed && [test[@"reviewFallback"] boolValue]) {\n            parsed = ReviewDraftForUnrecognizedBankSMS(test[@"sms"], NSDate.date);\n        }\n'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one self-test parser line, found {count}")
text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print("Added unrecognized transfer review-fallback regression test.")
