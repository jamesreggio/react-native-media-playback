#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RNMediaControlsDelegate<NSObject>
@optional

- (void)remoteDidRequestPlay;
- (void)remoteDidRequestPause;
- (void)remoteDidRequestToggle;
- (void)remoteDidRequestStop;
- (void)remoteDidRequestNextTrack;
- (void)remoteDidRequestPrevTrack;
- (void)remoteDidRequestSeekForward;
- (void)remoteDidRequestSeekBackward;
- (void)remoteDidRequestSeekTo:(NSNumber *)position;
- (void)remoteDidRequestSkipBy:(NSNumber *)interval;

- (void)systemDidLoseOutputRoute;
- (void)systemWillBeginInterruption;
- (void)systemDidFinishInterruptionAndShouldResume:(BOOL)shouldResume;
- (void)systemDidReset;

@end

@interface RNMediaControls : NSObject

@property (nonatomic, weak) id<RNMediaControlsDelegate> delegate;

+ (instancetype)sharedInstance;
- (instancetype)init NS_UNAVAILABLE;

- (void)updateDetails:(NSDictionary *)details;
- (void)resetDetails;

- (void)showRoutePicker;
- (NSArray<NSDictionary *> *)outputRoutes;

@end

NS_ASSUME_NONNULL_END

