#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNMediaSession : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithOptions:(NSDictionary *)options NS_DESIGNATED_INITIALIZER;

- (void)activate;
- (void)deactivate;

@end

NS_ASSUME_NONNULL_END
