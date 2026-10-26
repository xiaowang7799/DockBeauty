#import "AxsDockBeautyConfig.h"
#import "AxsDockBeautyPreferences.h"
#import <math.h>

@interface AxsDockBeautyConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_dockbeauty_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsDockBeautyConfig *config = (__bridge AxsDockBeautyConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_dockbeauty_reload];
    });
}

@implementation AxsDockBeautyConfig

+ (instancetype)axs_dockbeauty_shared {
    static AxsDockBeautyConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.dockbeauty.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_dockbeauty_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_dockbeauty_preferencesDidChange,
            (__bridge CFStringRef)AxsDockBeautyPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_dockbeauty_reload]; });
    }
    return self;
}

- (void)axs_dockbeauty_reload {
    self.snapshot = axs_dockbeauty_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsDockBeautyPreferencesChanged object:self];
    });
}

- (id)axs_dockbeauty_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

static double axs_dockbeauty_doubleForKey(AxsDockBeautyConfig *self, NSString *key, double fallback) {
    id value = self.snapshot[key];
    if (![value isKindOfClass:[NSNumber class]]) return fallback;
    double d = [value doubleValue];
    return isnan(d) ? fallback : d;
}

// Hue wrapped to [0,1); saturation/value clamped to [0,1].
- (double)axs_dockbeauty_bubbleHue {
    double r = fmod(axs_dockbeauty_doubleForKey(self, @"bubble_hue", 0.58), 1.0);
    return r < 0.0 ? r + 1.0 : r;
}

- (double)axs_dockbeauty_bubbleSaturation {
    return fmax(0.0, fmin(1.0, axs_dockbeauty_doubleForKey(self, @"bubble_saturation", 0.85)));
}

- (double)axs_dockbeauty_bubbleValue {
    return fmax(0.0, fmin(1.0, axs_dockbeauty_doubleForKey(self, @"bubble_value", 1.0)));
}

- (double)axs_dockbeauty_streamHue {
    double r = fmod(axs_dockbeauty_doubleForKey(self, @"stream_hue", 0.83), 1.0);
    return r < 0.0 ? r + 1.0 : r;
}

- (double)axs_dockbeauty_streamHue2 {
    double r = fmod(axs_dockbeauty_doubleForKey(self, @"stream_hue2", 0.52), 1.0);
    return r < 0.0 ? r + 1.0 : r;
}

- (AxsDockBeautyBubbleColorMode)axs_dockbeauty_bubbleColorMode {
    id value = self.snapshot[@"bubble_color_mode"];
    if (![value isKindOfClass:[NSNumber class]]) return AxsDockBeautyBubbleColorRainbow;
    switch ([value integerValue]) {
        case AxsDockBeautyBubbleColorSingle: return AxsDockBeautyBubbleColorSingle;
        case AxsDockBeautyBubbleColorTransparent: return AxsDockBeautyBubbleColorTransparent;
        default: return AxsDockBeautyBubbleColorRainbow;
    }
}

- (NSArray<NSDictionary *> *)axs_dockbeauty_customPresets {
    id value = self.snapshot[@"custom_presets"];
    if ([value isKindOfClass:[NSArray class]]) return value;
    return @[];
}

- (double)axs_dockbeauty_bubbleSizeMin {
    return fmax(1.0, fmin(40.0, axs_dockbeauty_doubleForKey(self, @"bubble_size_min", 6.0)));
}

- (double)axs_dockbeauty_bubbleSizeMax {
    return fmax(1.0, fmin(40.0, axs_dockbeauty_doubleForKey(self, @"bubble_size_max", 12.0)));
}

- (double)axs_dockbeauty_bubbleDensity {
    return fmax(0.0, fmin(4.0, axs_dockbeauty_doubleForKey(self, @"bubble_density", 1.0)));
}

- (BOOL)axs_dockbeauty_animFloat {
    id v = self.snapshot[@"anim_float"];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : YES;
}
- (BOOL)axs_dockbeauty_animBreathing {
    id v = self.snapshot[@"anim_breathing"];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}
- (BOOL)axs_dockbeauty_animRandom {
    id v = self.snapshot[@"anim_random"];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}
- (BOOL)axs_dockbeauty_animStream {
    id v = self.snapshot[@"anim_stream"];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}
- (BOOL)axs_dockbeauty_animFirefly {
    id v = self.snapshot[@"anim_firefly"];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}
- (BOOL)axs_dockbeauty_animFish {
    id v = self.snapshot[@"anim_fish"];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}
- (NSInteger)axs_dockbeauty_fishCount {
    double d = axs_dockbeauty_doubleForKey(self, @"fish_count", 5.0);
    return (NSInteger)fmax(1.0, fmin(12.0, d));
}

- (BOOL)axs_dockbeauty_wallpaperTint {
    id value = self.snapshot[@"wallpaper_tint"];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (BOOL)axs_dockbeauty_autoSchedule {
    id value = self.snapshot[@"auto_schedule"];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (NSString *)axs_dockbeauty_scheduleDayName {
    id value = self.snapshot[@"schedule_day"];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (NSString *)axs_dockbeauty_scheduleNightName {
    id value = self.snapshot[@"schedule_night"];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (BOOL)axs_dockbeauty_isEnabled {
    id value = [self axs_dockbeauty_valueForKey:@"enabled" defaultValue:@(YES)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
