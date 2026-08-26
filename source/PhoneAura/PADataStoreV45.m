#import "PADataStore.h"
#import <sqlite3.h>

@implementation PARecentCall
@end

@interface PADataStore ()
@property(nonatomic,strong) CNContactStore *contactStore;
@property(nonatomic,strong) NSCache<NSString *, NSString *> *nameCache;
@property(nonatomic) dispatch_queue_t workQueue;
@end

@implementation PADataStore

+ (instancetype)sharedStore {
    static PADataStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[self alloc] init];
    });
    return store;
}

- (instancetype)init {
    if ((self = [super init])) {
        _contactStore = [[CNContactStore alloc] init];
        _nameCache = [[NSCache alloc] init];
        _nameCache.countLimit = 600;
        _workQueue = dispatch_queue_create("com.zeshan.phoneaura.data", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

/*
 * CNContactFormatter can throw an exception when even one formatter-required
 * name property was not requested from CNContactStore. The previous build
 * fetched only givenName and familyName. Requesting Apple's descriptor makes
 * every returned contact safe for full-name formatting on iOS 16.
 */
- (NSArray<id<CNKeyDescriptor>> *)contactKeys {
    id<CNKeyDescriptor> fullNameDescriptor =
        [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName];

    NSMutableArray<id<CNKeyDescriptor>> *keys = [NSMutableArray array];
    if (fullNameDescriptor) [keys addObject:fullNameDescriptor];

    [keys addObjectsFromArray:@[
        CNContactIdentifierKey,
        CNContactGivenNameKey,
        CNContactMiddleNameKey,
        CNContactFamilyNameKey,
        CNContactNamePrefixKey,
        CNContactNameSuffixKey,
        CNContactNicknameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactThumbnailImageDataKey,
        CNContactImageDataAvailableKey
    ]];

    return keys;
}

- (BOOL)contactsCanBeRead {
    CNAuthorizationStatus status =
        [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    return status != CNAuthorizationStatusDenied &&
           status != CNAuthorizationStatusRestricted;
}

- (void)finishContacts:(NSArray<CNContact *> *)contacts
             completion:(void (^)(NSArray<CNContact *> *contacts))completion {
    NSArray<CNContact *> *snapshot = [contacts copy] ?: @[];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(snapshot);
    });
}

- (void)favoriteContactsForIdentifiers:(NSArray<NSString *> *)identifiers
                              completion:(void (^)(NSArray<CNContact *> *contacts))completion {
    NSArray<NSString *> *cleanIdentifiers =
        [identifiers isKindOfClass:[NSArray class]] ? [identifiers copy] : @[];

    if (cleanIdentifiers.count == 0 || ![self contactsCanBeRead]) {
        [self finishContacts:@[] completion:completion];
        return;
    }

    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSMutableArray<CNContact *> *contacts = [NSMutableArray array];

            @try {
                NSArray<id<CNKeyDescriptor>> *keys = [self contactKeys];
                for (NSString *identifier in cleanIdentifiers) {
                    if (![identifier isKindOfClass:[NSString class]] ||
                        identifier.length == 0) {
                        continue;
                    }

                    NSError *error = nil;
                    CNContact *contact =
                        [self.contactStore unifiedContactWithIdentifier:identifier
                                                            keysToFetch:keys
                                                                  error:&error];

                    if (contact && !error && contact.phoneNumbers.count > 0) {
                        [contacts addObject:contact];
                    }
                    if (contacts.count >= 4) break;
                }
            } @catch (__unused NSException *exception) {
                [contacts removeAllObjects];
            }

            [self finishContacts:contacts completion:completion];
        }
    });
}

- (void)allContactsWithCompletion:(void (^)(NSArray<CNContact *> *contacts))completion {
    if (![self contactsCanBeRead]) {
        [self finishContacts:@[] completion:completion];
        return;
    }

    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSMutableArray<CNContact *> *contacts = [NSMutableArray array];

            @try {
                CNContactFetchRequest *request =
                    [[CNContactFetchRequest alloc] initWithKeysToFetch:[self contactKeys]];
                request.sortOrder = CNContactSortOrderUserDefault;
                request.unifyResults = YES;
                request.mutableObjects = NO;

                NSError *error = nil;
                BOOL success =
                    [self.contactStore enumerateContactsWithFetchRequest:request
                                                                   error:&error
                                                              usingBlock:^(CNContact *contact, BOOL *stop) {
                    BOOL hasDisplayName =
                        contact.givenName.length > 0 ||
                        contact.middleName.length > 0 ||
                        contact.familyName.length > 0 ||
                        contact.nickname.length > 0 ||
                        contact.organizationName.length > 0;

                    if (hasDisplayName) [contacts addObject:contact];
                    if (contacts.count >= 1200) *stop = YES;
                }];

                if (!success || error) [contacts removeAllObjects];
            } @catch (__unused NSException *exception) {
                [contacts removeAllObjects];
            }

            [self finishContacts:contacts completion:completion];
        }
    });
}

static NSString *PAStringFromColumn(sqlite3_stmt *statement, int index) {
    const unsigned char *text = sqlite3_column_text(statement, index);
    return text ? [NSString stringWithUTF8String:(const char *)text] : @"";
}

- (NSString *)callHistoryDatabasePath {
    NSArray<NSString *> *candidates = @[
        @"/var/mobile/Library/CallHistoryDB/CallHistory.storedata",
        @"/private/var/mobile/Library/CallHistoryDB/CallHistory.storedata"
    ];

    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return nil;
}

- (NSDictionary<NSString *, NSString *> *)columnsForTable:(NSString *)table
                                                  database:(sqlite3 *)database {
    NSMutableDictionary<NSString *, NSString *> *columns = [NSMutableDictionary dictionary];
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
    sqlite3_stmt *statement = NULL;

    if (sqlite3_prepare_v2(database, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) {
        return columns;
    }

    while (sqlite3_step(statement) == SQLITE_ROW) {
        NSString *name = PAStringFromColumn(statement, 1);
        if (name.length) columns[name.uppercaseString] = name;
    }

    sqlite3_finalize(statement);
    return columns;
}

- (NSString *)safeDisplayNameForContact:(CNContact *)contact fallback:(NSString *)fallback {
    if (!contact) return fallback.length ? fallback : @"Unknown Caller";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (contact.givenName.length) [parts addObject:contact.givenName];
    if (contact.middleName.length) [parts addObject:contact.middleName];
    if (contact.familyName.length) [parts addObject:contact.familyName];

    NSString *name = [parts componentsJoinedByString:@" "];
    if (name.length) return name;
    if (contact.nickname.length) return contact.nickname;
    if (contact.organizationName.length) return contact.organizationName;
    return fallback.length ? fallback : @"Unknown Caller";
}

- (NSString *)displayNameForNumber:(NSString *)number {
    if (number.length == 0) return @"Unknown Caller";

    NSString *cached = [self.nameCache objectForKey:number];
    if (cached) return cached;

    NSString *name = number;
    if ([self contactsCanBeRead]) {
        @try {
            CNPhoneNumber *phoneNumber =
                [CNPhoneNumber phoneNumberWithStringValue:number];
            NSPredicate *predicate =
                [CNContact predicateForContactsMatchingPhoneNumber:phoneNumber];
            NSError *error = nil;
            NSArray<CNContact *> *matches =
                [self.contactStore unifiedContactsMatchingPredicate:predicate
                                                         keysToFetch:[self contactKeys]
                                                               error:&error];
            CNContact *contact = matches.firstObject;
            if (contact && !error) {
                name = [self safeDisplayNameForContact:contact fallback:number];
            }
        } @catch (__unused NSException *exception) {
        }
    }

    [self.nameCache setObject:name forKey:number];
    return name;
}

- (void)recentCallsMissedOnly:(BOOL)missedOnly
                         limit:(NSUInteger)limit
                    completion:(void (^)(NSArray<PARecentCall *> *calls))completion {
    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSMutableArray<PARecentCall *> *calls = [NSMutableArray array];
            NSString *databasePath = [self callHistoryDatabasePath];
            sqlite3 *database = NULL;

            if (!databasePath ||
                sqlite3_open_v2(databasePath.fileSystemRepresentation,
                                &database,
                                SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                                NULL) != SQLITE_OK) {
                if (database) sqlite3_close(database);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(@[]);
                });
                return;
            }

            NSDictionary<NSString *, NSString *> *columns =
                [self columnsForTable:@"ZCALLRECORD" database:database];
            NSString *address = columns[@"ZADDRESS"];
            NSString *date = columns[@"ZDATE"];

            if (!address || !date) {
                sqlite3_close(database);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(@[]);
                });
                return;
            }

            NSString *(^columnOrZero)(NSString *) = ^NSString *(NSString *key) {
                NSString *column = columns[key];
                return column ?: @"0";
            };

            NSString *duration = columnOrZero(@"ZDURATION");
            NSString *originated = columnOrZero(@"ZORIGINATED");
            NSString *answered = columnOrZero(@"ZANSWERED");

            NSUInteger safeLimit =
                MAX((NSUInteger)10, MIN(limit ?: 80, (NSUInteger)250));
            NSString *sql = [NSString stringWithFormat:
                @"SELECT %@, %@, %@, %@, %@ FROM ZCALLRECORD ORDER BY %@ DESC LIMIT %lu",
                address,
                date,
                duration,
                originated,
                answered,
                date,
                (unsigned long)safeLimit];

            sqlite3_stmt *statement = NULL;
            if (sqlite3_prepare_v2(database,
                                   sql.UTF8String,
                                   -1,
                                   &statement,
                                   NULL) == SQLITE_OK) {
                while (sqlite3_step(statement) == SQLITE_ROW) {
                    NSString *number = PAStringFromColumn(statement, 0);
                    NSTimeInterval rawDate = sqlite3_column_double(statement, 1);
                    NSTimeInterval callDuration = sqlite3_column_double(statement, 2);
                    BOOL callOriginated = sqlite3_column_int(statement, 3) != 0;
                    BOOL callAnswered = sqlite3_column_int(statement, 4) != 0;
                    BOOL callMissed = !callOriginated && !callAnswered;

                    if (missedOnly && !callMissed) continue;

                    NSTimeInterval unixDate =
                        rawDate < 1200000000.0 ? rawDate + 978307200.0 : rawDate;

                    PARecentCall *call = [[PARecentCall alloc] init];
                    call.number = number.length ? number : @"Unknown";
                    call.displayName = [self displayNameForNumber:number];
                    call.date = [NSDate dateWithTimeIntervalSince1970:unixDate];
                    call.duration = callDuration;
                    call.missed = callMissed;
                    call.outgoing = callOriginated;
                    [calls addObject:call];
                }
            }

            if (statement) sqlite3_finalize(statement);
            sqlite3_close(database);

            NSArray<PARecentCall *> *snapshot = [calls copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(snapshot);
            });
        }
    });
}

@end
