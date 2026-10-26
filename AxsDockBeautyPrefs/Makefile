include ../AxsDockBeautyBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsDockBeautyPrefs
AxsDockBeautyPrefs_FILES = $(wildcard *.m)
AxsDockBeautyPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsDockBeautyPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsDockBeautyPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsDockBeautyPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
