ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ModuleGlassPrefsExtension
ModuleGlassPrefsExtension_FILES = Tweak.m
ModuleGlassPrefsExtension_CFLAGS = -fobjc-arc
ModuleGlassPrefsExtension_FRAMEWORKS = Foundation UIKit CoreFoundation
ModuleGlassPrefsExtension_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
