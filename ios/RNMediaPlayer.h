#import <Foundation/Foundation.h>
#import "RNMediaTrack.h"

NS_ASSUME_NONNULL_BEGIN

@class RNMediaPlayer;

@protocol RNMediaPlayerDelegate<NSObject>
@optional

- (void)playerWillActivate:(RNMediaPlayer *)player;
- (void)playerWillDeactivate:(RNMediaPlayer *)player;
- (void)playerDidActivateTrack:(RNMediaPlayer *)player track:(RNMediaTrack *)track;
- (void)playerDidUpdateTrack:(RNMediaPlayer *)player track:(RNMediaTrack *)track;
- (void)playerDidFinishTrack:(RNMediaPlayer *)player track:(RNMediaTrack *)track withError:(nullable NSError *)error;

@end

@interface RNMediaPlayer : NSObject<RNMediaTrackDelegate>

@property (nonatomic, nonnull, readonly, strong) NSNumber *key;
@property (nonatomic, nonnull, readonly, strong) AVQueuePlayer *AVPlayer;
@property (nonatomic, nullable, weak) id<RNMediaPlayerDelegate> delegate;
@property (nonatomic, readonly, assign) dispatch_queue_t methodQueue;

@property (nonatomic, nullable, readonly) RNMediaTrack *track;
@property (nonatomic, nonnull, readonly) NSString *status;
@property (nonatomic, nonnull, readonly) NSNumber *statusRate;
@property (nonatomic, nonnull, readonly) NSNumber *targetRate;
@property (nonatomic, nullable, readonly) NSNumber *position;
@property (nonatomic, nullable, readonly) NSNumber *duration;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKey:(NSNumber *)key methodQueue:(dispatch_queue_t)methodQueue options:(NSDictionary *)options NS_DESIGNATED_INITIALIZER;

- (void)activate;
- (void)deactivate;

- (void)insertTracks:(NSArray *)tracks options:(NSDictionary *)options;
- (void)replaceTracks:(NSArray *)tracks options:(NSDictionary *)options;
- (void)nextTrack;

- (void)play;
- (void)playWithOptions:(NSDictionary *)options;
- (void)pause;
- (void)toggle;
- (void)stop;
- (void)seekTo:(NSNumber *)position completion:(void (^__nullable)(BOOL))completion;
- (void)skipBy:(NSNumber *)interval completion:(void (^__nullable)(BOOL))completion;
- (void)setRate:(NSNumber *)rate;
- (void)setRange:(NSDictionary *)range;

@end

NS_ASSUME_NONNULL_END
