#import <Foundation/Foundation.h>
@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

@interface RNMediaAsset : NSObject

@property (nonatomic, nonnull, readonly, strong) NSString *id;
@property (nonatomic, nonnull, readonly, strong) AVAsset *AVAsset;
@property (nonatomic, readonly) BOOL preciseTiming;

+ (instancetype)assetForID:(NSString *)id;
+ (instancetype)assetWithPreciseTiming:(BOOL)preciseTiming options:(NSDictionary *)options;
- (instancetype)init NS_UNAVAILABLE;

- (void)setWaveform:(NSDictionary *)waveform;
- (CMTime)seekPositionForTarget:(CMTime)target window:(CMTime)window;

@end

NS_ASSUME_NONNULL_END
