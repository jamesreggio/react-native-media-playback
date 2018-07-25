@import AVFoundation;

@interface AVPlayerItem (RNMediaPlayback)
@property (nonatomic, strong, nonnull) NSString *RNMediaPlayback_id;
@property (nonatomic, strong, nullable) NSArray<NSValue *> *RNMediaPlayback_boundaries;
@property (nonatomic, strong, nullable) id RNMediaPlayback_boundaryObserver;
@end
