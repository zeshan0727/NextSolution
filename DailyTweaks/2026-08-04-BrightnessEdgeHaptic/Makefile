ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BrightnessEdgeHaptic
BrightnessEdgeHaptic_FILES = Tweak.xm
BrightnessEdgeHaptic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness
BrightnessEdgeHaptic_FRAMEWORKS = UIKit Foundation
BrightnessEdgeHaptic_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 Preferences SpringBoard 2>/dev/null || true"
