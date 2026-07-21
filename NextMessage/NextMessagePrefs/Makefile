include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NextMessagePrefs
NextMessagePrefs_FILES = NMRootListController.m
NextMessagePrefs_CFLAGS = -fobjc-arc
NextMessagePrefs_FRAMEWORKS = UIKit
NextMessagePrefs_PRIVATE_FRAMEWORKS = Preferences
NextMessagePrefs_INSTALL_PATH = /Library/PreferenceBundles
NextMessagePrefs_RESOURCE_DIRS = Resources
NextMessagePrefs_CODESIGN_FLAGS = -SNextMessagePrefs.entitlements

include $(THEOS_MAKE_PATH)/bundle.mk
