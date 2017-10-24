#import "RNMediaPlaybackItem.h"
#import <React/RCTAssert.h>
#import <React/RCTConvert.h>

@import AVFoundation;

static void *AVPlayerItemContext = &AVPlayerItemContext;

@implementation RNMediaPlaybackItem
{
  NSNumber *_key;
  __weak RCTEventEmitter *_manager;
  void (^_prepareCompletion)(NSError *error);

  NSString *_url;
  AVPlayer *_player;
  AVPlayerItem *_item;
  id _intervalObserver; //XXX remove in dealloc
  id _boundaryObserver;
  float _rate;
}

- (instancetype)initWithKey:(NSNumber *)key manager:(RCTEventEmitter *)manager
{
  if (self = [super init]) {
    _key = key;
    _manager = manager;

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(itemDidFinish:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [notificationCenter addObserver:self selector:@selector(itemDidFinishWithError:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
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
  return _manager.methodQueue;
}

#pragma mark - Events

- (void)sendUpdateWithBody:(NSMutableDictionary *)body
{
  dispatch_async(_manager.methodQueue, ^{
    body[@"key"] = _key;
    body[@"position"] = self.position;
    [_manager sendEventWithName:@"updated" body:body];
  });
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
  RCTAssert(_item == notification.object, @"Received notification for unexpected AVPlayerItem");
  NSMutableDictionary *body = [NSMutableDictionary dictionary];
  body[@"status"] = @"FINISHED";
  [self sendUpdateWithBody:body];
}

- (void)itemDidFinishWithError:(NSNotification*)notification {
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

  AVAsset *asset = [AVAsset assetWithURL:[NSURL URLWithString:options[@"url"]]];
  _item = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:@[@"duration"]];

  NSNumber *position = options[@"position"];
  if (position) {
    [self seekTo:position completion:nil];
  }

  NSNumber *buffer = options[@"buffer"];
  if (buffer) {
    [self setBuffer:buffer];
  }

  _prepareCompletion = completion;
  [_item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:AVPlayerItemContext];
  _player = [AVPlayer playerWithPlayerItem:_item];
  _player.automaticallyWaitsToMinimizeStalling = NO; //XXX make configurable?
}

- (void)activateWithOptions:(NSDictionary *)options
{
  RCTAssert(_item, @"Item not prepared");
  RCTAssert(!_intervalObserver, @"Item already activated");

  NSNumber *position = options[@"position"];
  if (position) {
    [self seekTo:position completion:nil];
  }

  NSNumber *rate = options[@"rate"];
  _rate = rate ? rate.floatValue : 1.0f;

  __weak typeof(self) weakSelf = self;
  void (^updateBlock)(void) = ^() {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"status"] = weakSelf.status;
    [weakSelf sendUpdateWithBody:body];
  };

  NSNumber *updateInterval = options[@"updateInterval"] ?: @(DEFAULT_UPDATE_INTERVAL);
  CMTime interval = CMTimeMakeWithSeconds(updateInterval.intValue, NSEC_PER_MSEC);
  _intervalObserver = [_player addPeriodicTimeObserverForInterval:interval queue:self.methodQueue usingBlock:^(CMTime time) {
    updateBlock();
  }];

  if (options[@"updateBoundaries"]) {
    NSArray<NSNumber *> *updateBoundaries = [RCTConvert NSNumberArray:options[@"updateBoundaries"]];
    NSMutableArray<NSValue *> *boundaries = [NSMutableArray arrayWithCapacity:updateBoundaries.count];
    for (NSNumber *updateBoundary in updateBoundaries) {
      CMTime boundary = CMTimeMakeWithSeconds(updateBoundary.intValue, NSEC_PER_MSEC);
      [boundaries addObject:[NSValue valueWithBytes:&boundary objCType:@encode(CMTime)]];
    }
    _boundaryObserver = [_player addBoundaryTimeObserverForTimes:boundaries queue:self.methodQueue usingBlock:updateBlock];
  }
}

- (void)deactivateWithOptions:(NSDictionary *)options
{
  RCTAssert(_item, @"Item not prepared");
  RCTAssert(_intervalObserver, @"Item not activated");
  [self pause];

  [_player removeTimeObserver:_intervalObserver];
  _intervalObserver = nil;

  if (_boundaryObserver) {
    [_player removeTimeObserver:_boundaryObserver];
    _boundaryObserver = nil;
  }
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
  CMTime time = CMTimeMakeWithSeconds(position.floatValue, NSEC_PER_SEC);
  [_player seekToTime:time completionHandler:completion];
}

- (void)setBuffer:(NSNumber *)amount
{
  _item.preferredForwardBufferDuration = amount.floatValue;
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
