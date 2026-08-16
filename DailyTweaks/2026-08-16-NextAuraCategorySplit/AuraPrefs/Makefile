ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AuraPrefs
AuraPrefs_FILES = AuraPrefs.m
AuraPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AuraPrefs_INSTALL_PATH = /Library/PreferenceBundles
AuraPrefs_CFLAGS = -fobjc-arc
AuraPrefs_LDFLAGS = -undefined dynamic_lookup
AuraPrefs_RESOURCE_FILES = Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk
