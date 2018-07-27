#import <React/RCTAssert.h>
#import "RNMediaSession.h"

@import AVFoundation;

#define DEFAULT_MODE AVAudioSessionModeDefault
#define DEFAULT_CATEGORY AVAudioSessionCategoryPlayback

@implementation RNMediaSession
{
  NSString *_mode;
  NSString *_category;
  BOOL _active;
}

#pragma mark - AVFoundation Enumerations

+ (NSString *)getSessionMode:(NSString *)name
{
  if ([name isEqual: @"default"]) {
    return AVAudioSessionModeDefault;
  } else if ([name isEqual: @"voiceChat"]) {
    return AVAudioSessionModeVoiceChat;
  } else if ([name isEqual: @"videoChat"]) {
    return AVAudioSessionModeVideoChat;
  } else if ([name isEqual: @"gameChat"]) {
    return AVAudioSessionModeGameChat;
  } else if ([name isEqual: @"videoRecording"]) {
    return AVAudioSessionModeVideoRecording;
  } else if ([name isEqual: @"measurement"]) {
    return AVAudioSessionModeMeasurement;
  } else if ([name isEqual: @"moviePlayback"]) {
    return AVAudioSessionModeMoviePlayback;
  } else if ([name isEqual: @"spokenAudio"]) {
    return AVAudioSessionModeSpokenAudio;
  }

  RCTAssert(!name, @"Unknown mode: %@", name);
  return DEFAULT_MODE;
}

+ (NSString *)getSessionCategory:(NSString *)name
{
  if ([name isEqual: @"ambient"]) {
    return AVAudioSessionCategoryAmbient;
  } else if ([name isEqual: @"soloAmbient"]) {
    return AVAudioSessionCategorySoloAmbient;
  } else if ([name isEqual: @"playback"]) {
    return AVAudioSessionCategoryPlayback;
  } else if ([name isEqual: @"record"]) {
    return AVAudioSessionCategoryRecord;
  } else if ([name isEqual: @"playAndRecord"]) {
    return AVAudioSessionCategoryPlayAndRecord;
  }
#if TARGET_OS_IOS
  else if ([name isEqual: @"audioProcessing"]) {
    return AVAudioSessionCategoryAudioProcessing;
  }
#endif
  else if ([name isEqual: @"multiRoute"]) {
    return AVAudioSessionCategoryMultiRoute;
  }

  RCTAssert(!name, @"Unknown category: %@", name);
  return DEFAULT_CATEGORY;
}

#pragma mark - Constructors

+ (instancetype)sessionWithOptions:(NSDictionary *)options
{
  return [[RNMediaSession alloc] initWithOptions:options];
}

- (instancetype)initWithOptions:(NSDictionary *)options
{
  if (self = [super init]) {
    _mode = [RNMediaSession getSessionMode:options[@"mode"]];
    _category = [RNMediaSession getSessionCategory:options[@"category"]];
    _active = NO;
  }
  return self;
}

#pragma mark - Lifecycle

- (void)activate
{
  RCTAssert(!_active, @"RNMediaSession already active");
  [self setSessionActive:YES];
  _active = YES;
}

- (void)deactivate
{
  RCTAssert(_active, @"RNMediaSession already inactive");
  [self setSessionActive:NO];
  _active = NO;
}

- (void)setSessionActive:(BOOL)active
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  if (active) {
    [session setCategory:_category mode:_mode options:0 error:nil];
  }
  [session setActive:active error:nil];
}

@end
