#import <Foundation/Foundation.h>

@interface ESInstaller : NSObject

@property (nonatomic, copy) void (^progressHandler)(double fraction, NSString *stage);
// 开关：给装进去的应用附加 platform-application / no-sandbox 等扩展权限
@property (nonatomic, assign) BOOL boostEntitlements;
// 开关：给装进去的应用附加 JIT 相关权限（dynamic-codesigning / get-task-allow）
@property (nonatomic, assign) BOOL jitEnabled;

+ (instancetype)shared;

- (void)installIPAAtURL:(NSURL *)ipaURL
              completion:(void (^)(BOOL ok, NSString *message))completion;

// 把持久助手植入系统 App（默认「提示」），让它变成可用的特权入口
- (void)plantHelperIntoSystemApp:(NSString *)appName
                      completion:(void (^)(BOOL ok, NSString *message))completion;

// 恢复被替换的系统 App 原始二进制
- (void)restoreSystemApp:(NSString *)appName
               completion:(void (^)(BOOL ok, NSString *message))completion;

- (void)rebuildIconCache:(void (^)(NSUInteger count))completion;

- (NSArray<NSDictionary *> *)enumerateInstalledApplications;

@end
