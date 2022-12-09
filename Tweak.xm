#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <HBLog.h>
#import "Tweak.h"

#define TWEAK_NAME @"Return YouTube Dislike"
#define maxRetryCount 3
#define apiUrl @"https://returnyoutubedislikeapi.com"
#define UserIDKey @"RYD-USER-ID"
#define RegistrationConfirmedKey @"RYD-USER-REGISTERED"
#define EnableVoteSubmissionKey @"RYD-VOTE-SUBMISSION"
#define ExactLikeKey @"RYD-EXACT-LIKE-NUMBER"
#define ExactDislikeKey @"RYD-EXACT-NUMBER"
#define DidShowEnableVoteSubmissionAlertKey @"RYD-DID-SHOW-VOTE-SUBMISSION-ALERT"
#define FETCHING @"⌛"
#define FAILED @"❌"

#define _LOC(b, x) [b localizedStringForKey:x value:nil table:nil]
#define LOC(x) _LOC(tweakBundle, x)

static const NSInteger RYDSection = 1080;

@interface YTSettingsSectionItemManager (RYD)
- (void)updateRYDSectionWithEntry:(id)entry;
@end

static NSCache <NSString *, NSDictionary *> *cache;

NSBundle *RYDBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"RYD" ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else {
            bundle = [NSBundle bundleWithPath:@"/Library/Application Support/RYD.bundle"];
            if (!bundle)
                bundle = [NSBundle bundleWithPath:@"/var/jb/Library/Application Support/RYD.bundle"];
        }
    });
    return bundle;
}

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

static BOOL VoteSubmissionEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:EnableVoteSubmissionKey];
}

static BOOL ExactLikeNumber() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExactLikeKey];
}

static BOOL ExactDislikeNumber() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExactDislikeKey];
}

static const char *charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Ported to objc from RYD browser extension
static NSString *generateUserID() {
    NSString *existingID = getUserID();
    if (existingID) {
        return existingID;
    }
    HBLogDebug(@"generateUserID()");
    char userID[36 + 1];
    for (int i = 0; i < 36; ++i) {
        userID[i] = charset[arc4random_uniform(64)];
    }
    userID[36] = '\0';
    NSString *result = [NSString stringWithUTF8String:userID];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:result forKey:UserIDKey];
    [defaults synchronize];
    return result;
}

// Ported to objc from RYD browser extension
static int countLeadingZeroes(uint8_t *hash) {
    int zeroes = 0;
    int value = 0;
    for (int i = 0; i < CC_SHA512_DIGEST_LENGTH; i++) {
        value = hash[i];
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

// Ported to objc from RYD browser extension
static NSString *btoa(NSString *input) {
    NSMutableString *output = [NSMutableString string];
    for (int i = 0; i < input.length; i += 3) {
        int groupsOfSix[4] = { -1, -1, -1, -1 };
        unichar ci = [input characterAtIndex:i];
        groupsOfSix[0] = ci >> 2;
        groupsOfSix[1] = (ci & 0x03) << 4;
        if (input.length > i + 1) {
            unichar ci1 = [input characterAtIndex:i + 1];
            groupsOfSix[1] |= ci1 >> 4;
            groupsOfSix[2] = (ci1 & 0x0f) << 2;
        }
        if (input.length > i + 2) {
            unichar ci2 = [input characterAtIndex:i + 2];
            groupsOfSix[2] |= ci2 >> 6;
            groupsOfSix[3] = ci2 & 0x3f;
        }
        for (int j = 0; j < 4; ++j) {
            if (groupsOfSix[j] == -1) {
                [output appendString:@"="];
            } else {
                [output appendFormat:@"%c", charset[groupsOfSix[j]]];
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
    void (^networkErrorHandler)(void),
    void (^dataErrorHandler)(void)
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
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSUInteger responseCode = [httpResponse statusCode];
        if (responseCodeHandler) {
            if (!responseCodeHandler(responseCode)) {
                return;
            }
        }
        if (error || responseCode != 200) {
            HBLogDebug(@"fetch() error requesting: %@ (%lu)", error, responseCode);
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

// Ported to objc from RYD browser extension
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
    int maxCount = (1 << difficulty) * 3;
    for (int i = 4; i < 20; ++i) {
        buffer[i] = c[i - 4];
    }
    for (int i = 0; i < maxCount; ++i) {
        uInt32View[0] = i;
        uint8_t hash[CC_SHA512_DIGEST_LENGTH] = {0};
        CC_SHA512(buffer, 20, hash);
        if (countLeadingZeroes(hash) >= difficulty) {
            char chars[4] = { buffer[0], buffer[1], buffer[2], buffer[3] };
            NSString *s = [[NSString alloc] initWithBytes:chars length:4 encoding:NSASCIIStringEncoding];
            solution = btoa(s);
            HBLogDebug(@"solvePuzzle() success (%@)", solution);
            break;
        }
    }
    free(buffer);
    if (!solution) {
        HBLogDebug(@"solvePuzzle() failed");
    }
    return solution;
}

// Ported to objc from RYD browser extension
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
                    if ([data isKindOfClass:[NSNumber class]] && ![(NSNumber *)data boolValue]) {
                        HBLogInfo(@"registerUser() failed");
                        return;
                    }
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

// Ported to objc from RYD browser extension
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
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    registerUser();
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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

static NSString *formattedNumber(NSNumber *number, NSString *error) {
    return error ?: [NSNumberFormatter localizedStringFromNumber:number numberStyle:NSNumberFormatterDecimalStyle];
}

static NSString *getXPointYFormat(NSString *count, char c) {
    char firstInt = [count characterAtIndex:0];
    char secondInt = [count characterAtIndex:1];
    if (secondInt == '0') {
        return [NSString stringWithFormat:@"%c%c", firstInt, c];
    }
    return [NSString stringWithFormat:@"%c.%c%c", firstInt, secondInt, c];
}

static NSString *getNormalizedDislikes(NSNumber *dislikeNumber, NSString *error) {
    if (!dislikeNumber) {
        return FAILED;
    }
    if (error) {
        return error;
    }
    if (ExactDislikeNumber()) {
        return formattedNumber(dislikeNumber, nil);
    }
    NSString *dislikeCount = [dislikeNumber stringValue];
    NSUInteger digits = dislikeCount.length;
    if (digits <= 3) { // 0 - 999
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

static void getVoteFromVideoWithHandler(NSString *videoId, int retryCount, void (^handler)(NSDictionary *d, NSString *error)) {
    if (retryCount <= 0) {
        return;
    }
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
                getVoteFromVideoWithHandler(videoId, retryCount - 1, handler);
            });
        },
        ^() {
            handler(nil, FAILED);
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
        if ((ExactLikeNumber() && [renderer slimButton_isLikeButton]) || [renderer slimButton_isDislikeButton]) {
            YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
            getVoteFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([renderer slimButton_isDislikeButton]) {
                        [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:getNormalizedDislikes(data[@"dislikes"], error)]];
                    } else if ([renderer slimButton_isLikeButton]) {
                        [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:formattedNumber(data[@"likes"], error)]];
                    }
                    [self setNeedsLayout];
                });
            });
        }
    }
    return self;
}

- (void)setToggled:(BOOL)toggled {
    YTISlimMetadataButtonSupportedRenderers *renderer = [self valueForKey:@"_supportedRenderer"];
    BOOL isLikeButton = ExactLikeNumber() && [renderer slimButton_isLikeButton];
    BOOL isDislikeButton = [renderer slimButton_isDislikeButton];
    YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
    YTIToggleButtonRenderer *buttonRenderer = meta.button.toggleButtonRenderer;
    BOOL changed = NO;
    if (isLikeButton || isDislikeButton) {
        changed = self.toggled != toggled;
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:FETCHING];
        buttonRenderer.defaultText = formattedText;
        buttonRenderer.toggledText = formattedText;
    }
    %orig;
    if (changed && (isLikeButton || isDislikeButton)) {
        getVoteFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
            NSString *defaultText = isDislikeButton ? getNormalizedDislikes(data[@"dislikes"], error) : formattedNumber(data[@"likes"], error);
            NSString *toggledText = isDislikeButton ? getNormalizedDislikes(@([data[@"dislikes"] unsignedIntegerValue] + 1), error) : formattedNumber(@([data[@"likes"] unsignedIntegerValue] + 1), error);
            YTIFormattedString *formattedDefaultText = [%c(YTIFormattedString) formattedStringWithString:defaultText];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:toggledText];
            buttonRenderer.defaultText = formattedDefaultText;
            buttonRenderer.toggledText = formattedToggledText;
            if ([self isKindOfClass:%c(YTSlimVideoDetailsActionView)]) {
                [self.label setFormattedString:toggled ? formattedToggledText : formattedDefaultText];
                [self setNeedsLayout];
            }
        });
    }
}

%end

%hook YTFullscreenEngagementActionBarButtonView

- (void)updateButtonAndLabelForToggled:(BOOL)toggled {
    YTFullscreenEngagementActionBarButtonRenderer *renderer = [self valueForKey:@"_buttonRenderer"];
    BOOL isLikeButton = ExactLikeNumber() && [renderer isLikeButton];
    BOOL isDislikeButton = [renderer isDislikeButton];
    YTISlimMetadataToggleButtonRenderer *meta = [renderer valueForKey:@"_toggleButtonRenderer"];
    YTIToggleButtonRenderer *buttonRenderer = meta.button.toggleButtonRenderer;
    if (isLikeButton || isDislikeButton) {
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:FETCHING];
        buttonRenderer.defaultText = formattedText;
        buttonRenderer.toggledText = formattedText;
    }
    %orig;
    if (isLikeButton || isDislikeButton) {
        getVoteFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
            NSString *defaultText = isDislikeButton ? getNormalizedDislikes(data[@"dislikes"], error) : formattedNumber(data[@"likes"], error);
            NSString *toggledText = isDislikeButton ? getNormalizedDislikes(@([data[@"dislikes"] unsignedIntegerValue] + 1), error) : formattedNumber(@([data[@"likes"] unsignedIntegerValue] + 1), error);
            YTIFormattedString *formattedDefaultText = [%c(YTIFormattedString) formattedStringWithString:defaultText];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:toggledText];
            buttonRenderer.defaultText = formattedDefaultText;
            buttonRenderer.toggledText = formattedToggledText;
            if ([self isKindOfClass:%c(YTFullscreenEngagementActionBarButtonView)]) {
                [self.label setFormattedString:toggled ? formattedToggledText : formattedDefaultText];
                [self setNeedsLayout];
            }
        });
    }
}

%end

%hook YTReelWatchLikesController

- (void)updateLikeButtonWithRenderer:(YTILikeButtonRenderer *)renderer {
    %orig;
    YTQTMButton *dislikeButton = self.dislikeButton;
    [dislikeButton setTitle:FETCHING forState:UIControlStateNormal];
    [dislikeButton setTitle:FETCHING forState:UIControlStateSelected];
    YTLikeStatus likeStatus = renderer.likeStatus;
    getVoteFromVideoWithHandler(renderer.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        NSString *formattedDislikeCount = getNormalizedDislikes(data[@"dislikes"], error);
        NSString *formattedToggledDislikeCount = getNormalizedDislikes(@([data[@"dislikes"] unsignedIntegerValue] + 1), error);
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedDislikeCount];
        YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:formattedToggledDislikeCount];
        if (renderer.hasDislikeCountText) {
            renderer.dislikeCountText = formattedText;
        }
        if (renderer.hasDislikeCountWithDislikeText) {
            renderer.dislikeCountWithDislikeText = formattedToggledText;
        }
        if (renderer.hasDislikeCountWithUndislikeText) {
            renderer.dislikeCountWithUndislikeText = formattedText;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (likeStatus == YTLikeStatusDislike) {
                [dislikeButton setTitle:[renderer.dislikeCountWithUndislikeText stringWithFormattingRemoved] forState:UIControlStateNormal];
                [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateSelected];
            } else {
                [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateNormal];
                [dislikeButton setTitle:[renderer.dislikeCountWithDislikeText stringWithFormattingRemoved] forState:UIControlStateSelected];
            }
        });
        if (ExactLikeNumber()) {
            YTQTMButton *likeButton = self.likeButton;
            NSString *formattedLikeCount = formattedNumber(data[@"likes"], error);
            NSString *formattedToggledLikeCount = getNormalizedDislikes(@([data[@"likes"] unsignedIntegerValue] + 1), error);
            YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedLikeCount];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:formattedToggledLikeCount];
            if (renderer.hasLikeCountText) {
                renderer.likeCountText = formattedText;
            }
            if (renderer.hasLikeCountWithLikeText) {
                renderer.likeCountWithLikeText = formattedToggledText;
            }
            if (renderer.hasLikeCountWithUnlikeText) {
                renderer.likeCountWithUnlikeText = formattedText;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (likeStatus == YTLikeStatusLike) {
                    [likeButton setTitle:[renderer.likeCountWithUnlikeText stringWithFormattingRemoved] forState:UIControlStateNormal];
                    [likeButton setTitle:[renderer.likeCountText stringWithFormattingRemoved] forState:UIControlStateSelected];
                } else {
                    [likeButton setTitle:[renderer.likeCountText stringWithFormattingRemoved] forState:UIControlStateNormal];
                    [likeButton setTitle:[renderer.likeCountWithLikeText stringWithFormattingRemoved] forState:UIControlStateSelected];
                }
            });
        }
    });
}

%end

%hook YTLikeService

- (void)makeRequestWithStatus:(YTLikeStatus)likeStatus target:(YTILikeTarget *)target clickTrackingParams:(id)arg3 requestParams:(id)arg4 responseBlock:(id)arg5 errorBlock:(id)arg6 {
    if (VoteSubmissionEnabled()) {
        sendVote(target.videoId, likeStatus);
    }
    %orig;
}

- (void)makeRequestWithStatus:(YTLikeStatus)likeStatus target:(YTILikeTarget *)target clickTrackingParams:(id)arg3 queueContextParams:(id)arg4 requestParams:(id)arg5 responseBlock:(id)arg6 errorBlock:(id)arg7 {
    if (VoteSubmissionEnabled()) {
        sendVote(target.videoId, likeStatus);
    }
    %orig;
}

%end

%hook _ASDisplayView

- (void)didMoveToSuperview {
    %orig;
    ELMContainerNode *node = (ELMContainerNode *)self.keepalive_node;
    if (![node.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) {
        return;
    }
    UIViewController *vc = [node closestViewController];
    if (![vc isKindOfClass:%c(YTWatchNextResultsViewController)]) {
        return;
    }
    NSString *likeCount = nil;
    if (node.yogaChildren.count != 2) {
        _ASDisplayView *superview = (_ASDisplayView *)self.superview;
        ELMContainerNode *snode = (ELMContainerNode *)superview.keepalive_node;
        ELMContainerNode *likeNode = snode.yogaChildren[0];
        if (![likeNode.accessibilityIdentifier isEqualToString:@"id.video.like.button"] || likeNode.yogaChildren.count < 2) {
            return;
        }
        ELMTextNode *likeTextNode = likeNode.yogaChildren[1];
        if (![likeTextNode isKindOfClass:%c(ELMTextNode)]) {
            return;
        }
        likeCount = likeTextNode.attributedText.string;
        NSMutableArray *newArray = [node.yogaChildren mutableCopy];
        [newArray addObject:likeTextNode];
        node.yogaChildren = newArray;
    }
    ELMTextNode *candidate = node.yogaChildren[1];
    if (![candidate isKindOfClass:%c(ELMTextNode)]) {
        return;
    }
    NSObject *wc = [vc valueForKey:@"_metadataPanelStateProvider"];
    YTWatchPlaybackController *wpc = ((YTWatchController *)wc).watchPlaybackController;
    YTPlayerViewController *pvc = [wpc valueForKey:@"_playerViewController"];
    NSString *videoId = [pvc currentVideoID];
    NSMutableAttributedString *mutableText = [[NSMutableAttributedString alloc] initWithAttributedString:candidate.attributedText];
    mutableText.mutableString.string = FETCHING;
    candidate.attributedText = mutableText;
    getVoteFromVideoWithHandler(videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *finalLikeCount = ExactLikeNumber() ? formattedNumber(data[@"likes"], error) : likeCount;
            NSString *dislikeCount = getNormalizedDislikes(data[@"dislikes"], error);
            mutableText.mutableString.string = finalLikeCount ? [NSString stringWithFormat:@"%@ | %@", finalLikeCount, dislikeCount] : dislikeCount;
            candidate.attributedText = mutableText;
        });
    });
}

%end

static void enableVoteSubmission(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:EnableVoteSubmissionKey];
}

%hook YTAppSettingsPresentationData

+ (NSArray *)settingsCategoryOrder {
    NSArray *order = %orig;
    NSMutableArray *mutableOrder = [order mutableCopy];
    NSUInteger insertIndex = [order indexOfObject:@(1)];
    if (insertIndex != NSNotFound)
        [mutableOrder insertObject:@(RYDSection) atIndex:insertIndex + 1];
    return mutableOrder;
}

%end

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateRYDSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    NSBundle *tweakBundle = RYDBundle();
    YTSettingsViewController *delegate = [self valueForKey:@"_dataDelegate"];
    YTSettingsSectionItem *vote = [%c(YTSettingsSectionItem) switchItemWithTitle:LOC(@"ENABLE_VOTE_SUBMIT")
        titleDescription:[NSString stringWithFormat:LOC(@"ENABLE_VOTE_SUBMIT_DESC"), apiUrl]
        accessibilityIdentifier:nil
        switchOn:VoteSubmissionEnabled()
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            enableVoteSubmission(enabled);
            return YES;
        }
        settingItemId:0];
    [sectionItems addObject:vote];
    YTSettingsSectionItem *exactDislike = [%c(YTSettingsSectionItem) switchItemWithTitle:LOC(@"EXACT_DISLIKE_NUMBER")
        titleDescription:[NSString stringWithFormat:LOC(@"EXACT_DISLIKE_NUMBER_DESC"), @"12345", [NSNumberFormatter localizedStringFromNumber:@(12345) numberStyle:NSNumberFormatterDecimalStyle]]
        accessibilityIdentifier:nil
        switchOn:ExactDislikeNumber()
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ExactDislikeKey];
            return YES;
        }
        settingItemId:0];
    [sectionItems addObject:exactDislike];
    YTSettingsSectionItem *exactLike = [%c(YTSettingsSectionItem) switchItemWithTitle:LOC(@"EXACT_LIKE_NUMBER")
        titleDescription:nil
        accessibilityIdentifier:nil
        switchOn:ExactLikeNumber()
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
            [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ExactLikeKey];
            return YES;
        }
        settingItemId:0];
    [sectionItems addObject:exactLike];
    [delegate setSectionItems:sectionItems forCategory:RYDSection title:TWEAK_NAME titleDescription:nil headerHidden:NO];
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == RYDSection) {
        [self updateRYDSectionWithEntry:entry];
        return;
    }
    %orig;
}

%end

%ctor {
    cache = [NSCache new];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:DidShowEnableVoteSubmissionAlertKey] && !VoteSubmissionEnabled()) {
        [defaults setBool:YES forKey:DidShowEnableVoteSubmissionAlertKey];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSBundle *tweakBundle = RYDBundle();
            YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                enableVoteSubmission(YES);
            } actionTitle:_LOC([NSBundle mainBundle], @"settings.yes")];
            alertView.title = TWEAK_NAME;
            alertView.subtitle = [NSString stringWithFormat:LOC(@"WANT_TO_ENABLE"), apiUrl, TWEAK_NAME, LOC(@"ENABLE_VOTE_SUBMIT")];
            [alertView show];
        });
    }
}