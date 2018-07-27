#import <React/RCTAssert.h>
#import "RNMediaPlaybackManager.h"
#import "RNMediaPlayback.h"
#import "RNMediaControls.h"
#import "RNMediaPlayer.h"
#import "RNMediaTrack.h"

@implementation RNMediaPlaybackManager
{
  NSMutableDictionary<NSNumber *, RNMediaPlayer *> *_players;
  RNMediaPlayer *_activePlayer;
  NSNumber *_wasPlaying;
}

RCT_EXPORT_MODULE(MediaPlaybackManager)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (instancetype)init
{
  if (self = [super init]) {
    [RNMediaControls sharedInstance].delegate = self;
    _players = [NSMutableDictionary dictionary];
    _activePlayer = nil;
    _wasPlaying = nil;
  }
  return self;
}

- (void)invalidate
{
  [RNMediaControls sharedInstance].delegate = nil;
  [_players removeAllObjects];
  _activePlayer = nil;
  _wasPlaying = nil;
}

- (dispatch_queue_t)methodQueue
{
  static dispatch_queue_t queue;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create("com.github.jamesreggio.react.media", DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[
    @"systemReset",
    @"playerActivated",
    @"playerDeactivated",
    @"trackActivated",
    @"trackUpdated",
    @"trackFinished",
  ];
}

#pragma mark - Player Management

- (RNMediaPlayer *)playerForKey:(NSNumber *)key
{
  RNMediaPlayer *player = _players[key];
  RCTAssert(player, @"Expected player for key");
  return player;
}

- (void)sendEventForPlayer:(RNMediaPlayer *)player withName:(NSString *)name body:(NSDictionary *)body
{
  NSMutableDictionary *mutableBody = body ? [body mutableCopy] : [NSMutableDictionary dictionary];
  mutableBody[@"key"] = player.key;
  [self sendEventWithName:name body:mutableBody];
}

RCT_EXPORT_METHOD(createPlayer:(nonnull NSNumber *)key
                       options:(NSDictionary *)options
                      resolver:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  RCTAssert(!_players[key], @"Already have player for key");

  RNMediaPlayer *player = [[RNMediaPlayer alloc] initWithKey:key
                                                 methodQueue:self.methodQueue
                                                     options:options];

  player.delegate = self;
  _players[key] = player;
  resolve(nil);
}

- (void)playerWillActivate:(RNMediaPlayer *)player
{
  [_activePlayer deactivate];
  _activePlayer = player;
  [_activePlayer activate];
  [self updateRemote];
  [self sendEventForPlayer:player withName:@"playerActivated" body:nil];
}

- (void)playerWillDeactivate:(RNMediaPlayer *)player
{
  RCTAssert(_activePlayer == player, @"Received deactivation for inactive RNMediaPlayer");

  if (_activePlayer == player) {
    _activePlayer = nil;
    [player deactivate];
    [self resetRemote];
    [self sendEventForPlayer:player withName:@"playerDeactivated" body:nil];
  }
}

- (void)playerDidActivateTrack:(RNMediaPlayer *)player track:(RNMediaTrack *)track
{
  [self updateRemote];
  [self sendEventForPlayer:player withName:@"trackActivated" body:@{@"id": track.id}];
}

- (void)playerDidUpdateTrack:(RNMediaPlayer *)player track:(RNMediaTrack *)track
{
  [self updateRemote];
  [self sendEventForPlayer:player withName:@"trackUpdated" body:@{
    @"id": track.id,
    @"status": track.status,
    @"position": nullNil(track.position),
    @"duration": nullNil(track.duration),
  }];
}

- (void)playerDidFinishTrack:(RNMediaPlayer *)player track:(RNMediaTrack*)track withError:(NSError *)error
{
  [self updateRemote];
  [self sendEventForPlayer:player withName:@"trackFinished" body:@{
    @"id": track.id,
    @"error": nullNil(error),
  }];
}

#pragma mark - Track Management

RCT_EXPORT_METHOD(insertPlayerTracks:(nonnull NSNumber *)key
                              tracks:(NSArray *)tracks
                             options:(NSDictionary *)options
                          andAdvance:(BOOL)advance
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player insertTracks:tracks options:options];
  resolve(nil);
}

RCT_EXPORT_METHOD(replacePlayerTracks:(nonnull NSNumber *)key
                               tracks:(NSArray *)tracks
                              options:(NSDictionary *)options
                             resolver:(RCTPromiseResolveBlock)resolve
                             rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player replaceTracks:tracks options:options];
  resolve(nil);
}

RCT_EXPORT_METHOD(nextPlayerTrack:(nonnull NSNumber *)key
                         resolver:(RCTPromiseResolveBlock)resolve
                         rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player nextTrack];
  resolve(nil);
}

#pragma mark - Playback Controls

RCT_EXPORT_METHOD(playPlayer:(nonnull NSNumber *)key
                    resolver:(RCTPromiseResolveBlock)resolve
                    rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player play];
  resolve(nil);
}

RCT_EXPORT_METHOD(pausePlayer:(nonnull NSNumber *)key
                     resolver:(RCTPromiseResolveBlock)resolve
                     rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player pause];
  resolve(nil);
}

RCT_EXPORT_METHOD(togglePlayer:(nonnull NSNumber *)key
                      resolver:(RCTPromiseResolveBlock)resolve
                      rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player toggle];
  resolve(nil);
}

RCT_EXPORT_METHOD(stopPlayer:(nonnull NSNumber *)key
                    resolver:(RCTPromiseResolveBlock)resolve
                    rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player stop];
  resolve(nil);
}

RCT_EXPORT_METHOD(seekPlayer:(nonnull NSNumber *)key
                    position:(nonnull NSNumber *)position
                    resolver:(RCTPromiseResolveBlock)resolve
                    rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player seekTo:position completion:^(BOOL finished) {
    resolve(@(finished));
  }];
}

RCT_EXPORT_METHOD(skipPlayer:(nonnull NSNumber *)key
                    interval:(nonnull NSNumber *)interval
                    resolver:(RCTPromiseResolveBlock)resolve
                    rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player skipBy:interval completion:^(BOOL finished) {
    resolve(@(finished));
  }];
}

RCT_EXPORT_METHOD(setPlayerRate:(nonnull NSNumber *)key
                           rate:(nonnull NSNumber *)rate
                       resolver:(RCTPromiseResolveBlock)resolve
                       rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player setRate:rate];
  resolve(nil);
}

#pragma mark - Remote Details

- (void)resetRemote
{
  [[RNMediaControls sharedInstance] resetDetails];
}

- (void)updateRemote
{
  static NSDictionary *lastTrackDetails = nil;
  NSDictionary *trackDetails = self.remoteTrackDetails;
  NSDictionary *nextDetails;

  if (!trackDetails) {
    return;
  } else if (lastTrackDetails == trackDetails) {
    nextDetails = self.remotePlaybackDetails;
  } else {
    nextDetails = [NSMutableDictionary dictionaryWithDictionary:trackDetails];
    [nextDetails setValuesForKeysWithDictionary:self.remotePlaybackDetails];
  }

  [[RNMediaControls sharedInstance] updateDetails:nextDetails];
  lastTrackDetails = trackDetails;
}

- (NSDictionary *)remoteTrackDetails
{
  return _activePlayer.track.remote;
}

- (NSDictionary *)remotePlaybackDetails
{
  if (!_activePlayer) {
    return nil;
  }

  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[@"statusRate"] = _activePlayer.statusRate;
  details[@"targetRate"] = _activePlayer.targetRate;
  details[@"position"] = nullNil(_activePlayer.position);
  details[@"duration"] = nullNil(_activePlayer.duration);
  return details;
}

#pragma mark - Remote Events

- (void)remoteDidRequestPlay
{
  [_activePlayer play];
}

- (void)remoteDidRequestPause
{
  [_activePlayer pause];
}

- (void)remoteDidRequestToggle
{
  [_activePlayer toggle];
}

- (void)remoteDidRequestStop
{
  [_activePlayer stop];
}

// Carplay makes it easy to change tracks, but difficult to skip.
// As such, we remap track change actions to skipping.

- (void)remoteDidRequestNextTrack
{
  [_activePlayer skipBy:@(SKIP_FORWARD_INTERVAL) completion:nil];
}

- (void)remoteDidRequestPrevTrack
{
  [_activePlayer skipBy:@(-SKIP_BACKWARD_INTERVAL) completion:nil];
}

- (void)remoteDidRequestSeekTo:(NSNumber *)position
{
  [_activePlayer seekTo:position completion:nil];
}

- (void)remoteDidRequestSkipBy:(NSNumber *)interval
{
  [_activePlayer skipBy:interval completion:nil];
}

- (void)systemDidLoseOutputRoute
{
  [_activePlayer pause];
}

- (void)systemWillBeginInterruption
{
  if (_activePlayer) {
    _wasPlaying = @([_activePlayer.status isEqualToString:@"PLAYING"]);
  }
}

- (void)systemDidFinishInterruptionAndShouldResume:(BOOL)shouldResume
{
  if (shouldResume && _wasPlaying) {
    [_activePlayer play];
  }
  _wasPlaying = nil;
}

- (void)systemDidReset
{
  [self sendEventWithName:@"systemReset" body:nil];
}

@end
