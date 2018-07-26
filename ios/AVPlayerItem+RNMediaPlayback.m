#import <objc/runtime.h>
#import "AVPlayerItem+RNMediaPlayback.h"

@implementation AVPlayerItem (RNMediaPlayback)

- (NSString *)RNMediaPlayback_id
{
  return objc_getAssociatedObject(self, @selector(RNMediaPlayback_id));
}

- (void)setRNMediaPlayback_id:(NSString *)id
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_id), id, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)RNMediaPlayback_boundaryObserver
{
  return objc_getAssociatedObject(self, @selector(RNMediaPlayback_boundaryObserver));
}

- (void)setRNMediaPlayback_boundaryObserver:(id)boundaryObserver
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_boundaryObserver), boundaryObserver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CMTimeRange)RNMediaPlayback_range
{
  NSValue *value = objc_getAssociatedObject(self, @selector(RNMediaPlayback_range));
  return value ? [value CMTimeRangeValue] : kCMTimeRangeInvalid;
}

- (void)setRNMediaPlayback_range:(CMTimeRange)range
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_range), [NSValue valueWithCMTimeRange:range], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
