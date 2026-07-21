ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = MobileSMS Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextMessage
NextMessage_FILES = Tweak.xm NMDiagnostics.m
NextMessage_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextMessage_FRAMEWORKS = UIKit Foundation QuartzCore
NextMessage_LIBRARIES = sqlite3

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += NextMessagePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	@chmod 0755 layout/DEBIAN/postinst 2>/dev/null || true
	@chmod 0755 layout/DEBIAN/postrm 2>/dev/null || true

after-install::
	install.exec "uicache -a 2>/dev/null || true; killall -9 MobileSMS Preferences 2>/dev/null || true"
