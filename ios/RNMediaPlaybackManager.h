#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTInvalidating.h>
#import "RNMediaPlayer.h"

@interface RNMediaPlaybackManager : RCTEventEmitter<RCTBridgeModule, RCTInvalidating, RNMediaPlayerDelegate>
@end
