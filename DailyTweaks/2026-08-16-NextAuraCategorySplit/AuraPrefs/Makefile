ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AuraPrefs
AuraPrefs_FILES = AuraPrefs.m
AuraPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AuraPrefs_PRIVATE_FRAMEWORKS = Preferences
AuraPrefs_INSTALL_PATH = /Library/PreferenceBundles
AuraPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
