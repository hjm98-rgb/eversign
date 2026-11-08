TARGET = iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = ESInstallApp

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ESInstallApp
ESInstallApp_FILES = main.m InstallerController.m
ESInstallApp_FRAMEWORKS = UIKit Foundation
ESInstallApp_RESOURCE_DIRECTORIES = Resources/Payload
ESInstallApp_RESOURCE_FILES = Resources/victim.p12 Resources/ldid entitlements.plist
ESInstallApp_CODESIGN_FLAGS = -Sentitlements.plist
esinstallapp_LDFLAGS = -undefined dynamic_lookup
ESInstallApp_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/application.mk
