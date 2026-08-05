TARGET := iphone:clang:16.5:16.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextPasswordOverlay
NextPasswordOverlay_FILES = Tweak.xm
NextPasswordOverlay_CFLAGS = -fobjc-arc
NextPasswordOverlay_FRAMEWORKS = UIKit Foundation
NextPasswordOverlay_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
