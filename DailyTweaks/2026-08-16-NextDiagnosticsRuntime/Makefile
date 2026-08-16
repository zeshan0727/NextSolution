ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NextDiagnosticsRuntime
NextDiagnosticsRuntime_FILES = NextDiagnosticsRuntime.m
NextDiagnosticsRuntime_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness
NextDiagnosticsRuntime_FRAMEWORKS = Foundation UIKit
NextDiagnosticsRuntime_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk
