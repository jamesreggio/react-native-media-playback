#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RNMediaPlayer;

@protocol RNMediaPlayerDelegate<NSObject>
@optional

- (void)playerWillActivate:(RNMediaPlayer *)player;
- (void)playerDidDeactivate:(RNMediaPlayer *)player;
- (void)playerWillActivateTrack:(RNMediaPlayer *)player withBody:(NSDictionary *)body;
- (void)playerDidUpdateTrack:(RNMediaPlayer *)player withBody:(NSDictionary *)body;
- (void)playerDidFinishTrack:(RNMediaPlayer *)player withBody:(NSDictionary *)body;

@end

@interface RNMediaPlayer : NSObject

@property (nonatomic, strong, readonly) NSNumber *key;
@property (nonatomic, weak) id<RNMediaPlayerDelegate> delegate;
@property (nonatomic, assign) BOOL active;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKey:(NSNumber *)key methodQueue:(dispatch_queue_t)methodQueue options:(NSDictionary *)options NS_DESIGNATED_INITIALIZER;

- (void)insertTracks:(NSArray *)tracks andAdvance:(BOOL)advance;
- (void)replaceTracks:(NSArray *)tracks andAdvance:(BOOL)advance;
- (void)nextTrack;

- (void)play;
- (void)pause;
- (void)toggle;
- (void)stop;
- (void)seekTo:(NSNumber *)position completion:(void (^__nullable)(BOOL))completion;
- (void)skipBy:(NSNumber *)interval completion:(void (^__nullable)(BOOL))completion;
- (void)setRate:(NSNumber *)rate;

@end

NS_ASSUME_NONNULL_END
