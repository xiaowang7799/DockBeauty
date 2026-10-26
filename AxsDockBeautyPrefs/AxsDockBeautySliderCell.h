#pragma once

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#include <math.h>

@protocol AxsDockBeautySliderCellHandler <NSObject>
- (double)axs_dockbeauty_sliderValueForSpecifier:(PSSpecifier *)specifier;
- (void)axs_dockbeauty_setSliderValue:(double)value specifier:(PSSpecifier *)specifier;
@end

@interface AxsDockBeautySliderCell : PSTableCell
@property (nonatomic, weak) id<AxsDockBeautySliderCellHandler> handler;
- (void)axs_dockbeauty_reloadState;
@end
