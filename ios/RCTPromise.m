#import "RCTPromise.h"

@implementation RCTPromise

- (instancetype)initWithResolver:(nonnull RCTPromiseResolveBlock)resolve
                        rejecter:(nonnull RCTPromiseRejectBlock)reject
{
  if (self = [super init]) {
    _resolve = resolve;
    _reject = reject;
  }
  return self;
}

+ (instancetype)promiseWithResolver:(nonnull RCTPromiseResolveBlock)resolve
                           rejecter:(nonnull RCTPromiseRejectBlock)reject
{
  return [[self alloc] initWithResolver:resolve rejecter:reject];
}

@end
