#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTInvalidating.h>
#import "RNMediaControls.h"
#import "RNMediaPlayer.h"

@interface RNMediaPlaybackManager : RCTEventEmitter<RCTBridgeModule, RCTInvalidating, RNMediaControlsDelegate, RNMediaPlayerDelegate>
@end
