include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PhoneAuraStudio
PhoneAuraStudio_FILES = main.m PAStudioAppDelegate.m PAStudioRootController.m
PhoneAuraStudio_FRAMEWORKS = UIKit Contacts ContactsUI QuartzCore
PhoneAuraStudio_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
PhoneAuraStudio_INSTALL_PATH = /Applications
PhoneAuraStudio_CODESIGN_FLAGS = -SPhoneAuraStudio.entitlements
PhoneAuraStudio_LDFLAGS = -Wl,-segalign,4000
PhoneAuraStudio_RESOURCE_FILES = ../phoneauraprefs/Resources/icon.png

include $(THEOS_MAKE_PATH)/application.mk
