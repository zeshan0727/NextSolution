ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCModuleBackgrounds
CCModuleBackgrounds_FILES = Tweak.mm
CCModuleBackgrounds_CFLAGS = -fobjc-arc -include $(THEOS_PROJECT_DIR)/Compat.h
CCModuleBackgrounds_CXXFLAGS = -std=c++17
CCModuleBackgrounds_FRAMEWORKS = Foundation UIKit CoreFoundation CoreGraphics QuartzCore
CCModuleBackgrounds_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
