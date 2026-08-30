ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextLockPhotoOnly20
NextLockPhotoOnly20_FILES = Tweak.m
NextLockPhotoOnly20_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextLockPhotoOnly20_FRAMEWORKS = Foundation UIKit CoreFoundation QuartzCore
NextLockPhotoOnly20_LIBRARIES = substrate

BUNDLE_NAME = NextLockPhotoOnlyPrefs
NextLockPhotoOnlyPrefs_FILES = PhotoPrefs.m
NextLockPhotoOnlyPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NextLockPhotoOnlyPrefs_FRAMEWORKS = Foundation UIKit CoreFoundation
NextLockPhotoOnlyPrefs_PRIVATE_FRAMEWORKS = Preferences
NextLockPhotoOnlyPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload"
