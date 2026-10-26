DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsDockBeautyBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsDockBeauty
AxsDockBeauty_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsDockBeauty_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsDockBeauty_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsDockBeauty_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsDockBeautyPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
