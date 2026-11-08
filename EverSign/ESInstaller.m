#import "ESInstaller.h"
#import "ESZip.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <dlfcn.h>
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
	char chunk[1024];
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
		if (S_ISDIR(st.st_mode)) {
			chmod(full.fileSystemRepresentation, 0755);
		} else if (st.st_mode & 0111) {
			chmod(full.fileSystemRepresentation, 0755);
		} else {
			chmod(full.fileSystemRepresentation, 0644);
		}
	}
}

@implementation ESInstaller

+ (instancetype)shared {
	static ESInstaller *inst = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ inst = [[ESInstaller alloc] init]; });
	return inst;
}

- (void)report:(double)f stage:(NSString *)s {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.progressHandler) self.progressHandler(f, s);
	});
}

- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type {
	return [[NSBundle mainBundle] pathForResource:name ofType:type];
}

- (void)installIPAAtURL:(NSURL *)ipaURL completion:(void (^)(BOOL, NSString *))completion {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *err = nil;
		NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:
						  [NSString stringWithFormat:@"eversign-%@", [[NSUUID UUID] UUIDString]]];
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];

		[self report:0.05 stage:@"解包中"];
		BOOL ok = [ESZip extractArchiveAtPath:ipaURL.path toDirectory:work error:&err];
		if (!ok) {
			completion(NO, [NSString stringWithFormat:@"解包失败: %@", err.localizedDescription ?: @"未知错误"]);
			return;
		}

		[self report:0.25 stage:@"解析应用"];
		NSString *payload = [work stringByAppendingPathComponent:@"Payload"];
		NSString *appName = nil;
		for (NSString *item in [fm contentsOfDirectoryAtPath:payload error:nil]) {
			if ([item hasSuffix:@".app"]) { appName = item; break; }
		}
		if (!appName) {
			completion(NO, @"这个 IPA 里没有 Payload/*.app");
			return;
		}

		NSString *srcApp = [payload stringByAppendingPathComponent:appName];
		NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[srcApp stringByAppendingPathComponent:@"Info.plist"]];
		NSString *bundleID = info[@"CFBundleIdentifier"];
		NSString *execName = info[@"CFBundleExecutable"];
		if (!bundleID || !execName) {
			completion(NO, @"Info.plist 缺少 BundleIdentifier / Executable");
			return;
		}

		[self report:0.4 stage:@"写入系统目录"];
		NSString *destApp = [@"/Applications" stringByAppendingPathComponent:appName];
		if ([fm fileExistsAtPath:destApp]) {
			[fm removeItemAtPath:destApp error:nil];
		}
		if (![fm copyItemAtPath:srcApp toPath:destApp error:&err]) {
			completion(NO, [NSString stringWithFormat:@"写入 /Applications 失败（无权限）: %@", err.localizedDescription]);
			return;
		}

		[self report:0.55 stage:@"修正权限"];
		ESFixOwnership(destApp);

		[self report:0.65 stage:@"伪造签名"];
		NSString *ldidPath = [self pathForResource:@"ldid" ofType:nil];
		NSString *p12Path = [self pathForResource:@"victim" ofType:@"p12"];
		NSString *entsPath = [self pathForResource:@"entitlements" ofType:@"plist"];
		if (!ldidPath) {
			completion(NO, @"App 内缺少签名组件 ldid");
			return;
		}

		NSDirectoryEnumerator *en = [fm enumeratorAtPath:destApp];
		NSString *rel = nil;
		NSUInteger signedCount = 0;
		while ((rel = [en nextObject])) {
			NSString *full = [destApp stringByAppendingPathComponent:rel];
			if (ESIsMachO(full)) {
				NSMutableArray *args = [NSMutableArray array];
				if (p12Path) [args addObject:[@"-K" stringByAppendingString:p12Path]];
				if (entsPath) [args addObject:[@"-S" stringByAppendingString:entsPath]];
				[args addObject:full];
				NSString *log = nil;
				ESRunTool(ldidPath, args, &log);
				signedCount++;
			}
		}

		[self report:0.85 stage:@"注册应用"];
		Class WS = NSClassFromString(@"LSApplicationWorkspace");
		if (WS) {
			id ws = [WS performSelector:@selector(defaultWorkspace)];
			SEL sel = NSSelectorFromString(@"applicationProxyForBundleURL:");
			if ([ws respondsToSelector:sel]) {
				id proxy = [ws performSelector:sel withObject:[NSURL fileURLWithPath:destApp]];
				if (proxy) {
					[ws performSelector:NSSelectorFromString(@"registerApplication:") withObject:proxy];
				}
			}
		}

		[self report:1.0 stage:@"完成"];
		[fm removeItemAtPath:work error:nil];

		NSString *msg = [NSString stringWithFormat:@"%@ 已安装，签名 %lu 个二进制", bundleID, (unsigned long)signedCount];
		completion(YES, msg);
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
