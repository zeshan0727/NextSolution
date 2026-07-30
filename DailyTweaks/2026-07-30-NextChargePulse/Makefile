ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextChargePulse
NextChargePulse_FILES = Tweak.xm
NextChargePulse_CFLAGS = -fobjc-arc
NextChargePulse_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
