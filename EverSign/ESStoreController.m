#import "ESStoreController.h"
#import "ESInstaller.h"
#import "ESTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ESRingView : UIView
@property (nonatomic, assign) CGFloat progress;
- (void)setProgress:(CGFloat)p animated:(BOOL)animated;
@end

@implementation ESRingView {
	CAShapeLayer *_track;
	CAShapeLayer *_bar;
	UILabel *_pct;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;
	self.backgroundColor = UIColor.clearColor;

	_track = [CAShapeLayer layer];
	_track.strokeColor = ESColorStroke().CGColor;
	_track.fillColor = UIColor.clearColor.CGColor;
	_track.lineWidth = 6;
	_track.lineCap = kCALineCapRound;
	[self.layer addSublayer:_track];

	_bar = [CAShapeLayer layer];
	_bar.strokeColor = ESColorAccent().CGColor;
	_bar.fillColor = UIColor.clearColor.CGColor;
	_bar.lineWidth = 6;
	_bar.lineCap = kCALineCapRound;
	_bar.strokeEnd = 0;
	[self.layer addSublayer:_bar];

	_pct = [[UILabel alloc] initWithFrame:CGRectZero];
	_pct.textColor = ESColorText();
	_pct.font = ESFontBold(20);
	_pct.textAlignment = NSTextAlignmentCenter;
	_pct.text = @"0%";
	[self addSubview:_pct];

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect b = self.bounds;
	CGFloat r = MIN(b.size.width, b.size.height) / 2 - 4;
	CGPathRef path = CGPathCreateWithEllipseInRect(CGRectMake(b.size.width/2 - r, b.size.height/2 - r, r*2, r*2), NULL);
	_track.path = path;
	_bar.path = path;
	CGPathRelease(path);
	_pct.frame = b;
}

- (void)setProgress:(CGFloat)p {
	[self setProgress:p animated:NO];
}

- (void)setProgress:(CGFloat)p animated:(BOOL)animated {
	_progress = MAX(0, MIN(1, p));
	_pct.text = [NSString stringWithFormat:@"%d%%", (int)round(_progress * 100)];
	CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
	a.fromValue = @(_bar.strokeEnd);
	a.toValue = @(_progress);
	a.duration = animated ? 0.25 : 0;
	[_bar addAnimation:a forKey:@"strokeEnd"];
	_bar.strokeEnd = _progress;
}

@end

@interface ESStoreController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) ESRingView *ring;
@property (nonatomic, strong) UILabel *stageLabel;
@property (nonatomic, strong) UIButton *installButton;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation ESStoreController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = ESColorBg();

	UILabel *title = [[UILabel alloc] init];
	title.text = @"永签";
	title.font = ESFontBold(34);
	title.textColor = ESColorText();
	[title sizeToFit];
	title.frame = CGRectMake(24, 24, 200, 42);
	[self.view addSubview:title];

	UILabel *sub = [[UILabel alloc] init];
	sub.text = @"EverSign · 永久签名安装";
	sub.font = ESFontMed(13);
	sub.textColor = ESColorDim();
	sub.frame = CGRectMake(24, 66, 280, 18);
	[self.view addSubview:sub];

	UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, 104, self.view.bounds.size.width - 40, 220)];
	card.backgroundColor = ESColorCard();
	card.layer.cornerRadius = 18;
	card.layer.borderColor = ESColorStroke().CGColor;
	card.layer.borderWidth = 1;
	[self.view addSubview:card];

	self.ring = [[ESRingView alloc] initWithFrame:CGRectMake((card.bounds.size.width - 130)/2, 24, 130, 130)];
	[card addSubview:self.ring];

	self.stageLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 164, card.bounds.size.width - 32, 20)];
	self.stageLabel.text = @"待安装";
	self.stageLabel.textAlignment = NSTextAlignmentCenter;
	self.stageLabel.font = ESFontMed(14);
	self.stageLabel.textColor = ESColorDim();
	[card addSubview:self.stageLabel];

	self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 186, card.bounds.size.width - 32, 18)];
	self.statusLabel.text = @"就绪";
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.font = ESFontReg(12);
	self.statusLabel.textColor = ESColorDim();
	[card addSubview:self.statusLabel];

	self.installButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.installButton.frame = CGRectMake(20, 348, self.view.bounds.size.width - 40, 54);
	[self.installButton setTitle:@"选择 IPA 文件" forState:UIControlStateNormal];
	[self.installButton setTitleColor:ESColorBg() forState:UIControlStateNormal];
	self.installButton.titleLabel.font = ESFontBold(17);
	self.installButton.backgroundColor = ESColorAccent();
	self.installButton.layer.cornerRadius = 14;
	[self.installButton addTarget:self action:@selector(pickIPA) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.installButton];

	UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(24, 416, self.view.bounds.size.width - 48, 60)];
	hint.numberOfLines = 0;
	hint.font = ESFontReg(12);
	hint.textColor = ESColorDim();
	hint.text = @"安装后应用写入 /Applications 并保留自签名，重启不失效。首次需要已获取签名能力的设备环境。";
	[self.view addSubview:hint];
}

- (void)pickIPA {
	if (@available(iOS 14.0, *)) {
		UTType *t = [UTType typeWithFilenameExtension:@"ipa"];
		if (!t) t = UTTypeData;
		UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ t ]];
		p.delegate = self;
		p.allowsMultipleSelection = NO;
		[self presentViewController:p animated:YES completion:nil];
	}
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	if (!url) return;

	[self.ring setProgress:0 animated:NO];
	self.stageLabel.text = @"准备中";
	self.statusLabel.text = url.lastPathComponent;
	self.installButton.enabled = NO;
	self.installButton.alpha = 0.5;

	ESInstaller *inst = [ESInstaller shared];
	inst.progressHandler = ^(double f, NSString *stage) {
		[self.ring setProgress:f animated:YES];
		self.stageLabel.text = stage;
	};

	[inst installIPAAtURL:url completion:^(BOOL ok, NSString *message) {
		self.stageLabel.text = ok ? @"安装完成" : @"安装失败";
		self.stageLabel.textColor = ok ? ESColorAccent() : ESColorDanger();
		self.statusLabel.text = message;
		self.statusLabel.textColor = ok ? ESColorDim() : ESColorDanger();
		self.installButton.enabled = YES;
		self.installButton.alpha = 1.0;
	}];
}

@end
