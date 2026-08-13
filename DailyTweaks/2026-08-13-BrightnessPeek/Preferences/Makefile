include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = BrightnessPeekPreferences
BrightnessPeekPreferences_FILES = BPRootListController.m
BrightnessPeekPreferences_FRAMEWORKS = UIKit
BrightnessPeekPreferences_INSTALL_PATH = /Library/PreferenceBundles
BrightnessPeekPreferences_RESOURCE_DIRS = Resources
BrightnessPeekPreferences_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
BrightnessPeekPreferences_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/bundle.mk
