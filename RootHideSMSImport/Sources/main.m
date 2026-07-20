        status = [NSString stringWithFormat:@"The latest matching SMS containing %@ was already recorded.", matchText];
    } else {
        status = [NSString stringWithFormat:@"No recent SMS containing %@ was found.", matchText];
    }
    UpdateStatus(ledgerPath, status);
    SaveTweakStatus(status);
    Log(@"%@", status);
}

#if !defined(DAILYLEDGER_TWEAK)
static int RunSelfTest(void) {
    NSString *sample = @"Your card ending **6760\nused for QAR 20.00\nat NEW NASCO RESTAURANT\nat 14:03\n07-May-26\nAvailable Limit: QAR 107.01";
    NSDictionary *parsed = ParseTransaction(sample, [NSDate dateWithTimeIntervalSince1970:0]);
    NSString *category = CategoryForVendor(parsed[@"vendor"], DefaultRules());
    BOOL markerMatches = [sample rangeOfString:kDefaultMatchText].location != NSNotFound;
    BOOL passed = parsed && markerMatches &&
        [parsed[@"amount"] isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"20.00"]] &&
        [parsed[@"vendor"] isEqualToString:@"NEW NASCO RESTAURANT"] && [category isEqualToString:@"Restaurant"];
    NSDictionary *result = parsed ? @{
        @"passed": @(passed), @"marker": kDefaultMatchText, @"amount": parsed[@"amount"],
        @"vendor": parsed[@"vendor"], @"category": category, @"type": parsed[@"type"],
        @"date": ISODate(parsed[@"date"])
    } : @{@"passed": @NO};
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    fprintf(stdout, "%s\n", [[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]);
    return passed ? 0 : 1;
}
#endif

#if defined(DAILYLEDGER_TWEAK)
static dispatch_source_t gDailyLedgerTimer;

__attribute__((constructor))
static void DailyLedgerSMSImportInitialize(void) {
    @autoreleasepool {
        Log(@"Daily Ledger SMS Import 1.4.0 native RootHide tweak loaded in SpringBoard; exact marker is %@.", kDefaultMatchText);
        SaveTweakStatus(@"Tweak loaded in SpringBoard. Waiting for an SMS or manual scan.");
        dispatch_queue_t queue = dispatch_queue_create("com.nextsolution.dailyledger.smsimport", DISPATCH_QUEUE_SERIAL);
        gDailyLedgerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(gDailyLedgerTimer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(gDailyLedgerTimer, ^{
            @autoreleasepool { ProcessMessages(NO); }
        });
        dispatch_resume(gDailyLedgerTimer);
    }
}
#else
int main(int argc, char *argv[]) {
