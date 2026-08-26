include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PhoneAuraPrefs
PhoneAuraPrefs_FILES = PARootListControllerV44.m
PhoneAuraPrefs_FRAMEWORKS = UIKit
PhoneAuraPrefs_INSTALL_PATH = /Library/PreferenceBundles
PhoneAuraPrefs_RESOURCE_DIRS = Resources
PhoneAuraPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
PhoneAuraPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/bundle.mk
