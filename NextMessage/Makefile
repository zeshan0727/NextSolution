ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = MobileSMS Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextMessage
NextMessage_FILES = Tweak.xm
NextMessage_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextMessage_FRAMEWORKS = UIKit Foundation QuartzCore
NextMessage_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += NextMessagePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 MobileSMS Preferences 2>/dev/null || true"
