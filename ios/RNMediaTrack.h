#import <Foundation/Foundation.h>
#import "RNMediaAsset.h"
@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

@class RNMediaPlayer;
@class RNMediaTrack;

@protocol RNMediaTrackDelegate<NSObject>
@optional

- (void)trackDidFinish:(RNMediaTrack *)track withError:(nullable NSError *)error;
- (void)trackDidFinishRange:(RNMediaTrack *)track withError:(nullable NSError *)error;

@end

@interface RNMediaTrack : NSObject

+ (instancetype)trackWithPlayer:(RNMediaPlayer *)player asset:(RNMediaAsset *)asset options:(NSDictionary *)options;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, nonnull, readonly, strong) NSString *id;
@property (nonatomic, nullable, readonly, weak) AVPlayerItem *AVPlayerItem;
@property (nonatomic, nullable, weak) id<RNMediaTrackDelegate> delegate;
@property (nonatomic, nullable, readonly, strong) NSDictionary *remote;
@property (nonatomic, readonly, assign) CMTimeRange range;

@property (nonatomic, readonly, nonnull) NSString *status;
@property (nonatomic, readonly, nonnull) NSNumber *statusRate;
@property (nonatomic, readonly, nonnull) NSNumber *targetRate;
@property (nonatomic, readonly, nullable) NSNumber *position;
@property (nonatomic, readonly, nullable) NSNumber *duration;

- (void)enqueued;
- (void)activate;
- (void)deactivate;
- (CMTime)seekPositionForTarget:(CMTime)target window:(CMTime)window;

@end

NS_ASSUME_NONNULL_END
