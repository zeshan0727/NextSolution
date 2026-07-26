ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextPasswordKeyboard
NextPasswordKeyboard_FILES = Tweak.xm
NextPasswordKeyboard_FRAMEWORKS = UIKit Foundation
NextPasswordKeyboard_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
