TARGET = iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = EverSign

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = EverSign

EverSign_FILES = $(wildcard *.m)
EverSign_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore UniformTypeIdentifiers
EverSign_LIBRARIES = z
EverSign_RESOURCE_FILES = Resources/ldid Resources/victim.p12 Resources/ESHelper entitlements.plist
EverSign_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-EverSign-stage::
	@echo "staged EverSign.app"
