#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AxsDockBeautyBubbleColorMode) {
    AxsDockBeautyBubbleColorRainbow = 0,
    AxsDockBeautyBubbleColorSingle = 1,
    AxsDockBeautyBubbleColorTransparent = 2,
};

@interface AxsDockBeautyConfig : NSObject
+ (instancetype)axs_dockbeauty_shared;
- (BOOL)axs_dockbeauty_isEnabled;
- (id)axs_dockbeauty_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_dockbeauty_reload;

// ── 美化版新增：单色气泡取色 ─────────────────────────────────────────────
// 0..1 色相（HSV hue），用于单色气泡 / 流光主色；缺省 0.58（青）。
- (double)axs_dockbeauty_bubbleHue;
// 单色气泡的饱和与明度，缺省 0.85 / 1.0。
- (double)axs_dockbeauty_bubbleSaturation;
- (double)axs_dockbeauty_bubbleValue;
// 流光（RGB 流光模式）主色相；缺省 0.83（品红）。
- (double)axs_dockbeauty_streamHue;
// 流光次色相（用于双色渐变），缺省 0.52（青）。
- (double)axs_dockbeauty_streamHue2;
- (AxsDockBeautyBubbleColorMode)axs_dockbeauty_bubbleColorMode;
// 气泡粒子尺寸（pt）与密度（影响发射速率），缺省 6/12/1.0。
- (double)axs_dockbeauty_bubbleSizeMin;
- (double)axs_dockbeauty_bubbleSizeMax;
- (double)axs_dockbeauty_bubbleDensity;
// 描边宽度（pt），缺省 3.0，范围 1–10。
- (double)axs_dockbeauty_glowWidth;
// 壁纸取色：开启后单色气泡 / 流光优先用桌面壁纸主色。
- (BOOL)axs_dockbeauty_wallpaperTint;
// 按时段自动换预设：白天 [7,19) 用 day 预设，其余用 night 预设。
- (BOOL)axs_dockbeauty_autoSchedule;
- (NSString *)axs_dockbeauty_scheduleDayName;
- (NSString *)axs_dockbeauty_scheduleNightName;
// 自定义预设：返回以 displayName 为键的字典数组；缺省空。
- (NSArray<NSDictionary *> *)axs_dockbeauty_customPresets;
@end
