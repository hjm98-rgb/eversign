#import "ESInstaller.h"
#import "ESZip.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <dirent.h>

extern char **environ;

static BOOL ESRunTool(NSString *tool, NSArray<NSString *> *args, NSString **output) {
	const char *argv[16];
	int i = 0;
	argv[i++] = tool.UTF8String;
	for (NSString *a in args) {
		if (i >= 15) break;
		argv[i++] = a.UTF8String;
	}
	argv[i] = NULL;

	int pipefd[2];
	if (pipe(pipefd) != 0) return NO;

	posix_spawn_file_actions_t actions;
	posix_spawn_file_actions_init(&actions);
	posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
	posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
	posix_spawn_file_actions_addclose(&actions, pipefd[0]);

	pid_t pid = 0;
	int rc = posix_spawn(&pid, tool.UTF8String, &actions, NULL, (char *const *)argv, environ);
	posix_spawn_file_actions_destroy(&actions);
	close(pipefd[1]);
	if (rc != 0) { close(pipefd[0]); return NO; }

	NSMutableData *buf = [NSMutableData data];
	char chunk[2048];
	ssize_t n = 0;
	while ((n = read(pipefd[0], chunk, sizeof(chunk))) > 0) {
		[buf appendBytes:chunk length:(NSUInteger)n];
	}
	close(pipefd[0]);

	int status = 0;
	waitpid(pid, &status, 0);
	if (output) *output = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
	return (WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

static BOOL ESIsMachO(NSString *path) {
	FILE *f = fopen(path.fileSystemRepresentation, "rb");
	if (!f) return NO;
	uint32_t magic = 0;
	if (fread(&magic, 1, 4, f) != 4) { fclose(f); return NO; }
	fclose(f);
	return (magic == 0xFEEDFACF || magic == 0xFEEDFACE || magic == 0xBEBAFECA || magic == 0xCAFEBABE);
}

static void ESFixOwnership(NSString *root) {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
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

static void ESRegisterApp(NSString *appPath) {
	Class WS = NSClassFromString(@"LSApplicationWorkspace");
	if (!WS) return;
	id ws = [WS performSelector:@selector(defaultWorkspace)];
	SEL proxySel = NSSelectorFromString(@"applicationProxyForBundleURL:");
	if (![ws respondsToSelector:proxySel]) return;
	id proxy = [ws performSelector:proxySel withObject:[NSURL fileURLWithPath:appPath]];
	if (proxy) [ws performSelector:NSSelectorFromString(@"registerApplication:") withObject:proxy];
}

@implementation ESInstaller

+ (instancetype)shared {
	static ESInstaller *inst = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ inst = [[ESInstaller alloc] init]; });
	return inst;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_boostEntitlements = [[NSUserDefaults standardUserDefaults] boolForKey:@"ESBoostEntitlements"];
		_jitEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"ESJITEnabled"];
	}
	return self;
}

- (NSString *)toolPath {
	return [[NSBundle mainBundle] pathForResource:@"ldid" ofType:nil];
}

- (NSString *)p12Path {
	return [[NSBundle mainBundle] pathForResource:@"victim" ofType:@"p12"];
}

- (NSString *)defaultEntitlementsPath {
	return [[NSBundle mainBundle] pathForResource:@"entitlements" ofType:@"plist"];
}

- (void)report:(double)f stage:(NSString *)s {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.progressHandler) self.progressHandler(f, s);
	});
}

#pragma mark - Entitlements

// 读取二进制里原有的 entitlements；没有就返回空字典
- (NSMutableDictionary *)entitlementsForBinary:(NSString *)binary {
	NSString *out = nil;
	NSString *ldid = [self toolPath];
	if (ldid) ESRunTool(ldid, @[ @"-e", binary ], &out);
	if (!out || ![out containsString:@"<plist"]) return [NSMutableDictionary dictionary];

	NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
	id plist = [NSPropertyListSerialization propertyListWithData:data
														 options:NSPropertyListImmutable
														  format:NULL
														   error:NULL];
	if ([plist isKindOfClass:[NSDictionary class]]) return [plist mutableCopy];
	return [NSMutableDictionary dictionary];
}

// 给某个二进制签名：先取它自己的权限，再按需叠加扩展权限
- (BOOL)signBinary:(NSString *)binary workDir:(NSString *)workDir {
	NSString *ldid = [self toolPath];
	NSString *p12 = [self p12Path];
	if (!ldid) return NO;

	NSMutableDictionary *ents = [self entitlementsForBinary:binary];

	if (self.boostEntitlements) {
		NSDictionary *boost = [NSDictionary dictionaryWithContentsOfFile:[self defaultEntitlementsPath]];
		if (boost) {
			for (NSString *k in boost) {
				if (!ents[k]) ents[k] = boost[k];
			}
		}
	}

	// JIT：dynamic-codesigning 让目标进程可以申请 RWX 内存，get-task-allow 允许被调试器附加
	if (self.jitEnabled) {
		ents[@"dynamic-codesigning"] = @YES;
		ents[@"get-task-allow"] = @YES;
	}

	NSString *entsPath = nil;
	if (ents.count > 0) {
		NSData *xml = [NSPropertyListSerialization dataWithPropertyList:ents
																 format:NSPropertyListXMLFormat_v1_0
																options:0
																  error:NULL];
		if (xml) {
			entsPath = [workDir stringByAppendingPathComponent:@"ents-tmp.plist"];
			[xml writeToFile:entsPath atomically:YES];
		}
	}

	NSMutableArray *args = [NSMutableArray array];
	if (p12) [args addObject:[@"-K" stringByAppendingString:p12]];
	if (entsPath) [args addObject:[@"-S" stringByAppendingString:entsPath]];
	[args addObject:binary];

	NSString *log = nil;
	return ESRunTool(ldid, args, &log);
}

#pragma mark - Install IPA

- (void)installIPAAtURL:(NSURL *)ipaURL completion:(void (^)(BOOL, NSString *))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:
						  [NSString stringWithFormat:@"eversign-%@", [[NSUUID UUID] UUIDString]]];
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];

		[self report:0.05 stage:@"解包中"];
		if (![ESZip extractArchiveAtPath:ipaURL.path toDirectory:work error:&err]) {
			completion(NO, [NSString stringWithFormat:@"解包失败: %@", err.localizedDescription ?: @"未知错误"]);
			return;
		}

		[self report:0.25 stage:@"解析应用"];
		NSString *payload = [work stringByAppendingPathComponent:@"Payload"];
		NSString *appName = nil;
		for (NSString *item in [fm contentsOfDirectoryAtPath:payload error:nil]) {
			if ([item hasSuffix:@".app"]) { appName = item; break; }
		}
		if (!appName) { completion(NO, @"这个 IPA 里没有 Payload/*.app"); return; }

		NSString *srcApp = [payload stringByAppendingPathComponent:appName];
		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[srcApp stringByAppendingPathComponent:@"Info.plist"]];
		NSString *bundleID = info[@"CFBundleIdentifier"];
		if (!bundleID) { completion(NO, @"Info.plist 缺少 BundleIdentifier"); return; }

		[self report:0.4 stage:@"写入系统目录"];
		NSString *destApp = [@"/Applications" stringByAppendingPathComponent:appName];
		if ([fm fileExistsAtPath:destApp]) [fm removeItemAtPath:destApp error:nil];
		if (![fm copyItemAtPath:srcApp toPath:destApp error:&err]) {
			completion(NO, [NSString stringWithFormat:@"写入 /Applications 失败（无权限）: %@", err.localizedDescription]);
			return;
		}

		[self report:0.55 stage:@"修正权限"];
		ESFixOwnership(destApp);

		[self report:0.65 stage:@"伪造签名"];
		NSDirectoryEnumerator *en = [fm enumeratorAtPath:destApp];
		NSString *rel = nil;
		NSUInteger signedCount = 0;
		while ((rel = [en nextObject])) {
			NSString *full = [destApp stringByAppendingPathComponent:rel];
			if (ESIsMachO(full)) {
				[self signBinary:full workDir:work];
				ESFixOwnership(full);
				signedCount++;
			}
		}

		[self report:0.85 stage:@"注册应用"];
		ESRegisterApp(destApp);

		[self report:1.0 stage:@"完成"];
		[fm removeItemAtPath:work error:nil];

		NSString *msg = [NSString stringWithFormat:@"%@ 已安装，重签 %lu 个二进制%@",
						 bundleID, (unsigned long)signedCount,
						 self.boostEntitlements ? @"（已附加扩展权限）" : @""];
		completion(YES, msg);
	});
}

#pragma mark - 系统 App 接管

- (void)plantHelperIntoSystemApp:(NSString *)appName completion:(void (^)(BOOL, NSString *))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *appDir = [@"/Applications" stringByAppendingPathComponent:[appName stringByAppendingString:@".app"]];
		if (![fm fileExistsAtPath:appDir]) {
			completion(NO, [NSString stringWithFormat:@"找不到 %@.app", appName]);
			return;
		}

		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appDir stringByAppendingPathComponent:@"Info.plist"]];
		NSString *execName = info[@"CFBundleExecutable"];
		if (!execName) execName = appName;
		NSString *targetBinary = [appDir stringByAppendingPathComponent:execName];
		NSString *backup = [targetBinary stringByAppendingString:@".es-original"];

		NSString *helperSrc = [[NSBundle mainBundle] pathForResource:@"ESHelper" ofType:nil];
		if (!helperSrc) { completion(NO, @"App 内缺少助手二进制 ESHelper"); return; }

		if (![fm fileExistsAtPath:backup]) {
			[fm copyItemAtPath:targetBinary toPath:backup error:nil];
		}

		if (![fm copyItemAtPath:helperSrc toPath:targetBinary error:nil]) {
			completion(NO, @"写入失败：没有对系统 App 目录的写权限");
			return;
		}
		chown(targetBinary.fileSystemRepresentation, 0, 0);
		chmod(targetBinary.fileSystemRepresentation, 0755);

		BOOL ok = [self signBinary:targetBinary workDir:NSTemporaryDirectory()];
		if (!ok) {
			// 签名失败就还原，避免把「提示」弄坏
			[fm removeItemAtPath:targetBinary error:nil];
			[fm copyItemAtPath:backup toPath:targetBinary error:nil];
			chmod(targetBinary.fileSystemRepresentation, 0755);
			completion(NO, @"签名失败，已还原原始 App");
			return;
		}

		ESRegisterApp(appDir);
		completion(YES, [NSString stringWithFormat:@"「%@」已被接管为持久助手", appName]);
	});
}

- (void)restoreSystemApp:(NSString *)appName completion:(void (^)(BOOL, NSString *))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *appDir = [@"/Applications" stringByAppendingPathComponent:[appName stringByAppendingString:@".app"]];
		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appDir stringByAppendingPathComponent:@"Info.plist"]];
		NSString *execName = info[@"CFBundleExecutable"] ?: appName;
		NSString *targetBinary = [appDir stringByAppendingPathComponent:execName];
		NSString *backup = [targetBinary stringByAppendingString:@".es-original"];

		if (![fm fileExistsAtPath:backup]) {
			completion(NO, @"没有找到备份，可能本来就没接管过");
			return;
		}
		[fm removeItemAtPath:targetBinary error:nil];
		[fm copyItemAtPath:backup toPath:targetBinary error:nil];
		chmod(targetBinary.fileSystemRepresentation, 0755);
		ESRegisterApp(appDir);
		completion(YES, [NSString stringWithFormat:@"「%@」已恢复原版", appName]);
	});
}

- (void)rebuildIconCache:(void (^)(NSUInteger))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSMutableArray *apps = [NSMutableArray array];
		NSFileManager *fm = [NSFileManager defaultManager];
		for (NSString *item in [fm contentsOfDirectoryAtPath:@"/Applications" error:nil]) {
			if ([item hasSuffix:@".app"]) [apps addObject:item];
		}
		for (NSString *item in apps) {
			ESRegisterApp([@"/Applications" stringByAppendingPathComponent:item]);
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(apps.count);
		});
	});
}

- (NSArray<NSDictionary *> *)enumerateInstalledApplications {
	NSMutableArray *out = [NSMutableArray array];
	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *item in [fm contentsOfDirectoryAtPath:@"/Applications" error:nil]) {
		if (![item hasSuffix:@".app"]) continue;
		NSString *full = [@"/Applications" stringByAppendingPathComponent:item];
		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[full stringByAppendingPathComponent:@"Info.plist"]];
		NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: [item stringByDeletingPathExtension];
		NSString *bid = info[@"CFBundleIdentifier"] ?: @"";
		[out addObject:@{ @"name": name, @"bundleID": bid, @"path": full }];
	}
	return out;
}

@end
