#import <React/RCTAssert.h>
#import <React/RCTConvert.h>
#import "AVPlayerItem+RNMediaPlayback.h"
#import "RNMediaPlayback.h"
#import "RNMediaAsset.h"
#import "RNMediaTrack.h"
#import "RNMediaSession.h"
#import "RNMediaPlayer.h"
@import AVFoundation;

#define DEFAULT_RATE @(1.0f)
#define DEFAULT_AVOID_STALLS @NO
#define DEFAULT_PRECISE_TIMING @NO
#define DEFAULT_UPDATE_INTERVAL @(15000) // ms
#define DEFAULT_END_BEHAVIOR AVPlayerActionAtItemEndAdvance

#define SKIP_INTERVAL_WINDOW_RATIO (2.0f / 3.0f)
#define RAPID_UPDATE_DEBOUNCE_INTERVAL 100 // ms
#define SEEK_DURATION_ADJUSTMENT 250 // ms

static void *AVPlayerContext = &AVPlayerContext;

@implementation RNMediaPlayer
{
  RNMediaSession *_session;
  BOOL _preciseTiming;
  BOOL _active;
  float _rate;

  id _intervalObserver;
  id _boundaryObserver;
  BOOL _updateQueued;
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

#pragma mark - Constructors

- (instancetype)initWithKey:(NSNumber *)key
                methodQueue:(dispatch_queue_t)methodQueue
                    options:(NSDictionary *)options

{
  if (self = [super init]) {
    // Initialize instance variables.

    _key = key;
    _methodQueue = methodQueue;
    _session = [RNMediaSession sessionWithOptions:options];
    _AVPlayer = [AVQueuePlayer queuePlayerWithItems:[NSArray array]];
    _active = NO;
    _updateQueued = NO;

    // Process options.

    _AVPlayer.actionAtItemEnd = [RNMediaPlayer getEndBehavior:nilNull(options[@"endBehavior"])];

    NSNumber *avoidStalls = nilNull(options[@"avoidStalls"]) ?: DEFAULT_AVOID_STALLS;
    _AVPlayer.automaticallyWaitsToMinimizeStalling = avoidStalls.boolValue;

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
    CMTime updateIntervalTime = CMTimeMakeWithSeconds(updateInterval.intValue / 1000.0f, NSEC_PER_SEC);
    _intervalObserver = [_AVPlayer addPeriodicTimeObserverForInterval:updateIntervalTime
                                                                queue:_methodQueue
                                                           usingBlock:intervalBlock];

    [_AVPlayer addObserver:self
                forKeyPath:@"currentItem"
                   options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld)
                   context:AVPlayerContext];

    [_AVPlayer addObserver:self
                forKeyPath:@"timeControlStatus"
                   options:0
                   context:AVPlayerContext];
  }
  return self;
}

- (void)dealloc
{
  if (_intervalObserver) {
    [_AVPlayer removeTimeObserver:_intervalObserver];
    _intervalObserver = nil;
  }

  if (_boundaryObserver) {
    [_AVPlayer removeTimeObserver:_boundaryObserver];
    _boundaryObserver = nil;
  }

  @try {
    [_AVPlayer removeObserver:self forKeyPath:@"currentItem" context:AVPlayerContext];
    [_AVPlayer removeObserver:self forKeyPath:@"timeControlStatus" context:AVPlayerContext];
  } @catch (__unused NSException *exception) {
    // If the subscription doesn't exist, KVO will throw.
  }

  // We assert inactivity in [RNMediaTrack dealloc] in order to avoid losing track deactivation events
  // during normal operation, so we need to explicitly deactivate the active track here to avoid throwing.
  [self.track deactivate];
}

#pragma mark - Events

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context
{
  if (context == AVPlayerContext) {
    RCTAssert(_AVPlayer == object, @"Received update for unexpected AVPlayer");

    if ([keyPath isEqualToString:@"currentItem"]) {
      AVPlayerItem *prevItem = nilNull(change[NSKeyValueChangeOldKey]);
      AVPlayerItem *nextItem = nilNull(change[NSKeyValueChangeNewKey]);
      RNMediaTrack *prevTrack = prevItem.RNMediaPlayback_track;
      RNMediaTrack *nextTrack = nextItem.RNMediaPlayback_track;
      LOG(@"[RNMediaPlayer updatedCurrentItem] %@ -> %@", prevTrack.id, nextTrack.id);
      [prevTrack deactivate];
      [nextTrack activate];

      if (nextTrack) {
        [self playerDidActivateTrack];
      } else if (prevTrack) {
        [self playerWillDeactivate];
      }
    } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
      LOG(@"[RNMediaPlayer updatedTimeControlStatus] %@", self.track.id);
      [self playerDidUpdateTrack];
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

#pragma mark - Lifecycle

- (void)activate
{
  RCTAssert(!_active, @"RNMediaPlayer already active");
  LOG(@"[RNMediaPlayer activate] %@", self.key);
  [_session activate];
  _active = YES;
}

- (void)deactivate
{
  RCTAssert(_active, @"RNMediaPlayer already inactive");
  LOG(@"[RNMediaPlayer deactivate] %@", self.key);
  if (self.track) {
    [self pause];
  }
  [_session deactivate];
  _active = NO;
}

- (void)playerWillActivate
{
  if (_active) {
    return;
  }

  LOG(@"[RNMediaPlayer playerWillActivate] %@", self.key);
  if ([_delegate respondsToSelector:@selector(playerWillActivate:)]) {
    [_delegate playerWillActivate:self];
  }
}

- (void)playerWillDeactivate
{
  if (!_active) {
    return;
  }

  LOG(@"[RNMediaPlayer playerWillDeactivate] %@", self.key);
  if ([_delegate respondsToSelector:@selector(playerWillDeactivate:)]) {
    [_delegate playerWillDeactivate:self];
  }
}

- (void)playerDidActivateTrack
{
  RCTAssert(self.track, @"Expected track to activate");
  LOG(@"[RNMediaPlayer playerDidActivateTrack] %@ %@", self.key, self.track.id);
  if ([_delegate respondsToSelector:@selector(playerDidActivateTrack:track:)]) {
    [_delegate playerDidActivateTrack:self track:self.track];
  }
}

- (void)playerDidUpdateTrack
{
  if (_updateQueued) {
    return;
  }

  _updateQueued = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, RAPID_UPDATE_DEBOUNCE_INTERVAL * NSEC_PER_MSEC), _methodQueue, ^{
    typeof(self) strongSelf = weakSelf;
    if (strongSelf) {
      strongSelf->_updateQueued = NO;
      [strongSelf _playerDidUpdateTrack];
    }
  });
}

- (void)_playerDidUpdateTrack
{
  // We may arrive here after the player's queue has been purged.
  if (!self.track) {
    return;
  }

  LOG(@"[RNMediaPlayer playerDidUpdateTrack] %@ %@", self.key, self.track.id);
  if ([_delegate respondsToSelector:@selector(playerDidUpdateTrack:track:)]) {
    [_delegate playerDidUpdateTrack:self track:self.track];
  }
}

- (void)trackDidFinish:(RNMediaTrack *)track withError:(NSError *)error
{
  RCTAssert(track == self.track, @"Received delegate callback for inactive track");
  LOG(@"[RNMediaPlayer trackDidFinishWithError] %@ %@", self.key, track.id);
  if ([_delegate respondsToSelector:@selector(playerDidFinishTrack:track:withError:)]) {
    [_delegate playerDidFinishTrack:self track:track withError:error];
  }
  if (error) {
    [self stop];
  }
}

- (void)trackDidFinishRange:(RNMediaTrack *)track withError:(NSError *)error
{
  RCTAssert(track == self.track, @"Received delegate callback for inactive track");
  LOG(@"[RNMediaPlayer trackDidFinishRangeWithError] %@ %@", self.key, track.id);
  if ([_delegate respondsToSelector:@selector(playerDidFinishTrack:track:withError:)]) {
    [_delegate playerDidFinishTrack:self track:track withError:error];
  }
  switch (_AVPlayer.actionAtItemEnd) {
    case AVPlayerActionAtItemEndAdvance:
      [self nextTrack];
      break;
    case AVPlayerActionAtItemEndPause:
      [self pause];
      [self seekTo:@(0) completion:nil];
      break;
    case AVPlayerActionAtItemEndNone:
      break;
  }
}

#pragma mark - Tracks

- (void)insertTracks:(NSArray<NSDictionary *> *)tracks options:(NSDictionary *)options
{
  AVPlayerItem *firstItem;
  AVPlayerItem *prevItem = _AVPlayer.currentItem;
  for (NSDictionary *options in tracks) {
    RNMediaAsset *asset = [RNMediaAsset assetWithPreciseTiming:_preciseTiming options:nilNull(options[@"asset"])];
    RNMediaTrack *track = [RNMediaTrack trackWithPlayer:self asset:asset options:options];
    track.delegate = self;

    AVPlayerItem *nextItem = track.AVPlayerItem;
    [_AVPlayer insertItem:nextItem afterItem:prevItem];
    [track enqueued];

    prevItem = nextItem;
    if (!firstItem) {
      firstItem = nextItem;
    }
  }

  if ([nilNull(options[@"advance"]) boolValue]) {
    if (_AVPlayer.currentItem != firstItem) {
      [self nextTrack];
      RCTAssert(_AVPlayer.currentItem == firstItem, @"Expected next AVPlayerItem to be the first");
    }
  }

  if ([nilNull(options[@"activate"]) boolValue]) {
    [self playerWillActivate];
  }

  if ([nilNull(options[@"play"]) boolValue]) {
    [self play];
  }
}

- (void)replaceTracks:(NSArray<NSDictionary *> *)tracks options:(NSDictionary *)options
{
  NSArray<AVPlayerItem *> *items = _AVPlayer.items;
  NSUInteger currentIndex = [items indexOfObject:_AVPlayer.currentItem];

  if (currentIndex == NSNotFound) {
    [_AVPlayer removeAllItems];
  } else {
    for (NSUInteger index = currentIndex + 1; index < items.count; index++) {
      [_AVPlayer removeItem:items[index]];
    }
  }

  [self insertTracks:tracks options:options];
}

- (void)nextTrack
{
  [_AVPlayer advanceToNextItem];
}

#pragma mark - Playback

- (void)play
{
  [self _prepareToPlay];
  [self _play];
}

- (void)playWithOptions:(NSDictionary *)options
{
  [self _prepareToPlay];

  __weak typeof(self) weakSelf = self;
  void (^playBlock)(void) = ^() {
    [weakSelf _play];
  };

  if (options) {
    NSNumber *position = nilNull(options[@"position"]);
    NSNumber *duration = nilNull(options[@"duration"]);

    if (duration) {
      CMTime startTime = position ? CMTimeMakeWithSeconds(position.doubleValue, NSEC_PER_SEC) : _AVPlayer.currentTime;
      CMTime pauseTime = CMTimeAdd(startTime, CMTimeMakeWithSeconds(duration.doubleValue, NSEC_PER_SEC));
      NSArray<NSValue *> *boundaries = @[[NSValue valueWithCMTime:pauseTime]];

      playBlock = ^() {
        _boundaryObserver = [_AVPlayer addBoundaryTimeObserverForTimes:boundaries queue:_methodQueue usingBlock:^{
          [weakSelf pause];
        }];

        [weakSelf _play];
      };
    }

    if (position) {
      [self seekTo:position completion:^(__unused BOOL finished) {
        playBlock();
      }];
      return;
    }
  }

  playBlock();
}

- (void)_prepareToPlay
{
  [self playerWillActivate];
  if (_boundaryObserver) {
    [_AVPlayer removeTimeObserver:_boundaryObserver];
    _boundaryObserver = nil;
  }
}

- (void)_play
{
  _AVPlayer.rate = _rate;
}

- (void)pause
{
  _AVPlayer.rate = 0.0f;
}

- (void)toggle
{
  if (_AVPlayer.rate) {
    [self pause];
  } else {
    [self play];
  }
}

- (void)stop
{
  [_AVPlayer removeAllItems];
  [self playerWillDeactivate];
}

- (void)seekTo:(NSNumber *)position completion:(void (^)(BOOL finished))completion
{
  CMTimeRange range = self.track.range;
  if (CMTIMERANGE_IS_INVALID(range)) {
    // AVQueuePlayer will advance two tracks if you seek beyond the duration of the current track.
    // We subtract a small amount to prevent this from happening.
    CMTime duration = CMTimeSubtract(_AVPlayer.currentItem.duration, CMTimeMakeWithSeconds(SEEK_DURATION_ADJUSTMENT / 1000.0f, NSEC_PER_SEC));
    range = CMTimeRangeMake(kCMTimeZero, CMTIME_IS_INDEFINITE(duration) ? kCMTimePositiveInfinity : duration);
  }

  __weak typeof(self) weakSelf = self;
  CMTime clampedPosition = CMTimeClampToRange(CMTimeMakeWithSeconds(position.doubleValue, NSEC_PER_SEC), range);
  [_AVPlayer seekToTime:clampedPosition toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    [weakSelf playerDidUpdateTrack];
    if (completion) {
      completion(finished);
    }
  }];
}

//XXX make waveforms configurable
- (void)skipBy:(NSNumber *)interval completion:(void (^)(BOOL finished))completion
{
  CMTime target = CMTimeAdd(_AVPlayer.currentTime, CMTimeMakeWithSeconds(interval.doubleValue, NSEC_PER_SEC));
  CMTime window = CMTimeMakeWithSeconds(fabs(SKIP_INTERVAL_WINDOW_RATIO * interval.doubleValue), NSEC_PER_SEC);
  target = [self.track seekPositionForTarget:target window:window];
  [self seekTo:@(CMTimeGetSeconds(target)) completion:completion];
}

- (void)setRate:(NSNumber *)rate
{
  // Only update the player rate directly if it's playing.
  if (_AVPlayer.rate == _rate) {
    _AVPlayer.rate = rate.floatValue;
  }
  _rate = rate.floatValue;
  [self playerDidUpdateTrack];
}

- (void)setRange:(NSDictionary *)range
{
  [self.track setRange:range];
}

#pragma mark - Properties

- (RNMediaTrack *)track
{
  return _AVPlayer.currentItem.RNMediaPlayback_track;
}

- (NSString *)status
{
  if (!_AVPlayer.currentItem) {
    return @"IDLE";
  }

  switch (_AVPlayer.timeControlStatus) {
    case AVPlayerTimeControlStatusPaused:
      return @"PAUSED";
    case AVPlayerTimeControlStatusPlaying:
      return @"PLAYING";
    case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
      return @"STALLED";
  }
}

- (NSNumber *)statusRate
{
  return @(_AVPlayer.rate);
}

- (NSNumber *)targetRate
{
  return @(_rate);
}

- (NSNumber *)position
{
  CMTime position = _AVPlayer.currentTime;
  return CMTIME_IS_INDEFINITE(position) ? nil : @(CMTimeGetSeconds(position));
}

- (NSNumber *)duration
{
  CMTime duration = _AVPlayer.currentItem.duration;
  return CMTIME_IS_INDEFINITE(duration) ? nil : @(CMTimeGetSeconds(duration));
}

@end
