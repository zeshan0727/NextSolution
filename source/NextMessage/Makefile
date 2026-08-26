ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextMessage
NextMessage_FILES = Tweak.xm
NextMessage_FRAMEWORKS = UIKit QuartzCore
NextMessage_LIBRARIES = sqlite3
NextMessage_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-unguarded-availability-new
NextMessage_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += nextmessageprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"$(ECHO_END)
	$(ECHO_NOTHING)cp postinst "$(THEOS_STAGING_DIR)/DEBIAN/postinst"$(ECHO_END)
	$(ECHO_NOTHING)cp prerm "$(THEOS_STAGING_DIR)/DEBIAN/prerm"$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/prerm"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/NextMessagePrefs.bundle"$(ECHO_END)
	$(ECHO_NOTHING)cp ../../CydiaIcon.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/NextMessagePrefs.bundle/icon.png"$(ECHO_END)

after-install::
	install.exec "uicache -a 2>/dev/null || true; killall -9 Preferences MobileSMS 2>/dev/null || true"
