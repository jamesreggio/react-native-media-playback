#import <objc/runtime.h>
#import "AVAsset+RNMediaPlayback.h"

@implementation AVAsset (RNMediaPlayback)

- (BOOL)RNMediaPlayback_preciseTiming
{
  NSNumber *value = objc_getAssociatedObject(self, @selector(RNMediaPlayback_preciseTiming));
  return value ? value.boolValue : NO;
}

- (void)setRNMediaPlayback_preciseTiming:(BOOL)preciseTiming
{
  objc_setAssociatedObject(self, @selector(RNMediaPlayback_preciseTiming), @(preciseTiming), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
