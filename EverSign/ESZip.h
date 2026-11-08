#import <Foundation/Foundation.h>

// Minimal zip reader (stored + deflate), no external deps beyond libz.
@interface ESZip : NSObject
+ (BOOL)extractArchiveAtPath:(NSString *)zipPath toDirectory:(NSString *)destDir error:(NSError **)error;
@end
