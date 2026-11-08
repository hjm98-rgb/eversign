#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <dirent.h>
#import <dlfcn.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

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

@interface ESAppContainer : NSObject
+ (id)containerWithIdentifier:(NSString *)ident createIfNecessary:(BOOL)create existed:(BOOL *)existed error:(NSError **)error;
- (NSURL *)url;
@end

@interface ESWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)registerApplicationDictionary:(NSDictionary *)dict;
- (BOOL)unregisterApplication:(NSURL *)url;
@end

static void *ESMCMHandle = NULL;

static void ESLoadContainerFramework(void) {
	if (ESMCMHandle) return;
	ESMCMHandle = dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_NOW);
}

static NSString *ESBundleContainerPath(NSString *bundleId, BOOL create) {
	ESLoadContainerFramework();
	Class cls = NSClassFromString(@"MCMAppContainer");
	if (!cls) return nil;
	id cont = [cls containerWithIdentifier:bundleId createIfNecessary:create existed:NULL error:NULL];
	NSURL *u = [cont url];
	return u.path;
}

static NSString *ESDataContainerPath(NSString *bundleId) {
	ESLoadContainerFramework();
	Class cls = NSClassFromString(@"MCMAppDataContainer");
	if (!cls) return nil;
	id cont = [cls containerWithIdentifier:bundleId createIfNecessary:YES existed:NULL error:NULL];
	NSURL *u = [cont url];
	return u.path;
}

static NSDictionary *ESReadPlist(NSString *path) {
	NSData *d = [NSData dataWithContentsOfFile:path];
	if (!d) return nil;
	id obj = [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:NULL error:NULL];
	return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL ESRegisterSystemApp(NSString *appPath, NSDictionary *entitlements) {
	if (!appPath) return NO;
	NSDictionary *info = ESReadPlist([appPath stringByAppendingPathComponent:@"Info.plist"]);
	NSString *bid = info[@"CFBundleIdentifier"];
	if (!bid) return NO;

	NSString *dataPath = ESDataContainerPath(bid);
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	if (entitlements) dict[@"Entitlements"] = entitlements;
	dict[@"ApplicationType"] = @"System";
	dict[@"CFBundleIdentifier"] = bid;
	dict[@"CodeInfoIdentifier"] = bid;
	dict[@"CompatibilityState"] = @0;
	dict[@"IsContainerized"] = @YES;
	if (dataPath) {
		dict[@"Container"] = dataPath;
		dict[@"EnvironmentVariables"] = @{
			@"CFFIXED_USER_HOME" : dataPath,
			@"HOME" : dataPath,
			@"TMPDIR" : [dataPath stringByAppendingPathComponent:@"tmp"]
		};
	}
	dict[@"IsDeletable"] = @YES;
	dict[@"Path"] = appPath;
	dict[@"SignerOrganization"] = @"Apple Inc.";
	dict[@"SignatureVersion"] = @132352;
	dict[@"SignerIdentity"] = @"Apple iPhone OS Application Signing";
	dict[@"IsAdHocSigned"] = @YES;
	dict[@"LSInstallType"] = @1;
	dict[@"HasMIDBasedSINF"] = @0;
	dict[@"MissingSINF"] = @0;
	dict[@"FamilyID"] = @0;
	dict[@"IsOnDemandInstallCapable"] = @0;
	NSString *team = entitlements[@"com.apple.developer.team-identifier"];
	dict[@"TeamIdentifier"] = team ? team : @"EverSign";

	Class WS = NSClassFromString(@"LSApplicationWorkspace");
	if (!WS) return NO;
	id ws = [WS defaultWorkspace];
	SEL sel = NSSelectorFromString(@"registerApplicationDictionary:");
	if (![ws respondsToSelector:sel]) return NO;
	BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, sel, dict);
	if (ok) {
		CFPreferencesSetValue(CFSTR("SBShowNonDefaultSystemApps"), kCFBooleanTrue,
							  CFSTR("com.apple.springboard"), CFSTR("mobile"), kCFPreferencesAnyHost);
		CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
	}
	return ok;
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
	[self logLine:[NSString stringWithFormat:@"① 内置本体: %@", payload ? @"就绪" : @"缺失"]];
	if (!payload) return NO;

	NSString *ldid = [bundle pathForResource:@"ldid" ofType:nil];
	NSString *p12 = [bundle pathForResource:@"victim" ofType:@"p12"];
	NSString *ents = [bundle pathForResource:@"entitlements" ofType:@"plist"];
	if (!ldid || !p12) {
		[self logLine:@"签名工具缺失"];
		return NO;
	}

	NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"eversign-%@", [[NSUUID UUID] UUIDString]]];
	if (![fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:NULL]) {
		[self logLine:@"无法创建工作区"];
		return NO;
	}
	NSString *staged = [work stringByAppendingPathComponent:@"EverSign.app"];
	NSError *err = nil;
	if (![fm copyItemAtPath:payload toPath:staged error:&err]) {
		[self logLine:[NSString stringWithFormat:@"暂存失败: %@", err.localizedDescription]];
		return NO;
	}

	NSUInteger signedCount = 0;
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:staged];
	NSString *rel = nil;
	while ((rel = [en nextObject])) {
		NSString *full = [staged stringByAppendingPathComponent:rel];
		if (!ESIsMachO(full)) continue;
		NSMutableArray *args = [NSMutableArray array];
		[args addObject:[@"-K" stringByAppendingString:p12]];
		if (ents) [args addObject:[@"-S" stringByAppendingString:ents]];
		[args addObject:full];
		if (ESRun(ldid, args)) signedCount++;
		[self logLine:[NSString stringWithFormat:@"② 伪造签名 %@", rel]];
	}
	ESFixPerms(staged);
	[self logLine:[NSString stringWithFormat:@"③ 已签 %lu 个二进制", (unsigned long)signedCount]];
	if (signedCount == 0) {
		[self logLine:@"没有可签名的二进制，终止"];
		return NO;
	}

	NSString *containerPath = ESBundleContainerPath(@"com.hjm.eversign", YES);
	if (!containerPath) {
		[self logLine:@"④ 无法创建应用容器"];
		return NO;
	}
	[self logLine:[NSString stringWithFormat:@"④ 容器: %@", containerPath]];

	NSString *dest = [containerPath stringByAppendingPathComponent:@"EverSign.app"];
	if ([fm fileExistsAtPath:dest]) [fm removeItemAtPath:dest error:nil];
	if (![fm copyItemAtPath:staged toPath:dest error:&err]) {
		[self logLine:[NSString stringWithFormat:@"写入容器失败: %@", err.localizedDescription]];
		return NO;
	}
	ESFixPerms(dest);
	[fm removeItemAtPath:work error:nil];

	NSDictionary *entsDict = ESReadPlist(ents);
	BOOL ok = ESRegisterSystemApp(dest, entsDict);
	[self logLine:ok ? @"⑤ 已注册为系统应用，回桌面看「永签」" : @"⑤ 注册失败"];
	return ok;
}

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
