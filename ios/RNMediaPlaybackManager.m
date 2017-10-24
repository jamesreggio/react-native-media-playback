#import "RNMediaPlaybackManager.h"
#import "RNMediaPlaybackItem.h"
#import "RCTPromise.h"
#import <React/RCTAssert.h>

@import AVFoundation;

@implementation RNMediaPlaybackManager
{
  NSMutableDictionary *_items;
}

RCT_EXPORT_MODULE(MediaPlaybackManager)

- (instancetype)init
{
  if (self = [super init]) {
    _items = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)invalidate
{
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

#pragma mark - Session

- (void)setSessionActive:(BOOL)active
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setActive:active error:nil];
}

- (void)setSessionCategory:(NSString *)categoryName mode:(NSString *)modeName
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSString *category = nil;
  NSString *mode = nil;

  if ([categoryName isEqual: @"Ambient"]) {
    category = AVAudioSessionCategoryAmbient;
  } else if ([categoryName isEqual: @"SoloAmbient"]) {
    category = AVAudioSessionCategorySoloAmbient;
  } else if ([categoryName isEqual: @"Playback"]) {
    category = AVAudioSessionCategoryPlayback;
  } else if ([categoryName isEqual: @"Record"]) {
    category = AVAudioSessionCategoryRecord;
  } else if ([categoryName isEqual: @"PlayAndRecord"]) {
    category = AVAudioSessionCategoryPlayAndRecord;
  }
#if TARGET_OS_IOS
  else if ([categoryName isEqual: @"AudioProcessing"]) {
    category = AVAudioSessionCategoryAudioProcessing;
  }
#endif
  else if ([categoryName isEqual: @"MultiRoute"]) {
    category = AVAudioSessionCategoryMultiRoute;
  }

  if ([modeName isEqual: @"Default"]) {
    mode = AVAudioSessionModeDefault;
  } else if ([modeName isEqual: @"VoiceChat"]) {
    mode = AVAudioSessionModeVoiceChat;
  } else if ([modeName isEqual: @"VideoChat"]) {
    mode = AVAudioSessionModeVideoChat;
  } else if ([modeName isEqual: @"GameChat"]) {
    mode = AVAudioSessionModeGameChat;
  } else if ([modeName isEqual: @"VideoRecording"]) {
    mode = AVAudioSessionModeVideoRecording;
  } else if ([modeName isEqual: @"Measurement"]) {
    mode = AVAudioSessionModeMeasurement;
  } else if ([modeName isEqual: @"MoviePlayback"]) {
    mode = AVAudioSessionModeMoviePlayback;
  } else if ([modeName isEqual: @"SpokenAudio"]) {
    mode = AVAudioSessionModeSpokenAudio;
  }

  [session setCategory:category mode:mode options:0 error:nil];
}

#pragma mark - Lifecycle

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
  [self setSessionCategory:options[@"category"] mode:options[@"mode"]];
  [self setSessionActive:YES];
  resolve(nil);
}

RCT_EXPORT_METHOD(deactivateItem:(nonnull NSNumber *)key
                         options:(NSDictionary *)options
                        resolver:(RCTPromiseResolveBlock)resolve
                        rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item deactivateWithOptions:options];

  NSNumber *remainActive = options[@"remainActive"];
  if (!remainActive || !remainActive.boolValue) {
    [self setSessionActive:NO];
  }

  resolve(nil);
}

RCT_EXPORT_METHOD(releaseItem:(nonnull NSNumber *)key
                      options:(NSDictionary *)options
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlaybackItem *item = [self itemForKey:key];
  [item releaseWithOptions:options];

  NSNumber *remainActive = options[@"remainActive"];
  if (!remainActive || !remainActive.boolValue) {
    [self setSessionActive:NO];
  }

  resolve(nil);
}

#pragma mark - Playback Controls

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

#pragma mark - Playback Properties

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
