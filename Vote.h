#ifndef VOTE_H_
#define VOTE_H_

#import <Foundation/Foundation.h>

NSString *formattedLongNumber(NSNumber *number, NSString *error);
NSString *getNormalizedLikes(NSNumber *likeNumber, NSString *error);
NSString *getNormalizedDislikes(NSNumber *dislikeNumber, NSString *error);
void getVoteFromVideoWithHandler(NSCache <NSString *, NSDictionary *> *cache, NSString *videoId, int retryCount, void (^handler)(NSDictionary *d, NSString *error));

#define maxRetryCount 3
#define FETCHING @"⌛"
#define FAILED @"❌"

#endif
