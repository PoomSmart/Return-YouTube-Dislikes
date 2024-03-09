#import "TweakSettings.h"

BOOL TweakEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:EnabledKey];
}

BOOL VoteSubmissionEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:EnableVoteSubmissionKey];
}

BOOL ExactLikeNumber() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExactLikeKey];
}

BOOL ExactDislikeNumber() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:ExactDislikeKey];
}

void enableVoteSubmission(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:EnableVoteSubmissionKey];
}
