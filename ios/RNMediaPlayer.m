#import <React/RCTAssert.h>
#import <React/RCTConvert.h>
#import "AVAsset+RNMediaPlayback.h"
#import "AVPlayerItem+RNMediaPlayback.h"
#import "RNMediaPlayback.h"
#import "RNMediaPlayer.h"
#import "RNMediaSession.h"

@import AVFoundation;

#define DEFAULT_RATE @(1.0f)
#define DEFAULT_AVOID_STALLS @NO
#define DEFAULT_PRECISE_TIMING @NO
#define DEFAULT_UPDATE_INTERVAL @(15000) // ms
#define DEFAULT_END_BEHAVIOR AVPlayerActionAtItemEndAdvance
#define DEFAULT_PITCH_ALGORITHM AVAudioTimePitchAlgorithmLowQualityZeroLatency

#define RAPID_UPDATE_DEBOUNCE_INTERVAL 100 // ms
#define SEEK_DURATION_ADJUSTMENT 250 // ms

static void *AVPlayerContext = &AVPlayerContext;

@implementation RNMediaPlayer
{
  NSNumber *_key;
  dispatch_queue_t _methodQueue;
  RNMediaSession *_session;
  AVQueuePlayer *_player;
  BOOL _preciseTiming;

  float _rate;
  id _intervalObserver;
}

#pragma mark - AVFoundation Enumerations

+ (AVPlayerActionAtItemEnd)getEndBehavior:(NSString *)name
{
  if ([name isEqual: @"advance"]) {
    return AVPlayerActionAtItemEndAdvance;
  } else if ([name isEqual: @"pause"]) {
    return AVPlayerActionAtItemEndPause;
  }

  RCTAssert(!name, @"Unknown end behavior: %@", name);
  return DEFAULT_END_BEHAVIOR;
}

+ (AVAudioTimePitchAlgorithm)getPitchAlgorithm:(NSString *)name
{
  if ([name isEqual: @"lowQuality"]) {
    return AVAudioTimePitchAlgorithmLowQualityZeroLatency;
  } else if ([name isEqual: @"timeDomain"]) {
    return AVAudioTimePitchAlgorithmTimeDomain;
  } else if ([name isEqual: @"spectral"]) {
    return AVAudioTimePitchAlgorithmSpectral;
  } else if ([name isEqual: @"varispeed"]) {
    return AVAudioTimePitchAlgorithmVarispeed;
  }

  RCTAssert(!name, @"Unknown pitch algorithm: %@", name);
  return DEFAULT_PITCH_ALGORITHM;
}

#pragma mark - Constructors

- (instancetype)initWithKey:(NSNumber *)key
                methodQueue:(dispatch_queue_t)methodQueue
                    options:(NSDictionary *)options

{
  if (self = [super init]) {
    // Initialize instance variables.

    _key = key;
    _methodQueue = methodQueue;
    _session = [[RNMediaSession alloc] initWithOptions:options];
    _player = [AVQueuePlayer queuePlayerWithItems:[NSArray array]];
    _active = NO;

    // Process options.

    _player.actionAtItemEnd = [RNMediaPlayer getEndBehavior:nilNull(options[@"endBehavior"])];

    NSNumber *avoidStalls = nilNull(options[@"avoidStalls"]) ?: DEFAULT_AVOID_STALLS;
    _player.automaticallyWaitsToMinimizeStalling = avoidStalls.boolValue;

    NSNumber *preciseTiming = nilNull(options[@"preciseTiming"]) ?: DEFAULT_PRECISE_TIMING;
    _preciseTiming = preciseTiming.boolValue;

    NSNumber *rate = nilNull(options[@"rate"]) ?: DEFAULT_RATE;
    _rate = rate.floatValue;

    // Observe events.

    __weak typeof(self) weakSelf = self;
    void (^intervalBlock)(CMTime) = ^(__unused CMTime time) {
      [weakSelf playerDidUpdateTrack];
    };

    NSNumber *updateInterval = nilNull(options[@"updateInterval"]) ?: DEFAULT_UPDATE_INTERVAL;
    _intervalObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(updateInterval.intValue / 1000.0f, NSEC_PER_SEC)
                                                              queue:_methodQueue
                                                         usingBlock:intervalBlock];

    [_player addObserver:self
              forKeyPath:@"currentItem"
                 options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld)
                 context:AVPlayerContext];

    [_player addObserver:self
              forKeyPath:@"timeControlStatus"
                 options:0
                 context:AVPlayerContext];
  }
  return self;
}

- (void)dealloc
{
  if (_player.currentItem) {
    [self removeObserversForItem:_player.currentItem];
  }

  if (_intervalObserver) {
    [_player removeTimeObserver:_intervalObserver];
    _intervalObserver = nil;
  }

  @try {
    [_player removeObserver:self forKeyPath:@"currentItem" context:AVPlayerContext];
    [_player removeObserver:self forKeyPath:@"timeControlStatus" context:AVPlayerContext];
  } @catch (__unused NSException *exception) {
    // If the subscription doesn't exist, KVO will throw.
  }
}

#pragma mark - Event Observers

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context
{
  if (context == AVPlayerContext) {
    RCTAssert(_player == object, @"Received update for unexpected AVPlayer");

    if ([keyPath isEqualToString:@"currentItem"]) {
      LOG(@"updated currentItem: %@", self.id);

      AVPlayerItem *lastItem = nilNull(change[NSKeyValueChangeOldKey]);
      AVPlayerItem *nextItem = nilNull(change[NSKeyValueChangeNewKey]);
      [self removeObserversForItem:lastItem];
      [self addObserversForItem:nextItem];

      if (nextItem) {
        [self playerWillActivateTrack];
      } else {
        [self playerDidDeactivate];
      }
    } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
      LOG(@"updated timeControlStatus: %@", self.id);
      [self playerDidUpdateTrack];
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)addObserversForItem:(AVPlayerItem *)item
{
  if (!item) {
    return;
  }

  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

  [notificationCenter addObserver:self
                         selector:@selector(itemDidFinish:)
                             name:AVPlayerItemDidPlayToEndTimeNotification
                           object:item];

  [notificationCenter addObserver:self
                         selector:@selector(itemDidFinishWithError:)
                             name:AVPlayerItemFailedToPlayToEndTimeNotification
                           object:item];

  CMTimeRange range = item.RNMediaPlayback_range;
  if (!CMTIMERANGE_IS_INDEFINITE(range)) {
    NSMutableArray<NSValue *> *boundaries = [NSMutableArray arrayWithCapacity:2];
    if (!CMTIME_IS_POSITIVE_INFINITY(range.duration)) {
      [boundaries addObject:[NSValue valueWithCMTime:CMTimeRangeGetEnd(range)]];
    }

    // We only attach an observer for the upper end of the range, since it should not
    // technically be possible to rewrind past the lower end (and there's nothing we
    // can do if it does happen).
    if (boundaries.count) {
      __weak typeof(self) weakSelf = self;
      void (^boundaryBlock)(void) = ^() {
        LOG(@"range itemDidFinish");
        [weakSelf playerDidFinishTrackWithError:nil];
        [weakSelf nextTrack];
      };

      item.RNMediaPlayback_boundaryObserver = [_player addBoundaryTimeObserverForTimes:boundaries
                                                                                 queue:_methodQueue
                                                                            usingBlock:boundaryBlock];
    }
  }
}

- (void)removeObserversForItem:(AVPlayerItem *)item
{
  if (!item) {
    return;
  }

  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:item];
  [notificationCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];

  id boundaryObserver = item.RNMediaPlayback_boundaryObserver;
  if (boundaryObserver) {
    [_player removeTimeObserver:boundaryObserver];
    item.RNMediaPlayback_boundaryObserver = nil;
  }
}

- (void)itemDidFinish:(NSNotification*)notification {
  LOG(@"itemDidFinish");
  RCTAssert(_player.currentItem == notification.object, @"Received notification for unexpected AVPlayerItem");
  [self playerDidFinishTrackWithError:nil];
}

- (void)itemDidFinishWithError:(NSNotification*)notification {
  LOG(@"itemDidFinishWithError");
  RCTAssert(_player.currentItem == notification.object, @"Received notification for unexpected AVPlayerItem");
  [self playerDidFinishTrackWithError:notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]];
}

#pragma mark - AVFoundation Factories

+ (NSMapTable<NSURL *, AVAsset *> *)assetCache
{
  static NSMapTable<NSURL *, AVAsset *> *cache;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [NSMapTable strongToWeakObjectsMapTable];
  });
  return cache;
}

- (AVAsset *)assetForURL:(NSURL *)url
{
  NSMapTable<NSURL *, AVAsset *> *cache = RNMediaPlayer.assetCache;
  AVAsset *asset = [cache objectForKey:url];

  // If we're streaming a non-M4A audio file, playback may never start if precise timing is requested.
  BOOL preciseTiming = _preciseTiming && (url.isFileURL || [url.pathExtension isEqualToString:@"m4a"]);

  if (!asset || (preciseTiming && !asset.RNMediaPlayback_preciseTiming)) {
    LOG(@"new assetForURL: %@", url);
    asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @(preciseTiming)}];
    asset.RNMediaPlayback_preciseTiming = preciseTiming;
    [cache setObject:asset forKey:url];
  } else {
    LOG(@"reusing assetForURL: %@", url);
  }

  return asset;
}

- (AVPlayerItem *)itemForTrack:(NSDictionary *)options
{
  NSString *id = nilNull(options[@"id"]);
  RCTAssert(id, @"Expected track ID");
  LOG(@"itemForTrack: %@", id);

  NSString *url = nilNull(options[@"url"]);
  RCTAssert(url, @"Expected item URL");
  AVAsset *asset = [self assetForURL:[NSURL URLWithString:url]];
  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];

  item.RNMediaPlayback_id = id;
  item.audioTimePitchAlgorithm = [RNMediaPlayer getPitchAlgorithm:options[@"pitchAlgorithm"]];

  NSNumber *position = nilNull(options[@"position"]);
  if (position) {
    CMTime time = CMTimeMakeWithSeconds(position.doubleValue, NSEC_PER_SEC);
    [item seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
  }

  NSNumber *buffer = nilNull(options[@"buffer"]);
  if (buffer) {
    item.preferredForwardBufferDuration = buffer.doubleValue;
  }

  if (nilNull(options[@"range"])) {
    NSDictionary *range = [RCTConvert NSDictionary:options[@"range"]];
    NSNumber *lower = nilNull(range[@"lower"]);
    NSNumber *upper = nilNull(range[@"upper"]);
    CMTime start = lower ? CMTimeMakeWithSeconds(lower.doubleValue, NSEC_PER_SEC) : kCMTimeZero;
    CMTime duration = upper ? CMTimeSubtract(CMTimeMakeWithSeconds(upper.doubleValue, NSEC_PER_SEC), start) : kCMTimePositiveInfinity;
    item.RNMediaPlayback_range = CMTimeRangeMake(start, duration);
  }

  return item;
}

#pragma mark - Player Lifecycle

- (void)ensureActive
{
  if (!_active) {
    [self playerWillActivate];
  }
}

- (void)resignActive
{
  if (_active) {
    [self playerDidDeactivate];
  }
}

- (void)playerWillActivate
{
  [_session activate];
  LOG(@"playerWillActivate");
  if ([_delegate respondsToSelector:@selector(playerWillActivate:)]) {
    [_delegate playerWillActivate:self];
  }
}

- (void)playerDidDeactivate
{
  [_session deactivate];
  LOG(@"playerDidDeactivate");
  if ([_delegate respondsToSelector:@selector(playerDidDeactivate:)]) {
    [_delegate playerDidDeactivate:self];
  }
}

- (void)playerWillActivateTrack
{
  RCTAssert(_player.currentItem, @"No track to activate");
  NSDictionary *body = @{@"id": self.id};
  LOG(@"playerWillActivateTrack: %@", body);
  if ([_delegate respondsToSelector:@selector(playerWillActivateTrack:withBody:)]) {
    [_delegate playerWillActivateTrack:self withBody:body];
  }
}

- (void)playerDidUpdateTrack
{
  static BOOL queued = NO;
  if (queued) {
    return;
  }

  queued = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, RAPID_UPDATE_DEBOUNCE_INTERVAL * NSEC_PER_MSEC), _methodQueue, ^{
    queued = NO;
    [weakSelf _playerDidUpdateTrack];
  });
}

- (void)_playerDidUpdateTrack
{
  // We may arrive here after the player has been deactivated.
  if (!_player.currentItem) {
    return;
  }

  NSDictionary *body = @{
    @"id": self.id,
    @"status": self.status,
    @"position": nullNil(self.position),
    @"duration": nullNil(self.duration),
  };

  LOG(@"playerDidUpdateTrack: %@", body);
  if ([_delegate respondsToSelector:@selector(playerDidUpdateTrack:withBody:)]) {
    [_delegate playerDidUpdateTrack:self withBody:body];
  }
}

- (void)playerDidFinishTrackWithError:(NSError *)error
{
  RCTAssert(_player.currentItem, @"No track to finish");

  NSDictionary *body = @{
    @"id": self.id,
    @"error": nullNil(error),
  };

  LOG(@"playerDidFinishTrack: %@", body);
  if ([_delegate respondsToSelector:@selector(playerDidFinishTrack:withBody:)]) {
    [_delegate playerDidFinishTrack:self withBody:body];
  }
}

#pragma mark - Track Management

- (void)insertTracks:(NSArray<NSDictionary *> *)tracks andAdvance:(BOOL)advance
{
  AVPlayerItem *firstItem;
  AVPlayerItem *prevItem = _player.currentItem;
  for (NSDictionary *track in tracks) {
    AVPlayerItem *nextItem = [self itemForTrack:track];
    [_player insertItem:nextItem afterItem:prevItem];
    prevItem = nextItem;
    if (!firstItem) {
      firstItem = nextItem;
    }
  }

  if (advance) {
    if (_player.currentItem != firstItem) {
      [_player advanceToNextItem];
      RCTAssert(_player.currentItem == firstItem, @"Expected next AVPlayerItem to be the first");
    }
  }
}

- (void)replaceTracks:(NSArray<NSDictionary *> *)tracks andAdvance:(BOOL)advance
{
  NSArray<AVPlayerItem *> *items = _player.items;
  NSUInteger currentIndex = [items indexOfObject:_player.currentItem];

  if (currentIndex == NSNotFound) {
    [_player removeAllItems];
  } else {
    for (NSUInteger index = currentIndex + 1; index < items.count; index++) {
      [_player removeItem:items[index]];
    }
  }

  [self insertTracks:tracks andAdvance:advance];
}

- (void)nextTrack
{
  [_player advanceToNextItem];
}

#pragma mark - Playback Controls

- (void)play
{
  [self ensureActive];
  _player.rate = _rate;
}

- (void)pause
{
  _player.rate = 0.0f;
}

- (void)toggle
{
  if (_player.rate) {
    [self pause];
  } else {
    [self play];
  }
}

- (void)stop
{
  [_player removeAllItems];
  [self resignActive];
}

//XXX waveforms
- (void)seekTo:(NSNumber *)position completion:(void (^)(BOOL finished))completion
{
  CMTimeRange range = _player.currentItem.RNMediaPlayback_range;
  if (CMTIMERANGE_IS_INDEFINITE(range)) {
    // AVQueuePlayer will advance two tracks if you seek beyond the duration of the current track.
    // We subtract a small amount to prevent this from happening.
    CMTime duration = CMTimeSubtract(_player.currentItem.duration, CMTimeMakeWithSeconds(SEEK_DURATION_ADJUSTMENT / 1000.0f, NSEC_PER_SEC));
    range = CMTimeRangeMake(kCMTimeZero, CMTIME_IS_INDEFINITE(duration) ? kCMTimePositiveInfinity : duration);
  }

  __weak typeof(self) weakSelf = self;
  CMTime clampedPosition = CMTimeClampToRange(CMTimeMakeWithSeconds(position.doubleValue, NSEC_PER_SEC), range);
  [_player seekToTime:clampedPosition toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    [weakSelf playerDidUpdateTrack];
    if (completion) {
      completion(finished);
    }
  }];
}

//XXX waveforms
- (void)skipBy:(NSNumber *)interval completion:(void (^)(BOOL finished))completion
{
  CMTime position = CMTimeAdd(_player.currentTime, CMTimeMakeWithSeconds(interval.doubleValue, NSEC_PER_SEC));
  [self seekTo:@(CMTimeGetSeconds(position)) completion:completion];
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

- (NSString *)id
{
  return _player.currentItem.RNMediaPlayback_id;
}

- (NSString *)status
{
  if (!_player.currentItem) {
    return @"IDLE";
  }

  switch (_player.timeControlStatus) {
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
  CMTime position = _player.currentTime;
  return CMTIME_IS_INDEFINITE(position) ? nil : @(CMTimeGetSeconds(position));
}

- (NSNumber *)duration
{
  CMTime duration = _player.currentItem.duration;
  return CMTIME_IS_INDEFINITE(duration) ? nil : @(CMTimeGetSeconds(duration));
}

@end
