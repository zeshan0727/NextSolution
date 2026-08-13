ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = MobilePhone

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhoneAuraNativeFeatures
PhoneAuraNativeFeatures_FILES = Tweak.m
PhoneAuraNativeFeatures_FRAMEWORKS = UIKit Foundation Contacts ContactsUI
PhoneAuraNativeFeatures_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
PhoneAuraNativeFeatures_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk
