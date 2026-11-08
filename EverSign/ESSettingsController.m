#import "ESSettingsController.h"
#import "ESTheme.h"
#import <sys/utsname.h>

@interface ESSettingsController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *rows;
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
		@{ @"t": @"设备", @"s": [NSString stringWithFormat:@"%@ · %@", model, ver] },
		@{ @"t": @"签名方式", @"s": @"CoreTrust 伪造签名 (CVE-2023-41991)" },
		@{ @"t": @"安装目录", @"s": @"/Applications" },
		@{ @"t": @"重建图标缓存", @"s": @"点击执行" },
	];

	UILabel *title = [[UILabel alloc] init];
	title.text = @"设置";
	title.font = ESFontBold(34);
	title.textColor = ESColorText();
	title.frame = CGRectMake(24, 24, 200, 42);
	[self.view addSubview:title];

	self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 84, self.view.bounds.size.width, 320) style:UITableViewStylePlain];
	self.table.backgroundColor = UIColor.clearColor;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.dataSource = self;
	self.table.delegate = self;
	[self.view addSubview:self.table];

	UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(24, 430, 300, 20)];
	ver.text = @"EverSign 1.0.0";
	ver.font = ESFontReg(12);
	ver.textColor = ESColorDim();
	[self.view addSubview:ver];
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
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

@end
