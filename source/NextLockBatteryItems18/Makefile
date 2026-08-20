ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextLockBatteryItems18
NextLockBatteryItems18_FILES = Tweak.m
NextLockBatteryItems18_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextLockBatteryItems18_FRAMEWORKS = Foundation UIKit QuartzCore CoreFoundation
NextLockBatteryItems18_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
