#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <dirent.h>

extern char **environ;

static BOOL ESRun(NSString *tool, NSArray<NSString *> *args) {
	const char *argv[16];
	int i = 0;
	argv[i++] = tool.UTF8String;
	for (NSString *a in args) { if (i >= 15) break; argv[i++] = a.UTF8String; }
	argv[i] = NULL;
	pid_t pid = 0;
	int rc = posix_spawn(&pid, tool.UTF8String, NULL, NULL, (char *const *)argv, environ);
	if (rc != 0) return NO;
	int status = 0;
	waitpid(pid, &status, 0);
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static BOOL ESIsMachO(NSString *path) {
	FILE *f = fopen(path.fileSystemRepresentation, "rb");
	if (!f) return NO;
	uint32_t magic = 0;
	BOOL ok = (fread(&magic, 1, 4, f) == 4) &&
			  (magic == 0xFEEDFACF || magic == 0xFEEDFACE || magic == 0xBEBAFECA || magic == 0xCAFEBABE);
	fclose(f);
	return ok;
}

static void ESFixPerms(NSString *root) {
	NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:root];
	NSString *rel = nil;
	while ((rel = [en nextObject])) {
		NSString *full = [root stringByAppendingPathComponent:rel];
		struct stat st;
		if (lstat(full.fileSystemRepresentation, &st) != 0) continue;
		if (S_ISLNK(st.st_mode)) continue;
		chown(full.fileSystemRepresentation, 0, 0);
		if (S_ISDIR(st.st_mode)) chmod(full.fileSystemRepresentation, 0755);
		else if (st.st_mode & 0111) chmod(full.fileSystemRepresentation, 0755);
		else chmod(full.fileSystemRepresentation, 0644);
	}
}

static void ESRegister(NSString *appPath) {
	Class WS = NSClassFromString(@"LSApplicationWorkspace");
	if (!WS) return;
	id ws = [WS performSelector:@selector(defaultWorkspace)];
	SEL proxySel = NSSelectorFromString(@"applicationProxyForBundleURL:");
	if (![ws respondsToSelector:proxySel]) return;
	id proxy = [ws performSelector:proxySel withObject:[NSURL fileURLWithPath:appPath]];
	if (proxy) [ws performSelector:NSSelectorFromString(@"registerApplication:") withObject:proxy];
}

@interface ESInstallerViewController : UIViewController
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *installButton;
@property (nonatomic, strong) UITextView *log;
@end

@implementation ESInstallerViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	UIColor *bg = [UIColor colorWithRed:0.055 green:0.063 blue:0.086 alpha:1.0];
	UIColor *accent = [UIColor colorWithRed:0.29 green:0.867 blue:0.78 alpha:1.0];
	self.view.backgroundColor = bg;

	UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(24, 96, 327, 38)];
	t.text = @"永签安装器";
	t.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
	t.textColor = UIColor.whiteColor;
	[self.view addSubview:t];

	UILabel *s = [[UILabel alloc] initWithFrame:CGRectMake(24, 140, 327, 56)];
	s.numberOfLines = 0;
	s.font = [UIFont systemFontOfSize:13];
	s.textColor = [UIColor colorWithWhite:1 alpha:0.55];
	s.text = @"点下面的按钮，用 CoreTrust 签名校验缺陷把永签装成系统应用。装完这个入口就没用了。";
	[self.view addSubview:s];

	self.installButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.installButton.frame = CGRectMake(24, 220, 327, 56);
	[self.installButton setTitle:@"安装永签" forState:UIControlStateNormal];
	self.installButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
	self.installButton.backgroundColor = accent;
	[self.installButton setTitleColor:[UIColor colorWithWhite:0.06 alpha:1.0] forState:UIControlStateNormal];
	self.installButton.layer.cornerRadius = 14;
	[self.installButton addTarget:self action:@selector(startInstall) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.installButton];

	self.status = [[UILabel alloc] initWithFrame:CGRectMake(24, 292, 327, 22)];
	self.status.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
	self.status.textColor = accent;
	self.status.text = @"就绪";
	[self.view addSubview:self.status];

	self.log = [[UITextView alloc] initWithFrame:CGRectMake(20, 326, 335, 380)];
	self.log.backgroundColor = [UIColor colorWithRed:0.108 green:0.122 blue:0.157 alpha:1.0];
	self.log.textColor = [UIColor colorWithWhite:1 alpha:0.7];
	self.log.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
	self.log.editable = NO;
	self.log.layer.cornerRadius = 12;
	self.log.text = @"";
	[self.view addSubview:self.log];
}

- (void)append:(NSString *)line {
	self.log.text = [self.log.text stringByAppendingFormat:@"%@\n", line];
	NSRange r = NSMakeRange(self.log.text.length, 0);
	[self.log scrollRangeToVisible:r];
}

- (void)startInstall {
	self.installButton.enabled = NO;
	self.status.text = @"安装中…";
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BOOL ok = [self doInstall];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.status.text = ok ? @"已安装，回桌面查看「永签」" : @"失败，看下面的日志";
			self.installButton.enabled = !ok;
		});
	});
}

- (void)logLine:(NSString *)s {
	dispatch_async(dispatch_get_main_queue(), ^{ [self append:s]; });
}

- (BOOL)doInstall {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSBundle *bundle = [NSBundle mainBundle];

	NSString *payload = [bundle pathForResource:@"EverSign" ofType:@"app" inDirectory:@"Payload"];
	[self logLine:[NSString stringWithFormat:@"payload: %@", payload ?: @"(缺失)"]];
	if (!payload) return NO;

	NSString *dest = @"/Applications/EverSign.app";
	if ([fm fileExistsAtPath:dest]) [fm removeItemAtPath:dest error:nil];
	NSError *err = nil;
	if (![fm copyItemAtPath:payload toPath:dest error:&err]) {
		[self logLine:[NSString stringWithFormat:@"写入失败: %@", err.localizedDescription]];
		return NO;
	}
	[self logLine:@"已写入 /Applications"];

	ESFixPerms(dest);
	[self logLine:@"权限已修正 root:wheel"];

	NSString *ldid = [bundle pathForResource:@"ldid" ofType:nil];
	NSString *p12 = [bundle pathForResource:@"victim" ofType:@"p12"];
	NSString *ents = [bundle pathForResource:@"entitlements" ofType:@"plist"];
	[self logLine:[NSString stringWithFormat:@"ldid: %@", ldid ? @"ok" : @"缺失"]];
	if (!ldid || !p12) return NO;

	NSUInteger n = 0;
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:dest];
	NSString *rel = nil;
	while ((rel = [en nextObject])) {
		NSString *full = [dest stringByAppendingPathComponent:rel];
		if (!ESIsMachO(full)) continue;
		NSMutableArray *args = [NSMutableArray array];
		[args addObject:[@"-K" stringByAppendingString:p12]];
		if (ents) [args addObject:[@"-S" stringByAppendingString:ents]];
		[args addObject:full];
		BOOL signed_ok = ESRun(ldid, args);
		[self logLine:[NSString stringWithFormat:@"%@ %@", signed_ok ? @"签名" : @"签名失败", rel]];
		if (signed_ok) n++;
	}
	ESFixPerms(dest);

	[self logLine:[NSString stringWithFormat:@"已重签 %lu 个二进制", (unsigned long)n]];
	ESRegister(dest);
	[self logLine:@"已注册到 LaunchServices"];
	return YES;
}

@end

@interface ESInstallAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ESInstallAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [[ESInstallerViewController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}
@end
