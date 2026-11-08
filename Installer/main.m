#import <unistd.h>
#import <UIKit/UIKit.h>

static NSString *const ESLogPath = @"/var/mobile/Documents/eversign_launch.log";

static void ESBootLog(NSString *msg) {
	NSMutableString *line = [NSMutableString string];
	NSDateFormatter *df = [[NSDateFormatter alloc] init];
	[df setDateFormat:@"HH:mm:ss"];
	[line appendFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];
	NSString *old = [NSString stringWithContentsOfFile:ESLogPath encoding:NSUTF8StringEncoding error:NULL];
	NSString *all = old ? [old stringByAppendingString:line] : line;
	[all writeToFile:ESLogPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		ESBootLog([NSString stringWithFormat:@"main 进入 pid=%d", getpid()]);
		@try {
			int rc = UIApplicationMain(argc, argv, nil, @"ESInstallAppDelegate");
			ESBootLog([NSString stringWithFormat:@"UIApplicationMain 返回 %d", rc]);
			return rc;
		} @catch (NSException *e) {
			ESBootLog([NSString stringWithFormat:@"异常: %@ %@", e.name, e.reason]);
			return -1;
		}
	}
}
