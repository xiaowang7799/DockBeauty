#import <UIKit/UIKit.h>
#import <math.h>
#import "AxsDockBeautyConfig.h"
#import "AxsDockBeautyPreferences.h"
#import "AxsDockBeautyPrivate.h"

// ── Dock 美化版：浮动 + 气泡 / 流光配色 ──────────────────────────────────────
// Dock 的取用方式随 iOS 版本变化，所以用三条路确保挂上：
//   1) 直接 %hook SBMainDockView / SBDockView（最可靠）；
//   2) 遍历所有 UIWindow 找 *DockView（兜底）；
//   3) 定时重试（Dock 可能晚建 / 锁屏后重建）。
// 拿不到视图就静默退出，绝不强改。

// UIImage 平均色（壁纸取色用，安全实现，取不到返回 nil）。
@interface UIImage (AxsDockBeautyAverage)
- (UIColor *)axs_dockbeauty_averageColor;
@end
@implementation UIImage (AxsDockBeautyAverage)
- (UIColor *)axs_dockbeauty_averageColor {
    CGImageRef cg = self.CGImage;
    if (!cg) return nil;
    size_t w = 32, h = (size_t)(32 * (double)CGImageGetHeight(cg) / CGImageGetWidth(cg) ?: 32);
    if (h == 0) h = 32;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    uint8_t *buf = (uint8_t *)calloc(w * h * 4, 1);
    if (!buf) { CGColorSpaceRelease(space); return nil; }
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!ctx) { free(buf); CGColorSpaceRelease(space); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    double r = 0, g = 0, b = 0;
    for (size_t i = 0; i < w * h; i++) { r += buf[i*4]; g += buf[i*4+1]; b += buf[i*4+2]; }
    size_t n = w * h;
    UIColor *color = [UIColor colorWithRed:r/n/255.0 green:g/n/255.0 blue:b/n/255.0 alpha:1.0];
    CGContextRelease(ctx); CGColorSpaceRelease(space); free(buf);
    return color;
}
@end

// 壁纸取色（仅 iOS 13+ 的私有类，失败返回 nil，不强制）。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static UIColor *axs_dockbeauty_wallpaperColor(void) {
    if (@available(iOS 13.0, *)) {
        Class cls = NSClassFromString(@"SBFWallpaperView");
        if (!cls) return nil;
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (![cls respondsToSelector:sharedSel]) return nil;
        id view = [cls performSelector:sharedSel];
        if (!view) return nil;
        SEL imgSel = NSSelectorFromString(@"currentWallpaperImage");
        if (![view respondsToSelector:imgSel]) return nil;
        UIImage *img = [view performSelector:imgSel];
        if (![img isKindOfClass:[UIImage class]]) return nil;
        return [img axs_dockbeauty_averageColor];
    }
    return nil;
}
#pragma clang diagnostic pop

// 单色气泡颜色：透明模式返回 clearColor；开启壁纸取色则改取壁纸主色。
static UIColor *axs_dockbeauty_bubbleColor(AxsDockBeautyConfig *config) {
    AxsDockBeautyBubbleColorMode mode = [config axs_dockbeauty_bubbleColorMode];
    if (mode == AxsDockBeautyBubbleColorTransparent) return [UIColor clearColor];
    double hue = [config axs_dockbeauty_bubbleHue];
    double sat = [config axs_dockbeauty_bubbleSaturation];
    double val = [config axs_dockbeauty_bubbleValue];
    if ([config axs_dockbeauty_wallpaperTint]) {
        UIColor *wp = axs_dockbeauty_wallpaperColor();
        if (wp) {
            CGFloat h, s, b;
            [wp getHue:&h saturation:&s brightness:&b alpha:nil];
            hue = h; sat = fmax(0.5, s); val = b;
        }
    }
    if (mode == AxsDockBeautyBubbleColorSingle) {
        return [UIColor colorWithHue:hue saturation:sat brightness:val alpha:1.0];
    }
    double rainbow = fmod(CFAbsoluteTimeGetCurrent() / 6.0, 1.0);
    return [UIColor colorWithHue:rainbow saturation:0.85 brightness:1.0 alpha:1.0];
}

// 流光色相（开启壁纸取色时跟随壁纸），否则用双色往返。
static UIColor *axs_dockbeauty_streamColor(AxsDockBeautyConfig *config, double t) {
    if ([config axs_dockbeauty_wallpaperTint]) {
        UIColor *wp = axs_dockbeauty_wallpaperColor();
        if (wp) {
            CGFloat h, s, b;
            [wp getHue:&h saturation:&s brightness:&b alpha:nil];
            double hue = h + 0.02 * sin(t * M_PI * 2.0);
            hue = fmod(hue, 1.0); if (hue < 0.0) hue += 1.0;
            return [UIColor colorWithHue:hue saturation:fmax(0.5, s) brightness:b alpha:0.9];
        }
    }
    double a = [config axs_dockbeauty_streamHue];
    double b = [config axs_dockbeauty_streamHue2];
    double phase = (sin(t * M_PI) + 1.0) / 2.0;
    double hue = fmod(a + (b - a) * phase, 1.0);
    if (hue < 0.0) hue += 1.0;
    return [UIColor colorWithHue:hue saturation:0.9 brightness:1.0 alpha:0.9];
}

@interface AxsDockBeautyAnimator : NSObject
@property (nonatomic, weak) UIView *dockView;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) CFTimeInterval start;
@property (nonatomic, strong) CALayer *glowLayer;
@property (nonatomic, strong) CAEmitterLayer *bubbles;
@end

@implementation AxsDockBeautyAnimator

+ (instancetype)animatorForDock:(UIView *)dock config:(AxsDockBeautyConfig *)config {
    AxsDockBeautyAnimator *a = [[self alloc] init];
    a.dockView = dock;
    a.start = CFAbsoluteTimeGetCurrent();

    CALayer *glow = [CALayer layer];
    // 关键修正：frame 必须在 bounds 之内，否则会被 masksToBounds 裁掉而完全不可见。
    glow.frame = dock.bounds;
    glow.cornerRadius = dock.layer.cornerRadius > 0 ? dock.layer.cornerRadius : 28.0;
    glow.zPosition = 100;            // 浮在 Dock 图标之上，作为霓虹描边
    glow.backgroundColor = [UIColor clearColor].CGColor;
    glow.borderWidth = 3.0;
    glow.borderColor = [UIColor cyanColor].CGColor;   // 初始就有颜色，立即可见
    glow.opacity = 0.95;
    [dock.layer addSublayer:glow];
    a.glowLayer = glow;

    // 气泡粒子层（默认隐藏，开气泡模式时点亮）。
    CAEmitterLayer *emit = [CAEmitterLayer layer];
    emit.frame = dock.bounds;
    emit.emitterPosition = CGPointMake(CGRectGetMidX(dock.bounds), CGRectGetMaxY(dock.bounds));
    emit.emitterSize = CGSizeMake(dock.bounds.size.width, 4.0);
    emit.emitterShape = kCAEmitterLayerLine;
    emit.renderMode = kCAEmitterLayerAdditive;
    emit.opacity = 0.0;
    [dock.layer addSublayer:emit];
    a.bubbles = emit;

    a.link = [CADisplayLink displayLinkWithTarget:a selector:@selector(tick:)];
    [a.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return a;
}

- (void)tick:(CADisplayLink *)link {
    UIView *dock = self.dockView;
    if (!dock) { [self stop]; return; }
    // 同步帧到当前 bounds（Dock 尺寸可能被系统改动）。
    self.glowLayer.frame = dock.bounds;
    self.glowLayer.cornerRadius = dock.layer.cornerRadius > 0 ? dock.layer.cornerRadius : 28.0;
    self.bubbles.frame = dock.bounds;

    AxsDockBeautyConfig *config = [AxsDockBeautyConfig axs_dockbeauty_shared];
    id strengthVal = [config axs_dockbeauty_valueForKey:@"value" defaultValue:@(1.0)];
    double strength = [strengthVal isKindOfClass:[NSNumber class]] ? [strengthVal doubleValue] : 1.0;
    double t = CFAbsoluteTimeGetCurrent() - self.start;

    // 浮动：明显正弦位移（默认启用即见）。
    CGFloat floatAmp = 12.0 * strength;
    dock.transform = CGAffineTransformMakeTranslation(0.0, (CGFloat)(sin(t * 1.2) * floatAmp));

    // 流光描边：霓虹边框颜色随时间在两色间往返。
    UIColor *stream = axs_dockbeauty_streamColor(config, t * 0.4);
    self.glowLayer.borderColor = stream.CGColor;

    // 气泡粒子：仅单色/彩虹模式（非透明）时显示，颜色随取色逻辑。
    AxsDockBeautyBubbleColorMode mode = [config axs_dockbeauty_bubbleColorMode];
    if (mode == AxsDockBeautyBubbleColorTransparent) {
        self.bubbles.opacity = 0.0;
    } else {
        self.bubbles.opacity = (float)(fmin(1.0, [config axs_dockbeauty_bubbleDensity]));
        UIColor *c = axs_dockbeauty_bubbleColor(config);
        CAEmitterCell *cell = self.bubbles.emitterCells.firstObject;
        if (!cell) {
            cell = [CAEmitterCell emitterCell];
            cell.name = @"bubble";
            cell.birthRate = 8.0 * (float)[config axs_dockbeauty_bubbleDensity];
            cell.lifetime = 4.0;
            cell.velocity = 40.0 * (float)strength;
            cell.velocityRange = 20.0;
            cell.emissionLongitude = -M_PI_2;
            cell.emissionRange = M_PI_4;
            cell.scale = (float)([config axs_dockbeauty_bubbleSizeMin] / 12.0);
            cell.scaleRange = (float)(([config axs_dockbeauty_bubbleSizeMax]
                                       - [config axs_dockbeauty_bubbleSizeMin]) / 12.0);
            cell.alphaSpeed = -0.25;
            self.bubbles.emitterCells = @[cell];
        }
        cell.color = c.CGColor;
    }
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    [self.glowLayer removeFromSuperlayer];
    [self.bubbles removeFromSuperlayer];
}
@end

@class AxsDockBeautyAnimator;
static NSMutableArray<AxsDockBeautyAnimator *> *axs_dockbeauty_animators;

// 给指定 Dock 视图挂动画（已挂过的跳过；顺带清理已失效的动画器）。
static void axs_dockbeauty_attachToDock(UIView *dock) {
    if (!dock) return;
    AxsDockBeautyConfig *config = [AxsDockBeautyConfig axs_dockbeauty_shared];
    if (![config axs_dockbeauty_isEnabled]) return;
    if (axs_dockbeauty_animators == nil) axs_dockbeauty_animators = [NSMutableArray array];

    // 清理已失效（dockView 被释放）的动画器。
    NSMutableArray<AxsDockBeautyAnimator *> *dead = [NSMutableArray array];
    for (AxsDockBeautyAnimator *a in axs_dockbeauty_animators) {
        if (a.dockView == nil) { [dead addObject:a]; continue; }
        if (a.dockView == dock) return;    // 已挂过
    }
    if (dead.count) [axs_dockbeauty_animators removeObjectsInArray:dead];

    [axs_dockbeauty_animators addObject:[AxsDockBeautyAnimator animatorForDock:dock config:config]];
}

// 递归遍历视图树：遇到 *DockView 就挂载动画。
static void axs_dockbeauty_walk(UIView *view) {
    for (UIView *sub in view.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls hasSuffix:@"DockView"]) {
            axs_dockbeauty_attachToDock(sub);
        }
        axs_dockbeauty_walk(sub);
    }
}

// 遍历所有窗口（不只 key window——锁屏时 key window 不含 Dock）。
static void axs_dockbeauty_attachIfNeeded(void) {
    if (axs_dockbeauty_animators == nil) axs_dockbeauty_animators = [NSMutableArray array];

    NSMutableArray<UIWindow *> *all = [NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *legacy = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
    if (legacy.count) [all addObjectsFromArray:legacy];

    // iOS 13+ 场景窗口（legacy.windows 可能为空）。
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [all addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
    }

    for (UIWindow *w in all) {
        axs_dockbeauty_walk(w);
    }
}

// ── 按时段自动换预设 ─────────────────────────────────────────────────────────
// 找不到对应名字的预设就静默跳过；不改写 enabled 等其它键。
static NSArray<NSString *> *axs_dockbeauty_presetKeys(void) {
    return @[@"value", @"bubble_color_mode",
             @"bubble_hue", @"bubble_saturation", @"bubble_value",
             @"stream_hue", @"stream_hue2",
             @"bubble_size_min", @"bubble_size_max", @"bubble_density",
             @"wallpaper_tint", @"auto_schedule",
             @"schedule_day", @"schedule_night"];
}
static void axs_dockbeauty_applyScheduledPreset(void) {
    AxsDockBeautyConfig *config = [AxsDockBeautyConfig axs_dockbeauty_shared];
    if (![config axs_dockbeauty_autoSchedule]) return;
    NSArray<NSDictionary *> *presets = [config axs_dockbeauty_customPresets];
    if (presets.count == 0) return;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger hour = [cal component:NSCalendarUnitHour fromDate:[NSDate date]];
    BOOL isDay = (hour >= 7 && hour < 19);
    NSString *want = isDay ? [config axs_dockbeauty_scheduleDayName]
                           : [config axs_dockbeauty_scheduleNightName];
    if (want.length == 0) return;
    for (NSDictionary *preset in presets) {
        if ([[preset objectForKey:@"name"] isEqualToString:want]) {
            NSDictionary *settings = [preset objectForKey:@"settings"];
            if ([settings isKindOfClass:[NSDictionary class]]) {
                NSError *error = nil;
                for (NSString *key in axs_dockbeauty_presetKeys()) {
                    id v = settings[key];
                    if (v) axs_dockbeauty_writePreference(key, v, &error);
                }
            }
            break;
        }
    }
}

// ── 路 1：直接 hook Dock 类（最可靠） ───────────────────────────────────────
%hook SBMainDockView
- (void)didMoveToWindow {
    %orig;
    axs_dockbeauty_attachToDock(self);
}
%end

%hook SBDockView
- (void)didMoveToWindow {
    %orig;
    axs_dockbeauty_attachToDock(self);
}
%end

// ── 路 2+3：启动后定时重试遍历所有窗口 ─────────────────────────────────────
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    axs_dockbeauty_applyScheduledPreset();
    NSTimer *hourly = [NSTimer scheduledTimerWithTimeInterval:3600.0 repeats:YES block:^(NSTimer *t) {
        axs_dockbeauty_applyScheduledPreset();
    }];
    [NSRunLoop.mainRunLoop addTimer:hourly forMode:NSRunLoopCommonModes];
}

%end

%ctor {
    @autoreleasepool {
        // Readers load a snapshot; they never write default preferences.
        [AxsDockBeautyConfig axs_dockbeauty_shared];

        // 【诊断】启动 3 秒后在 key window 画红色边框 2 秒。
        // 看到红框 = tweak 已注入；看不到 = 注入失败（装错包/未 respring）。
        // 确认后请删掉这段。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            UIWindow *key = nil;
            for (UIWindow *w in UIApplication.sharedApplication.windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
#pragma clang diagnostic pop
            if (key) {
                key.layer.borderWidth = 5.0;
                key.layer.borderColor = [UIColor redColor].CGColor;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    key.layer.borderWidth = 0.0;
                });
            }
        });

        // 兜底重试：即使 applicationDidFinishLaunching 未触发，也要尝试挂载。
        // 前 60 秒每 2 秒扫一次（Dock 可能晚建 / 锁屏后重建）。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __block NSInteger tries = 0;
            NSTimer *scan = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
                axs_dockbeauty_attachIfNeeded();
                tries++;
                if (tries >= 30) { [t invalidate]; }
            }];
            [NSRunLoop.mainRunLoop addTimer:scan forMode:NSRunLoopCommonModes];
        });
    }
}
