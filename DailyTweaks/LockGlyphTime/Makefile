ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

before-all::
	python3 prefs/generate_root.py
	python3 patch_v023.py

TWEAK_NAME = LockGlyphTime
LockGlyphTime_FILES = RuntimeV023.xm
LockGlyphTime_CFLAGS = -fobjc-arc
LockGlyphTime_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk