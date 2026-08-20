ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextLockDateFix17
NextLockDateFix17_FILES = Tweak.m
NextLockDateFix17_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextLockDateFix17_FRAMEWORKS = Foundation UIKit CoreFoundation
NextLockDateFix17_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
