#import "ESInstalledController.h"
#import "ESInstaller.h"
#import "ESTheme.h"

@interface ESInstalledController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@end

@implementation ESInstalledController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = ESColorBg();

	UILabel *title = [[UILabel alloc] init];
	title.text = @"已安装";
	title.font = ESFontBold(34);
	title.textColor = ESColorText();
	title.frame = CGRectMake(24, 24, 200, 42);
	[self.view addSubview:title];

	self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 84, self.view.bounds.size.width, self.view.bounds.size.height - 150)
												 style:UITableViewStylePlain];
	self.table.backgroundColor = UIColor.clearColor;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.dataSource = self;
	self.table.delegate = self;
	[self.view addSubview:self.table];

	[self reload];
}

- (void)reload {
	self.items = [[ESInstaller shared] enumerateInstalledApplications];
	[self.table reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 68;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];

	NSDictionary *d = self.items[indexPath.row];
	cell.backgroundColor = ESColorCard();
	cell.textLabel.text = d[@"name"];
	cell.textLabel.textColor = ESColorText();
	cell.textLabel.font = ESFontMed(15);
	cell.detailTextLabel.text = d[@"bundleID"];
	cell.detailTextLabel.textColor = ESColorDim();
	cell.detailTextLabel.font = ESFontReg(11);
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = [UIImage systemImageNamed:@"app.dashed"];
	cell.imageView.tintColor = ESColorAccent();
	return cell;
}

@end
