#import <Foundation/Foundation.h>
@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

@interface RNMediaWaveform : NSObject

+ (instancetype)waveformWithData:(NSDictionary *)data;
- (instancetype)init NS_UNAVAILABLE;

- (CMTime)seekPositionForTarget:(CMTime)target window:(CMTime)window;

@end

NS_ASSUME_NONNULL_END
