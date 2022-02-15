#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <HBLog.h>
#import "Tweak.h"

#define maxRetryCount 3
#define apiUrl @"https://returnyoutubedislikeapi.com"
#define UserIDKey @"RYD-USER-ID"
#define RegistrationConfirmedKey @"RYD-USER-REGISTERED"
#define EnableVoteSubmissionKey @"RYD-VOTE-SUBMISSION"
#define FETCHING @"Fetching"
#define FAILED @"Failed"

static NSCache <NSString *, NSNumber *> *cache;

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
    int maxCount = (1 << difficulty) * 5;
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

static void getDislikeFromVideoWithHandler(NSString *videoId, int retryCount, void (^handler)(NSNumber *dislikeCount, NSString *error)) {
    if (retryCount <= 0) {
        return;
    }
    if ([cache objectForKey:videoId]) {
        handler([cache objectForKey:videoId], nil);
        return;
    }
    fetch(
        [NSString stringWithFormat:@"/votes?videoId=%@", videoId],
        @"GET",
        nil,
        ^(NSDictionary *data) {
            NSNumber *dislikeNumber = data[@"dislikes"];
            [cache setObject:dislikeNumber forKey:videoId];
            handler(dislikeNumber, nil);
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
                getDislikeFromVideoWithHandler(videoId, retryCount - 1, handler);
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
        if ([renderer slimButton_isDislikeButton]) {
            YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
            getDislikeFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSNumber *dislikeNumber, NSString *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:getNormalizedDislikes(dislikeNumber, error)]];
                    [self setNeedsLayout];
                });
            });
        }
    }
    return self;
}

- (void)setToggled:(BOOL)toggled {
    YTISlimMetadataButtonSupportedRenderers *renderer = [self valueForKey:@"_supportedRenderer"];
    BOOL isDislikeButton = [renderer slimButton_isDislikeButton];
    YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
    YTIToggleButtonRenderer *buttonRenderer = meta.button.toggleButtonRenderer;
    BOOL changed = NO;
    if (isDislikeButton) {
        changed = self.toggled != toggled;
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:FETCHING];
        buttonRenderer.defaultText = formattedText;
        buttonRenderer.toggledText = formattedText;
    }
    %orig;
    if (changed && isDislikeButton) {
        getDislikeFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSNumber *dislikeNumber, NSString *error) {
            NSString *defaultText = getNormalizedDislikes(dislikeNumber, error);
            NSString *toggledText = getNormalizedDislikes(@([dislikeNumber unsignedIntegerValue] + 1), error);
            YTIFormattedString *formattedDefaultText = [%c(YTIFormattedString) formattedStringWithString:defaultText];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:toggledText];
            buttonRenderer.defaultText = formattedDefaultText;
            buttonRenderer.toggledText = formattedToggledText;
            [self.label setFormattedString:toggled ? formattedToggledText : formattedDefaultText];
            [self setNeedsLayout];
        });
    }
}

%end

%hook YTFullscreenEngagementActionBarButtonView

- (void)updateButtonAndLabelForToggled:(BOOL)toggled {
    YTFullscreenEngagementActionBarButtonRenderer *renderer = [self valueForKey:@"_buttonRenderer"];
    BOOL isDislikeButton = [renderer isDislikeButton];
    YTISlimMetadataToggleButtonRenderer *meta = [renderer valueForKey:@"_toggleButtonRenderer"];
    YTIToggleButtonRenderer *buttonRenderer = meta.button.toggleButtonRenderer;
    if (isDislikeButton) {
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:FETCHING];
        buttonRenderer.defaultText = formattedText;
        buttonRenderer.toggledText = formattedText;
    }
    %orig;
    if (isDislikeButton) {
        getDislikeFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSNumber *dislikeNumber, NSString *error) {
            NSString *defaultText = getNormalizedDislikes(dislikeNumber, error);
            NSString *toggledText = getNormalizedDislikes(@([dislikeNumber unsignedIntegerValue] + 1), error);
            YTIFormattedString *formattedDefaultText = [%c(YTIFormattedString) formattedStringWithString:defaultText];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:toggledText];
            buttonRenderer.defaultText = formattedDefaultText;
            buttonRenderer.toggledText = formattedToggledText;
            [self.label setFormattedString:toggled ? formattedToggledText : formattedDefaultText];
            [self setNeedsLayout];
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
    getDislikeFromVideoWithHandler(renderer.target.videoId, maxRetryCount, ^(NSNumber *dislikeNumber, NSString *error) {
        NSString *formattedDislikeCount = getNormalizedDislikes(dislikeNumber, error);
        NSString *formattedToggledDislikeCount = getNormalizedDislikes(@([dislikeNumber unsignedIntegerValue] + 1), error);
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

%end

%hook _ASDisplayView

- (void)didMoveToSuperview {
    %orig;
    ELMContainerNode *node = (ELMContainerNode *)self.keepalive_node;
    if (node.yogaChildren.count != 2) {
        return;
    }
    UIViewController *vc = [node closestViewController];
    if (![vc isKindOfClass:%c(YTWatchNextResultsViewController)]) {
        return;
    }
    if (![node.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) {
        return;
    }
    ELMTextNode *candidate = node.yogaChildren[1];
    if (![candidate isKindOfClass:%c(ELMTextNode)]) {
        return;
    }
    YTWatchController *wc = [vc valueForKey:@"_metadataPanelStateProvider"];
    YTPlayerViewController *pvc = [wc valueForKey:@"_playerViewController"];
    NSString *videoId = [pvc currentVideoID];
    NSMutableAttributedString *mutableText = [[NSMutableAttributedString alloc] initWithAttributedString:candidate.attributedText];
    mutableText.mutableString.string = FETCHING;
    candidate.attributedText = mutableText;
    getDislikeFromVideoWithHandler(videoId, maxRetryCount, ^(NSNumber *dislikeNumber, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *dislikeCount = getNormalizedDislikes(dislikeNumber, error);
            mutableText.mutableString.string = dislikeCount;
            candidate.attributedText = mutableText;
        });
    });
}

%end

%hook YTSettingsViewController

- (void)setSectionItems:(NSMutableArray <YTSettingsSectionItem *> *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden {
    if (category == 1) {
        NSUInteger statsForNerdsIndex = [sectionItems indexOfObjectPassingTest:^BOOL (YTSettingsSectionItem *item, NSUInteger idx, BOOL *stop) { 
            return item.settingItemId == 265;
        }];
        if (statsForNerdsIndex != NSNotFound) {
            YTSettingsSectionItem *vote = [%c(YTSettingsSectionItem) switchItemWithTitle:@"Enable vote submission"
                titleDescription:@"Allow your unique anonymous ID and videos/shorts likes/dislikes data to be submitted to returnyoutubedislikeapi.com"
                accessibilityIdentifier:nil
                switchOn:VoteSubmissionEnabled()
                switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
                    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setBool:enabled forKey:EnableVoteSubmissionKey];
                    [defaults synchronize];
                    return YES;
                }
                settingItemId:0];
            [sectionItems insertObject:vote atIndex:statsForNerdsIndex + 1];
        }
    }
    %orig(sectionItems, category, title, titleDescription, headerHidden);
}

%end

%ctor {
    cache = [NSCache new];
}