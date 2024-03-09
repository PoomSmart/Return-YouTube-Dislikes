#import "unicode/unum.h"
#import "Vote.h"
#import "API.h"
#import "TweakSettings.h"
#import "../Return-YouTube-Dislikes/API.h"

NSString *formattedLongNumber(NSNumber *number, NSString *error) {
    return error ?: [NSNumberFormatter localizedStringFromNumber:number numberStyle:NSNumberFormatterDecimalStyle];
}

static NSString *getXPointYFormat(NSString *count, char c) {
    char firstInt = [count characterAtIndex:0];
    char secondInt = [count characterAtIndex:1];
    if (secondInt == '0')
        return [NSString stringWithFormat:@"%c%c", firstInt, c];
    return [NSString stringWithFormat:@"%c.%c%c", firstInt, secondInt, c];
}

// https://gist.github.com/danpashin/5951706a6aa25748a7faa1acd5c1db8b
API_AVAILABLE(ios(13))
static NSString *formattedShortNumber(int64_t number) {
    UErrorCode status;
    status = U_ZERO_ERROR;
    NSString *currentLocale = [[[NSLocale preferredLanguages] firstObject] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    UNumberFormat *formatter = unum_open(UNUM_DECIMAL_COMPACT_SHORT, NULL, 0, [currentLocale UTF8String], NULL, &status);
    assert(!U_FAILURE(status));
    status = U_ZERO_ERROR;
    int32_t used = unum_formatInt64(formatter, number, NULL, 0, NULL, &status);
    NSString *resultString = nil;
    if (status == U_BUFFER_OVERFLOW_ERROR) {
        NSUInteger length = sizeof(UChar) * (NSUInteger)used;
        UChar *ustr = (UChar *)CFAllocatorAllocate(kCFAllocatorSystemDefault, (CFIndex)length + 1, 0);
        status = U_ZERO_ERROR;
        unum_formatInt64(formatter, number, ustr, used, NULL, &status);
        resultString = [[NSString alloc] initWithBytesNoCopy:ustr length:length encoding:NSUTF16LittleEndianStringEncoding freeWhenDone:YES];
    }
    unum_close(formatter);
    formatter = NULL;
    return resultString;
}

NSString *getNormalizedDislikes(NSNumber *dislikeNumber, NSString *error) {
    if (!dislikeNumber) return FAILED;
    if (error) return error;
    if (ExactDislikeNumber())
        return formattedLongNumber(dislikeNumber, nil);
    NSString *dislikeCount = [dislikeNumber stringValue];
    NSUInteger digits = dislikeCount.length;
    if (digits <= 3) // 0 - 999
        return dislikeCount;
    if (@available(iOS 13.0, *))
        return formattedShortNumber([dislikeNumber unsignedIntegerValue]);
    if (digits == 4) // 1000 - 9999
        return getXPointYFormat(dislikeCount, 'K');
    if (digits <= 6) // 10_000 - 999_999
        return [NSString stringWithFormat:@"%@K", [dislikeCount substringToIndex:digits - 3]];
    if (digits <= 9) // 1_000_000 - 999_999_999
        return [NSString stringWithFormat:@"%@M", [dislikeCount substringToIndex:digits - 6]];
    return [NSString stringWithFormat:@"%@B", [dislikeCount substringToIndex:digits - 9]]; // 1_000_000_000+
}

void getVoteFromVideoWithHandler(NSCache <NSString *, NSDictionary *> *cache, NSString *videoId, int retryCount, void (^handler)(NSDictionary *d, NSString *error)) {
    if (retryCount <= 0) return;
    NSDictionary *data = [cache objectForKey:videoId];
    if (data) {
        handler(data, nil);
        return;
    }
    fetch(
        [NSString stringWithFormat:@"/votes?videoId=%@", videoId],
        @"GET",
        nil,
        ^(NSDictionary *data) {
            [cache setObject:data forKey:videoId];
            handler(data, nil);
        },
        ^BOOL(NSUInteger responseCode) {
            if (responseCode == 502 || responseCode == 503) {
                handler(nil, @"CON"); // connection error
                return NO;
            }
            if (responseCode == 401 || responseCode == 403 || responseCode == 407) {
                handler(nil, @"AUTH"); // unauthorized
                return NO;
            }
            if (responseCode == 429) {
                handler(nil, @"RL"); // rate limit
                return NO;
            }
            if (responseCode == 404) {
                handler(nil, @"NULL"); // non-existing video
                return NO;
            }
            if (responseCode == 400) {
                handler(nil, @"INV"); // malformed video
                return NO;
            }
            return YES;
        },
        ^() {
            handler(nil, FAILED);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                getVoteFromVideoWithHandler(cache, videoId, retryCount - 1, handler);
            });
        },
        ^() {
            handler(nil, FAILED);
        }
    );
}
