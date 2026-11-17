#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

// Adopt a separately installed upstream Proxy Audio Device. Does not implement
// another PCM engine or copy/reimplement the upstream driver.
@protocol DBNativeAudioBackend <NSObject>
- (NSArray<NSDictionary*>*)outputs;
- (NSString*)defaultOutputUID;
- (BOOL)setDefaultOutputUID:(NSString*)uid error:(NSError**)error;
@optional
- (NSDictionary*)diagnostics;
- (BOOL)setProxyPublished:(BOOL)published error:(NSError**)error;
- (BOOL)configureProxyUID:(NSString*)proxyUID physicalUID:(NSString*)physicalUID error:(NSError**)error;
@end
@interface DBNativeProxyAudio:NSObject
- (instancetype)initWithBackend:(id<DBNativeAudioBackend>)backend;
- (NSDictionary*)status;
// The upstream Settings app must first be configured to the physical output.
// Manual CLI sessions require explicit route confirmation; the app uses the
// verified upstream Box configuration protocol through activateConfiguredProxy.
- (BOOL)activateProxy:(NSString*)proxyUID physicalOutput:(NSString*)physicalUID routeConfirmed:(BOOL)confirmed error:(NSError**)error;
- (BOOL)activateConfiguredProxy:(NSString*)proxyUID physicalOutput:(NSString*)physicalUID error:(NSError**)error;
- (BOOL)activateAutomaticProxy:(NSString*)proxyUID physicalOutput:(NSString*)physicalUID restoreOutput:(NSString*)restoreUID error:(NSError**)error;
- (BOOL)deactivate:(NSError**)error;
@end
FOUNDATION_EXPORT NSString *DBDisplayAudioOutputUID(NSDictionary *display,NSArray<NSDictionary*> *displays,NSArray<NSDictionary*> *outputs);
FOUNDATION_EXPORT BOOL DBNativeProxyIdentityMatches(NSDictionary *record, AudioObjectID pluginID, NSArray<NSNumber*> *pluginDevices);
@interface DBSystemAudioBackend:NSObject<DBNativeAudioBackend>
@property(nonatomic,readonly) NSDictionary *diagnostics;
@end
