ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = NextDiagnosticsModuleGlassTrace
NextDiagnosticsModuleGlassTrace_FILES = NextDiagnosticsModuleGlassTrace.m
NextDiagnosticsModuleGlassTrace_FRAMEWORKS = Foundation UIKit QuartzCore
NextDiagnosticsModuleGlassTrace_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter
include $(THEOS_MAKE_PATH)/tweak.mk
