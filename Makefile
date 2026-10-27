# RednoteTools - 小红书 9.52 去水印

THEOS_DEVICE_IP = 192.168.1.100
THEOS_DEVICE_PORT = 22

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

DESKTOP ?= $(HOME)/Desktop

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RednoteTools

RednoteTools_FILES = Tweak.xm
RednoteTools_CFLAGS = -fobjc-arc -Wno-unused-variable
RednoteTools_FRAMEWORKS = UIKit Foundation Photos

include $(THEOS_MAKE_PATH)/tweak.mk

after-all::
	@dest="$(DESKTOP)"; \
	if [ ! -d "$$dest" ]; then dest="$$HOME/Desktop"; fi; \
	src="$(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib"; \
	if [ -f "$$src" ] && [ -d "$$dest" ]; then \
		cp -f "$$src" "$$dest/$(TWEAK_NAME).dylib"; \
		echo "copied $$src -> $$dest/$(TWEAK_NAME).dylib"; \
	else \
		echo "skip desktop copy: src=$$src dest=$$dest"; \
	fi

after-install::
	install.exec "killall -9 discover 2>/dev/null || true"
