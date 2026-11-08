#import <Foundation/Foundation.h>

@interface ESInstaller : NSObject

@property (nonatomic, copy) void (^progressHandler)(double fraction, NSString *stage);

+ (instancetype)shared;

// Installs an IPA permanently into /Applications using the CoreTrust signature flaw.
- (void)installIPAAtURL:(NSURL *)ipaURL
              completion:(void (^)(BOOL ok, NSString *message))completion;

- (NSArray<NSDictionary *> *)enumerateInstalledApplications;

@end
