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
// 动画模式开关。
- (BOOL)axs_dockbeauty_animFloat;
- (BOOL)axs_dockbeauty_animIconFloat;
- (BOOL)axs_dockbeauty_animBreathing;
- (BOOL)axs_dockbeauty_animRandom;
- (BOOL)axs_dockbeauty_animStream;
- (BOOL)axs_dockbeauty_animFirefly;
- (BOOL)axs_dockbeauty_animFish;
- (BOOL)axs_dockbeauty_animRoll;
- (BOOL)axs_dockbeauty_animShake;
- (NSInteger)axs_dockbeauty_fishCount;
// Dock 本体：背景不透明度（0 = 隐藏背景）、圆角。
- (double)axs_dockbeauty_bgOpacity;
- (double)axs_dockbeauty_cornerRadius;
// 图标效果：大小倍数、发光开关/强度。
- (double)axs_dockbeauty_iconScale;
- (BOOL)axs_dockbeauty_iconGlow;
- (double)axs_dockbeauty_iconGlowIntensity;
// 翻滚/抖动参数。
- (double)axs_dockbeauty_rollAmplitude;
- (double)axs_dockbeauty_rollPeriod;
- (double)axs_dockbeauty_shakeAmplitude;
- (double)axs_dockbeauty_shakePeriod;
// 点击反馈：涟漪 + 弹性回弹。
- (BOOL)axs_dockbeauty_tapRipple;
- (BOOL)axs_dockbeauty_tapBounce;
// 季节粒子：0=关 1=雪花 2=樱花 3=落叶 4=星星 5=爱心 6=自动（节日优先，否则按季节）。
- (NSInteger)axs_dockbeauty_particleStyle;
// 系统保护：低电量降载、减弱动态适配。
- (BOOL)axs_dockbeauty_lowPowerGuard;
- (BOOL)axs_dockbeauty_reduceMotionGuard;
// 浮动参数：振幅倍数（1.0 = 12pt）、周期秒。
- (double)axs_dockbeauty_floatAmplitude;
- (double)axs_dockbeauty_floatPeriod;
// 图标独立浮动参数：振幅倍数（1.0 = 8pt）、周期秒、相位差（弧度/图标，越大波浪越明显）。
- (double)axs_dockbeauty_iconFloatAmplitude;
- (double)axs_dockbeauty_iconFloatPeriod;
- (double)axs_dockbeauty_iconFloatSpread;
// 呼吸参数：缩放振幅（0.08 = ±8%）、周期秒。
- (double)axs_dockbeauty_breathingAmplitude;
- (double)axs_dockbeauty_breathingPeriod;
// 弹簧物理：浮动用弹簧追踪而非纯正弦（更柔）。
- (BOOL)axs_dockbeauty_springEnabled;
// 流光控制：速度、宽度（占 Dock 宽比例）、高度（占 Dock 高比例）、不透明度。
- (double)axs_dockbeauty_streamSpeed;
- (double)axs_dockbeauty_streamWidth;
- (double)axs_dockbeauty_streamHeight;
- (double)axs_dockbeauty_streamOpacity;
// 壁纸取色：开启后单色气泡 / 流光优先用桌面壁纸主色。
- (BOOL)axs_dockbeauty_wallpaperTint;
// 按时段自动换预设：白天 [7,19) 用 day 预设，其余用 night 预设。
- (BOOL)axs_dockbeauty_autoSchedule;
- (NSString *)axs_dockbeauty_scheduleDayName;
- (NSString *)axs_dockbeauty_scheduleNightName;
// 自定义预设：返回以 displayName 为键的字典数组；缺省空。
- (NSArray<NSDictionary *> *)axs_dockbeauty_customPresets;
@end
