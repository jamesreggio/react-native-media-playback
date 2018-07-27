#define PLAYBACK_DEBUG 1

#if PLAYBACK_DEBUG
#define LOG(...) NSLog(@"[playback.native] " __VA_ARGS__)
#else
#define LOG(...)
#endif

#define nilNull(value) ((value) == [NSNull null] ? nil : (value))
#define nullNil(value) ((value) == nil ? [NSNull null] : (value))

// It would be ideal to make these more configurable.
#define SKIP_FORWARD_INTERVAL 30 // sec
#define SKIP_BACKWARD_INTERVAL 15 // sec
