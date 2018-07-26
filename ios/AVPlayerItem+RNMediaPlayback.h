@import AVFoundation;

@interface AVPlayerItem (RNMediaPlayback)
@property (nonatomic, strong, nonnull) NSString *RNMediaPlayback_id;
@property (nonatomic, strong, nullable) id RNMediaPlayback_boundaryObserver;
@property (nonatomic, assign) CMTimeRange RNMediaPlayback_range;
@end
