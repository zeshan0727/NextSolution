ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InternetLostHaptic
InternetLostHaptic_FILES = Tweak.xm
InternetLostHaptic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness
InternetLostHaptic_FRAMEWORKS = UIKit Foundation Network
InternetLostHaptic_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 Preferences SpringBoard 2>/dev/null || true"
