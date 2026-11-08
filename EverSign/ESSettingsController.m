#import "ESSettingsController.h"
#import "ESInstaller.h"
#import "ESTheme.h"
#import <sys/utsname.h>

@interface ESSettingsController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *rows;
@property (nonatomic, strong) UILabel *toast;
@end

@implementation ESSettingsController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = ESColorBg();

	struct utsname u;
	uname(&u);
	NSString *model = [NSString stringWithUTF8String:u.machine];
	NSString *ver = [[NSProcessInfo processInfo] operatingSystemVersionString];

	self.rows = @[
		@{ @"t": @"设备", @"s": [NSString stringWithFormat:@"%@ · %@", model, ver], @"k": @"info" },
		@{ @"t": @"签名方式", @"s": @"CoreTrust 伪造签名 (CVE-2023-41991)", @"k": @"info" },
		@{ @"t": @"接管「提示」", @"s": @"替换为持久助手，图标缓存刷新后可恢复", @"k": @"plant" },
		@{ @"t": @"恢复「提示」", @"s": @"还原系统 App 原始二进制", @"k": @"restore" },
		@{ @"t": @"扩展权限注入", @"s": @"platform-application / no-sandbox", @"k": @"boost" },
		@{ @"t": @"JIT 支持", @"s": @"给应用附加 dynamic-codesigning / get-task-allow", @"k": @"jit" },
		@{ @"t": @"重建图标缓存", @"s": @"重新注册 /Applications 下所有应用", @"k": @"cache" },
	];

	UILabel *title = [[UILabel alloc] init];
	title.text = @"设置";
	title.font = ESFontBold(34);
	title.textColor = ESColorText();
	title.frame = CGRectMake(24, 24, 200, 42);
	[self.view addSubview:title];

	self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 84, self.view.bounds.size.width, 460) style:UITableViewStylePlain];
	self.table.backgroundColor = UIColor.clearColor;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.dataSource = self;
	self.table.delegate = self;
	[self.view addSubview:self.table];

	self.toast = [[UILabel alloc] initWithFrame:CGRectMake(24, 556, self.view.bounds.size.width - 48, 60)];
	self.toast.numberOfLines = 0;
	self.toast.font = ESFontReg(12);
	self.toast.textColor = ESColorDim();
	self.toast.text = @"EverSign 1.0.0";
	[self.view addSubview:self.toast];
}

- (void)showToast:(NSString *)text color:(UIColor *)color {
	self.toast.text = text;
	self.toast.textColor = color;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.rows.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 68; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
	NSDictionary *d = self.rows[indexPath.row];
	cell.backgroundColor = ESColorCard();
	cell.textLabel.text = d[@"t"];
	cell.textLabel.textColor = ESColorText();
	cell.textLabel.font = ESFontMed(15);
	cell.detailTextLabel.text = d[@"s"];
	cell.detailTextLabel.textColor = ESColorDim();
	cell.detailTextLabel.font = ESFontReg(11);

	NSString *k = d[@"k"];
	if ([k isEqualToString:@"boost"] || [k isEqualToString:@"jit"]) {
		UISwitch *sw = [[UISwitch alloc] init];
		sw.onTintColor = ESColorAccent();
		sw.on = [k isEqualToString:@"boost"] ? [ESInstaller shared].boostEntitlements
											 : [ESInstaller shared].jitEnabled;
		sw.tag = [k isEqualToString:@"boost"] ? 1 : 2;
		[sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else if ([k isEqualToString:@"info"]) {
		cell.accessoryView = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else {
		cell.accessoryView = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	}
	return cell;
}

- (void)switchChanged:(UISwitch *)sw {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if (sw.tag == 1) {
		[ESInstaller shared].boostEntitlements = sw.on;
		[d setBool:sw.on forKey:@"ESBoostEntitlements"];
		[self showToast:(sw.on ? @"扩展权限注入已开启" : @"扩展权限注入已关闭") color:ESColorAccent()];
	} else {
		[ESInstaller shared].jitEnabled = sw.on;
		[d setBool:sw.on forKey:@"ESJITEnabled"];
		[self showToast:(sw.on ? @"JIT 支持已开启" : @"JIT 支持已关闭") color:ESColorAccent()];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *k = self.rows[indexPath.row][@"k"];
	__weak typeof(self) weakSelf = self;

	if ([k isEqualToString:@"plant"]) {
		[self showToast:@"正在接管「提示」…" color:ESColorDim()];
		[[ESInstaller shared] plantHelperIntoSystemApp:@"Tips" completion:^(BOOL ok, NSString *msg) {
			[weakSelf showToast:msg color:(ok ? ESColorAccent() : ESColorDanger())];
		}];
	} else if ([k isEqualToString:@"restore"]) {
		[self showToast:@"正在恢复「提示」…" color:ESColorDim()];
		[[ESInstaller shared] restoreSystemApp:@"Tips" completion:^(BOOL ok, NSString *msg) {
			[weakSelf showToast:msg color:(ok ? ESColorAccent() : ESColorDanger())];
		}];
	} else if ([k isEqualToString:@"cache"]) {
		[self showToast:@"正在重建图标缓存…" color:ESColorDim()];
		[[ESInstaller shared] rebuildIconCache:^(NSUInteger n) {
			[weakSelf showToast:[NSString stringWithFormat:@"已重新注册 %lu 个应用", (unsigned long)n] color:ESColorAccent()];
		}];
	}
}

@end
