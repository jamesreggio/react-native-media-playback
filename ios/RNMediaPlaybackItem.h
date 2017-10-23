#import <React/RCTEventEmitter.h>

@interface RNMediaPlaybackItem : NSObject

- (instancetype)initWithKey:(NSNumber *)key manager:(RCTEventEmitter *)manager;

// Lifecycle
- (void)prepareWithOptions:(NSDictionary *)options completion:(void (^)(NSError *error))completion;
- (void)activateWithOptions:(NSDictionary *)options;
- (void)deactivateWithOptions:(NSDictionary *)options;
- (void)releaseWithOptions:(NSDictionary *)options;

// Playback Controls
- (void)play;
- (void)pause;
- (void)seekTo:(NSNumber *)position completion:(void (^)(BOOL finished))completion;
- (void)setRate:(NSNumber *)rate;
- (void)setBuffer:(NSNumber *)duration;

// Playback Properties
@property (nonatomic, readonly) NSString *status;
@property (nonatomic, readonly) NSNumber *position;
@property (nonatomic, readonly) NSNumber *duration;

@end
