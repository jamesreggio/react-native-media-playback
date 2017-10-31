#import <Foundation/Foundation.h>

@interface RNMediaPlaybackSession : NSObject

- (instancetype)initWithKey:(NSNumber *)key options:(NSDictionary *)options;

// Lifecycle
- (void)activate;
- (void)deactivate;

@end
