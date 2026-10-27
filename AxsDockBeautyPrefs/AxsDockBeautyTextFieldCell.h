#pragma once

#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>

// 自定义文本输入 Cell（PSTextFieldCell 在 iOS 14+ 不再渲染输入框，用自绘 UITextField 取代）。
// 布局：左侧 label + 右侧圆角输入框；编辑时实时写入偏好并广播变更。
@interface AxsDockBeautyTextFieldCell : PSTableCell
@end
