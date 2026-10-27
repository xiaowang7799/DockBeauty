#import "AxsDockBeautyRootListController.h"
#import "AxsDockBeautyPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "AxsDockBeautySliderCell.h"

@interface AxsDockBeautyRootListController () <AxsDockBeautySliderCellHandler>
@end

@implementation AxsDockBeautyRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsDockBeautyRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_dockbeauty_addButton:@"GitHub 仓库" action:@selector(axs_dockbeauty_openRepository:) to:items];

        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"一键预设" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_dockbeauty_addButton:@"禅意（浮动+呼吸+弹簧）" action:@selector(axs_dockbeauty_applyZenPreset:) to:items];
        [self axs_dockbeauty_addButton:@"赛博（流光+萤火虫+呼吸+随机）" action:@selector(axs_dockbeauty_applyCyberPreset:) to:items];
        [self axs_dockbeauty_addButton:@"水族馆（鱼缸5条+彩虹气泡）" action:@selector(axs_dockbeauty_applyAquariumPreset:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)axs_dockbeauty_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_dockbeauty_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_dockbeauty_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)axs_dockbeauty_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self axs_dockbeauty_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)axs_dockbeauty_openRepository:(id)sender {
    NSString *source = @"https://github.com/xiaowang7799/DockBeauty";
    // Encode the entire URL as a path component, including its own delimiters.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [source stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded]];
    [self axs_dockbeauty_openURL:primary fallback:[NSURL URLWithString:source]];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    }
    if ([cell isKindOfClass:[AxsDockBeautySliderCell class]]) {
        AxsDockBeautySliderCell *sliderCell = (AxsDockBeautySliderCell *)cell;
        sliderCell.handler = self;
        [sliderCell axs_dockbeauty_reloadState];
    }
}

- (double)axs_dockbeauty_sliderValueForSpecifier:(PSSpecifier *)specifier {
    id value = [self readPreferenceValue:specifier];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0.0;
}

- (void)axs_dockbeauty_setSliderValue:(double)value specifier:(PSSpecifier *)specifier {
    double minimum = [[specifier propertyForKey:@"min"] doubleValue];
    double maximum = [[specifier propertyForKey:@"max"] doubleValue];
    if (!isfinite(minimum)) minimum = 0.0;
    if (!isfinite(maximum) || maximum <= minimum) maximum = minimum + 1.0;
    if (!isfinite(value)) value = minimum;
    [self setPreferenceValue:@(fmax(minimum, fmin(maximum, value))) specifier:specifier];
}

#pragma mark - Custom presets (#3: save / apply / delete)

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

- (NSArray<NSDictionary *> *)axs_dockbeauty_currentPresets {
    id value = axs_dockbeauty_readPreferences()[@"custom_presets"];
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

- (void)axs_dockbeauty_savePreset:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存预设"
        message:@"给当前配色方案起个名字" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"例如：暗夜青";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        if (name.length == 0) return;
        NSDictionary *all = axs_dockbeauty_readPreferences();
        NSMutableDictionary *settings = [NSMutableDictionary dictionary];
        for (NSString *key in axs_dockbeauty_presetKeys()) {
            id v = all[key];
            if (v) settings[key] = v;
        }
        NSMutableArray *presets = [self axs_dockbeauty_currentPresets].mutableCopy;
        [presets addObject:@{@"name": name, @"settings": settings}];
        NSError *error = nil;
        if (!axs_dockbeauty_writePreference(@"custom_presets", presets, &error)) {
            [self axs_dockbeauty_showSaveError:error];
        }
        [self reloadSpecifiers];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_dockbeauty_managePresets:(id)sender {
    NSArray<NSDictionary *> *presets = [self axs_dockbeauty_currentPresets];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"已存预设"
        message:presets.count ? nil : @"还没有保存任何预设" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *preset in presets) {
        NSString *name = preset[@"name"] ?: @"未命名";
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            [self axs_dockbeauty_applyPreset:preset[@"settings"]];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:[@"删除 · " stringByAppendingString:name]
                          style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
            NSMutableArray *next = [self axs_dockbeauty_currentPresets].mutableCopy;
            [next removeObject:preset];
            NSError *error = nil;
            if (!axs_dockbeauty_writePreference(@"custom_presets", next, &error)) {
                [self axs_dockbeauty_showSaveError:error];
            }
            [self reloadSpecifiers];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = self.view;
        pop.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)axs_dockbeauty_applyPreset:(NSDictionary *)settings {
    if (![settings isKindOfClass:[NSDictionary class]]) return;
    NSError *error = nil;
    for (NSString *key in axs_dockbeauty_presetKeys()) {
        id value = settings[key];
        if (value) {
            BOOL ok = axs_dockbeauty_writePreference(key, value, &error);
            if (!ok) {
                [self axs_dockbeauty_showSaveError:error];
                return;
            }
        }
    }
    [self reloadSpecifiers];
}

- (void)axs_dockbeauty_applyZenPreset:(id)sender {
    NSDictionary *settings = @{
        @"anim_float": @YES,
        @"float_amplitude": @0.5,
        @"float_period": @4.0,
        @"anim_breathing": @YES,
        @"breathing_amplitude": @0.08,
        @"breathing_period": @5.0,
        @"spring_enabled": @YES,
        @"anim_random": @NO,
        @"anim_stream": @NO,
        @"anim_firefly": @NO,
        @"anim_fish": @NO,
        @"bubble_color_mode": @2,  // Transparent
        @"bubble_density": @0.3,
    };
    NSError *error = nil;
    for (NSString *key in settings) {
        axs_dockbeauty_writePreference(key, settings[key], &error);
    }
    [self reloadSpecifiers];
}

- (void)axs_dockbeauty_applyCyberPreset:(id)sender {
    NSDictionary *settings = @{
        @"anim_float": @YES,
        @"anim_breathing": @YES,
        @"anim_random": @YES,
        @"anim_stream": @YES,
        @"anim_firefly": @YES,
        @"anim_fish": @NO,
        @"bubble_color_mode": @1,  // Single
        @"bubble_hue": @0.5,       // 青色
        @"bubble_saturation": @0.9,
        @"bubble_value": @1.0,
        @"stream_hue": @0.5,
        @"stream_hue2": @0.83,
        @"bubble_density": @1.0,
    };
    NSError *error = nil;
    for (NSString *key in settings) {
        axs_dockbeauty_writePreference(key, settings[key], &error);
    }
    [self reloadSpecifiers];
}

- (void)axs_dockbeauty_applyAquariumPreset:(id)sender {
    NSDictionary *settings = @{
        @"anim_float": @NO,
        @"anim_breathing": @NO,
        @"anim_random": @NO,
        @"anim_stream": @NO,
        @"anim_firefly": @NO,
        @"anim_fish": @YES,
        @"fish_count": @5,
        @"bubble_color_mode": @0,  // Rainbow
        @"bubble_density": @1.5,
        @"bubble_size_min": @6,
        @"bubble_size_max": @12,
    };
    NSError *error = nil;
    for (NSString *key in settings) {
        axs_dockbeauty_writePreference(key, settings[key], &error);
    }
    [self reloadSpecifiers];
}

- (void)axs_dockbeauty_showSaveError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
        message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
