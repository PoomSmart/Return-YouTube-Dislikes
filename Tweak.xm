#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Tweak.h"

#define maxRetryCount 3
#define apiUrl @"https://returnyoutubedislikeapi.com"
#define FETCHING @"Fetching"

// enum YTLikeStatus : int {
//     YTLikeStatusLike = 0,
//     YTLikeStatusDislike = 1,
//     YTLikeStatusNeutral = 2
// };

// static int toRYDLikeStatus(YTLikeStatus likeStatus) {
//     switch (likeStatus) {
//         case YTLikeStatusLike:
//             return 1;
//         case YTLikeStatusDislike:
//             return -1;
//         default:
//             return 0;
//     }
// }

static NSString *getXPointYFormat(NSString *count, char c) {
    char firstInt = [count characterAtIndex:0];
    char secondInt = [count characterAtIndex:1];
    if (secondInt == '0') {
        return [NSString stringWithFormat:@"%c%c", firstInt, c];
    }
    return [NSString stringWithFormat:@"%c.%c%c", firstInt, secondInt, c];
}

static NSString *getNormalizedDislikes(NSString *dislikeCount) {
    if (!dislikeCount) {
        return @"Failed";
    }
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

static void setDislikeCount(YTSlimVideoDetailsActionView *self, NSString *dislikeCount) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:dislikeCount]];
        [self.label sizeToFit];
    });
}

static void getDislikeFromVideoWithHandler(NSString *videoIdentifier, int retryCount, void (^handler)(NSString *dislikeCount)) {
    if (retryCount <= 0) {
        return;
    }
    NSURL *dataUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@/votes?videoId=%@", apiUrl, videoIdentifier]];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[session dataTaskWithURL:dataUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse *)response;
        NSUInteger responseCode = [httpResponse statusCode];
        if (responseCode == 502 || responseCode == 503) {
            handler(@"CON");
            return;
        }
        if (responseCode == 429) {
            handler(@"RL");
            return;
        }
        if (responseCode == 404) {
            handler(@"NULL");
            return;
        }
        if (responseCode == 400) {
            handler(@"INV");
            return;
        }
        if (error) {
            handler(nil);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                getDislikeFromVideoWithHandler(videoIdentifier, retryCount - 1, handler);
            });
            return;
        }
        NSError *jsonError;
        NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError) {
            handler(nil);
            return;
        }
        NSString *dislikeCount = [NSString stringWithFormat:@"%@", [responseObject objectForKey:@"dislikes"]];
        handler(dislikeCount);
    }] resume];
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
            setDislikeCount(self, FETCHING);
            YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
            getDislikeFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSString *dislikeCount) {
                setDislikeCount(self, getNormalizedDislikes(dislikeCount));
            });
        }
    }
    return self;
}

- (void)setToggled:(BOOL)toggled {
    YTISlimMetadataButtonSupportedRenderers *renderer = [self valueForKey:@"_supportedRenderer"];
    BOOL isDislikeButton = [renderer slimButton_isDislikeButton];
    YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
    BOOL changed = NO;
    if (isDislikeButton) {
        changed = self.toggled != toggled;
        YTIToggleButtonRenderer *buttonRenderer = meta.button.toggleButtonRenderer;
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:FETCHING];
        buttonRenderer.toggledText = formattedText;
        buttonRenderer.defaultText = formattedText;
    }
    %orig;
    if (isDislikeButton && changed) {
        getDislikeFromVideoWithHandler(meta.target.videoId, maxRetryCount, ^(NSString *dislikeCount) {
            NSString *response = getNormalizedDislikes(dislikeCount);
            YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:response];
            [self.label setFormattedString:formattedText];
            [self setNeedsLayout];
        });
    }
}

%end

// %hook YTSlimVideoDetailsActionsView
//
// - (void)setLikeStatus:(YTLikeStatus)likeStatus {
//     YTSlimVideoScrollableActionBarCellController *videoActionsDelegate = (YTSlimVideoScrollableActionBarCellController *)self.videoActionsDelegate;
//     YTSlimVideoMetadataExpandingBehavior *delegate = (YTSlimVideoMetadataExpandingBehavior *)videoActionsDelegate.delegate;
//     NSString *videoID = [delegate videoId];
//     HBLogDebug(@"YDR like for video ID %@: %d", videoID, toRYDLikeStatus(likeStatus));
//     %orig;
// }
//
// %end

// %hook YTSlimVideoScrollableDetailsActionsView
//
// - (void)setLikeStatus:(YTLikeStatus)likeStatus {
//     YTSlimVideoScrollableActionBarCellController *videoActionsDelegate = (YTSlimVideoScrollableActionBarCellController *)self.videoActionsDelegate;
//     YTSlimVideoMetadataExpandingBehavior *delegate = (YTSlimVideoMetadataExpandingBehavior *)videoActionsDelegate.delegate;
//     NSString *videoID = [delegate videoId];
//     HBLogDebug(@"YDR (scrollable) like for video ID %@: %d", videoID, toRYDLikeStatus(likeStatus));
//     %orig;
// }
//
// %end

%hook YTReelWatchLikesController

- (void)updateLikeButtonWithRenderer:(YTILikeButtonRenderer *)renderer {
    %orig;
    YTQTMButton *dislikeButton = self.dislikeButton;
    [dislikeButton setTitle:FETCHING forState:UIControlStateNormal];
    [dislikeButton setTitle:FETCHING forState:UIControlStateSelected];
    getDislikeFromVideoWithHandler(renderer.target.videoId, maxRetryCount, ^(NSString *dislikeCount) {
        if (dislikeCount) {
            NSString *formattedDislikeCount = getNormalizedDislikes(dislikeCount);
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

// - (void)triggerServiceEndpointForLikeButtonRenderer:(YTILikeButtonRenderer *)renderer forRequestID:(id)requestID withLikeStatus:(YTLikeStatus)likeStatus {
//     HBLogDebug(@"YDR reel like for video %@: %d", renderer.target.videoId, toRYDLikeStatus(likeStatus));
//     %orig;
// }

%end
