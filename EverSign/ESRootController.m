#import "ESRootController.h"
#import "ESStoreController.h"
#import "ESInstalledController.h"
#import "ESSettingsController.h"
#import "ESTheme.h"

@implementation ESRootController

- (void)viewDidLoad {
	[super viewDidLoad];

	ESStoreController *store = [[ESStoreController alloc] init];
	store.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"安装" image:[UIImage systemImageNamed:@"square.and.arrow.down"] tag:0];

	ESInstalledController *installed = [[ESInstalledController alloc] init];
	installed.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"已安装" image:[UIImage systemImageNamed:@"square.grid.2x2"] tag:1];

	ESSettingsController *settings = [[ESSettingsController alloc] init];
	settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置" image:[UIImage systemImageNamed:@"gearshape"] tag:2];

	self.viewControllers = @[ store, installed, settings ];

	if (@available(iOS 15.0, *)) {
		UITabBarAppearance *ap = [[UITabBarAppearance alloc] init];
		[ap configureWithOpaqueBackground];
		ap.backgroundColor = ESColorCard();
		ap.shadowColor = ESColorStroke();
		self.tabBar.standardAppearance = ap;
		self.tabBar.scrollEdgeAppearance = ap;
	}
	self.tabBar.tintColor = ESColorAccent();
	self.tabBar.unselectedItemTintColor = ESColorDim();
	self.view.backgroundColor = ESColorBg();
}

- (UIStatusBarStyle)preferredStatusBarStyle {
	return UIStatusBarStyleLightContent;
}

@end
