#import "RNMediaPlaybackManager.h"
#import "RNMediaPlaybackItem.h"
#import "RNMediaPlaybackSession.h"
#import "RCTPromise.h"
#import <React/RCTAssert.h>

@import AVFoundation;

#define nilNull(value) ((value) == [NSNull null] ? nil : (value))

@implementation RNMediaPlaybackManager
{
  NSMutableDictionary *_items;
  NSMutableDictionary *_sessions;
  NSMutableOrderedSet *_activeSessions;
}

RCT_EXPORT_MODULE(MediaPlaybackManager)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (instancetype)init
{
  if (self = [super init]) {
    _items = [NSMutableDictionary dictionary];
    _sessions = [NSMutableDictionary dictionary];
    _activeSessions = [NSMutableOrderedSet orderedSet];
  }
  return self;
}

- (void)invalidate
{
  [[_activeSessions lastObject] deactivate];
  [_activeSessions removeAllObjects];
  [_sessions removeAllObjects];
  [_items removeAllObjects];
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_queue_create("com.github.jamesreggio.react.media", DISPATCH_QUEUE_SERIAL);
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"updated"];
}

#pragma mark - Accessors

- (RNMediaPlaybackItem *)itemForKey:(NSNumber *)key
{
  RNMediaPlaybackItem *item = _items[key];
  RCTAssert(item, @"Expected item for key");
  return item;
}

- (RNMediaPlaybackSession *)sessionForKey:(NSNumber *)key
{
  RNMediaPlaybackSession *session = _sessions[key];
  RCTAssert(session, @"Expected session for key");
  return session;
}

#pragma mark - Session Lifecycle

RCT_EXPORT_METHOD(activateSession:(nonnull NSNumber *)key
                          options:(NSDictionary *)options
                         resolver:(RCTPromiseResolveBlock)resolve
                         rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackSession *session = _sessions[key];

  if (!session) {
    session = [[RNMediaPlaybackSession alloc] initWithKey:key options:options];
    _sessions[key] = session;
  }

  RCTAssert(![_activeSessions containsObject:session], @"Session already active");

  [session activate];
  [_activeSessions addObject:session];
  resolve(nil);
}

RCT_EXPORT_METHOD(deactivateSession:(nonnull NSNumber *)key
                            options:(NSDictionary *)options
                           resolver:(RCTPromiseResolveBlock)resolve
                           rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackSession *session = [self sessionForKey:key];
  RCTAssert([_activeSessions containsObject:session], @"Session not active");

  BOOL active = [_activeSessions lastObject] == session;
  [_activeSessions removeObject:session];

  if (active) {
    [_activeSessions removeObject:session];

    if ([_activeSessions count] == 0) {
      [session deactivate];
    } else {
      [[_activeSessions lastObject] activate];
    }
  }

  resolve(nil);
}

#pragma mark - Item Lifecycle

RCT_EXPORT_METHOD(prepareItem:(nonnull NSNumber *)key
                      options:(NSDictionary *)options
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject)
{
  __block RNMediaPlaybackItem *item = _items[key];

  if (!item) {
    item = [[RNMediaPlaybackItem alloc] initWithKey:key manager:self];
    _items[key] = item;
  }

  __block RCTPromise *promise = [RCTPromise promiseWithResolver:resolve rejecter:reject];
  [item prepareWithOptions:options completion:^(NSError *error) {
    if (error) {
      promise.reject(@"PLAYBACK_LOAD_FAILURE", @"The item failed to load", error);
    } else {
      promise.resolve(@{@"duration": item.duration});
    }
  }];
}

RCT_EXPORT_METHOD(activateItem:(nonnull NSNumber *)key
                       options:(NSDictionary *)options
                      resolver:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item activateWithOptions:options];
  resolve(nil);
}

RCT_EXPORT_METHOD(deactivateItem:(nonnull NSNumber *)key
                         options:(NSDictionary *)options
                        resolver:(RCTPromiseResolveBlock)resolve
                        rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item deactivateWithOptions:options];
  resolve(nil);
}

RCT_EXPORT_METHOD(releaseItem:(nonnull NSNumber *)key
                      options:(NSDictionary *)options
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item releaseWithOptions:options];
  resolve(nil);
}

#pragma mark - Item Playback Controls

RCT_EXPORT_METHOD(playItem:(nonnull NSNumber *)key
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item play];
  resolve(nil);
}

RCT_EXPORT_METHOD(pauseItem:(nonnull NSNumber *)key
                   resolver:(RCTPromiseResolveBlock)resolve
                   rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item pause];
  resolve(nil);
}

RCT_EXPORT_METHOD(seekItem:(nonnull NSNumber *)key
                  position:(nonnull NSNumber *)position
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item seekTo:position completion:^(BOOL finished) {
    resolve(@(finished));
  }];
}

RCT_EXPORT_METHOD(skipItem:(nonnull NSNumber *)key
                  position:(nonnull NSNumber *)interval
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item skipBy:interval completion:^(BOOL finished) {
    resolve(@(finished));
  }];
}

RCT_EXPORT_METHOD(setRateForItem:(nonnull NSNumber *)key
                            rate:(nonnull NSNumber *)rate
                        resolver:(RCTPromiseResolveBlock)resolve
                        rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  item.rate = rate;
  resolve(nil);
}

RCT_EXPORT_METHOD(setBufferForItem:(nonnull NSNumber *)key
                          duration:(nonnull NSNumber *)duration
                          resolver:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  item.buffer = duration;
  resolve(nil);
}

#pragma mark - Item Playback Properties

RCT_EXPORT_METHOD(getStatusForItem:(nonnull NSNumber *)key
                          resolver:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  resolve(item.status);
}

RCT_EXPORT_METHOD(getPositionForItem:(nonnull NSNumber *)key
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  resolve(item.position);
}

RCT_EXPORT_METHOD(getDurationForItem:(nonnull NSNumber *)key
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  resolve(item.duration);
}

@end
