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
// 结果缓存 5 秒：每帧解码整张壁纸是发热主因，绝不能逐帧重算。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static UIColor *axs_dockbeauty_wallpaperColor(void) {
    static UIColor *cached = nil;
    static CFTimeInterval cachedAt = -100.0;
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (cached && now - cachedAt < 5.0) return cached;
    cachedAt = now;   // 失败也 5 秒后再试，不逐帧重试
    if (@available(iOS 13.0, *)) {
        Class cls = NSClassFromString(@"SBFWallpaperView");
        if (!cls) return cached;
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (![cls respondsToSelector:sharedSel]) return cached;
        id view = [cls performSelector:sharedSel];
        if (!view) return cached;
        SEL imgSel = NSSelectorFromString(@"currentWallpaperImage");
        if (![view respondsToSelector:imgSel]) return cached;
        UIImage *img = [view performSelector:imgSel];
        if (![img isKindOfClass:[UIImage class]]) return cached;
        cached = [img axs_dockbeauty_averageColor];
        return cached;
    }
    return cached;
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

// 收集真正的图标视图（SBIconView 等）。
// 关键：图标不是 Dock 的直接子视图——结构是 Dock → *IconListView（容器）→ SBIconView，
// 所以必须递归找类名以 IconView 结尾的视图（IconListView 是 ListView 后缀，不会误收）。
static void axs_dockbeauty_collectIconsInto(UIView *view, NSMutableArray<UIView *> *out) {
    for (UIView *sub in view.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls hasSuffix:@"IconView"]) {
            [out addObject:sub];   // 找到图标即停，不再深入（内部是角标/图片）
        } else {
            axs_dockbeauty_collectIconsInto(sub, out);
        }
    }
}
static NSArray<UIView *> *axs_dockbeauty_collectIcons(UIView *dock) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    if (dock) axs_dockbeauty_collectIconsInto(dock, out);
    return out;
}

// 查找 Dock 的背景视图（毛玻璃/材质/壁纸效果层）。
static UIView *axs_dockbeauty_findBackgroundView(UIView *view) {
    for (UIView *sub in view.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"WallpaperEffect"] || [cls containsString:@"Material"]
            || [cls containsString:@"Backdrop"] || [cls containsString:@"Background"]) {
            return sub;
        }
        UIView *deep = axs_dockbeauty_findBackgroundView(sub);
        if (deep) return deep;
    }
    return nil;
}

// emoji 渲染成粒子 sprite。
static UIImage *axs_dockbeauty_emojiImage(NSString *emoji, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = NSTextAlignmentCenter;
    [emoji drawInRect:CGRectMake(0, size * 0.05, size, size * 0.9)
       withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:size * 0.8],
                        NSParagraphStyleAttributeName: style}];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// 节日 emoji（🎃 万圣 10/25-11/2、🎄 圣诞 12/20-28、🧧 春节 1/21-2/20、❤️ 情人节 2/14）。
static NSString *axs_dockbeauty_holidayEmoji(void) {
    NSDateComponents *c = [[NSCalendar currentCalendar]
        components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[NSDate date]];
    NSInteger m = c.month, d = c.day;
    if ((m == 10 && d >= 25) || (m == 11 && d <= 2)) return @"🎃";
    if (m == 12 && d >= 20 && d <= 28) return @"🎄";
    if ((m == 1 && d >= 21) || (m == 2 && d <= 20)) return @"🧧";
    if (m == 2 && d == 14) return @"❤️";
    return nil;
}

// 季节 emoji（冬 ❄️ / 春 🌸 / 夏 ⭐ / 秋 🍂）。
static NSString *axs_dockbeauty_seasonEmoji(void) {
    NSInteger m = [[NSCalendar currentCalendar] component:NSCalendarUnitMonth fromDate:[NSDate date]];
    if (m == 12 || m <= 2) return @"❄️";
    if (m <= 5) return @"🌸";
    if (m <= 8) return @"⭐";
    return @"🍂";
}

// 把自定义文本按 emoji 字符序列拆分（正确处理多码点 emoji，如 🐟🎉✨）。
static NSArray<NSString *> *axs_dockbeauty_splitEmoji(NSString *text) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
        options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *sub, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            NSString *trimmed = [sub stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) [out addObject:sub];
        }];
    return out.count ? out : @[@"✨"];
}

@interface AxsDockBeautyAnimator : NSObject
@property (nonatomic, weak) UIView *dockView;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) CFTimeInterval start;
@property (nonatomic, strong) CAEmitterLayer *bubbles;
@property (nonatomic, strong) CAEmitterLayer *fireflies;
@property (nonatomic, strong) CAGradientLayer *streamLayer;
@property (nonatomic, strong) NSMutableArray<CALayer *> *fishLayers;
@property (nonatomic, strong) CAEmitterLayer *seasonEmitter;   // 季节粒子（雪/花瓣/落叶/星星/爱心）
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *rippleLayers;  // 点击涟漪
@property (nonatomic, assign) NSInteger lastParticleStyle;     // 粒子样式缓存（变化时换 sprite）
@property (nonatomic, assign) CGPoint originalCenter;
@property (nonatomic, assign) CGPoint lastWritten;   // 上帧写入的 position（检测系统重新布局用）
@property (nonatomic, assign) CGFloat springPos;   // 弹簧物理：当前偏移
@property (nonatomic, assign) CGFloat springVel;   // 弹簧物理：速度
@property (nonatomic, assign) CFTimeInterval lastTick;
@property (nonatomic, assign) NSUInteger frameCounter;  // 帧计数（发射器参数降频更新）
// 点击反馈入口（弹性 + 涟漪）。
- (void)axs_dockbeauty_tapFeedbackAt:(CGPoint)point inDock:(UIView *)dock icon:(UIView *)icon;
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
    // 哨兵值：强制第一帧把实际位置采纳为基准（挂载时布局可能未完成，不能信任 dock.center）。
    a.lastWritten = CGPointMake(-99999.0, -99999.0);

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

    // 季节粒子层（雪/花瓣/落叶/星星/爱心，从上方飘落）。
    CAEmitterLayer *season = [CAEmitterLayer layer];
    season.frame = dock.bounds;
    season.emitterPosition = CGPointMake(CGRectGetMidX(dock.bounds), -10.0);
    season.emitterSize = CGSizeMake(dock.bounds.size.width, 4.0);
    season.emitterShape = kCAEmitterLayerLine;
    season.renderMode = kCAEmitterLayerUnordered;
    season.opacity = 0.0;
    [dock.layer addSublayer:season];
    a.seasonEmitter = season;
    a.lastParticleStyle = -1;
    a.rippleLayers = [NSMutableArray array];

    a.link = [CADisplayLink displayLinkWithTarget:a selector:@selector(tick:)];
    // 限帧 30fps：浮动/呼吸/流光是慢动画，30fps 足够流畅，CPU 直接降一半以上
    //（ProMotion 屏默认 120Hz，不限帧等于每秒 120 次全量计算，是发热主因）。
    a.link.preferredFramesPerSecond = 30;
    [a.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return a;
}

- (void)tick:(CADisplayLink *)link {
    UIView *dock = self.dockView;
    if (!dock) { [self stop]; return; }

    AxsDockBeautyConfig *config = [AxsDockBeautyConfig axs_dockbeauty_shared];
    BOOL animFloat = [config axs_dockbeauty_animFloat];
    BOOL animIconFloat = [config axs_dockbeauty_animIconFloat];
    BOOL animBreathing = [config axs_dockbeauty_animBreathing];
    BOOL animRandom = [config axs_dockbeauty_animRandom];
    BOOL animStream = [config axs_dockbeauty_animStream];
    BOOL animFirefly = [config axs_dockbeauty_animFirefly];
    BOOL animFish = [config axs_dockbeauty_animFish];
    BOOL animRoll = [config axs_dockbeauty_animRoll];
    BOOL animShake = [config axs_dockbeauty_animShake];
    AxsDockBeautyBubbleColorMode bubbleMode = [config axs_dockbeauty_bubbleColorMode];
    BOOL bubbleOn = (bubbleMode != AxsDockBeautyBubbleColorTransparent)
                    && [config axs_dockbeauty_bubbleDensity] > 0.01;
    NSInteger particleStyle = [config axs_dockbeauty_particleStyle];

    // ── 系统保护：低电量降载、减弱动态适配 ──
    BOOL lowPower = [config axs_dockbeauty_lowPowerGuard]
                    && [NSProcessInfo processInfo].isLowPowerModeEnabled;
    BOOL reduceMotion = [config axs_dockbeauty_reduceMotionGuard]
                        && UIAccessibilityIsReduceMotionEnabled();
    if (reduceMotion) {
        // 减弱动态：禁用位移/翻滚/抖动类动画，保留颜色/透明度。
        animFloat = NO; animIconFloat = NO; animRandom = NO;
        animRoll = NO; animShake = NO; animBreathing = NO;
    }
    if (lowPower) {
        // 低电量：粒子全关、保留轻量位移。
        animFirefly = NO; animFish = NO; particleStyle = 0; bubbleOn = NO; animStream = NO;
    }

    // 全部关闭时什么都不做（也停掉发射器），彻底归零 CPU。
    if (!animFloat && !animIconFloat && !animBreathing && !animRandom && !animStream
        && !animFirefly && !animFish && !animRoll && !animShake && !bubbleOn
        && particleStyle == 0
        && [config axs_dockbeauty_bgOpacity] >= 0.999
        && ![config axs_dockbeauty_iconGlow]) {
        if (self.bubbles.opacity != 0) self.bubbles.opacity = 0;
        if (self.fireflies.opacity != 0) self.fireflies.opacity = 0;
        if (self.streamLayer.opacity != 0) self.streamLayer.opacity = 0;
        if (self.seasonEmitter.opacity != 0) self.seasonEmitter.opacity = 0;
        // 曾写过偏移则复位到基准（否则 Dock 会停在最后一帧的偏移位置）。
        if (self.lastWritten.x > -90000.0) {
            CGPoint cur = dock.layer.position;
            if (fabs(cur.x - self.lastWritten.x) < 0.5 && fabs(cur.y - self.lastWritten.y) < 0.5) {
                dock.layer.position = self.originalCenter;
            }
            self.lastWritten = CGPointMake(-99999.0, -99999.0);
        }
        return;
    }

    // 每帧改 CALayer 属性时禁用隐式动画，避免逐帧创建 CAAnimation 对象。
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.bubbles.frame = dock.bounds;
    self.fireflies.frame = dock.bounds;

    id strengthVal = [config axs_dockbeauty_valueForKey:@"value" defaultValue:@(1.0)];
    double strength = [strengthVal isKindOfClass:[NSNumber class]] ? [strengthVal doubleValue] : 1.0;
    double t = CFAbsoluteTimeGetCurrent() - self.start;

    // dt（弹簧积分用），钳制在 [1/120, 1/20] 秒。
    double dt = link.duration > 0 ? link.duration : 1.0 / 60.0;
    dt = fmax(1.0 / 120.0, fmin(1.0 / 20.0, dt));
    if (self.lastTick <= 0) self.lastTick = t;

    // ── 位置偏移：浮动（振幅/周期可调，可选弹簧物理） + 随机抖动 ──
    CGFloat offsetX = 0, offsetY = 0;
    if (animFloat) {
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
    if (animRandom) {
        offsetX += (CGFloat)(sin(t * 3.7) * 2.0 + sin(t * 7.3) * 1.5) * strength;
        offsetY += (CGFloat)(cos(t * 4.1) * 2.0 + cos(t * 9.1) * 1.5) * strength;
    }
    // 抖动：高频小幅抖动（幅度/周期可调）。
    if (animShake) {
        double sAmp = [config axs_dockbeauty_shakeAmplitude] * strength;
        double sPeriod = [config axs_dockbeauty_shakePeriod];
        double omegaS = 2.0 * M_PI / sPeriod;
        offsetX += (CGFloat)(sin(t * omegaS * 6.0) * 2.0 * sAmp);
        offsetY += (CGFloat)(cos(t * omegaS * 7.3) * 1.5 * sAmp);
    }
    // 基准自愈：位置 ≠ 上帧写入值 → 系统重新布局了（或首帧/挂载时布局未完成），以现值为新基准。
    // 修复"有的设备 Dock 跑到左上角"：挂载时机早于布局完成时，旧代码把 (0,0) 记成基准。
    CGPoint currentPos = dock.layer.position;
    if (fabs(currentPos.x - self.lastWritten.x) > 0.5 || fabs(currentPos.y - self.lastWritten.y) > 0.5) {
        self.originalCenter = currentPos;
    }
    CGPoint base = self.originalCenter;
    CGPoint written = CGPointMake(base.x + offsetX, base.y + offsetY);
    dock.layer.position = written;
    self.lastWritten = written;

    // ── Dock 本体：背景透明度 + 圆角 ──
    double bgOpacity = [config axs_dockbeauty_bgOpacity];
    UIView *bgView = axs_dockbeauty_findBackgroundView(dock);
    if (bgView && fabs(bgView.alpha - bgOpacity) > 0.01) {
        bgView.alpha = (CGFloat)bgOpacity;
    }
    double corner = [config axs_dockbeauty_cornerRadius];
    if (fabs(dock.layer.cornerRadius - corner) > 0.5) {
        dock.layer.cornerRadius = (CGFloat)corner;
        dock.layer.masksToBounds = YES;
    }

    // ── 呼吸：sublayerTransform 缩放（view.transform 会被 SpringBoard 重置，这个不会） ──
    CGFloat scale = 1.0;
    if (animBreathing) {
        double bAmp = [config axs_dockbeauty_breathingAmplitude];
        double bPeriod = [config axs_dockbeauty_breathingPeriod];
        scale = 1.0 + (CGFloat)(sin(t * 2.0 * M_PI / bPeriod) * bAmp * strength);
        dock.layer.sublayerTransform = CATransform3DMakeScale(scale, scale, 1.0);
    } else {
        dock.layer.sublayerTransform = CATransform3DIdentity;
    }

    // ── 图标效果：独立浮动（波浪）+ 翻滚 + 大小 + 发光，transform 不被 SpringBoard 覆盖 ──
    {
        NSArray<UIView *> *icons = axs_dockbeauty_collectIcons(dock);
        double iAmp = 8.0 * [config axs_dockbeauty_iconFloatAmplitude] * strength;
        double iPeriod = [config axs_dockbeauty_iconFloatPeriod];
        double spread = [config axs_dockbeauty_iconFloatSpread];
        double omega = 2.0 * M_PI / iPeriod;
        double iconScale = [config axs_dockbeauty_iconScale];
        double rAmp = [config axs_dockbeauty_rollAmplitude] * strength;
        double rPeriod = [config axs_dockbeauty_rollPeriod];
        double omegaR = 2.0 * M_PI / rPeriod;
        BOOL glowOn = [config axs_dockbeauty_iconGlow];
        double glowIntensity = [config axs_dockbeauty_iconGlowIntensity];

        for (NSUInteger i = 0; i < icons.count; i++) {
            UIView *icon = icons[i];
            CATransform3D it = CATransform3DIdentity;
            if (iconScale != 1.0) {
                it = CATransform3DMakeScale((CGFloat)iconScale, (CGFloat)iconScale, 1.0);
            }
            if (animIconFloat) {
                double phase = t * omega + (double)i * spread;
                it = CATransform3DConcat(it, CATransform3DMakeTranslation(0, (CGFloat)(sin(phase) * iAmp), 0));
            }
            if (animRoll) {
                // 翻滚：绕 Y 轴摆动，带透视（m34），每图标相位错开。
                double rPhase = t * omegaR + (double)i * 0.4;
                CATransform3D roll = CATransform3DIdentity;
                roll.m34 = -1.0f / 500.0f;
                roll = CATransform3DRotate(roll, (CGFloat)(sin(rPhase) * 0.35 * rAmp), 0, 1, 0);
                it = CATransform3DConcat(it, roll);
            }
            icon.layer.transform = it;

            // 图标发光（柔和彩色投影，色相缓慢流动）。
            if (glowOn) {
                icon.layer.shadowColor = [UIColor colorWithHue:(CGFloat)fmod(0.55 + t * 0.03, 1.0)
                                                  saturation:0.8 brightness:1 alpha:1].CGColor;
                icon.layer.shadowRadius = (CGFloat)(6.0 + 6.0 * glowIntensity);
                icon.layer.shadowOpacity = (float)(0.35 * glowIntensity);
                icon.layer.shadowOffset = CGSizeMake(0, 3);
            } else if (icon.layer.shadowOpacity != 0) {
                icon.layer.shadowOpacity = 0;
            }
        }
    }

    // ── 流光：移动光带（长/宽/高/速度/透明度可调） ──
    if (animStream) {
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
    }

    // ── 萤火虫 ──
    self.fireflies.opacity = animFirefly ? 0.8f : 0.0f;

    // ── 鱼缸 ──
    NSInteger fishCount = [config axs_dockbeauty_fishCount];
    for (NSInteger i = 0; i < (NSInteger)self.fishLayers.count; i++) {
        CALayer *fish = self.fishLayers[i];
        if (!animFish || i >= fishCount) {
            if (fish.opacity != 0) fish.opacity = 0;
            continue;
        }
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

    // ── 气泡：仅发射器参数变化时更新（每 10 帧一次，色彩渐变足够平滑） ──
    if (bubbleOn) {
        self.bubbles.opacity = (float)fmin(1.0, [config axs_dockbeauty_bubbleDensity]);
        if ((self.frameCounter++ % 10) == 0) {
            double density = [config axs_dockbeauty_bubbleDensity];
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
    } else {
        self.bubbles.opacity = 0.0;
    }

    // ── 季节粒子：style 1-5 手动 / 6 自动（节日优先季节兜底）/ 7 自定义 emoji（多个混合飘） ──
    if (particleStyle > 0) {
        self.seasonEmitter.frame = dock.bounds;
        self.seasonEmitter.emitterPosition = CGPointMake(CGRectGetMidX(dock.bounds), -10.0);
        self.seasonEmitter.emitterSize = CGSizeMake(dock.bounds.size.width, 4.0);
        self.seasonEmitter.opacity = 0.85;

        NSArray<NSString *> *emojis = nil;
        NSInteger styleKey = particleStyle;
        if (particleStyle == 7) {
            // 自定义：文本按 emoji 拆分，多个混合飘。key 含字符串哈希（改了文本就重建）。
            NSString *custom = [config axs_dockbeauty_particleCustom];
            emojis = axs_dockbeauty_splitEmoji(custom);
            styleKey = 7000 + (NSInteger)((NSUInteger)[custom hash] % 100000);
        } else if (particleStyle == 6) {
            // 自动：节日主题优先，否则按季节。key 用日期（同一天不重复重建 sprite）。
            emojis = @[axs_dockbeauty_holidayEmoji() ?: axs_dockbeauty_seasonEmoji()];
            NSDateComponents *c = [[NSCalendar currentCalendar]
                components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[NSDate date]];
            styleKey = 1000 + c.month * 31 + c.day;
        } else {
            NSArray<NSString *> *pool = @[@"", @"❄️", @"🌸", @"🍂", @"⭐", @"❤️"];
            emojis = @[pool[(NSUInteger)particleStyle < pool.count ? (NSUInteger)particleStyle : 1]];
        }

        if (self.lastParticleStyle != styleKey) {
            self.lastParticleStyle = styleKey;
            // 每个 emoji 一个 cell（自定义多 emoji 时混合发射），发射率平摊。
            NSMutableArray<CAEmitterCell *> *cells = [NSMutableArray array];
            float perRate = (float)(6.0 / MAX((NSUInteger)1, emojis.count));
            for (NSString *e in emojis) {
                UIImage *sprite = axs_dockbeauty_emojiImage(e, 24.0);
                CAEmitterCell *cell = [CAEmitterCell emitterCell];
                cell.contents = (__bridge id)sprite.CGImage;
                cell.birthRate = perRate;
                cell.lifetime = 8.0;
                cell.velocity = 45.0;
                cell.velocityRange = 20.0;
                cell.emissionLongitude = M_PI_2;     // 向下飘落
                cell.emissionRange = M_PI / 6.0;
                cell.spin = 0.6;
                cell.spinRange = 1.5;
                cell.alphaSpeed = -0.04;
                [cells addObject:cell];
            }
            self.seasonEmitter.emitterCells = cells;
        }
        // 大小每帧同步（滑块实时生效）。
        double pSize = [config axs_dockbeauty_particleSize];
        for (CAEmitterCell *cell in self.seasonEmitter.emitterCells) {
            cell.scale = (float)pSize;
            cell.scaleRange = (float)(pSize * 0.4);
        }
    } else {
        if (self.seasonEmitter.opacity != 0) self.seasonEmitter.opacity = 0;
    }

    // ── 点击涟漪：扩散圆环，播完移除 ──
    for (NSInteger i = (NSInteger)self.rippleLayers.count - 1; i >= 0; i--) {
        CAShapeLayer *ring = self.rippleLayers[(NSUInteger)i];
        if (ring.animationKeys.count == 0) {
            [ring removeFromSuperlayer];
            [self.rippleLayers removeObjectAtIndex:(NSUInteger)i];
        }
    }

    [CATransaction commit];
}

// 点击反馈入口：图标点击时调用（弹性 + 涟漪）。
- (void)axs_dockbeauty_tapFeedbackAt:(CGPoint)point inDock:(UIView *)dock icon:(UIView *)icon {
    AxsDockBeautyConfig *config = [AxsDockBeautyConfig axs_dockbeauty_shared];
    if ([config axs_dockbeauty_tapBounce] && icon) {
        CAKeyframeAnimation *pop = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        pop.values = @[@1.0, @0.82, @1.08, @1.0];
        pop.keyTimes = @[@0, @0.25, @0.6, @1.0];
        pop.duration = 0.4;
        pop.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [icon.layer addAnimation:pop forKey:@"axs_bounce"];
    }
    if ([config axs_dockbeauty_tapRipple] && dock) {
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-12, -12, 24, 24)].CGPath;
        ring.position = point;
        ring.fillColor = [UIColor clearColor].CGColor;
        ring.strokeColor = [UIColor colorWithHue:0.55 saturation:0.7 brightness:1 alpha:0.8].CGColor;
        ring.lineWidth = 2.5;
        [dock.layer addSublayer:ring];
        [self.rippleLayers addObject:ring];

        CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        grow.fromValue = @1.0;
        grow.toValue = @5.0;
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.8;
        fade.toValue = @0.0;
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[grow, fade];
        group.duration = 0.7;
        group.removedOnCompletion = YES;
        [ring addAnimation:group forKey:@"axs_ripple"];
    }
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    [self.bubbles removeFromSuperlayer];
    [self.fireflies removeFromSuperlayer];
    [self.streamLayer removeFromSuperlayer];
    [self.seasonEmitter removeFromSuperlayer];
    for (CALayer *f in self.fishLayers) [f removeFromSuperlayer];
    for (CAShapeLayer *r in self.rippleLayers) [r removeFromSuperlayer];
    [self.rippleLayers removeAllObjects];
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
             @"anim_float", @"anim_icon_float", @"anim_breathing", @"anim_random",
             @"anim_stream", @"anim_firefly", @"anim_fish", @"fish_count",
             @"anim_roll", @"anim_shake",
             @"float_amplitude", @"float_period",
             @"icon_float_amplitude", @"icon_float_period", @"icon_float_spread",
             @"breathing_amplitude", @"breathing_period",
             @"roll_amplitude", @"roll_period",
             @"shake_amplitude", @"shake_period",
             @"spring_enabled",
             @"stream_speed", @"stream_width", @"stream_height", @"stream_opacity",
             @"bg_opacity", @"corner_radius",
             @"icon_scale", @"icon_glow", @"icon_glow_intensity",
             @"tap_ripple", @"tap_bounce",
             @"particle_style", @"particle_size", @"particle_custom",
             @"low_power_guard", @"reduce_motion_guard",
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

// ── 点击反馈：图标点击 → 弹性 + 涟漪 ─────────────────────────────────────────
%hook SBIconView
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    // 找到图标所在的 Dock（递归向上找 *DockView）。
    UIView *parent = self.superview;
    UIView *dock = nil;
    while (parent) {
        if ([NSStringFromClass([parent class]) hasSuffix:@"DockView"]) {
            dock = parent;
            break;
        }
        parent = parent.superview;
    }
    if (!dock) return;
    CGPoint tapInDock = [touch locationInView:dock];
    for (AxsDockBeautyAnimator *a in axs_dockbeauty_animators) {
        if (a.dockView == dock) {
            [a axs_dockbeauty_tapFeedbackAt:tapInDock inDock:dock icon:self];
            break;
        }
    }
}
%end

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

        // 兜底重试：即使 applicationDidFinishLaunching 未触发，也要尝试挂载。
        // 每 3 秒扫一次，挂上即停（最多 20 次）；Dock 晚建/锁屏重建由 didMoveToWindow 兜底。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __block NSInteger tries = 0;
            NSTimer *scan = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
                if (axs_dockbeauty_animators.count > 0) { [t invalidate]; return; }
                axs_dockbeauty_attachIfNeeded();
                if (axs_dockbeauty_animators.count > 0) { [t invalidate]; return; }
                if (++tries >= 20) { [t invalidate]; }
            }];
            [NSRunLoop.mainRunLoop addTimer:scan forMode:NSRunLoopCommonModes];
        });
    }
}
