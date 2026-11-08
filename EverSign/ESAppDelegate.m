#import "ESAppDelegate.h"
#import "ESRootController.h"
#import "ESTheme.h"

@implementation ESAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.backgroundColor = ESColorBg();
	self.window.rootViewController = [[ESRootController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

@end
