#import "RNMediaPlaybackSession.h"

@import AVFoundation;

#define nilNull(value) ((value) == [NSNull null] ? nil : (value))

@implementation RNMediaPlaybackSession
{
  NSNumber *_key;
  NSString *_category;
  NSString *_mode;
}

- (instancetype)initWithKey:(NSNumber *)key options:(NSDictionary *)options
{
  if (self = [super init]) {
    _key = key;
    _category = [self getSessionCategory:options[@"category"]];
    _mode = [self getSessionMode:options[@"mode"]];
  }
  return self;
}

#pragma mark - AVAudioSession

- (NSString *)getSessionCategory:(NSString *)name
{
  if ([name isEqual: @"Ambient"]) {
    return AVAudioSessionCategoryAmbient;
  } else if ([name isEqual: @"SoloAmbient"]) {
    return AVAudioSessionCategorySoloAmbient;
  } else if ([name isEqual: @"Playback"]) {
    return AVAudioSessionCategoryPlayback;
  } else if ([name isEqual: @"Record"]) {
    return AVAudioSessionCategoryRecord;
  } else if ([name isEqual: @"PlayAndRecord"]) {
    return AVAudioSessionCategoryPlayAndRecord;
  }
#if TARGET_OS_IOS
  else if ([name isEqual: @"AudioProcessing"]) {
    return AVAudioSessionCategoryAudioProcessing;
  }
#endif
  else if ([name isEqual: @"MultiRoute"]) {
    return AVAudioSessionCategoryMultiRoute;
  }

  return nil;
}

- (NSString *)getSessionMode:(NSString *)name
{
  if ([name isEqual: @"Default"]) {
    return AVAudioSessionModeDefault;
  } else if ([name isEqual: @"VoiceChat"]) {
    return AVAudioSessionModeVoiceChat;
  } else if ([name isEqual: @"VideoChat"]) {
    return AVAudioSessionModeVideoChat;
  } else if ([name isEqual: @"GameChat"]) {
    return AVAudioSessionModeGameChat;
  } else if ([name isEqual: @"VideoRecording"]) {
    return AVAudioSessionModeVideoRecording;
  } else if ([name isEqual: @"Measurement"]) {
    return AVAudioSessionModeMeasurement;
  } else if ([name isEqual: @"MoviePlayback"]) {
    return AVAudioSessionModeMoviePlayback;
  } else if ([name isEqual: @"SpokenAudio"]) {
    return AVAudioSessionModeSpokenAudio;
  }

  return nil;
}

- (void)setSessionActive:(BOOL)active
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  if (active) {
    [session setCategory:_category mode:_mode options:0 error:nil];
  }
  [session setActive:active error:nil];
}

#pragma mark - Lifecycle

- (void)activate
{
  [self setSessionActive:YES];
}

- (void)deactivate
{
  [self setSessionActive:NO];
}

@end
