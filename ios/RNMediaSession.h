#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNMediaSession : NSObject

+ (instancetype)sessionWithOptions:(NSDictionary *)options;
- (instancetype)init NS_UNAVAILABLE;

- (void)activate;
- (void)deactivate;

@end

NS_ASSUME_NONNULL_END
