#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Tweak.h"

#define maxRetryCount 3
#define apiUrl @"https://returnyoutubedislikeapi.com"
#define UserIDKey @"RYD-USER-ID"
#define RegistrationConfirmedKey @"RYD-USER-REGISTERED"
#define FETCHING @"Fetching"

static NSCache <NSString *, NSString *> *cache;

enum YTLikeStatus : int {
    YTLikeStatusLike = 0,
    YTLikeStatusDislike = 1,
    YTLikeStatusNeutral = 2
};

static int toRYDLikeStatus(YTLikeStatus likeStatus) {
    switch (likeStatus) {
        case YTLikeStatusLike:
            return 1;
        case YTLikeStatusDislike:
            return -1;
        default:
            return 0;
    }
}

static NSString *getUserID() {
    return [[NSUserDefaults standardUserDefaults] stringForKey:UserIDKey];
}

static BOOL isRegistered() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:RegistrationConfirmedKey];
}

static NSString *generateUserID() {
    NSString *existingID = getUserID();
    if (existingID) {
        return existingID;
    }
    HBLogDebug(@"generateUserID()");
    static const char *charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    char userID[36 + 1];
    for (int i = 0; i < 36; ++i) {
        userID[i] = charset[arc4random_uniform(36)];
    }
    userID[36] = '\0';
    NSString *result = [NSString stringWithUTF8String:userID];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:result forKey:UserIDKey];
    [defaults synchronize];
    return result;
}

static int countLeadingZeroes(uint8_t *uInt8View) {
    int zeroes = 0;
    int value = 0;
    for (int i = 0; i < CC_SHA512_DIGEST_LENGTH; i++) {
        value = uInt8View[i];
        if (value == 0) {
            zeroes += 8;
        } else {
            int count = 1;
            if (value >> 4 == 0) {
                count += 4;
                value <<= 4;
            }
            if (value >> 6 == 0) {
                count += 2;
                value <<= 2;
            }
            zeroes += count - (value >> 7);
            break;
        }
    }
    return zeroes;
}

static NSString *btoa(NSString *input) {
    static const char *chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    NSMutableString *output = [NSMutableString string];
    for (int i = 0; i < input.length; i += 3) {
        int groupsOfSix[4] = { -1, -1, -1, -1 };
        groupsOfSix[0] = [input characterAtIndex:i] >> 2;
        groupsOfSix[1] = ([input characterAtIndex:i] & 0x03) << 4;
        if (input.length > i + 1) {
            groupsOfSix[1] |= [input characterAtIndex:i + 1] >> 4;
            groupsOfSix[2] = ([input characterAtIndex:i + 1] & 0x0f) << 2;
        }
        if (input.length > i + 2) {
            groupsOfSix[2] |= [input characterAtIndex:i + 2] >> 6;
            groupsOfSix[3] = [input characterAtIndex:i + 2] & 0x3f;
        }
        for (int j = 0; j < 4; ++j) {
            if (groupsOfSix[j] == -1) {
                [output appendString:@"="];
            } else {
                [output appendFormat:@"%c", chars[groupsOfSix[j]]];
            }
        }
    }
    return output;
}

static void fetch(
    NSString *endpoint,
    NSString *method,
    NSDictionary *body,
    void (^dataHandler)(NSDictionary *data),
    BOOL (^responseCodeHandler)(NSUInteger responseCode),
    void (^networkErrorHandler)(),
    void (^dataErrorHandler)()
) {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", apiUrl, endpoint]];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    urlRequest.HTTPMethod = method;
    if (body) {
        [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingPrettyPrinted error:&error];
        if (error) {
            if (dataErrorHandler) {
                dataErrorHandler();
            }
            return;
        }
        HBLogDebug(@"fetch() POST body: %@", [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil]);
        urlRequest.HTTPBody = data;
    } else {
        [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    }
    [[session dataTaskWithRequest:urlRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (responseCodeHandler) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSUInteger responseCode = [httpResponse statusCode];
            if (!responseCodeHandler(responseCode)) {
                return;
            }
        }
        if (error) {
            if (networkErrorHandler) {
                networkErrorHandler();
            }
            return;
        }
        NSError *jsonError;
        NSDictionary *myData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&jsonError];
        if (jsonError) {
            HBLogDebug(@"fetch() error decoding response: %@", jsonError);
            if (dataErrorHandler) {
                dataErrorHandler();
            }
            return;
        }
        dataHandler(myData);
    }] resume];
}

static NSString *solvePuzzle(NSDictionary *data) {
    NSString *solution = nil;
    NSString *challenge = data[@"challenge"];
    int difficulty = [data[@"difficulty"] intValue];
    NSData *cd = [[NSData alloc] initWithBase64EncodedString:challenge options:0];
    NSString *decoded = [[NSString alloc] initWithData:cd encoding:NSASCIIStringEncoding];
    uint8_t c[decoded.length];
    char *buffer = (char *)calloc(20, sizeof(char));
    uint32_t *uInt32View = (uint32_t *)buffer;
    for (int i = 0; i < decoded.length; ++i) {
        c[i] = [decoded characterAtIndex:i];
    }
    int maxCount = pow(2, difficulty) * 5;
    for (int i = 4; i < 20; ++i) {
        buffer[i] = c[i - 4];
    }
    for (int i = 0; i < maxCount; ++i) {
        uInt32View[0] = i;
        uint8_t hash[CC_SHA512_DIGEST_LENGTH] = {0};
        CC_SHA512(buffer, 20, hash);
        if (countLeadingZeroes(hash) >= difficulty) {
            unichar chars[4] = { buffer[0], buffer[1], buffer[2], buffer[3] };
            NSString *s = [[NSString alloc] initWithBytes:chars length:4 encoding:NSASCIIStringEncoding];
            solution = btoa(s);
            HBLogDebug(@"solvePuzzle() success (%@)", solution);
        }
    }
    free(buffer);
    HBLogDebug(@"solvePuzzle() failed");
    return solution;
}

static void registerUser() {
    NSString *userId = generateUserID();
    HBLogDebug(@"registerUser() (%@)", userId);
    NSString *puzzleEndpoint = [NSString stringWithFormat:@"/puzzle/registration?userId=%@", userId];
    fetch(
        puzzleEndpoint,
        @"GET",
        nil,
        ^(NSDictionary *data) {
            NSString *solution = solvePuzzle(data);
            if (!solution) {
                HBLogDebug(@"registerUser() skipped");
                return;
            }
            fetch(
                puzzleEndpoint,
                @"POST",
                @{ @"solution": solution },
                ^(NSDictionary *data) {
                    if (!isRegistered()) {
                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:RegistrationConfirmedKey];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                    }
                    HBLogDebug(@"registerUser() success or already registered");
                },
                NULL,
                ^() {
                    HBLogDebug(@"registerUser() puzzle failed (network)");
                },
                ^() {
                    HBLogDebug(@"registerUser() puzzle failed (data)");
                }
            );
        },
        NULL,
        ^() {
            HBLogDebug(@"registerUser() failed (network)");
        },
        ^() {
            HBLogDebug(@"registerUser() failed (data)");
        }
    );
}

static void sendVote(NSString *videoId, YTLikeStatus s) {
    NSString *userId = getUserID();
    if (!userId || !isRegistered()) {
        registerUser();
        return;
    }
    int likeStatus = toRYDLikeStatus(s);
    HBLogDebug(@"sendVote(%@, %d)", videoId, likeStatus);
    fetch(
        @"/interact/vote",
        @"POST",
        @{
            @"userId": userId,
            @"videoId": videoId,
            @"value": @(likeStatus)
        },
        ^(NSDictionary *data) {
            NSString *solution = solvePuzzle(data);
            if (!solution) {
                HBLogDebug(@"sendVote() skipped");
                return;
            }
            fetch(
                @"/interact/confirmVote",
                @"POST",
                @{
                    @"userId": userId,
                    @"videoId": videoId,
                    @"solution": solution
                },
                ^(NSDictionary *data) {
                    HBLogDebug(@"sendVote() success");
                },
                NULL,
                ^() {
                    HBLogDebug(@"sendVote() confirm failed (network)");
                },
                ^() {
                    HBLogDebug(@"sendVote() confirm failed (data)");
                }
            );
        },
        ^BOOL(NSUInteger responseCode) {
            if (responseCode == 401) {
                HBLogDebug(@"sendVote() error 401, trying again");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        sendVote(videoId, s);
                    });
                });
                return NO;
            }
            return YES;
        },
        ^() {
            HBLogDebug(@"sendVote() failed (network)");
        },
        ^() {
            HBLogDebug(@"sendVote() failed (data)");
        }
    );
}

static NSString *getXPointYFormat(NSString *count, char c) {
    char firstInt = [count characterAtIndex:0];
    char secondInt = [count characterAtIndex:1];
    if (secondInt == '0') {
        return [NSString stringWithFormat:@"%c%c", firstInt, c];
    }
    return [NSString stringWithFormat:@"%c.%c%c", firstInt, secondInt, c];
}

static NSString *getNormalizedDislikes(NSString *dislikeCount, BOOL isNumber) {
    if (!dislikeCount) {
        return @"Failed";
    }
    NSUInteger digits = dislikeCount.length;
    if (digits <= 3 || !isNumber) { // 0 - 999
        return dislikeCount;
    }
    if (digits == 4) { // 1000 - 9999
        return getXPointYFormat(dislikeCount, 'K');
    }
    if (digits <= 6) { // 10_000 - 999_999
        return [NSString stringWithFormat:@"%@K", [dislikeCount substringToIndex:digits - 3]];
    }
    if (digits <= 9) { // 1_000_000 - 999_999_999
        return [NSString stringWithFormat:@"%@M", [dislikeCount substringToIndex:digits - 6]];
    }
    return [NSString stringWithFormat:@"%@B", [dislikeCount substringToIndex:digits - 9]]; // 1_000_000_000+
}

static void setDislikeCount(YTSlimVideoDetailsActionView *self, NSString *dislikeCount) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:dislikeCount]];
        [self.label sizeToFit];
    });
}

static void getDislikeFromVideoWithHandler(NSString *videoId, int retryCount, void (^handler)(NSString *dislikeCount, BOOL isNumber)) {
    if (retryCount <= 0) {
        return;
    }
    if ([cache objectForKey:videoId]) {
        handler([cache objectForKey:videoId], YES);
        return;
    }
    fetch(
        [NSString stringWithFormat:@"/votes?videoId=%@", videoId],
        @"GET",
        nil,
        ^(NSDictionary *data) {
            NSString *dislikeCount = [NSString stringWithFormat:@"%@", [data objectForKey:@"dislikes"]];
            [cache setObject:dislikeCount forKey:videoId];
            handler(dislikeCount, YES);
        },
        ^BOOL(NSUInteger responseCode) {
            if (responseCode == 502 || responseCode == 503) {
                handler(@"CON", NO); // connection error
                return NO;
            }
            if (responseCode == 401 || responseCode == 403 || responseCode == 407) {
                handler(@"AUTH", NO); // unauthorized
                return NO;
            }
            if (responseCode == 429) {
                handler(@"RL", NO); // rate limit
                return NO;
            }
            if (responseCode == 404) {
                handler(@"NULL", NO); // non-existing video
                return NO;
            }
            if (responseCode == 400) {
                handler(@"INV", NO); // malformed video
                return NO;
            }
            return YES;
        },
        ^() {
            handler(nil, NO);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                getDislikeFromVideoWithHandler(videoId, retryCount - 1, handler);
            });
        },
        ^() {
            handler(nil, NO);
        }
    );
}

%hook YTSlimVideoDetailsActionView

+ (YTSlimVideoDetailsActionView *)actionViewWithSlimMetadataButtonSupportedRenderer:(YTISlimMetadataButtonSupportedRenderers *)renderer withElementsContextBlock:(id)block {
    if ([renderer rendererOneOfCase] == 153515154) {
        return [[%c(YTSlimVideoDetailsActionView) alloc] initWithSlimMetadataButtonSupportedRenderer:renderer];
    }
    return %orig;
}

- (id)initWithSlimMetadataButtonSupportedRenderer:(id)arg1 {
    self = %orig;
    if (self) {
        YTISlimMetadataButtonSupportedRenderers *renderer = [self valueForKey:@"_supportedRenderer"];
        if ([renderer slimButton_isDislikeButton]) {
            YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
            getDislikeFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSString *dislikeCount, BOOL isNumber) {
                setDislikeCount(self, getNormalizedDislikes(dislikeCount, isNumber));
            });
        }
    }
    return self;
}

- (void)setToggled:(BOOL)toggled {
    YTISlimMetadataButtonSupportedRenderers *renderer = [self valueForKey:@"_supportedRenderer"];
    BOOL isLikeButton = [renderer slimButton_isLikeButton];
    BOOL isDislikeButton = [renderer slimButton_isDislikeButton];
    YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
    NSString *videoId = meta.target.videoId;
    BOOL changed = NO;
    changed = self.toggled != toggled;
    if (isDislikeButton) {
        YTIToggleButtonRenderer *buttonRenderer = meta.button.toggleButtonRenderer;
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:FETCHING];
        buttonRenderer.toggledText = formattedText;
        buttonRenderer.defaultText = formattedText;
    }
    %orig;
    if (changed) {
        if (isDislikeButton) {
            sendVote(videoId, toggled ? YTLikeStatusDislike : YTLikeStatusNeutral);
            getDislikeFromVideoWithHandler(videoId, maxRetryCount, ^(NSString *dislikeCount, BOOL isNumber) {
                NSString *response = getNormalizedDislikes(dislikeCount, isNumber);
                YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:response];
                [self.label setFormattedString:formattedText];
                [self setNeedsLayout];
            });
        } else if (isLikeButton) {
            sendVote(videoId, toggled ? YTLikeStatusLike : YTLikeStatusNeutral);
        }
    }
}

%end

%hook YTReelWatchLikesController

- (void)updateLikeButtonWithRenderer:(YTILikeButtonRenderer *)renderer {
    %orig;
    YTQTMButton *dislikeButton = self.dislikeButton;
    [dislikeButton setTitle:FETCHING forState:UIControlStateNormal];
    [dislikeButton setTitle:FETCHING forState:UIControlStateSelected];
    getDislikeFromVideoWithHandler(renderer.target.videoId, maxRetryCount, ^(NSString *dislikeCount, BOOL isNumber) {
        if (dislikeCount) {
            NSString *formattedDislikeCount = getNormalizedDislikes(dislikeCount, isNumber);
            YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedDislikeCount];
            if (renderer.hasDislikeCountText) {
                renderer.dislikeCountText = formattedText;
            }
            if (renderer.hasDislikeCountWithDislikeText) {
                renderer.dislikeCountWithDislikeText = formattedText;
            }
            if (renderer.hasDislikeCountWithUndislikeText) {
                renderer.dislikeCountWithUndislikeText = formattedText;
            }
            int likeStatus = renderer.likeStatus;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (likeStatus == 1) {
                    [dislikeButton setTitle:[renderer.dislikeCountWithUndislikeText stringWithFormattingRemoved] forState:UIControlStateNormal];
                    [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateSelected];
                } else {
                    [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateNormal];
                    [dislikeButton setTitle:[renderer.dislikeCountWithDislikeText stringWithFormattingRemoved] forState:UIControlStateSelected];
                }
            });
        }
    });
}

- (void)triggerServiceEndpointForLikeButtonRenderer:(YTILikeButtonRenderer *)renderer forRequestID:(id)requestID withLikeStatus:(YTLikeStatus)likeStatus {
    sendVote(renderer.target.videoId, likeStatus);
    %orig;
}

%end

%ctor {
    cache = [NSCache new];
}