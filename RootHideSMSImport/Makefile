ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DailyLedgerSMSImport
DailyLedgerSMSImport_FILES = Sources/main.m
DailyLedgerSMSImport_CFLAGS = -fobjc-arc -DDAILYLEDGER_TWEAK=1
DailyLedgerSMSImport_FRAMEWORKS = Foundation CoreFoundation AudioToolbox
DailyLedgerSMSImport_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = DailyLedgerSMSImportPreferences
DailyLedgerSMSImportPreferences_FILES = Preferences/DLRootListController.m
DailyLedgerSMSImportPreferences_CFLAGS = -fobjc-arc
DailyLedgerSMSImportPreferences_FRAMEWORKS = UIKit
DailyLedgerSMSImportPreferences_PRIVATE_FRAMEWORKS = Preferences
DailyLedgerSMSImportPreferences_RESOURCE_FILES = Preferences/Root.plist
DailyLedgerSMSImportPreferences_INFOPLIST = Preferences/Info.plist
DailyLedgerSMSImportPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
