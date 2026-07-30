ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextHomeLock
NextHomeLock_FILES = Tweak.xm
NextHomeLock_CFLAGS = -fobjc-arc
NextHomeLock_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = NextHomeLockPreferences
NextHomeLockPreferences_FILES = Preferences/NHLRootListController.m
NextHomeLockPreferences_CFLAGS = -fobjc-arc
NextHomeLockPreferences_FRAMEWORKS = UIKit Foundation
NextHomeLockPreferences_LDFLAGS = -undefined dynamic_lookup
NextHomeLockPreferences_RESOURCE_FILES = Preferences/Root.plist Preferences/Info.plist
NextHomeLockPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
