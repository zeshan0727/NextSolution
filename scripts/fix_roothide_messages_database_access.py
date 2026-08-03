from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


source = "RootHideSMSQueue/Sources/main.m"

replace_once(
    source,
    '''#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
''',
    '''#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
''',
)

replace_once(
    source,
    'static NSString *const kDaemonVersion = @"2.0.0";',
    'static NSString *const kDaemonVersion = @"2.0.3";',
)

replace_once(
    source,
    '''static NSString *StateDirectory(void) {
    return ExistingPath(@[
        @"/rootfs/var/mobile/Library/NextLedgerSMSImport",
        @"/var/mobile/Library/NextLedgerSMSImport"
    ]);
}
''',
    '''static NSString *StateDirectory(void) {
    return ExistingPath(@[
        @"/rootfs/private/var/mobile/Library/NextLedgerSMSImport",
        @"/rootfs/var/mobile/Library/NextLedgerSMSImport",
        @"/private/var/mobile/Library/NextLedgerSMSImport",
        @"/var/mobile/Library/NextLedgerSMSImport"
    ]);
}
''',
)

replace_once(
    source,
    '''    NSArray<NSString *> *bases = @[
        @"/rootfs/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Data/Application"
    ];
''',
    '''    NSArray<NSString *> *bases = @[
        @"/rootfs/private/var/mobile/Containers/Data/Application",
        @"/rootfs/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Data/Application"
    ];
''',
)

replace_once(
    source,
    '''static NSString *SMSDatabasePath(void) {
    return ExistingPath(@[
        @"/rootfs/var/mobile/Library/SMS/sms.db",
        @"/var/mobile/Library/SMS/sms.db"
    ]);
}
''',
    '''static NSArray<NSString *> *SMSDatabaseCandidates(void) {
    return @[
        @"/rootfs/private/var/mobile/Library/SMS/sms.db",
        @"/rootfs/var/mobile/Library/SMS/sms.db",
        @"/private/var/mobile/Library/SMS/sms.db",
        @"/var/mobile/Library/SMS/sms.db"
    ];
}

static NSString *SMSDatabasePath(void) {
    for (NSString *path in SMSDatabaseCandidates()) {
        errno = 0;
        if (access(path.fileSystemRepresentation, R_OK) == 0) return path;
    }
    return nil;
}

static NSString *PathProbe(NSString *path) {
    struct stat info;
    errno = 0;
    if (stat(path.fileSystemRepresentation, &info) == 0) {
        unsigned int mode = (unsigned int)(info.st_mode & 0777);
        errno = 0;
        if (access(path.fileSystemRepresentation, R_OK) == 0) {
            return [NSString stringWithFormat:@"%@ = readable (mode %03o uid %u gid %u)",
                path, mode, (unsigned int)info.st_uid, (unsigned int)info.st_gid];
        }
        int code = errno;
        return [NSString stringWithFormat:@"%@ = exists but unreadable: %s (%d), mode %03o uid %u gid %u",
            path, strerror(code), code, mode, (unsigned int)info.st_uid, (unsigned int)info.st_gid];
    }

    int code = errno;
    NSString *parent = path.stringByDeletingLastPathComponent;
    struct stat parentInfo;
    errno = 0;
    BOOL parentExists = stat(parent.fileSystemRepresentation, &parentInfo) == 0;
    int parentCode = errno;
    NSString *parentStatus = parentExists
        ? [NSString stringWithFormat:@"parent exists mode %03o uid %u gid %u",
            (unsigned int)(parentInfo.st_mode & 0777),
            (unsigned int)parentInfo.st_uid,
            (unsigned int)parentInfo.st_gid]
        : [NSString stringWithFormat:@"parent unavailable: %s (%d)", strerror(parentCode), parentCode];
    return [NSString stringWithFormat:@"%@ = unavailable: %s (%d); %@",
        path, strerror(code), code, parentStatus];
}

static NSString *SMSDatabaseDiagnostics(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:
        [NSString stringWithFormat:@"process uid=%d euid=%d gid=%d egid=%d",
            getuid(), geteuid(), getgid(), getegid()]];
    for (NSString *path in SMSDatabaseCandidates()) [parts addObject:PathProbe(path)];
    return [parts componentsJoinedByString:@" | "];
}
''',
)

replace_once(
    source,
    '''    NSString *databasePath = SMSDatabasePath();
    if (![NSFileManager.defaultManager fileExistsAtPath:databasePath]) {
        AddLog(@"error", @"Messages database was not found at the expected iOS 16 path.");
        WriteConsole(@"Messages database not found.");
        return;
    }
''',
    '''    NSString *databasePath = SMSDatabasePath();
    if (databasePath.length == 0) {
        NSString *diagnostic = SMSDatabaseDiagnostics();
        if (![gState[@"lastSMSDatabaseDiagnostic"] isEqualToString:diagnostic]) {
            gState[@"lastSMSDatabaseDiagnostic"] = diagnostic;
            AddLog(@"error", @"Messages database is inaccessible. %@", diagnostic);
        }
        WriteConsole(@"Messages database is inaccessible. Check the latest database path diagnostic.");
        return;
    }
    if (![gState[@"resolvedSMSDatabasePath"] isEqualToString:databasePath]) {
        gState[@"resolvedSMSDatabasePath"] = databasePath;
        [gState removeObjectForKey:@"lastSMSDatabaseDiagnostic"];
        AddLog(@"success", @"Messages database is readable at %@.", databasePath);
    }
''',
)

replace_once(
    source,
    '''    sqlite3 *database = NULL;
    if (sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        AddLog(@"error", @"Root daemon could not open sms.db read-only.");
        WriteConsole(@"Could not open Messages database.");
        return;
    }
''',
    '''    sqlite3 *database = NULL;
    int openResult = sqlite3_open_v2(databasePath.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
    if (openResult != SQLITE_OK) {
        NSString *message = database ? [NSString stringWithUTF8String:sqlite3_errmsg(database)] : @"No SQLite handle";
        AddLog(@"error", @"Could not open Messages database %@ read-only: %@ (%d).",
            databasePath, message ?: @"Unknown SQLite error", openResult);
        if (database) sqlite3_close(database);
        WriteConsole(@"Messages database path is visible but SQLite could not open it.");
        return;
    }
''',
)

replace_once(
    source,
    '''    if (!savedRow) {
        gState[@"lastRowID"] = @(maximum);
        gState[@"lastScanRequestID"] = @(requestID);
        sqlite3_close(database);
''',
    '''    if (!savedRow) {
        gState[@"lastRowID"] = @(maximum);
        gState[@"lastScanRequestID"] = @(requestID);
        gState[@"lastScanDate"] = ISODate(NSDate.date);
        sqlite3_close(database);
''',
)

print("Added protected Messages storage access, real-root path candidates, and detailed database diagnostics.")
