#ifndef TWEAK_SETTINGS_H_
#define TWEAK_SETTINGS_H_

#import <Foundation/Foundation.h>

BOOL TweakEnabled();
BOOL VoteSubmissionEnabled();
BOOL ExactLikeNumber();
BOOL ExactDislikeNumber();

void enableVoteSubmission(BOOL enabled);

#define EnabledKey @"RYD-ENABLED"
#define EnableVoteSubmissionKey @"RYD-VOTE-SUBMISSION"
#define ExactLikeKey @"RYD-EXACT-LIKE-NUMBER"
#define ExactDislikeKey @"RYD-EXACT-NUMBER"

#endif
