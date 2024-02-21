#ifndef SETTINGS_H_
#define SETTINGS_H_

#define UserIDKey @"RYD-USER-ID"
#define RegistrationConfirmedKey @"RYD-USER-REGISTERED"
#define EnabledKey @"RYD-ENABLED"
#define EnableVoteSubmissionKey @"RYD-VOTE-SUBMISSION"
#define ExactLikeKey @"RYD-EXACT-LIKE-NUMBER"
#define ExactDislikeKey @"RYD-EXACT-NUMBER"
#define DidShowEnableVoteSubmissionAlertKey @"RYD-DID-SHOW-VOTE-SUBMISSION-ALERT"

#define _LOC(b, x) [b localizedStringForKey:x value:nil table:nil]
#define LOC(x) _LOC(tweakBundle, x)

#endif
