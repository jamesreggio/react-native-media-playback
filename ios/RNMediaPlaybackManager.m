#import <React/RCTAssert.h>
#import "RNMediaPlaybackManager.h"
#import "RNMediaPlayer.h"

@implementation RNMediaPlaybackManager
{
  NSMutableDictionary<NSNumber *, RNMediaPlayer *> *_players;
  RNMediaPlayer *_activePlayer;
}

RCT_EXPORT_MODULE(MediaPlaybackManager)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (instancetype)init
{
  if (self = [super init]) {
    _players = [NSMutableDictionary dictionary];
    _activePlayer = nil;
  }
  return self;
}

- (void)invalidate
{
  [_players removeAllObjects];
  _activePlayer = nil;
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
    @"playerActivated",
    @"playerDeactivated",
    @"trackActivated",
    @"trackUpdated",
    @"trackFinished",
  ];
}

#pragma mark - Player Management

- (void)sendEventForPlayer:(RNMediaPlayer *)player withName:(NSString *)name body:(NSDictionary *)body
{
  NSMutableDictionary *mutableBody = body ? [body mutableCopy] : [NSMutableDictionary dictionary];
  mutableBody[@"key"] = player.key;
  [self sendEventWithName:name body:mutableBody];
}

- (RNMediaPlayer *)playerForKey:(NSNumber *)key
{
  RNMediaPlayer *player = _players[key];
  RCTAssert(player, @"Expected player for key");
  return player;
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
  _activePlayer.active = NO;
  _activePlayer = player;
  _activePlayer.active = YES;
  [self sendEventForPlayer:player withName:@"playerActivated" body:nil];
}

- (void)playerDidDeactivate:(RNMediaPlayer *)player
{
  RCTAssert(_activePlayer == player, @"Received deactivation for inactive RNMediaPlayer");

  if (_activePlayer == player) {
    [self sendEventForPlayer:player withName:@"playerDeactivated" body:nil];
    _activePlayer.active = NO;
    _activePlayer = nil;
  }
}

- (void)playerWillActivateTrack:(RNMediaPlayer *)player withBody:(NSDictionary *)body
{
  [self sendEventForPlayer:player withName:@"trackActivated" body:body];
}

- (void)playerDidUpdateTrack:(RNMediaPlayer *)player withBody:(NSDictionary *)body
{
  [self sendEventForPlayer:player withName:@"trackUpdated" body:body];
}

- (void)playerDidFinishTrack:(RNMediaPlayer *)player withBody:(NSDictionary *)body
{
  [self sendEventForPlayer:player withName:@"trackFinished" body:body];
}

#pragma mark - Track Management

RCT_EXPORT_METHOD(insertPlayerTracks:(nonnull NSNumber *)key
                              tracks:(NSArray *)tracks
                          andAdvance:(BOOL)advance
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player insertTracks:tracks andAdvance:advance];
  resolve(nil);
}

RCT_EXPORT_METHOD(replacePlayerTracks:(nonnull NSNumber *)key
                               tracks:(NSArray *)tracks
                           andAdvance:(BOOL)advance
                             resolver:(RCTPromiseResolveBlock)resolve
                             rejecter:(RCTPromiseRejectBlock)reject)
{
  RNMediaPlayer *player = [self playerForKey:key];
  [player replaceTracks:tracks andAdvance:advance];
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

@end
