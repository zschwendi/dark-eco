#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GOALPadRuntimeStatus : NSObject

@property(nonatomic, readonly) NSString *architecture;
@property(nonatomic, readonly) NSString *storagePath;
@property(nonatomic, readonly) NSUInteger workloadResult;
@property(nonatomic, readonly, getter=isWorkloadVerified) BOOL workloadVerified;
@property(nonatomic, readonly) NSString *message;

@end

@interface GOALPadRuntimeBridge : NSObject

+ (GOALPadRuntimeStatus *)initializeRuntime;

@end

NS_ASSUME_NONNULL_END
