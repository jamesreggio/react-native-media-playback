#import "RCTPromise.h"
#import "RNMediaPlayback.h"
#import <React/RCTAssert.h>
#import <React/RCTUtils.h>

@import AVFoundation;

#ifdef DEBUG
#define PLAYBACK_DEBUG
#endif

static void *AVPlayerItemContext = &AVPlayerItemContext;

@implementation RNMediaPlayback
{
  NSMutableDictionary *_items;
  NSMutableDictionary *_promises;

  id _timeObserver;
  AVQueuePlayer *_player;
  float _rate;

#ifdef PLAYBACK_DEBUG
  NSDate *_preparedAt;
#endif
}

RCT_EXPORT_MODULE()

- (instancetype)init
{
  if (self = [super init]) {
    _items = [NSMutableDictionary dictionary];
    _promises = [NSMutableDictionary dictionary];
    _player = [AVQueuePlayer queuePlayerWithItems:@[]];
    _rate = 1.0f;

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(itemDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [notificationCenter addObserver:self selector:@selector(itemDidFinishWithError:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
  }
  return self;
}

- (void)dealloc
{
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
  [notificationCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_queue_create("com.github.jamesreggio.RNMediaPlayback", DISPATCH_QUEUE_SERIAL);
}

#pragma mark - Accessors

- (NSNumber *)keyForItem:(AVPlayerItem *)item
{
  NSArray<NSNumber *> *keys = [_items allKeysForObject:item];
  RCTAssert(keys.count == 1, @"Exactly one key expected for AVPlayerItem");
  return keys.firstObject;
}

- (AVPlayerItem *)itemForKey:(NSNumber *)key
{
  AVPlayerItem *item = _items[key];
  RCTAssert(item, @"Expected AVPlayerItem for key");
  return item;
}

- (void)setItem:(AVPlayerItem *)item forKey:(NSNumber *)key
{
  RCTAssert(!_items[key], @"AVPlayerItem key already in use");
  _items[key] = item;
}

- (void)removeItemForKey:(NSNumber *)key
{
  RCTAssert(_items[key], @"AVPlayerItem key not in use");
  [_items removeObjectForKey:key];
}

- (RCTPromise *)promiseForKey:(NSNumber *)key
{
  RCTPromise *promise = _promises[key];
  RCTAssert(promise, @"Expected RCTPromise for key");
  return promise;
}

- (void)setPromise:(RCTPromise *)promise forKey:(NSNumber *)key
{
  RCTAssert(!_promises[key], @"RCTPromise key already in use");
  _promises[key] = promise;
}

- (void)removePromiseForKey:(NSNumber *)key
{
  // No assertion since we will attempt to remove the promise during release.
  [_promises removeObjectForKey:key];
}

#pragma mark - Events

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"updated"];
}

- (void)sendUpdate
{
  NSMutableDictionary *body = [NSMutableDictionary dictionary];
  body[@"position"] = self.playerPosition;
  body[@"status"] = self.playerStatus;

#ifdef PLAYBACK_DEBUG
  if (_preparedAt && [body[@"status"] isEqual:@"PLAYING"]) {
    NSTimeInterval playbackTime = [[NSDate date] timeIntervalSinceDate:_preparedAt];
    NSLog(@"[playback.native] time to play: %f", playbackTime);
    _preparedAt = nil;
  }
#endif

  [self sendEventWithName:@"updated" body:body];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context
{
  if (context == AVPlayerItemContext) {
    if ([keyPath isEqualToString:@"status"]) {
      AVPlayerItem *item = (AVPlayerItem *)object;
      NSNumber *key = [self keyForItem:item];
      RCTPromise *promise = [self promiseForKey:key];

      if (!promise) {
        return;
      }

      NSNumber *value = change[NSKeyValueChangeNewKey];
      AVPlayerItemStatus status = value.integerValue;
      NSMutableDictionary *payload = [NSMutableDictionary dictionary];

      switch (status) {
        case AVPlayerItemStatusReadyToPlay:
          payload[@"duration"] = @(CMTimeGetSeconds(item.asset.duration));
          promise.resolve(payload);
          break;
        case AVPlayerItemStatusFailed:
          promise.reject(@"PLAYBACK_LOAD_FAILURE", @"The item failed to load", item.error);
          break;
        case AVPlayerItemStatusUnknown:
          return;
      }

      [self removePromiseForKey:key];
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)itemDidFinish:(NSNotification*)notification {
  dispatch_async([self methodQueue], ^{
    RCTAssert(
      notification.object == self.player.currentItem,
      @"Received notification for non-current AVPlayerItem"
    );

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"position"] = self.playerPosition;
    body[@"status"] = @"FINISHED";

    [self sendEventWithName:@"updated" body:body];
  });
}

- (void)itemDidFinishWithError:(NSNotification*)notification {
  dispatch_async([self methodQueue], ^{
    RCTAssert(
      notification.object == self.player.currentItem,
      @"Received notification for non-current AVPlayerItem"
    );

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"position"] = self.playerPosition;
    body[@"status"] = @"FINISHED";
    body[@"error"] = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];

    [self sendEventWithName:@"updated" body:body];
  });
}

#pragma mark - AVAudioSession

- (void)setSessionActive:(BOOL)active
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setActive:active error:nil];
}

- (void)setSessionCategory:(NSString *)categoryName
                      mode:(NSString *)modeName
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

#pragma mark - AVPlayerItem

#define DEFAULT_UPDATE_INTERVAL 30

RCT_EXPORT_METHOD(prepareItem:(nonnull NSNumber *)key
                          url:(NSString *)url
                      options:(NSDictionary *)options
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject)
{
#ifdef PLAYBACK_DEBUG
  _preparedAt = [NSDate date];
#endif

  RCTPromise *promise = [RCTPromise promiseWithResolver:resolve rejecter:reject];
  [self setPromise:promise forKey:key];

  NSArray<NSString *> *keys = @[@"duration"];
  AVAsset *asset = [AVAsset assetWithURL:[NSURL URLWithString:url]];
  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:keys];

  NSNumber *position = options[@"position"];
  if (position) {
    [self seekItem:item position:position completion:nil];
  }

  [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:AVPlayerItemContext];
  [_player insertItem:item afterItem:_player.currentItem];
  [self setItem:item forKey:key];
}

RCT_EXPORT_METHOD(activateItem:(nonnull NSNumber *)key
                       options:(NSDictionary *)options
                      resolver:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  RCTAssert(!_timeObserver, @"Prior AVPlayerItem must be released before activation");
  AVPlayerItem *item = [self itemForKey:key];

  _rate = 1.0f;
  [_player replaceCurrentItemWithPlayerItem:item];
  [self setSessionCategory:options[@"category"] mode:options[@"mode"]];
  [self setSessionActive:YES];

  NSNumber *minimizeStalling = options[@"minimizeStalling"];
  _player.automaticallyWaitsToMinimizeStalling = minimizeStalling ? minimizeStalling.boolValue : NO;

  __weak RNMediaPlayback *weakSelf = self;
  NSNumber *updateInterval = options[@"updateInterval"] ?: @(DEFAULT_UPDATE_INTERVAL);
  CMTime interval = CMTimeMakeWithSeconds(updateInterval.intValue / 1000, NSEC_PER_SEC);
  _timeObserver = [_player addPeriodicTimeObserverForInterval:interval queue:self.methodQueue usingBlock:^(CMTime time) {
    [weakSelf sendUpdate];
  }];

  resolve(nil);
}

RCT_EXPORT_METHOD(releaseItem:(nonnull NSNumber *)key
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayerItem *item = [self itemForKey:key];
  [item removeObserver:self forKeyPath:@"status"];

  if (item == _player.currentItem) {
    [self setSessionActive:NO];
    if (_timeObserver) {
      [_player removeTimeObserver:_timeObserver];
      _timeObserver = nil;
    }
  }

  [_player removeItem:item];
  [self removeItemForKey:key];
  [self removePromiseForKey:key];
  resolve(nil);
}

- (void)seekItem:(AVPlayerItem *)item
        position:(NSNumber *)position
      completion:(void (^)(BOOL finished))completion
{
  CMTime time = CMTimeMakeWithSeconds(position.floatValue, NSEC_PER_SEC);
  [item seekToTime:time completionHandler:completion];
}

RCT_EXPORT_METHOD(seekItem:(nonnull NSNumber *)key
                  position:(nonnull NSNumber *)position
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayerItem *item = [self itemForKey:key];
  [self seekItem:item position:position completion:^(BOOL finished) {
    resolve(@(finished));
  }];
}

RCT_EXPORT_METHOD(getDurationForItem:(nonnull NSNumber *)key
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayerItem *item = [self itemForKey:key];
  NSTimeInterval duration = CMTimeGetSeconds(item.asset.duration);
  resolve(@(duration));
}

RCT_EXPORT_METHOD(setBufferForItem:(nonnull NSNumber *)key
                            amount:(nonnull NSNumber *)amount
                          resolver:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayerItem *item = [self itemForKey:key];
  NSTimeInterval duration = CMTimeGetSeconds(item.duration);
  item.preferredForwardBufferDuration = duration * amount.floatValue;
  resolve(nil);
}

#pragma mark - AVPlayer

- (AVPlayer *)player
{
  RCTAssert(_player.currentItem, @"Expected currentItem for AVPlayer");
  return _player;
}

- (NSNumber *)playerPosition
{
  return @(CMTimeGetSeconds(self.player.currentTime));
}

RCT_REMAP_METHOD(getPosition,
                 getPositionWithResolver:(RCTPromiseResolveBlock)resolve
                                rejecter:(RCTPromiseRejectBlock)reject)
{
  resolve(self.playerPosition);
}

- (NSString *)playerStatus
{
  AVPlayerTimeControlStatus status = self.player.timeControlStatus;

  switch (status) {
    case AVPlayerTimeControlStatusPaused:
      return @"PAUSED";
    case AVPlayerTimeControlStatusPlaying:
      return @"PLAYING";
    case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
      return @"STALLED";
  }
}

RCT_REMAP_METHOD(getStatus,
                 getStatusWithResolver:(RCTPromiseResolveBlock)resolve
                              rejecter:(RCTPromiseRejectBlock)reject)
{
  resolve(self.playerStatus);
}

RCT_EXPORT_METHOD(setRate:(nonnull NSNumber *)rate
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayer *player = self.player;

  // Only update the player rate directly if it's playing.
  if (player.rate == _rate) {
    player.rate = rate.floatValue;
  }

  _rate = rate.floatValue;
  resolve(nil);
}

RCT_REMAP_METHOD(play,
                 playWithResolver:(RCTPromiseResolveBlock)resolve
                         rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayer *player = self.player;
  player.rate = _rate;
  resolve(nil);
}

RCT_REMAP_METHOD(pause,
                 pauseWithResolver:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject)
{
  AVPlayer *player = self.player;
  player.rate = 0.0f;
  resolve(nil);
}

@end
