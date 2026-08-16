ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

# Build with either:
#   THEOS_PACKAGE_SCHEME=rootless make clean package FINALPACKAGE=1
#   THEOS_PACKAGE_SCHEME=roothide  make clean package FINALPACKAGE=1
THEOS_PACKAGE_SCHEME ?= rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockGlyphTime
LockGlyphTime_FILES = Tweak.xm
LockGlyphTime_CFLAGS = -fobjc-arc
LockGlyphTime_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
