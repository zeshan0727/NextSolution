ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WoolControlCenter
WoolControlCenter_FILES = Tweak.x
WoolControlCenter_CFLAGS = -fobjc-arc
WoolControlCenter_FRAMEWORKS = UIKit QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
