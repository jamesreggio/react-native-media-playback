#import <objc/runtime.h>
#import "AVPlayerItem+RNMediaPlayback.h"

@implementation AVPlayerItem (RNMediaPlayback)

- (RNMediaTrack *)RNMediaPlayback_track
{
  return objc_getAssociatedObject(self, @selector(RNMediaPlayback_track));
}

- (void)setRNMediaPlayback_track:(RNMediaTrack *)track
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_track), track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
