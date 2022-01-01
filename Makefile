TARGET := iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = YouTube
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YouTubeDislikesReturn
YouTubeDislikesReturn_FILES = Tweak.xm $(shell find AFNetworking -name '*.m')
YouTubeDislikesReturn_CFLAGS = -fobjc-arc
YouTubeDislikesReturn_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
