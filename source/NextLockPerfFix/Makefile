ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextLockPerfFix
NextLockPerfFix_FILES = TweakTest7.m
NextLockPerfFix_CFLAGS = -fobjc-arc -Wall -Wextra
NextLockPerfFix_FRAMEWORKS = Foundation UIKit QuartzCore CoreFoundation
NextLockPerfFix_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
