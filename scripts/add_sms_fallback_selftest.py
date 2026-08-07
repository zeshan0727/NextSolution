from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "RootHideSMSQueue/Sources/main.m"
text = path.read_text(encoding="utf-8")

old = '''        @{
            @"name": @"incoming Fawran transfer",
            @"sms": @"Current Acc xxx364001 credited with QAR 1,000.00 for Fawran instant payment ref zeeshan,MOHAMED ASHFAAQ MOHAMED AZW withM-33510982 at 16:09, 03-Aug-26 Current Acc Bal: QAR 2,596.69",
            @"kind": @"incomingTransfer", @"ending": @"364001", @"amount": @"1000"
        }
    ];
'''
new = '''        @{
            @"name": @"incoming Fawran transfer",
            @"sms": @"Current Acc xxx364001 credited with QAR 1,000.00 for Fawran instant payment ref zeeshan,MOHAMED ASHFAAQ MOHAMED AZW withM-33510982 at 16:09, 03-Aug-26 Current Acc Bal: QAR 2,596.69",
            @"kind": @"incomingTransfer", @"ending": @"364001", @"amount": @"1000"
        },
        @{
            @"name": @"unrecognized transfer review fallback",
            @"sms": @"Transfer notification QAR 825.50 sent to beneficiary TEST PERSON reference X992 at 18:42, 07-Aug-26 account balance QAR 1,900.00",
            @"kind": @"reviewTransfer", @"ending": @"", @"amount": @"825.50", @"reviewFallback": @YES
        }
    ];
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one Fawran self-test tail, found {count}")
text = text.replace(old, new, 1)

old = '''        NSDictionary *parsed = ParseTransaction(test[@"sms"], NSDate.date);
'''
new = '''        NSDictionary *parsed = ParseTransaction(test[@"sms"], NSDate.date);
        if (!parsed && [test[@"reviewFallback"] boolValue]) {
            parsed = ReviewDraftForUnrecognizedBankSMS(test[@"sms"], NSDate.date);
        }
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one self-test parser line, found {count}")
text = text.replace(old, new, 1)

multiline = '''            ImportResult automaticResult = reviewFallback
                ? ImportResultWaitingForMapping
                : AutoRecordParsedEvent(parsed, sourceKey, sender, config);
'''
one_line = '''            ImportResult automaticResult = reviewFallback ? ImportResultWaitingForMapping : AutoRecordParsedEvent(parsed, sourceKey, sender, config);
'''
count = text.count(multiline)
if count != 1:
    raise RuntimeError(f"Expected one fallback Auto Record safety line, found {count}")
text = text.replace(multiline, one_line, 1)

path.write_text(text, encoding="utf-8")
print("Added unrecognized transfer review-fallback regression test and normalized its safety assertion.")
