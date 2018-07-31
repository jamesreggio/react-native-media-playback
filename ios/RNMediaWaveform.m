//XXX add sound on skip

#import <React/RCTAssert.h>
#import <React/RCTConvert.h>
#import "RNMediaPlayback.h"
#import "RNMediaWaveform.h"
@import AVFoundation;

//XXX make configurable
#define RESUME_WINDOW_OFFSET 0.6 // sec
#define RESUME_WINDOW_SIZE 1.4 // sec

typedef struct {
  NSUInteger lower;
  NSUInteger upper;
} RNRange;

NSUInteger getRangeSize(RNRange range)
{
  return range.upper - range.lower;
}

NSUInteger getClosestPointInRange(RNRange range, NSUInteger target)
{
  if (target >= range.lower && target <= range.upper) {
    return target;
  }

  NSUInteger lowerDist = ABS(target - range.lower);
  NSUInteger upperDist = ABS(target - range.upper);
  return lowerDist < upperDist ? range.lower : range.upper;
}

double getGuassianPDF(double mean, double stddev, double x)
{
  return (
    exp(-pow(x - mean, 2) / (2 * pow(stddev, 2))) /
    (stddev * sqrt(2 * M_PI))
  );
}

double getScoreForRange(RNRange range, NSUInteger target, NSUInteger window)
{
  NSUInteger point = getClosestPointInRange(range, target);

  if (ABS(point - target) >= window) {
    return 0;
  }

  double mean = target;
  double stddev = window / 2;
  return getRangeSize(range) * getGuassianPDF(mean, stddev, point);
}

NSUInteger getMinValueIndex(RNRange range, float *values) {
  float minValue = values[range.lower];
  NSUInteger minIndex = range.lower;

  for (NSUInteger i = range.lower; i < range.upper; i++) {
    if (values[i] < minValue) {
      minValue = values[i];
      minIndex = i;
    }
  }

  return minIndex;
}

@implementation RNMediaWaveform
{
  NSUInteger _frequency;
  NSUInteger _silencesCount;
  NSMutableData *_silences;
  NSMutableData *_samples;
}

+ (instancetype)waveformWithData:(NSDictionary *)data
{
  return [[RNMediaWaveform alloc] initWithData:data];
}

- (instancetype)initWithData:(NSDictionary *)data
{
  if (self = [super init]) {
    _frequency = [RCTConvert NSNumber:data[@"frequency"]].unsignedIntegerValue;

    NSArray<NSDictionary *> *silenceData = [RCTConvert NSDictionaryArray:data[@"silences"]];
    NSUInteger silencesCount = _silencesCount = silenceData.count;
    _silences = [NSMutableData dataWithCapacity:(sizeof(RNRange) * silencesCount)];
    RNRange *silences = _silences.mutableBytes;
    for (NSUInteger i = 0; i < silencesCount; i++) {
      NSDictionary *silence = silenceData[i];
      RNRange range = {
        [RCTConvert NSNumber:silence[@"lower"]].unsignedIntegerValue,
        [RCTConvert NSNumber:silence[@"upper"]].unsignedIntegerValue,
      };
      silences[i] = range;
    }

    NSArray<NSNumber *> *samplesData = [RCTConvert NSNumberArray:data[@"samples"]];
    NSUInteger samplesCount = samplesData.count;
    _samples = [NSMutableData dataWithCapacity:(sizeof(float) * samplesCount)];
    float *samples = _samples.mutableBytes;
    for (NSUInteger i = 0; i < samplesCount; i++) {
      samples[i] = samplesData[i].floatValue;
    }
  }
  return self;
}

- (CMTime)seekPositionForTarget:(CMTime)_target window:(CMTime)_window
{
  double target = CMTimeGetSeconds(_target);
  double window = CMTimeGetSeconds(_window);

  NSUInteger frequency = _frequency;
  NSUInteger silencesCount = _silencesCount;
  RNRange *silences = _silences.mutableBytes;
  float *samples = _samples.mutableBytes;

  // Find the highest scoring range of silence.

  double topScore = 0;
  RNRange topSilence;
  NSUInteger scoringTarget = (NSUInteger)round(frequency * target);
  NSUInteger scoringWindow = (NSUInteger)round(frequency * window);

  for (NSUInteger i = 0; i < silencesCount; i++) {
    RNRange silence = silences[i];
    double score = getScoreForRange(silence, scoringTarget, scoringWindow);
    if (score > topScore) {
      topScore = score;
      topSilence = silence;
    }
  }

  if (!topScore) {
    return _target;
  }

  // Otherwise, find a suitable point within the range for resuming playback.

  NSUInteger resumeOffset = (NSUInteger)round(RESUME_WINDOW_OFFSET * frequency);
  NSUInteger resumeWindow = (NSUInteger)ceil(RESUME_WINDOW_SIZE * frequency);

  RNRange resumeRange = {
    MAX(topSilence.lower, topSilence.upper - resumeOffset - resumeWindow),
    MAX(topSilence.lower, topSilence.upper - resumeOffset),
  };

  NSUInteger resumeIndex = getMinValueIndex(resumeRange, samples);
  return CMTimeMakeWithSeconds(resumeIndex / frequency, NSEC_PER_SEC);
}

@end
