#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 持久助手：被植入「提示」App 后，每次点开图标就会重新把这些应用注册为
// System 状态，从而在图标缓存刷新后恢复可启动。
// 它靠 CoreTrust 伪造签名获得运行权限，本身不带任何 Apple 合法证书。

@interface ESHelperController : UIViewController
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *action;
@end

@implementation ESHelperController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.063 blue:0.086 alpha:1.0];

	UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(24, 90, 300, 34)];
	t.text = @"永签 · 持久助手";
	t.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
	t.textColor = [UIColor whiteColor];
	[self.view addSubview:t];

	UILabel *s = [[UILabel alloc] initWithFrame:CGRectMake(24, 132, 320, 60)];
	s.numberOfLines = 0;
	s.font = [UIFont systemFontOfSize:13];
	s.textColor = [UIColor colorWithWhite:1 alpha:0.55];
	s.text = @"这个图标原本是「提示」。它被替换为永签助手，用来在图标缓存刷新后恢复应用注册。";
	[self.view addSubview:s];

	self.status = [[UILabel alloc] initWithFrame:CGRectMake(24, 210, 327, 24)];
	self.status.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
	self.status.textColor = [UIColor colorWithRed:0.29 green:0.867 blue:0.78 alpha:1.0];
	self.status.text = @"就绪";
	[self.view addSubview:self.status];

	self.action = [UIButton buttonWithType:UIButtonTypeSystem];
	self.action.frame = CGRectMake(24, 250, 327, 50);
	[self.action setTitle:@"重新注册所有应用" forState:UIControlStateNormal];
	self.action.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
	self.action.backgroundColor = [UIColor colorWithRed:0.29 green:0.867 blue:0.78 alpha:1.0];
	self.action.layer.cornerRadius = 12;
	[self.action addTarget:self action:@selector(registerAll) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.action];
}

- (void)registerAll {
	Class WS = NSClassFromString(@"LSApplicationWorkspace");
	if (!WS) { self.status.text = @"LaunchServices 不可用"; return; }
	id ws = [WS performSelector:@selector(defaultWorkspace)];
	SEL proxySel = NSSelectorFromString(@"applicationProxyForBundleURL:");
	SEL regSel = NSSelectorFromString(@"registerApplication:");

	NSFileManager *fm = [NSFileManager defaultManager];
	NSUInteger n = 0;
	for (NSString *item in [fm contentsOfDirectoryAtPath:@"/Applications" error:nil]) {
		if (![item hasSuffix:@".app"]) continue;
		NSURL *url = [NSURL fileURLWithPath:[@"/Applications" stringByAppendingPathComponent:item]];
		if (![ws respondsToSelector:proxySel]) break;
		id proxy = [ws performSelector:proxySel withObject:url];
		if (proxy) {
			[ws performSelector:regSel withObject:proxy];
			n++;
		}
	}
	self.status.text = [NSString stringWithFormat:@"已重新注册 %lu 个应用", (unsigned long)n];
}

@end

@interface ESHelperAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ESHelperAppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [[ESHelperController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

@end
