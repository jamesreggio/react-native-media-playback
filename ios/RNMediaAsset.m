#import <React/RCTAssert.h>
#import <React/RCTConvert.h>
#import "RNMediaPlayback.h"
#import "RNMediaWaveform.h"
#import "RNMediaAsset.h"
@import AVFoundation;

@implementation RNMediaAsset
{
  RNMediaWaveform *_waveform;
}

#pragma mark - Constructors

+ (NSMapTable<NSString *, RNMediaAsset *> *)cache
{
  static NSMapTable<NSString *, RNMediaAsset *> *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [NSMapTable strongToWeakObjectsMapTable];
  });
  return instance;
}

+ (RNMediaAsset *)assetForID:(NSString *)id
{
  return [[RNMediaAsset cache] objectForKey:id];
}

+ (RNMediaAsset *)assetWithPreciseTiming:(BOOL)preciseTiming options:(NSDictionary *)options
{
  NSString *id = nilNull(options[@"id"]);
  RCTAssert(id, @"Expected ID for asset");

  NSString *src = nilNull(options[@"src"]);
  RCTAssert(src, @"Expected src for asset");

  NSURL *url = [NSURL URLWithString:src];

  NSMapTable<NSString *, RNMediaAsset *> *cache = [RNMediaAsset cache];
  RNMediaAsset *asset = [cache objectForKey:id];

  // If we're streaming a non-M4A audio file, playback may never start if precise timing is requested.
  preciseTiming = preciseTiming && (url.isFileURL || [url.pathExtension isEqualToString:@"m4a"]);

  if (!asset || (preciseTiming && !asset.preciseTiming)) {
    asset = [[RNMediaAsset alloc] initWithID:id URL:url preciseTiming:preciseTiming];
    [cache setObject:asset forKey:id];
  }

  return asset;
}

- (instancetype)initWithID:(NSString *)id URL:(NSURL *)url preciseTiming:(BOOL)preciseTiming
{
  if (self = [super init]) {
    _AVAsset = [AVURLAsset URLAssetWithURL:url options:@{
      AVURLAssetPreferPreciseDurationAndTimingKey: @(preciseTiming),
    }];
  }
  return self;
}

#pragma mark - Properties

- (BOOL)preciseTiming
{
  return _AVAsset.providesPreciseDurationAndTiming;
}

#pragma mark - Waveforms

- (void)setWaveform:(NSDictionary *)data
{
  _waveform = [RNMediaWaveform waveformWithData:data];
}

- (CMTime)seekPositionForTarget:(CMTime)target window:(CMTime)window
{
  return _waveform
    ? [_waveform seekPositionForTarget:target window:window]
    : target;
}

@end
