#pragma once

#import <UIKit/UIKit.h>

// Declare only private interfaces confirmed on the target iOS version.
//
// SBIconView is a UIView subclass (stable across iOS 14–18); declaring it as one
// lets the icon-tap hook resolve UIView members like superview / touchesEnded:.
@interface SBIconView : UIView
@end
