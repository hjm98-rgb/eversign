#import <UIKit/UIKit.h>

// EverSign design tokens -- dark card aesthetic, teal/amber accent
static inline UIColor *ESColorBg(void)      { return [UIColor colorWithRed:0.055 green:0.063 blue:0.086 alpha:1.0]; }
static inline UIColor *ESColorCard(void)    { return [UIColor colorWithRed:0.108 green:0.122 blue:0.157 alpha:1.0]; }
static inline UIColor *ESColorCardHi(void)  { return [UIColor colorWithRed:0.141 green:0.157 blue:0.200 alpha:1.0]; }
static inline UIColor *ESColorStroke(void)  { return [UIColor colorWithWhite:1.0 alpha:0.07]; }
static inline UIColor *ESColorText(void)    { return [UIColor colorWithRed:0.941 green:0.949 blue:0.972 alpha:1.0]; }
static inline UIColor *ESColorDim(void)     { return [UIColor colorWithRed:0.541 green:0.573 blue:0.639 alpha:1.0]; }
static inline UIColor *ESColorAccent(void)  { return [UIColor colorWithRed:0.290 green:0.867 blue:0.780 alpha:1.0]; }
static inline UIColor *ESColorWarn(void)    { return [UIColor colorWithRed:0.976 green:0.702 blue:0.353 alpha:1.0]; }
static inline UIColor *ESColorDanger(void)  { return [UIColor colorWithRed:0.949 green:0.376 blue:0.412 alpha:1.0]; }

static inline UIFont *ESFontBold(CGFloat s) { return [UIFont systemFontOfSize:s weight:UIFontWeightBold]; }
static inline UIFont *ESFontMed(CGFloat s)  { return [UIFont systemFontOfSize:s weight:UIFontWeightMedium]; }
static inline UIFont *ESFontReg(CGFloat s)  { return [UIFont systemFontOfSize:s weight:UIFontWeightRegular]; }
static inline UIFont *ESFontMono(CGFloat s) { return [UIFont monospacedSystemFontOfSize:s weight:UIFontWeightMedium]; }
