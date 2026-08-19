include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NextQuickReminderPreferences
NextQuickReminderPreferences_FILES = NQRRootListController.m NQRDiagnosticsController.m
NextQuickReminderPreferences_FRAMEWORKS = UIKit Foundation
NextQuickReminderPreferences_INSTALL_PATH = /Library/PreferenceBundles
NextQuickReminderPreferences_RESOURCE_DIRS = Resources
NextQuickReminderPreferences_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness
NextQuickReminderPreferences_LDFLAGS = -Wl,-undefined,dynamic_lookup -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/bundle.mk
