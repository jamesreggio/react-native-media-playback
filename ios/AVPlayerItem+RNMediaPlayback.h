#import "RNMediaTrack.h"
@import AVFoundation;

@interface AVPlayerItem (RNMediaPlayback)
@property (nonatomic, nullable, strong) RNMediaTrack *RNMediaPlayback_track;
@end
