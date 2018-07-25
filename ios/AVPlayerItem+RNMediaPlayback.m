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

- (NSArray<NSValue *> *)RNMediaPlayback_boundaries
{
  return objc_getAssociatedObject(self, @selector(RNMediaPlayback_boundaries));
}

- (void)setRNMediaPlayback_boundaries:(NSArray<NSValue *> *)boundaries
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_boundaries), boundaries, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)RNMediaPlayback_boundaryObserver
{
  return objc_getAssociatedObject(self, @selector(RNMediaPlayback_boundaryObserver));
}

- (void)setRNMediaPlayback_boundaryObserver:(id)boundaryObserver
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_boundaryObserver), boundaryObserver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
