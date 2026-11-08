#import "ESZip.h"
#import <zlib.h>

#define RD16(p) ((uint16_t)((uint8_t)(p)[0] | ((uint16_t)(uint8_t)(p)[1] << 8)))
#define RD32(p) ((uint32_t)((uint8_t)(p)[0] | ((uint32_t)(uint8_t)(p)[1] << 8) | ((uint32_t)(uint8_t)(p)[2] << 16) | ((uint32_t)(uint8_t)(p)[3] << 24)))

static BOOL ESInflateRaw(const uint8_t *src, size_t srcLen, uint8_t *dst, size_t dstLen) {
	z_stream zs;
	memset(&zs, 0, sizeof(zs));
	if (inflateInit2(&zs, -MAX_WBITS) != Z_OK) return NO;
	zs.next_in = (Bytef *)src;
	zs.avail_in = (uInt)srcLen;
	zs.next_out = (Bytef *)dst;
	zs.avail_out = (uInt)dstLen;
	int ret = inflate(&zs, Z_FINISH);
	inflateEnd(&zs);
	return (ret == Z_STREAM_END || ret == Z_OK);
}

@implementation ESZip

+ (BOOL)extractArchiveAtPath:(NSString *)zipPath toDirectory:(NSString *)destDir error:(NSError **)error {
	NSData *data = [NSData dataWithContentsOfFile:zipPath options:NSDataReadingMappedIfSafe error:error];
	if (!data || data.length < 22) return NO;

	const uint8_t *bytes = (const uint8_t *)data.bytes;
	size_t len = data.length;

	// locate end of central directory
	size_t eocd = SIZE_MAX;
	size_t scanStart = (len > 65557) ? (len - 65557) : 0;
	for (size_t i = len - 22; i >= scanStart && i != SIZE_MAX; i--) {
		if (RD32(bytes + i) == 0x06054b50) { eocd = i; break; }
		if (i == 0) break;
	}
	if (eocd == SIZE_MAX) {
		if (error) *error = [NSError errorWithDomain:@"ESZip" code:1 userInfo:@{NSLocalizedDescriptionKey: @"找不到 zip 目录结尾"}];
		return NO;
	}

	uint16_t count = RD16(bytes + eocd + 10);
	uint32_t cdOffset = RD32(bytes + eocd + 16);
	if (cdOffset >= len) return NO;

	NSFileManager *fm = [NSFileManager defaultManager];
	[fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];

	size_t p = cdOffset;
	for (uint16_t i = 0; i < count; i++) {
		if (p + 46 > len || RD32(bytes + p) != 0x02014b50) break;

		uint16_t method = RD16(bytes + p + 10);
		uint32_t csize = RD32(bytes + p + 20);
		uint32_t usize = RD32(bytes + p + 24);
		uint16_t nameLen = RD16(bytes + p + 28);
		uint16_t extraLen = RD16(bytes + p + 30);
		uint16_t commentLen = RD16(bytes + p + 32);
		uint32_t localOff = RD32(bytes + p + 42);

		if (p + 46 + nameLen > len) break;
		NSString *name = [[NSString alloc] initWithBytes:bytes + p + 46 length:nameLen encoding:NSUTF8StringEncoding];
		p += 46 + nameLen + extraLen + commentLen;

		if (name.length == 0) continue;
		if (localOff + 30 > len || RD32(bytes + localOff) != 0x04034b50) continue;

		uint16_t lNameLen = RD16(bytes + localOff + 26);
		uint16_t lExtraLen = RD16(bytes + localOff + 28);
		size_t dataStart = localOff + 30 + lNameLen + lExtraLen;
		if (dataStart + csize > len) continue;

		NSString *full = [destDir stringByAppendingPathComponent:name];

		if (usize == 0 && csize == 0) {
			[fm createDirectoryAtPath:full withIntermediateDirectories:YES attributes:nil error:nil];
			continue;
		}

		[fm createDirectoryAtPath:[full stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

		NSData *out = nil;
		if (method == 0) {
			out = [NSData dataWithBytes:bytes + dataStart length:csize];
		} else if (method == 8) {
			NSMutableData *buf = [NSMutableData dataWithLength:usize];
			if (!ESInflateRaw(bytes + dataStart, csize, (uint8_t *)buf.mutableBytes, usize)) {
				if (error) *error = [NSError errorWithDomain:@"ESZip" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"解压失败: %@", name]}];
				return NO;
			}
			out = buf;
		} else {
			continue;
		}

		if (![out writeToFile:full options:NSDataWritingAtomic error:error]) return NO;
	}

	return YES;
}

@end
