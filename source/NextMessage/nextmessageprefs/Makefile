include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NextMessagePrefs
NextMessagePrefs_FILES = NMRootListController.m
NextMessagePrefs_FRAMEWORKS = UIKit QuartzCore
NextMessagePrefs_PRIVATE_FRAMEWORKS = Preferences
NextMessagePrefs_INSTALL_PATH = /Library/PreferenceBundles
NextMessagePrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextMessagePrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/bundle.mk
