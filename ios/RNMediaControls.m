#import <React/RCTAssert.h>
#import <React/RCTConvert.h>
#import "RNMediaPlayback.h"
#import "RNMediaControls.h"

@import AVFoundation;
@import MediaPlayer;

#define MAX_UPDATE_ATTEMPTS 3
#define REMOTE_UPDATE_DELAY 1.5 // s

@implementation RNMediaControls
{
  NSString *_artwork;
}

#pragma mark - AVFoundation Enumerations

+ (NSString *)getRouteType:(NSString *)type
{
  if ([type isEqualToString:AVAudioSessionPortLineOut]) {
    return @"lineOut";
  } else if ([type isEqualToString:AVAudioSessionPortHeadphones]) {
    return @"headphones";
  } else if ([type isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
    return @"builtinReceiver";
  } else if ([type isEqualToString:AVAudioSessionPortBuiltInSpeaker]) {
    return @"builtinSpeaker";
  } else if ([type isEqualToString:AVAudioSessionPortHDMI]) {
    return @"hdmi";
  } else if ([type isEqualToString:AVAudioSessionPortAirPlay]) {
    return @"airplay";
  } else if ([type isEqualToString:AVAudioSessionPortBluetoothLE]) {
    return @"bluetoothLE";
  } else if ([type isEqualToString:AVAudioSessionPortBluetoothA2DP]) {
    return @"bluetoothA2DP";
  } else if ([type isEqualToString:AVAudioSessionPortBluetoothHFP]) {
    return @"bluetoothHFP";
  } else if ([type isEqualToString:AVAudioSessionPortUSBAudio]) {
    return @"usb";
  } else if ([type isEqualToString:AVAudioSessionPortCarAudio]) {
    return @"carplay";
  }

  RCTAssert(!type, @"Unknown route type: %@", type);
  return @"unknown";
}

#pragma mark - Constructors

+ (instancetype)sharedInstance
{
  static RNMediaControls *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[RNMediaControls alloc] initSingleton];
  });
  return sharedInstance;
}

- (instancetype)initSingleton
{
  if (self = [super init]) {
    [self addListeners];
  }
  return self;
}

- (void)dealloc
{
  [self removeListeners];
}

#pragma mark - Details

#define DETAIL_STRING_KEYS @{ \
  @"album": MPMediaItemPropertyAlbumTitle, \
  @"artist": MPMediaItemPropertyArtist, \
  @"title": MPMediaItemPropertyTitle, \
}

#define DETAIL_NUMBER_KEYS @{ \
  @"statusRate": MPNowPlayingInfoPropertyPlaybackRate, \
  @"targetRate": MPNowPlayingInfoPropertyDefaultPlaybackRate, \
  @"duration": MPMediaItemPropertyPlaybackDuration, \
  @"position": MPNowPlayingInfoPropertyElapsedPlaybackTime, \
}

- (void)updateDetails:(NSDictionary *)details
{
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf updateDetails:details attempt:0];
  });
}

- (void)updateDetails:(NSDictionary *)details attempt:(NSUInteger)attempt
{
  MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];

  NSMutableDictionary *nextDetails;
  if (center.nowPlayingInfo == nil) {
    nextDetails = [NSMutableDictionary dictionary];
  } else {
    nextDetails = [NSMutableDictionary dictionaryWithDictionary:center.nowPlayingInfo];
  }

  for (NSString *key in DETAIL_STRING_KEYS) {
    if (nilNull(details[key])) {
      nextDetails[DETAIL_STRING_KEYS[key]] = [RCTConvert NSString:details[key]];
    }
  }

  for (NSString *key in DETAIL_NUMBER_KEYS) {
    if (nilNull(details[key])) {
      nextDetails[DETAIL_NUMBER_KEYS[key]] = [RCTConvert NSNumber:details[key]];
    }
  }

  NSString *artwork = nilNull(details[@"artwork"]);
  BOOL updateArtwork = (artwork && ![artwork isEqual:_artwork]);
  if (updateArtwork) {
    [nextDetails removeObjectForKey:MPMediaItemPropertyArtwork];
  }

  center.nowPlayingInfo = nextDetails;
  NSDictionary *updatedDetails = center.nowPlayingInfo;
  BOOL updateSuccessful = [nextDetails isEqualToDictionary:updatedDetails];

  if (!updateSuccessful) {
    NSUInteger nextAttempt = attempt + 1;
    if (nextAttempt < MAX_UPDATE_ATTEMPTS) {
      LOG(@"[RNMediaControls updateDetails] retrying");
      __weak typeof(self) weakSelf = self;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, REMOTE_UPDATE_DELAY * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [weakSelf updateDetails:details attempt:nextAttempt];
      });
    } else {
      LOG(@"[RNMediaControls updateDetails] failed");
    }
    return;
  }

  if (updateArtwork) {
    _artwork = artwork;
    [self updateArtwork];
  }
}

- (void)updateArtwork
{
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf updateArtworkAttempt:0];
  });
}

- (void)updateArtworkAttempt:(NSUInteger)attempt
{
  if (attempt >= MAX_UPDATE_ATTEMPTS) {
    LOG(@"[RNMediaControls resetDetails] failed");
    return;
  } else if (attempt > 0) {
    LOG(@"[RNMediaControls resetDetails] retrying");
  }

  dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(REMOTE_UPDATE_DELAY * NSEC_PER_SEC));
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    NSString *url = _artwork;
    UIImage *image = nil;
    if (![url isEqual:@""]) {
      if ([url.lowercaseString hasPrefix:@"http://"] || [url.lowercaseString hasPrefix:@"https://"]) {
        NSURL *imageURL = [NSURL URLWithString:url];
        NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
        image = [UIImage imageWithData:imageData];
      } else {
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:url];
        if (fileExists) {
          image = [UIImage imageNamed:url];
        }
      }
    }

    if (image == nil) {
      return;
    }

    CIImage *cim = [image CIImage];
    CGImageRef cgref = [image CGImage];
    if (cim != nil || cgref != NULL) {
      dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
        if ([url isEqual:_artwork]) {
          MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];

          NSMutableDictionary *nextDetails;
          if (center.nowPlayingInfo == nil) {
            nextDetails = [NSMutableDictionary dictionary];
          } else {
            nextDetails = [NSMutableDictionary dictionaryWithDictionary:center.nowPlayingInfo];
          }

          MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage:image];
          [nextDetails setValue:artwork forKey:MPMediaItemPropertyArtwork];
          center.nowPlayingInfo = nextDetails;

          if (!center.nowPlayingInfo[MPMediaItemPropertyArtwork]) {
            [self updateArtwork:(attempt + 1)];
          }
        }
      });
    }
  });
}

- (void)resetDetails
{
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf resetDetailsAttempt:0];
  });
}

- (void)resetDetailsAttempt:(NSUInteger)attempt
{
  MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];

  center.nowPlayingInfo = nil;
  NSDictionary *updatedDetails = center.nowPlayingInfo;
  BOOL updateSuccessful = (updatedDetails == nil || updatedDetails.count == 0);

  if (!updateSuccessful) {
    NSUInteger nextAttempt = attempt + 1;
    if (nextAttempt < MAX_UPDATE_ATTEMPTS) {
      LOG(@"[RNMediaControls resetDetails] retrying");
      __weak typeof(self) weakSelf = self;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, REMOTE_UPDATE_DELAY * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [weakSelf resetDetailsAttempt:nextAttempt];
      });
    } else {
      LOG(@"[RNMediaControls resetDetails] failed");
    }
    return;
  }

  _artwork = nil;
}

#pragma mark - Routes

- (void)showRoutePicker
{
  // This is an absurdly hacky way to display the AirPlay selection popover.
  // https://stackoverflow.com/a/15583062
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *presentedController = RCTPresentedViewController();
    UIView *presentedView = presentedController.view;

    MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    volumeView.hidden = YES;
    [presentedView addSubview:volumeView];

    for (UIButton *button in volumeView.subviews) {
      if ([button isKindOfClass:[UIButton class]]) {
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        break;
      }
    }

    [volumeView removeFromSuperview];
  });
}

- (NSArray<NSDictionary *> *)outputRoutes
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSArray<AVAudioSessionPortDescription *> *descriptions = session.currentRoute.outputs;
  NSMutableArray<NSDictionary *> *routes = [[NSMutableArray alloc] initWithCapacity:descriptions.count];
  for (AVAudioSessionPortDescription *description in descriptions) {
    [routes addObject:@{
      @"name": description.portName,
      @"type": [RNMediaControls getRouteType:description.portType],
    }];
  }
  return routes;
}

#pragma mark - Event Management

- (void)addListeners
{
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf toggleListeners:YES];
  });
}

- (void)removeListeners
{
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf toggleListeners:NO];
  });
}

- (void)toggleListeners:(BOOL)enabled
{
  MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

  [self toggleCommandHandler:commandCenter.playCommand enabled:enabled selector:@selector(onPlay:)];
  [self toggleCommandHandler:commandCenter.pauseCommand enabled:enabled selector:@selector(onPause:)];
  [self toggleCommandHandler:commandCenter.togglePlayPauseCommand enabled:enabled selector:@selector(onToggle:)];
  [self toggleCommandHandler:commandCenter.stopCommand enabled:enabled selector:@selector(onStop:)];
  [self toggleCommandHandler:commandCenter.changePlaybackPositionCommand enabled:enabled selector:@selector(onSeek:)];
  [self toggleCommandHandler:commandCenter.seekForwardCommand enabled:enabled selector:@selector(onSeekForward:)];
  [self toggleCommandHandler:commandCenter.seekBackwardCommand enabled:enabled selector:@selector(onSeekBackward:)];

  {
    MPSkipIntervalCommand *command = commandCenter.skipForwardCommand;
    command.preferredIntervals = @[@(SKIP_FORWARD_INTERVAL)];
    [self toggleCommandHandler:command enabled:enabled selector:@selector(onSkipForward:)];
  }

  {
    MPSkipIntervalCommand *command = commandCenter.skipBackwardCommand;
    command.preferredIntervals = @[@(SKIP_BACKWARD_INTERVAL)];
    [self toggleCommandHandler:command enabled:enabled selector:@selector(onSkipBackward:)];
  }

  [self toggleCommandHandler:commandCenter.nextTrackCommand enabled:enabled selector:@selector(onNextTrack:)];
  [self toggleCommandHandler:commandCenter.previousTrackCommand enabled:enabled selector:@selector(onPrevTrack:)];

  [self toggleNotificationHandler:AVAudioSessionRouteChangeNotification enabled:enabled selector:@selector(onRouteChange:)];
  [self toggleNotificationHandler:AVAudioSessionInterruptionNotification enabled:enabled selector:@selector(onInterrupt:)];
  [self toggleNotificationHandler:AVAudioSessionMediaServicesWereResetNotification enabled:enabled selector:@selector(onSystemReset:)];
}

- (void)toggleCommandHandler:(MPRemoteCommand *)command enabled:(BOOL)enabled selector:(SEL)selector
{
  [command removeTarget:self action:selector];
  if (enabled) {
    [command addTarget:self action:selector];
  }
  command.enabled = enabled;
}

- (void)toggleNotificationHandler:(NSNotificationName)notification enabled:(BOOL)enabled selector:(SEL)selector
{
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  if (enabled) {
    [notificationCenter addObserver:self selector:selector name:notification object:nil];
  } else {
    [notificationCenter removeObserver:self name:notification object:nil];
  }
}

#pragma mark - Event Listeners

- (void)onPlay:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestPlay)]) {
    [_delegate remoteDidRequestPlay];
  }
}

- (void)onPause:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestPause)]) {
    [_delegate remoteDidRequestPause];
  }
}

- (void)onToggle:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestToggle)]) {
    [_delegate remoteDidRequestToggle];
  }
}

- (void)onStop:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestStop)]) {
    [_delegate remoteDidRequestStop];
  }
}

- (void)onNextTrack:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestNextTrack)]) {
    [_delegate remoteDidRequestNextTrack];
  }
}

- (void)onPrevTrack:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestPrevTrack)]) {
    [_delegate remoteDidRequestPrevTrack];
  }
}

- (void)onSeekForward:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestSeekForward)]) {
    [_delegate remoteDidRequestSeekForward];
  }
}

- (void)onSeekBackward:(MPRemoteCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestSeekBackward)]) {
    [_delegate remoteDidRequestSeekBackward];
  }
}

- (void)onSeek:(MPChangePlaybackPositionCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestSeekTo:)]) {
    [_delegate remoteDidRequestSeekTo:@(event.positionTime)];
  }
}

- (void)onSkipForward:(MPSkipIntervalCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestSkipBy:)]) {
    [_delegate remoteDidRequestSkipBy:@(event.interval)];
  }
}

- (void)onSkipBackward:(MPSkipIntervalCommandEvent*)event {
  if ([_delegate respondsToSelector:@selector(remoteDidRequestSkipBy:)]) {
    [_delegate remoteDidRequestSkipBy:@(-event.interval)];
  }
}

- (void)onRouteChange:(NSNotification*)notification {
  NSDictionary *userInfo = notification.userInfo;
  AVAudioSessionRouteChangeReason reason = [userInfo[AVAudioSessionRouteChangeReasonKey] intValue];

  if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
    if ([_delegate respondsToSelector:@selector(systemDidLoseOutputRoute)]) {
      [_delegate systemDidLoseOutputRoute];
    }
  }
}

- (void)onInterrupt:(NSNotification*)notification {
  NSDictionary *userInfo = notification.userInfo;
  AVAudioSessionInterruptionType type = [userInfo[AVAudioSessionInterruptionTypeKey] intValue];

  if (type == AVAudioSessionInterruptionTypeBegan) {
    BOOL wasSuspended = [userInfo[AVAudioSessionInterruptionWasSuspendedKey] boolValue];

    if (!wasSuspended) {
      if ([_delegate respondsToSelector:@selector(systemWillBeginInterruption)]) {
        [_delegate systemWillBeginInterruption];
      }
    }
  } else if (type == AVAudioSessionInterruptionTypeEnded) {
    AVAudioSessionInterruptionOptions option = [userInfo[AVAudioSessionInterruptionOptionKey] intValue];
    BOOL shouldResume = (option == AVAudioSessionInterruptionOptionShouldResume);

    if ([_delegate respondsToSelector:@selector(systemDidFinishInterruptionAndShouldResume:)]) {
      [_delegate systemDidFinishInterruptionAndShouldResume:shouldResume];
    }
  }
}

- (void)onSystemReset:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(systemDidReset)]) {
    [_delegate systemDidReset];
  }
}

@end
