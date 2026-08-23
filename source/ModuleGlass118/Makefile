ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = CCModuleBackgrounds ModuleGlassStandalonePrefsExtension ModuleGlassActivation

CCModuleBackgrounds_FILES = Tweak.m
CCModuleBackgrounds_CFLAGS = -fobjc-arc -Wno-unneeded-internal-declaration -include $(THEOS_PROJECT_DIR)/Compat.h
CCModuleBackgrounds_FRAMEWORKS = Foundation UIKit CoreFoundation CoreGraphics QuartzCore
CCModuleBackgrounds_LIBRARIES = substrate

ModuleGlassStandalonePrefsExtension_FILES = ModuleGlassPrefsExtension.m
ModuleGlassStandalonePrefsExtension_CFLAGS = -fobjc-arc
ModuleGlassStandalonePrefsExtension_FRAMEWORKS = Foundation UIKit CoreFoundation
ModuleGlassStandalonePrefsExtension_LIBRARIES = substrate

ModuleGlassActivation_FILES = ModuleGlassActivation.m
ModuleGlassActivation_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ModuleGlassActivation_FRAMEWORKS = Foundation UIKit CoreFoundation
ModuleGlassActivation_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
