TARGET = iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = ESHelper

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ESHelper
ESHelper_FILES = main.m ESHelperDelegate.m
ESHelper_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/application.mk
