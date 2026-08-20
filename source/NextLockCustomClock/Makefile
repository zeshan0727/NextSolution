ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextLockCustomClock
NextLockCustomClock_FILES = TweakPatched.m
NextLockCustomClock_CFLAGS = -fobjc-arc
NextLockCustomClock_FRAMEWORKS = Foundation UIKit QuartzCore CoreFoundation
NextLockCustomClock_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
