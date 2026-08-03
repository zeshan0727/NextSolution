ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = roothide
TARGET_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/entitlements.plist

include $(THEOS)/makefiles/common.mk

TOOL_NAME = nextledgersmsd
nextledgersmsd_FILES = Sources/main.m
nextledgersmsd_CFLAGS = -fobjc-arc
nextledgersmsd_FRAMEWORKS = Foundation CoreFoundation
nextledgersmsd_LIBRARIES = sqlite3
nextledgersmsd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk
