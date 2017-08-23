#import <React/RCTBridgeModule.h>

@interface RCTPromise : NSObject
@property (nonatomic, strong) RCTPromiseResolveBlock resolve;
@property (nonatomic, strong) RCTPromiseRejectBlock reject;

- (instancetype)initWithResolver:(nonnull RCTPromiseResolveBlock)resolve rejecter:(nonnull RCTPromiseRejectBlock)reject;
+ (instancetype)promiseWithResolver:(nonnull RCTPromiseResolveBlock)resolve rejecter:(nonnull RCTPromiseRejectBlock)reject;
@end
