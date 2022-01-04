TARGET := iphone:clang:latest:11.0
INSTALL_TARGET_PROCESSES = YouTube
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouTubeDislikesReturn
YouTubeDislikesReturn_FILES = Tweak.xm
YouTubeDislikesReturn_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
