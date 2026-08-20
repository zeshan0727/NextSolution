ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextLockFeatureFix
NextLockFeatureFix_FILES = Tweak.m
NextLockFeatureFix_CFLAGS = -fobjc-arc
NextLockFeatureFix_FRAMEWORKS = Foundation UIKit QuartzCore CoreFoundation
NextLockFeatureFix_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
