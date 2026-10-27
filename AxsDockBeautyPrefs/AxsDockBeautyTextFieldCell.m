#import "AxsDockBeautyTextFieldCell.h"
#import "AxsDockBeautyPreferences.h"
#import <UIKit/UIKit.h>

@interface AxsDockBeautyTextFieldCell ()
@property (nonatomic, strong) UITextField *axs_field;
@end

@implementation AxsDockBeautyTextFieldCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier
                  specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _axs_field = [[UITextField alloc] initWithFrame:CGRectZero];
        _axs_field.textAlignment = NSTextAlignmentLeft;
        _axs_field.font = [UIFont systemFontOfSize:15];
        _axs_field.borderStyle = UITextBorderStyleRoundedRect;
        _axs_field.clearButtonMode = UITextFieldViewModeWhileEditing;
        _axs_field.returnKeyType = UIReturnKeyDone;
        _axs_field.autocorrectionType = UITextAutocorrectionTypeNo;
        _axs_field.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                    | UIViewAutoresizingFlexibleTopMargin
                                    | UIViewAutoresizingFlexibleBottomMargin;
        [_axs_field addTarget:self action:@selector(axs_editingChanged)
             forControlEvents:UIControlEventEditingChanged];
        [_axs_field addTarget:self action:@selector(axs_dismissKeyboard)
             forControlEvents:UIControlEventEditingDidEndOnExit];
        [self.contentView addSubview:_axs_field];

        NSString *key = [specifier propertyForKey:@"key"];
        id value = axs_dockbeauty_readPreferences()[key];
        if (![value isKindOfClass:[NSString class]]) {
            value = [specifier propertyForKey:@"default"];
        }
        _axs_field.text = [value isKindOfClass:[NSString class]] ? value : @"";
        NSString *placeholder = [specifier propertyForKey:@"placeholder"];
        _axs_field.placeholder = placeholder.length ? placeholder : @"输入…";
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat height = self.contentView.bounds.size.height;
    CGFloat labelWidth = MIN(150.0, width * 0.42);
    self.textLabel.frame = CGRectMake(16.0, 0, labelWidth - 16.0, height);
    self.axs_field.frame = CGRectMake(labelWidth + 8.0, 7.0,
                                      MAX(0.0, width - labelWidth - 24.0),
                                      MAX(0.0, height - 14.0));
}

- (void)axs_editingChanged {
    NSString *key = [self.specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    axs_dockbeauty_writePreference(key, self.axs_field.text ?: @"", &error);
}

- (void)axs_dismissKeyboard {
    [self.axs_field resignFirstResponder];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.axs_field.text = @"";
}

@end
