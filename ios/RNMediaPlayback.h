#define PLAYBACK_DEBUG 0

#if PLAYBACK_DEBUG
#define LOG(...) NSLog(@"[playback.native] " __VA_ARGS__)
#else
#define LOG(...)
#endif

#define nilNull(value) ((value) == [NSNull null] ? nil : (value))
#define nullNil(value) ((value) == nil ? [NSNull null] : (value))
