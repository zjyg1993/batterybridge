#import <Cocoa/Cocoa.h>
@interface DBNativeAudioSetup : NSObject
- (void)beginOnboarding;
- (void)updateDisplayBridges:(NSArray<NSDictionary*>*)rows userInitiated:(BOOL)userInitiated;
- (void)prepareForTermination:(void(^)(BOOL restored))completion;
- (void)stop;
@end
