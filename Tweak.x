#import <UIKit/UIKit.h>
#import "Settings.h"
#import "TweakSettings.h"
#import "Tweak.h"
#import "API.h"
#import "Vote.h"

static NSCache <NSString *, NSDictionary *> *cache;

void (*ASNodeContextPush)(ASNodeContext *);
void (*ASNodeContextPop)(void);

extern NSBundle *RYDBundle();

%hook YTSlimVideoDetailsActionView

+ (YTSlimVideoDetailsActionView *)actionViewWithSlimMetadataButtonSupportedRenderer:(YTISlimMetadataButtonSupportedRenderers *)renderer withElementsContextBlock:(id)block {
    if ([renderer rendererOneOfCase] == 153515154 && TweakEnabled())
        return [[%c(YTSlimVideoDetailsActionView) alloc] initWithSlimMetadataButtonSupportedRenderer:renderer];
    return %orig;
}

- (id)initWithSlimMetadataButtonSupportedRenderer:(id)arg1 {
    self = %orig;
    if (self && TweakEnabled()) {
        YTISlimMetadataButtonSupportedRenderers *renderer = [self valueForKey:@"_supportedRenderer"];
        if ((ExactLikeNumber() && [renderer slimButton_isLikeButton]) || [renderer slimButton_isDislikeButton]) {
            YTISlimMetadataToggleButtonRenderer *meta = renderer.slimMetadataToggleButtonRenderer;
            getVoteFromVideoWithHandler(cache, meta.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([renderer slimButton_isDislikeButton])
                        [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:getNormalizedDislikes(data[@"dislikes"], error)]];
                    else if ([renderer slimButton_isLikeButton] && error == nil)
                        [self.label setFormattedString:[%c(YTIFormattedString) formattedStringWithString:formattedLongNumber(data[@"likes"], nil)]];
                    [self setNeedsLayout];
                });
            });
        }
    }
    return self;
}

- (void)setToggled:(BOOL)toggled {
    if (!TweakEnabled()) {
        %orig;
        return;
    }
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
        getVoteFromVideoWithHandler(cache, meta.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
            NSString *defaultText = isDislikeButton ? getNormalizedDislikes(data[@"dislikes"], error) : formattedLongNumber(data[@"likes"], error);
            NSString *toggledText = isDislikeButton ? getNormalizedDislikes(@([data[@"dislikes"] unsignedIntegerValue] + 1), error) : formattedLongNumber(@([data[@"likes"] unsignedIntegerValue] + 1), error);
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
    if (!TweakEnabled()) {
        %orig;
        return;
    }
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
        getVoteFromVideoWithHandler(cache, meta.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
            NSString *defaultText = isDislikeButton ? getNormalizedDislikes(data[@"dislikes"], error) : formattedLongNumber(data[@"likes"], error);
            NSString *toggledText = isDislikeButton ? getNormalizedDislikes(@([data[@"dislikes"] unsignedIntegerValue] + 1), error) : formattedLongNumber(@([data[@"likes"] unsignedIntegerValue] + 1), error);
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
    if (!TweakEnabled()) return;
    YTQTMButton *dislikeButton = self.dislikeButton;
    [dislikeButton setTitle:FETCHING forState:UIControlStateNormal];
    [dislikeButton setTitle:FETCHING forState:UIControlStateSelected];
    YTLikeStatus likeStatus = renderer.likeStatus;
    getVoteFromVideoWithHandler(cache, renderer.target.videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        NSString *formattedDislikeCount = getNormalizedDislikes(data[@"dislikes"], error);
        NSString *formattedToggledDislikeCount = getNormalizedDislikes(@([data[@"dislikes"] unsignedIntegerValue] + 1), error);
        YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedDislikeCount];
        YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:formattedToggledDislikeCount];
        if (renderer.hasDislikeCountText)
            renderer.dislikeCountText = formattedText;
        if (renderer.hasDislikeCountWithDislikeText)
            renderer.dislikeCountWithDislikeText = formattedToggledText;
        if (renderer.hasDislikeCountWithUndislikeText)
            renderer.dislikeCountWithUndislikeText = formattedText;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (likeStatus == YTLikeStatusDislike) {
                [dislikeButton setTitle:[renderer.dislikeCountWithUndislikeText stringWithFormattingRemoved] forState:UIControlStateNormal];
                [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateSelected];
            } else {
                [dislikeButton setTitle:[renderer.dislikeCountText stringWithFormattingRemoved] forState:UIControlStateNormal];
                [dislikeButton setTitle:[renderer.dislikeCountWithDislikeText stringWithFormattingRemoved] forState:UIControlStateSelected];
            }
        });
        if (ExactLikeNumber() && error == nil) {
            YTQTMButton *likeButton = self.likeButton;
            NSString *formattedLikeCount = formattedLongNumber(data[@"likes"], nil);
            NSString *formattedToggledLikeCount = getNormalizedDislikes(@([data[@"likes"] unsignedIntegerValue] + 1), nil);
            YTIFormattedString *formattedText = [%c(YTIFormattedString) formattedStringWithString:formattedLikeCount];
            YTIFormattedString *formattedToggledText = [%c(YTIFormattedString) formattedStringWithString:formattedToggledLikeCount];
            if (renderer.hasLikeCountText)
                renderer.likeCountText = formattedText;
            if (renderer.hasLikeCountWithLikeText)
                renderer.likeCountWithLikeText = formattedToggledText;
            if (renderer.hasLikeCountWithUnlikeText)
                renderer.likeCountWithUnlikeText = formattedText;
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
    if (TweakEnabled() && VoteSubmissionEnabled())
        sendVote(target.videoId, likeStatus);
    %orig;
}

- (void)makeRequestWithStatus:(YTLikeStatus)likeStatus target:(YTILikeTarget *)target clickTrackingParams:(id)arg3 queueContextParams:(id)arg4 requestParams:(id)arg5 responseBlock:(id)arg6 errorBlock:(id)arg7 {
    if (TweakEnabled() && VoteSubmissionEnabled())
        sendVote(target.videoId, likeStatus);
    %orig;
}

%end

%hook ELMTextNode

%property (assign) BOOL blockUpdate;

- (void)updatedAttributedText {
    if (self.blockUpdate) return;
    %orig;
}

%end

%hook _ASDisplayView

- (void)didMoveToSuperview {
    %orig;
    if (!TweakEnabled()) return;
    int mode = -1;
    ELMContainerNode *node = (ELMContainerNode *)self.keepalive_node;
    if ([node.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"] || [node.accessibilityIdentifier isEqualToString:@"id.reel_dislike_button"])
        mode = 0;
    if ([node.accessibilityIdentifier isEqualToString:@"id.video.like.button"] || [node.accessibilityIdentifier isEqualToString:@"id.reel_like_button"])
        mode = 1;
    if (mode == -1) return;
    BOOL isShorts = [node.accessibilityIdentifier hasPrefix:@"id.reel"];
    UIViewController *vc = [node closestViewController];
    if (![vc isKindOfClass:%c(YTWatchNextResultsViewController)] && ![vc isKindOfClass:%c(YTShortsPlayerViewController)]) return;
    if (node.yogaChildren.count < 1) return;
    BOOL pair = NO;
    id targetNode = nil;
    ELMTextNode *likeTextNode = nil;
    YTRollingNumberNode *likeRollingNumberNode = nil;
    ELMTextNode *dislikeTextNode = nil;
    YTRollingNumberNode *dislikeRollingNumberNode = nil;
    NSMutableAttributedString *mutableDislikeText = nil;
    if (mode == 0) {
        if (isShorts) {
            ELMContainerNode *node1 = [node.yogaChildren firstObject];
            if (node1.yogaChildren.count > 1)
                dislikeTextNode = (ELMTextNode *)node1.yogaChildren[1];
            else {
                ELMContainerNode *node2 = [node1.yogaChildren firstObject];
                if (node2.yogaChildren.count < 2) return;
                dislikeTextNode = (ELMTextNode *)node2.yogaChildren[1];
            }
            mutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:dislikeTextNode.attributedText];
        } else {
            _ASDisplayView *superview = (_ASDisplayView *)self.superview;
            ELMContainerNode *snode = (ELMContainerNode *)superview.keepalive_node;
            ELMContainerNode *likeNode = snode.yogaChildren[0];
            if ([likeNode.accessibilityIdentifier isEqualToString:@"id.video.like.button"] && likeNode.yogaChildren.count == 2) {
                targetNode = likeNode.yogaChildren[1];
                if ([targetNode isKindOfClass:%c(YTRollingNumberNode)]) {
                    likeRollingNumberNode = (YTRollingNumberNode *)targetNode;
                    ASNodeContext *context = [(ASNodeContext *)[%c(ASNodeContext) alloc] initWithOptions:1];
                    ASNodeContextPush(context);
                    dislikeRollingNumberNode = [[%c(YTRollingNumberNode) alloc] initWithElement:likeRollingNumberNode.element context:[likeRollingNumberNode valueForKey:@"_context"]];
                    ASNodeContextPop();
                    dislikeRollingNumberNode.alterMode = 1;
                    dislikeRollingNumberNode.updatedCount = FETCHING;
                    dislikeRollingNumberNode.updatedCountNumber = @(0);
                    [dislikeRollingNumberNode updateRollingNumberView];
                    [node addYogaChild:dislikeRollingNumberNode];
                    [self addSubview:dislikeRollingNumberNode.view];
                    pair = YES;
                } else if ([targetNode isKindOfClass:%c(ELMTextNode)]) {
                    likeTextNode = (ELMTextNode *)targetNode;
                    ASNodeContext *context = [(ASNodeContext *)[%c(ASNodeContext) alloc] initWithOptions:1];
                    ASNodeContextPush(context);
                    dislikeTextNode = [[%c(ELMTextNode) alloc] initWithElement:likeTextNode.element context:[likeTextNode valueForKey:@"_context"]];
                    ASNodeContextPop();
                    mutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                    dislikeTextNode.attributedText = mutableDislikeText;
                    [node addYogaChild:dislikeTextNode];
                    dislikeTextNode.blockUpdate = YES;
                    [self addSubview:dislikeTextNode.view];
                    pair = YES;
                }
            } else {
                dislikeTextNode = node.yogaChildren[1];
                if (![dislikeTextNode isKindOfClass:%c(ELMTextNode)]) return;
                mutableDislikeText = [[NSMutableAttributedString alloc] initWithAttributedString:dislikeTextNode.attributedText];
            }
        }
    } else {
        if (isShorts) {
            ELMContainerNode *node1 = [node.yogaChildren firstObject];
            if (node1.yogaChildren.count > 1)
                likeTextNode = (ELMTextNode *)node1.yogaChildren[1];
            else {
                ELMContainerNode *node2 = [node1.yogaChildren firstObject];
                if (node2.yogaChildren.count < 2) return;
                likeTextNode = (ELMTextNode *)node2.yogaChildren[1];
            }
        } else {
            targetNode = node.yogaChildren[1];
            if ([targetNode isKindOfClass:%c(YTRollingNumberNode)]) {
                likeRollingNumberNode = (YTRollingNumberNode *)targetNode;
                likeRollingNumberNode.alterMode = 2;
            }
            else if ([targetNode isKindOfClass:%c(ELMTextNode)])
                likeTextNode = (ELMTextNode *)targetNode;
            else return;
        }
    }
    YTPlayerViewController *pvc;
    if ([vc isKindOfClass:%c(YTShortsPlayerViewController)])
        pvc = ((YTShortsPlayerViewController *)vc).player;
    else {
        NSObject *wc;
        @try {
            wc = [vc valueForKey:@"_metadataPanelStateProvider"];
        } @catch (id ex) {
            wc = [vc valueForKey:@"_ngwMetadataPanelStateProvider"];
        }
        @try {
            YTWatchPlaybackController *wpc = ((YTWatchController *)wc).watchPlaybackController;
            pvc = [wpc valueForKey:@"_playerViewController"];
        } @catch (id ex) {
            pvc = [wc valueForKey:@"_playerViewController"];
        }
    }
    NSString *videoId = [pvc currentVideoID];
    if (mode == 0 && dislikeTextNode) {
        mutableDislikeText.mutableString.string = FETCHING;
        dislikeTextNode.attributedText = mutableDislikeText;
    }
    getVoteFromVideoWithHandler(cache, videoId, maxRetryCount, ^(NSDictionary *data, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ExactLikeNumber() && error == nil) {
                NSNumber *likeNumber = data[@"likes"];
                NSString *likeCount = formattedLongNumber(likeNumber, nil);
                if (likeCount) {
                    if (likeRollingNumberNode) {
                        likeRollingNumberNode.updatedCount = likeCount;
                        likeRollingNumberNode.updatedCountNumber = likeNumber;
                        [likeRollingNumberNode updateRollingNumberView];
                        [likeRollingNumberNode relayoutNode];
                    } else {
                        NSMutableAttributedString *mutableLikeText = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                        mutableLikeText.mutableString.string = likeCount;
                        likeTextNode.attributedText = mutableLikeText;
                        likeTextNode.accessibilityLabel = likeCount;
                    }
                }
            }
            if (mode == 0) {
                NSNumber *dislikeNumber = data[@"dislikes"];
                NSString *dislikeCount = getNormalizedDislikes(dislikeNumber, error);
                NSString *dislikeString = pair ? [NSString stringWithFormat:@"  %@ ", dislikeCount] : dislikeCount;
                if (dislikeRollingNumberNode) {
                    dislikeRollingNumberNode.updatedCount = dislikeString;
                    dislikeRollingNumberNode.updatedCountNumber = dislikeNumber;
                    [dislikeRollingNumberNode updateRollingNumberView];
                    [dislikeRollingNumberNode relayoutNode];
                } else {
                    mutableDislikeText.mutableString.string = dislikeString;
                    dislikeTextNode.attributedText = mutableDislikeText;
                    dislikeTextNode.accessibilityLabel = dislikeCount;
                }
            }
        });
    });
}

%end

%hook YTRollingNumberNode

%property (assign) int alterMode;
%property (strong, nonatomic) NSString *updatedCount;
%property (strong, nonatomic) NSNumber *updatedCountNumber;

- (void)updateRollingNumberView {
    %orig;
    if ((self.alterMode == 1 || self.alterMode == 2) && (self.updatedCount && self.updatedCountNumber)) {
        YTRollingNumberView *view = [self valueForKey:@"_rollingNumberView"];
        UIFont *font = view.font;
        UIColor *color = view.color;
        NSString *updatedCount = [NSString stringWithFormat:@" %@", self.updatedCount];
        if ([view respondsToSelector:@selector(setUpdatedCount:updatedCountNumber:font:fontAttributes:color:skipAnimation:)])
            [view setUpdatedCount:updatedCount updatedCountNumber:self.updatedCountNumber font:font fontAttributes:view.fontAttributes color:color skipAnimation:YES];
        else
            [view setUpdatedCount:updatedCount updatedCountNumber:self.updatedCountNumber font:font color:color skipAnimation:YES];
    }
}

- (void)controllerDidApplyProperties {}

%end

// %group ForceLegacy

// BOOL loadWatchNextRequest = NO;

// %hook YTVersionUtils

// + (NSString *)appVersion {
//     return loadWatchNextRequest && TweakEnabled() ? @"16.46.5" : %orig;
// }

// %end

// %hook YTWatchNextViewController

// - (void)loadWatchNextRequest:(id)arg1 withInitialWatchNextResponse:(id)arg2 disableUnloadModel:(BOOL)arg3 {
//     loadWatchNextRequest = YES;
//     %orig;
//     loadWatchNextRequest = NO;
// }

// %end

// %end

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
            alertView.title = @(TWEAK_NAME);
            alertView.subtitle = [NSString stringWithFormat:LOC(@"WANT_TO_ENABLE"), @(API_URL), TWEAK_NAME, LOC(@"ENABLE_VOTE_SUBMIT")];
            [alertView show];
        });
    }
    NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/Module_Framework.framework/Module_Framework", NSBundle.mainBundle.bundlePath];
    NSBundle *bundle = [NSBundle bundleWithPath:frameworkPath];
    if (!bundle.loaded) [bundle load];
    MSImageRef ref = MSGetImageByName([frameworkPath UTF8String]);
    ASNodeContextPush = (void (*)(ASNodeContext *))MSFindSymbol(ref, "_ASNodeContextPush");
    ASNodeContextPop = (void (*)(void))MSFindSymbol(ref, "_ASNodeContextPop");
    %init;
    // if (!IS_IOS_OR_NEWER(iOS_13_0)) {
    //     %init(ForceLegacy);
    // }
}