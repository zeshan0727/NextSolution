ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextHomeLock
NextHomeLock_FILES = Tweak.xm
NextHomeLock_CFLAGS = -fobjc-arc
NextHomeLock_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
