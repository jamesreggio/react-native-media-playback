#import <React/RCTAssert.h>
#import "AVPlayerItem+RNMediaPlayback.h"
#import "RNMediaPlayback.h"
#import "RNMediaAsset.h"
#import "RNMediaPlayer.h"
#import "RNMediaTrack.h"
@import AVFoundation;

#define DEFAULT_PITCH_ALGORITHM AVAudioTimePitchAlgorithmLowQualityZeroLatency

static void *AVPlayerItemContext = &AVPlayerItemContext;

CMTimeRange CMTimeRangeMakeFromBounds(CMTime start, CMTime end)
{
  return CMTimeRangeMake(start, CMTimeSubtract(end, start));
}

@implementation RNMediaTrack
{
  // This helps to prevent a retain cycle.
  // When initialized, we have to retain a strong reference to the AVPlayerItem.
  // We can remove the strong reference once the AVPlayerItem is enqueued, since
  // the AVPlayerItem is retained and retains a strong reference this this object.
  // (See AVPlayerItem.RNMediaPlayback_track and [RNMediaTrack enqueued] for more.
  AVPlayerItem *_strongAVPlayerItem;

  __weak RNMediaPlayer *_player;
  RNMediaAsset *_asset;
  id _boundaryObserver;
  BOOL _active;
}

#pragma mark - AVFoundation Enumerations

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

+ (instancetype)trackWithPlayer:(RNMediaPlayer *)player
                          asset:(RNMediaAsset *)asset
                        options:(NSDictionary *)options
{
  return [[RNMediaTrack alloc] initWithPlayer:player asset:asset options:options];
}

- (instancetype)initWithPlayer:(RNMediaPlayer *)player
                         asset:(RNMediaAsset *)asset
                       options:(NSDictionary *)options
{
  if (self = [super init]) {
    RCTAssert(player, @"Expected player for track");
    RCTAssert(asset, @"Expected asset for track");

    NSString *id = nilNull(options[@"id"]);
    RCTAssert(id, @"Expected ID for track");

    // Initialize instance variables.

    _id = id;
    _player = player;
    _asset = asset;
    _AVPlayerItem = _strongAVPlayerItem = [AVPlayerItem playerItemWithAsset:asset.AVAsset];
    _AVPlayerItem.RNMediaPlayback_track = self;
    _active = NO;

    // Process options.

    _remote = nilNull(options[@"remote"]);

    _AVPlayerItem.audioTimePitchAlgorithm = [RNMediaTrack getPitchAlgorithm:options[@"pitchAlgorithm"]];

    NSNumber *position = nilNull(options[@"position"]);
    if (position) {
      CMTime time = CMTimeMakeWithSeconds(position.doubleValue, NSEC_PER_SEC);
      [_AVPlayerItem seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }

    NSNumber *buffer = nilNull(options[@"buffer"]);
    if (buffer) {
      _AVPlayerItem.preferredForwardBufferDuration = buffer.doubleValue;
    }

    _range = [self convertRange:nilNull(options[@"range"])];
  }
  return self;
}

- (void)dealloc
{
  RCTAssert(!_active && !_boundaryObserver, @"RNMediaTrack dealloc'ed while active");
}

#pragma mark - Lifecycle

- (void)enqueued
{
  _strongAVPlayerItem = nil;
}

- (void)activate
{
  RCTAssert(!_active, @"RNMediaTrack already active");
  [self addListeners];
  _active = YES;
}

- (void)deactivate
{
  RCTAssert(_active, @"RNMediaTrack already inactive");
  [self removeListeners];
  _active = NO;
}

#pragma mark - Events

- (void)addListeners
{
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

  [notificationCenter addObserver:self
                         selector:@selector(trackDidPlayToEnd:)
                             name:AVPlayerItemDidPlayToEndTimeNotification
                           object:_AVPlayerItem];

  [notificationCenter addObserver:self
                         selector:@selector(trackDidFailWithError:)
                             name:AVPlayerItemFailedToPlayToEndTimeNotification
                           object:_AVPlayerItem];

  [_AVPlayerItem addObserver:self
                  forKeyPath:@"status"
                     options:0
                     context:AVPlayerItemContext];

  [self addRangeListeners];
}

- (void)removeListeners
{
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_AVPlayerItem];
  [notificationCenter removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_AVPlayerItem];

  @try {
    [_AVPlayerItem removeObserver:self forKeyPath:@"status" context:AVPlayerItemContext];
  } @catch (__unused NSException *exception) {
    // If the subscription doesn't exist, KVO will throw.
  }

  [self removeRangeListeners];
}

- (void)updateRangeListeners
{
  [self removeRangeListeners];
  [self addRangeListeners];
}

- (void)addRangeListeners
{
  if (!CMTIMERANGE_IS_INVALID(_range)) {
    // We only attach an observer for the upper end of the range, since it's not possible
    // to rewind past the lower end (and there's nothing we can do if it happens).
    if (!CMTIME_IS_POSITIVE_INFINITY(_range.duration)) {
      __weak typeof(self) weakSelf = self;
      void (^boundaryBlock)(void) = ^() {
        [weakSelf trackDidPlayToEndOfRange];
      };

      NSArray<NSValue *> *boundaries = @[[NSValue valueWithCMTime:CMTimeRangeGetEnd(_range)]];
      _boundaryObserver = [_player.AVPlayer addBoundaryTimeObserverForTimes:boundaries
                                                                      queue:_player.methodQueue
                                                                 usingBlock:boundaryBlock];
    }
  }
}

- (void)removeRangeListeners
{
  if (_boundaryObserver) {
    [_player.AVPlayer removeTimeObserver:_boundaryObserver];
    _boundaryObserver = nil;
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context
{
  if (context == AVPlayerItemContext) {
    RCTAssert(_AVPlayerItem == object, @"Received update for unexpected AVPlayerItem");

    if ([keyPath isEqualToString:@"status"]) {
      if (_AVPlayerItem.status == AVPlayerItemStatusFailed) {
        if ([_delegate respondsToSelector:@selector(trackDidFinish:withError:)]) {
          [_delegate trackDidFinish:self withError:_AVPlayerItem.error];
        }
      }
    }
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)trackDidPlayToEndOfRange
{
  RCTAssert(_active, @"Received notification for inactive RNMediaTrack");
  if ([_delegate respondsToSelector:@selector(trackDidFinishRange:withError:)]) {
    [_delegate trackDidFinishRange:self withError:nil];
  }
}

- (void)trackDidPlayToEnd:(NSNotification*)notification
{
  RCTAssert(_active, @"Received notification for inactive RNMediaTrack");
  RCTAssert(notification.object == _AVPlayerItem, @"Received notification for unexpected AVPlayerItem");
  if ([_delegate respondsToSelector:@selector(trackDidFinish:withError:)]) {
    [_delegate trackDidFinish:self withError:nil];
  }
}

- (void)trackDidFailWithError:(NSNotification*)notification
{
  RCTAssert(_active, @"Received notification for inactive RNMediaTrack");
  RCTAssert(notification.object == _AVPlayerItem, @"Received notification for unexpected AVPlayerItem");
  if ([_delegate respondsToSelector:@selector(trackDidFinish:withError:)]) {
    [_delegate trackDidFinish:self withError:notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]];
  }
}

#pragma mark - Properties

- (NSString *)status
{
  return _active ? _player.status : @"IDLE";
}

- (NSNumber *)statusRate
{
  return _active ? _player.statusRate : @(0);
}

- (NSNumber *)targetRate
{
  return _player.targetRate;
}

- (NSNumber *)position
{
  CMTime position = self.AVPlayerItem.currentTime;
  return CMTIME_IS_INDEFINITE(position) ? nil : @(CMTimeGetSeconds(position));
}

- (NSNumber *)duration
{
  CMTime duration = self.AVPlayerItem.duration;
  return CMTIME_IS_INDEFINITE(duration) ? nil : @(CMTimeGetSeconds(duration));
}

#pragma mark - Waveforms

- (CMTime)seekPositionForTarget:(CMTime)target window:(CMTime)window
{
  return [_asset seekPositionForTarget:target window:window];
}

#pragma mark - Ranges

- (void)setRange:(NSDictionary *)range
{
  _range = [self convertRange:range];
  [self updateRangeListeners];
}

- (CMTimeRange)convertRange:(NSDictionary *)range
{
  if (range) {
    NSNumber *lower = nilNull(range[@"lower"]);
    NSNumber *upper = nilNull(range[@"upper"]);
    return CMTimeRangeMakeFromBounds(
                                     lower ? CMTimeMakeWithSeconds(lower.doubleValue, NSEC_PER_SEC) : kCMTimeZero,
                                     upper ? CMTimeMakeWithSeconds(upper.doubleValue, NSEC_PER_SEC) : kCMTimePositiveInfinity
                                     );
  } else {
    return kCMTimeRangeInvalid;
  }
}

@end
