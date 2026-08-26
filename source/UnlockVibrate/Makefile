ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = UnlockVibrate
UnlockVibrate_FILES = Tweak.x
UnlockVibrate_FRAMEWORKS = AudioToolbox Foundation
UnlockVibrate_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += unlockvibrateprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
