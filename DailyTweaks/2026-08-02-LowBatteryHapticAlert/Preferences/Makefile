include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LowBatteryHapticAlertPreferences
LowBatteryHapticAlertPreferences_FILES = LBHARootListController.m
LowBatteryHapticAlertPreferences_FRAMEWORKS = UIKit
LowBatteryHapticAlertPreferences_PRIVATE_FRAMEWORKS = Preferences
LowBatteryHapticAlertPreferences_INSTALL_PATH = /Library/PreferenceBundles
LowBatteryHapticAlertPreferences_RESOURCE_DIRS = Resources
LowBatteryHapticAlertPreferences_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
LowBatteryHapticAlertPreferences_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/bundle.mk
