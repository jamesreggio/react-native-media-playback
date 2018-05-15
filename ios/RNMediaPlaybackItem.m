#import "RNMediaPlaybackItem.h"
#import <React/RCTAssert.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>

@import AVFoundation;

#define PLAYBACK_DEBUG 0

#if PLAYBACK_DEBUG
#define LOG(...) NSLog(@"[playback.native] " __VA_ARGS__)
#else
#define LOG(...)
#endif

#define nilNull(value) ((value) == [NSNull null] ? nil : (value))

static void *AVPlayerItemContext = &AVPlayerItemContext;

@implementation RNMediaPlaybackItem
{
  NSNumber *_key;
  __weak RCTEventEmitter *_manager;

  NSString *_url;
  AVPlayer *_player;
  AVPlayerItem *_item;
  float _rate;

  BOOL _updatesEnabled;
  void (^_prepareCompletion)(NSError *error);
  id _intervalObserver;
  id _boundaryObserver;
}

- (instancetype)initWithKey:(NSNumber *)key manager:(RCTEventEmitter *)manager
{
  if (self = [super init]) {
    _key = key;
    _manager = manager;
  }
  return self;
}

- (void)dealloc
{
  if (_prepareCompletion) {
    [_item removeObserver:self forKeyPath:@"status"];
    _prepareCompletion = nil;
  }

  if (_item) {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [notificationCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
  }

  if (_intervalObserver) {
    [_player removeTimeObserver:_intervalObserver];
    _intervalObserver = nil;
  }

  if (_boundaryObserver) {
    [_player removeTimeObserver:_boundaryObserver];
    _boundaryObserver = nil;
  }
}

- (dispatch_queue_t)methodQueue
{
  return _manager.methodQueue;
}

#pragma mark - Events

- (void)sendUpdate
{
  NSMutableDictionary *body = [NSMutableDictionary dictionary];
  body[@"status"] = self.status;
  [self sendUpdateWithBody:body];
}

- (void)sendUpdateWithBody:(NSMutableDictionary *)body
{
  if (!_updatesEnabled) {
    return;
  }

  body[@"key"] = _key;
  body[@"position"] = self.position;
  LOG(@"sendUpdateWithBody");
  [_manager sendEventWithName:@"updated" body:body];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context
{
  if (context == AVPlayerItemContext) {
    if ([keyPath isEqualToString:@"status"]) {
      RCTAssert(_item == object, @"Received update for unexpected AVPlayerItem");

      if (!_prepareCompletion) {
        return;
      }

      NSNumber *value = change[NSKeyValueChangeNewKey];
      AVPlayerItemStatus status = value.integerValue;
      switch (status) {
        case AVPlayerItemStatusReadyToPlay:
          _prepareCompletion(nil);
          break;
        case AVPlayerItemStatusFailed:
          _prepareCompletion(_item.error);
          break;
        case AVPlayerItemStatusUnknown:
          return;
      }

      [_item removeObserver:self forKeyPath:@"status"];
      _prepareCompletion = nil;
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)itemDidFinish:(NSNotification*)notification {
  LOG(@"itemDidFinish");
  RCTAssert(_item == notification.object, @"Received notification for unexpected AVPlayerItem");
  NSMutableDictionary *body = [NSMutableDictionary dictionary];
  body[@"status"] = @"FINISHED";
  [self sendUpdateWithBody:body];
}

- (void)itemDidFinishWithError:(NSNotification*)notification {
  LOG(@"itemDidFinishWithError");
  RCTAssert(_item == notification.object, @"Received notification for unexpected AVPlayerItem");
  NSMutableDictionary *body = [NSMutableDictionary dictionary];
  body[@"status"] = @"FINISHED";
  body[@"error"] = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
  [self sendUpdateWithBody:body];
}

#pragma mark - Lifecycle

#define DEFAULT_UPDATE_INTERVAL 30000

- (void)prepareWithOptions:(NSDictionary *)options completion:(void (^)(NSError *error))completion
{
  RCTAssert(!_item, @"Item already prepared");
  RCTAssert(!_intervalObserver, @"Item already activated");

  NSURL *url = [NSURL URLWithString:options[@"url"]];
  // If we're streaming a non-M4A audio file, playback may never start if precise timing is requested.
  BOOL preferPreciseTiming = url.isFileURL || [url.pathExtension isEqualToString:@"m4a"];
  AVAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @(preferPreciseTiming)}];
  _item = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:@[@"duration"]];

  NSNumber *position = nilNull(options[@"position"]);
  if (position) {
    [self seekTo:position completion:nil];
  }

  NSNumber *buffer = nilNull(options[@"buffer"]);
  if (buffer) {
    [self setBuffer:buffer];
  }

  _prepareCompletion = completion;
  [_item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:AVPlayerItemContext];
  _player = [AVPlayer playerWithPlayerItem:_item];

  // iOS 10+
  if ([_player respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
    _player.automaticallyWaitsToMinimizeStalling = YES; //XXX make configurable?
  }
}

- (void)activateWithOptions:(NSDictionary *)options
{
  RCTAssert(_item, @"Item not prepared");
  RCTAssert(!_intervalObserver, @"Item already activated");

  NSNumber *position = nilNull(options[@"position"]);
  if (position) {
    [self seekTo:position completion:nil];
  }

  NSNumber *rate = nilNull(options[@"rate"]);
  _rate = rate ? rate.floatValue : 1.0f;

  __weak typeof(self) weakSelf = self;
  void (^updateBlock)(void) = ^() {
    [weakSelf sendUpdate];
  };

  _updatesEnabled = YES;
  NSNumber *updateInterval = nilNull(options[@"updateInterval"]) ?: @(DEFAULT_UPDATE_INTERVAL);
  CMTime interval = CMTimeMakeWithSeconds(updateInterval.intValue / 1000, NSEC_PER_SEC);
  _intervalObserver = [_player addPeriodicTimeObserverForInterval:interval queue:self.methodQueue usingBlock:^(CMTime time) {
    LOG(@"intervalObserver");
    updateBlock();
  }];

  if (nilNull(options[@"updateBoundaries"])) {
    NSArray<NSNumber *> *updateBoundaries = [RCTConvert NSNumberArray:options[@"updateBoundaries"]];
    NSMutableArray<NSValue *> *boundaries = [NSMutableArray arrayWithCapacity:updateBoundaries.count];
    for (NSNumber *updateBoundary in updateBoundaries) {
      CMTime boundary = CMTimeMakeWithSeconds(updateBoundary.intValue, NSEC_PER_SEC);
      [boundaries addObject:[NSValue valueWithBytes:&boundary objCType:@encode(CMTime)]];
    }
    _boundaryObserver = [_player addBoundaryTimeObserverForTimes:boundaries queue:self.methodQueue usingBlock:updateBlock];
  }

  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter addObserver:self selector:@selector(itemDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
  [notificationCenter addObserver:self selector:@selector(itemDidFinishWithError:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
}

- (void)deactivateWithOptions:(NSDictionary *)options
{
  RCTAssert(_item, @"Item not prepared");
  RCTAssert(_intervalObserver, @"Item not activated");
  [self pause];

  _updatesEnabled = NO;
  [_player removeTimeObserver:_intervalObserver];
  _intervalObserver = nil;

  if (_boundaryObserver) {
    [_player removeTimeObserver:_boundaryObserver];
    _boundaryObserver = nil;
  }

  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
  [notificationCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_item];
}

- (void)releaseWithOptions:(NSDictionary *)options
{
  RCTAssert(_item, @"Item not prepared");
  RCTAssert(!_intervalObserver, @"Item still activated");

  [_player replaceCurrentItemWithPlayerItem:nil];
  _player = nil;
  _item = nil;
}

#pragma mark - Playback Controls

- (void)play
{
  _player.rate = _rate;
}

- (void)pause
{
  _player.rate = 0.0f;
}

- (void)seekTo:(NSNumber *)position completion:(void (^)(BOOL finished))completion
{
  _updatesEnabled = NO;
  __weak typeof(self) weakSelf = self;
  CMTime time = CMTimeMakeWithSeconds(position.floatValue, NSEC_PER_SEC);
  [_player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    __typeof__(self) strongSelf = weakSelf;
    if (strongSelf) {
      strongSelf->_updatesEnabled = YES;
      [strongSelf sendUpdate];
    }
    if (completion) {
      completion(finished);
    }
  }];
}

- (void)skipBy:(NSNumber *)interval completion:(void (^)(BOOL finished))completion
{
  NSInteger position = self.position.intValue + interval.intValue;
  position = MAX(0, position);
  position = MIN(position, self.duration.intValue);
  [self seekTo:@(position) completion: completion];
}

- (void)setBuffer:(NSNumber *)amount
{
  // iOS 10+
  if ([_item respondsToSelector:@selector(setPreferredForwardBufferDuration:)]) {
    _item.preferredForwardBufferDuration = amount.floatValue;
  }
}

- (void)setRate:(NSNumber *)rate
{
  // Only update the player rate directly if it's playing.
  if (_player.rate == _rate) {
    _player.rate = rate.floatValue;
  }
  _rate = rate.floatValue;
}

#pragma mark - Playback Properties

- (NSString *)status
{
  if (!_player) {
    return @"IDLE";
  }

  if (![_player respondsToSelector:@selector(timeControlStatus)]) {
    return _player.rate > 0 ? @"PLAYING" : @"PAUSED";
  }

  AVPlayerTimeControlStatus status = _player.timeControlStatus;
  switch (status) {
    case AVPlayerTimeControlStatusPaused:
      return @"PAUSED";
    case AVPlayerTimeControlStatusPlaying:
      return @"PLAYING";
    case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
      return @"STALLED";
  }
}

- (NSNumber *)position
{
  return _player ? @(CMTimeGetSeconds(_player.currentTime)) : nil;
}

- (NSNumber *)duration
{
  return _item ? @(CMTimeGetSeconds(_item.asset.duration)) : nil;
}

@end
