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

@interface AxsDockBeautyAnimator : NSObject
@property (nonatomic, weak) UIView *dockView;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) CFTimeInterval start;
@property (nonatomic, strong) CAEmitterLayer *bubbles;
@property (nonatomic, strong) CAEmitterLayer *fireflies;
@property (nonatomic, strong) CAGradientLayer *streamLayer;
@property (nonatomic, strong) NSMutableArray<CALayer *> *fishLayers;
@property (nonatomic, assign) CGPoint originalCenter;
@property (nonatomic, assign) CGFloat springPos;   // 弹簧物理：当前偏移
@property (nonatomic, assign) CGFloat springVel;   // 弹簧物理：速度
@property (nonatomic, assign) CFTimeInterval lastTick;
@end

// 画一条简易鱼（椭圆身体 + 三角尾），返回 CALayer。
static CALayer *axs_dockbeauty_makeFish(CGSize size, UIColor *color) {
    CALayer *fish = [CALayer layer];
    fish.bounds = (CGRect){CGPointZero, size};
    fish.cornerRadius = size.height / 2.0;
    fish.backgroundColor = color.CGColor;
    // 尾巴
    CALayer *tail = [CALayer layer];
    tail.bounds = CGRectMake(0, 0, size.width * 0.35, size.height * 0.7);
    tail.position = CGPointMake(-size.width * 0.15, size.height / 2.0);
    tail.backgroundColor = [color colorWithAlphaComponent:0.7].CGColor;
    tail.cornerRadius = 2;
    tail.transform = CATransform3DMakeRotation(M_PI_4, 0, 0, 1);
    [fish addSublayer:tail];
    // 眼睛
    CALayer *eye = [CALayer layer];
    eye.bounds = CGRectMake(0, 0, 3, 3);
    eye.position = CGPointMake(size.width * 0.75, size.height * 0.35);
    eye.cornerRadius = 1.5;
    eye.backgroundColor = [UIColor whiteColor].CGColor;
    [fish addSublayer:eye];
    return fish;
}

@implementation AxsDockBeautyAnimator

+ (instancetype)animatorForDock:(UIView *)dock config:(AxsDockBeautyConfig *)config {
    AxsDockBeautyAnimator *a = [[self alloc] init];
    a.dockView = dock;
    a.start = CFAbsoluteTimeGetCurrent();
    a.originalCenter = dock.center;

    // 流光渐变层（移动光带，zPosition 置于图标之上）。
    CAGradientLayer *stream = [CAGradientLayer layer];
    stream.frame = dock.bounds;
    stream.cornerRadius = dock.layer.cornerRadius > 0 ? dock.layer.cornerRadius : 28.0;
    stream.zPosition = 90;
    stream.startPoint = CGPointMake(0, 0.5);
    stream.endPoint = CGPointMake(1, 0.5);
    stream.colors = @[(id)[UIColor clearColor].CGColor,
                      (id)[UIColor cyanColor].CGColor,
                      (id)[UIColor magentaColor].CGColor,
                      (id)[UIColor clearColor].CGColor];
    stream.locations = @[@0, @0.35, @0.65, @1];
    stream.opacity = 0.0;
    stream.masksToBounds = YES;
    [dock.layer addSublayer:stream];
    a.streamLayer = stream;

    // 气泡粒子层。
    CAEmitterLayer *emit = [CAEmitterLayer layer];
    emit.frame = dock.bounds;
    emit.emitterPosition = CGPointMake(CGRectGetMidX(dock.bounds), CGRectGetMaxY(dock.bounds));
    emit.emitterSize = CGSizeMake(dock.bounds.size.width, 4.0);
    emit.emitterShape = kCAEmitterLayerLine;
    emit.renderMode = kCAEmitterLayerAdditive;
    emit.opacity = 0.0;
    [dock.layer addSublayer:emit];
    a.bubbles = emit;

    // 气泡 sprite。
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(2, 2, 20, 20));
    UIImage *bubbleImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CAEmitterCell *bCell = [CAEmitterCell emitterCell];
    bCell.name = @"bubble";
    bCell.contents = (__bridge id)bubbleImg.CGImage;
    bCell.birthRate = 8.0; bCell.lifetime = 4.0;
    bCell.velocity = 40.0; bCell.velocityRange = 20.0;
    bCell.emissionLongitude = -M_PI_2; bCell.emissionRange = M_PI_4;
    bCell.scale = 0.5; bCell.scaleRange = 0.3; bCell.alphaSpeed = -0.25;
    emit.emitterCells = @[bCell];

    // 萤火虫粒子层。
    CAEmitterLayer *ff = [CAEmitterLayer layer];
    ff.frame = dock.bounds;
    ff.emitterPosition = CGPointMake(CGRectGetMidX(dock.bounds), CGRectGetMidY(dock.bounds));
    ff.emitterSize = dock.bounds.size;
    ff.emitterShape = kCAEmitterLayerRectangle;
    ff.renderMode = kCAEmitterLayerAdditive;
    ff.opacity = 0.0;
    [dock.layer addSublayer:ff];
    a.fireflies = ff;
    CAEmitterCell *fCell = [CAEmitterCell emitterCell];
    fCell.name = @"firefly";
    fCell.contents = (__bridge id)bubbleImg.CGImage;
    fCell.birthRate = 3.0; fCell.lifetime = 6.0;
    fCell.velocity = 15.0; fCell.velocityRange = 10.0;
    fCell.emissionRange = M_PI * 2;
    fCell.scale = 0.15; fCell.scaleRange = 0.1;
    fCell.color = [UIColor colorWithRed:1 green:0.95 blue:0.4 alpha:1].CGColor;
    fCell.alphaSpeed = -0.1;
    ff.emitterCells = @[fCell];

    // 鱼缸：创建 N 条鱼。
    a.fishLayers = [NSMutableArray array];
    NSInteger fishCount = [config axs_dockbeauty_fishCount];
    NSArray<UIColor *> *fishColors = @[
        [UIColor systemOrangeColor], [UIColor systemTealColor],
        [UIColor systemPinkColor], [UIColor systemYellowColor],
        [UIColor systemPurpleColor], [UIColor systemGreenColor],
    ];
    for (NSInteger i = 0; i < fishCount; i++) {
        CGSize sz = CGSizeMake(28 + (i % 3) * 8, 14 + (i % 3) * 4);
        UIColor *c = fishColors[i % fishCount < fishColors.count ? i % fishColors.count : 0];
        CALayer *fish = axs_dockbeauty_makeFish(sz, c);
        fish.position = CGPointMake(CGRectGetMidX(dock.bounds) + (i - fishCount / 2.0) * 40,
                                     CGRectGetMidY(dock.bounds));
        fish.opacity = 0.0;
        fish.zPosition = 50;
        [dock.layer addSublayer:fish];
        [a.fishLayers addObject:fish];
    }

    a.link = [CADisplayLink displayLinkWithTarget:a selector:@selector(tick:)];
    [a.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return a;
}

- (void)tick:(CADisplayLink *)link {
    UIView *dock = self.dockView;
    if (!dock) { [self stop]; return; }
    self.bubbles.frame = dock.bounds;
    self.fireflies.frame = dock.bounds;

    AxsDockBeautyConfig *config = [AxsDockBeautyConfig axs_dockbeauty_shared];
    id strengthVal = [config axs_dockbeauty_valueForKey:@"value" defaultValue:@(1.0)];
    double strength = [strengthVal isKindOfClass:[NSNumber class]] ? [strengthVal doubleValue] : 1.0;
    double t = CFAbsoluteTimeGetCurrent() - self.start;

    // dt（弹簧积分用），钳制在 [1/120, 1/20] 秒。
    double dt = link.duration > 0 ? link.duration : 1.0 / 60.0;
    dt = fmax(1.0 / 120.0, fmin(1.0 / 20.0, dt));
    if (self.lastTick <= 0) self.lastTick = t;

    // ── 位置偏移：浮动（振幅/周期可调，可选弹簧物理） + 随机抖动 ──
    CGFloat offsetX = 0, offsetY = 0;
    if ([config axs_dockbeauty_animFloat]) {
        double amp = 12.0 * [config axs_dockbeauty_floatAmplitude] * strength;
        double period = [config axs_dockbeauty_floatPeriod];
        CGFloat target = (CGFloat)(sin(t * 2.0 * M_PI / period) * amp);
        if ([config axs_dockbeauty_springEnabled]) {
            // 弹簧物理：k*(target-pos) - c*vel，二阶积分追踪目标，带阻尼回弹。
            double k = 120.0, c = 14.0;
            self.springVel += (CGFloat)((k * (target - self.springPos) - c * self.springVel) * dt);
            self.springPos += self.springVel * (CGFloat)dt;
            offsetY += self.springPos;
        } else {
            offsetY += target;
        }
    }
    if ([config axs_dockbeauty_animRandom]) {
        offsetX += (CGFloat)(sin(t * 3.7) * 2.0 + sin(t * 7.3) * 1.5) * strength;
        offsetY += (CGFloat)(cos(t * 4.1) * 2.0 + cos(t * 9.1) * 1.5) * strength;
    }
    CGPoint base = self.originalCenter;
    dock.layer.position = CGPointMake(base.x + offsetX, base.y + offsetY);

    // ── 呼吸：sublayerTransform 缩放（view.transform 会被 SpringBoard 重置，这个不会） ──
    CGFloat scale = 1.0;
    if ([config axs_dockbeauty_animBreathing]) {
        double bAmp = [config axs_dockbeauty_breathingAmplitude];
        double bPeriod = [config axs_dockbeauty_breathingPeriod];
        scale = 1.0 + (CGFloat)(sin(t * 2.0 * M_PI / bPeriod) * bAmp * strength);
    }
    dock.layer.sublayerTransform = CATransform3DMakeScale(scale, scale, 1.0);

    // ── 流光：移动光带（长/宽/高/速度/透明度可调） ──
    if ([config axs_dockbeauty_animStream]) {
        self.streamLayer.opacity = (float)[config axs_dockbeauty_streamOpacity];
        // 光带尺寸：宽 = Dock宽*stream_width，高 = Dock高*stream_height，垂直居中。
        double wFrac = [config axs_dockbeauty_streamWidth];
        double hFrac = [config axs_dockbeauty_streamHeight];
        CGFloat bandW = (CGFloat)(dock.bounds.size.width * wFrac);
        CGFloat bandH = (CGFloat)(dock.bounds.size.height * hFrac);
        CGFloat bandY = (CGFloat)((dock.bounds.size.height - bandH) / 2.0);
        // 光带横向来回扫动，速度 = stream_speed。
        double speed = [config axs_dockbeauty_streamSpeed];
        double travel = (sin(t * speed * 2.0) + 1.0) / 2.0;  // 0..1 往返
        CGFloat bandX = (CGFloat)(travel * (dock.bounds.size.width - bandW));
        self.streamLayer.frame = CGRectMake(bandX, bandY, bandW, bandH);
        // 渐变：透明 → 主色 → 副色 → 透明（横向），色相随时间流动。
        double hue1 = [config axs_dockbeauty_streamHue];
        double hue2 = [config axs_dockbeauty_streamHue2];
        UIColor *c1 = [UIColor colorWithHue:fmod(hue1 + t * 0.05, 1.0) saturation:0.9 brightness:1 alpha:1];
        UIColor *c2 = [UIColor colorWithHue:fmod(hue2 + t * 0.05, 1.0) saturation:0.9 brightness:1 alpha:1];
        self.streamLayer.colors = @[(id)[UIColor clearColor].CGColor,
                                    (id)c1.CGColor, (id)c2.CGColor,
                                    (id)[UIColor clearColor].CGColor];
    } else {
        self.streamLayer.opacity = 0;
        self.streamLayer.frame = dock.bounds;
    }

    // ── 萤火虫 ──
    if ([config axs_dockbeauty_animFirefly]) {
        self.fireflies.opacity = 0.8;
    } else {
        self.fireflies.opacity = 0;
    }

    // ── 鱼缸 ──
    BOOL fishOn = [config axs_dockbeauty_animFish];
    NSInteger fishCount = [config axs_dockbeauty_fishCount];
    for (NSInteger i = 0; i < (NSInteger)self.fishLayers.count; i++) {
        CALayer *fish = self.fishLayers[i];
        if (!fishOn || i >= fishCount) { fish.opacity = 0; continue; }
        fish.opacity = 0.85;
        // 水平游动（正弦往返），垂直轻微摆动。
        double speed = 0.3 + (i % 5) * 0.08;
        double phase = t * speed + i * 1.3;
        CGFloat fishX = (CGFloat)(sin(phase) * dock.bounds.size.width * 0.35) + CGRectGetMidX(dock.bounds);
        CGFloat fishY = (CGFloat)(cos(phase * 0.7) * 10.0) + CGRectGetMidY(dock.bounds);
        fish.position = CGPointMake(fishX, fishY);
        // 根据方向翻转。
        double dx = cos(phase);
        fish.transform = dx < 0 ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity;
    }

    // ── 气泡 ──
    AxsDockBeautyBubbleColorMode mode = [config axs_dockbeauty_bubbleColorMode];
    if (mode == AxsDockBeautyBubbleColorTransparent) {
        self.bubbles.opacity = 0.0;
    } else {
        double density = [config axs_dockbeauty_bubbleDensity];
        self.bubbles.opacity = (float)fmin(1.0, density);
        UIColor *c = axs_dockbeauty_bubbleColor(config);
        CAEmitterCell *cell = self.bubbles.emitterCells.firstObject;
        if (cell) {
            cell.color = c.CGColor;
            cell.birthRate = (float)(8.0 * density * strength);
            cell.velocity = 40.0 * (float)strength;
            cell.scale = (float)([config axs_dockbeauty_bubbleSizeMin] / 12.0);
            cell.scaleRange = (float)(([config axs_dockbeauty_bubbleSizeMax]
                                       - [config axs_dockbeauty_bubbleSizeMin]) / 12.0);
        }
    }
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    [self.bubbles removeFromSuperlayer];
    [self.fireflies removeFromSuperlayer];
    [self.streamLayer removeFromSuperlayer];
    for (CALayer *f in self.fishLayers) [f removeFromSuperlayer];
}
@end

@class AxsDockBeautyAnimator;
static NSMutableArray<AxsDockBeautyAnimator *> *axs_dockbeauty_animators;

// 给指定 Dock 视图挂动画（已挂过的跳过；顺带清理已失效的动画器）。
static void axs_dockbeauty_attachToDock(id dockObj) {
    if (!dockObj || ![dockObj isKindOfClass:[UIView class]]) return;
    UIView *dock = (UIView *)dockObj;
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
             @"anim_float", @"anim_breathing", @"anim_random",
             @"anim_stream", @"anim_firefly", @"anim_fish", @"fish_count",
             @"float_amplitude", @"float_period",
             @"breathing_amplitude", @"breathing_period",
             @"spring_enabled",
             @"stream_speed", @"stream_width", @"stream_height", @"stream_opacity",
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
