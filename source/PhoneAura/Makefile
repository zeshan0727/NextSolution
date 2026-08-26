ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhoneAura
PhoneAura_FILES = Tweak.xm PhoneAuraManagerV46.m PAConceptDUI.m PAConceptDSurfaces.m PAContactFlowV46Fixed.m PADataStoreV45.m PARecentsV47.m PAContactActionsV47.m PAKeypadEnhancementsV49.m PAKeypadContactMenuV410.m PAKeypadStableSuggestionsV411.m PAKeypadHeaderBrandV414.m
PhoneAura_FRAMEWORKS = UIKit QuartzCore Contacts ContactsUI
PhoneAura_LIBRARIES = sqlite3
PhoneAura_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-protocol -Dpa47_initWithFrame=init_pa47WithFrame -Dpa47_contactsInitWithFrame=init_pa47ContactsWithFrame -include math.h
PhoneAura_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += phoneauraprefs phoneaurastudio
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"$(ECHO_END)
	$(ECHO_NOTHING)cp postinst "$(THEOS_STAGING_DIR)/DEBIAN/postinst"$(ECHO_END)
	$(ECHO_NOTHING)cp prerm "$(THEOS_STAGING_DIR)/DEBIAN/prerm"$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/prerm"$(ECHO_END)

after-install::
	install.exec "uicache -a 2>/dev/null || true; killall -9 Preferences MobilePhone PhoneAuraStudio 2>/dev/null || true"
