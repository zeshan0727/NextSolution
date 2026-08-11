ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhoneAuraDiagnostics
PhoneAuraDiagnostics_FILES = DiagnosticsTweak.m
PhoneAuraDiagnostics_FRAMEWORKS = Foundation UIKit Contacts CoreFoundation
PhoneAuraDiagnostics_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-error -Wno-unused-parameter -Wno-switch

include $(THEOS_MAKE_PATH)/tweak.mk
