#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/ASNodeContext.h>
#import <YouTubeHeader/ELMContainerNode.h>
#import <YouTubeHeader/ELMNodeController.h>
#import <YouTubeHeader/ELMNodeFactory.h>
#import <YouTubeHeader/ELMTextNode.h>
#import <YouTubeHeader/UIView+AsyncDisplayKit.h>
#import <YouTubeHeader/YTAlertView.h>
#import <YouTubeHeader/YTFullscreenEngagementActionBarButtonRenderer.h>
#import <YouTubeHeader/YTFullscreenEngagementActionBarButtonView.h>
#import <YouTubeHeader/YTIButtonSupportedRenderers.h>
#import <YouTubeHeader/YTIFormattedString.h>
#import <YouTubeHeader/YTILikeButtonRenderer.h>
#import <YouTubeHeader/YTISlimMetadataButtonSupportedRenderers.h>
#import <YouTubeHeader/YTIToggleButtonRenderer.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTReelWatchLikesController.h>
#import <YouTubeHeader/YTRollingNumberNode.h>
#import <YouTubeHeader/YTRollingNumberView.h>
#import <YouTubeHeader/YTShortsPlayerViewController.h>
#import <YouTubeHeader/YTSlimVideoDetailsActionView.h>
#import <YouTubeHeader/YTWatchController.h>

@interface ELMTextNode (RYD)
@property (assign) BOOL blockUpdate;
@end

@interface YTRollingNumberNode (RYD)
@property (assign) int alterMode;
@property (strong, nonatomic) NSString *updatedCount;
@property (strong, nonatomic) NSNumber *updatedCountNumber;
@end
