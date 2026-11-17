#import <Foundation/Foundation.h>
#import <IOKit/IOReturn.h>

// DisplayID 2.0 ContainerID payload. These helpers never modify caller data.
FOUNDATION_EXPORT BOOL DBBrightnessEDIDValid(NSData *data);
FOUNDATION_EXPORT NSData *DBBrightnessContainer(NSData *edid);
FOUNDATION_EXPORT NSData *DBBrightnessEDIDWithContainer(NSData *edid,NSData *container);
FOUNDATION_EXPORT NSData *DBBrightnessHIDDescriptor(void);
FOUNDATION_EXPORT NSNumber *DBBrightnessDecodeFeature(NSData *report);
FOUNDATION_EXPORT BOOL DBBrightnessHIDEntitled(void);
FOUNDATION_EXPORT NSDictionary *DBBrightnessSystemCapability(uint32_t displayID);
FOUNDATION_EXPORT NSData *DBBrightnessCopyEDID(id avService);
FOUNDATION_EXPORT IOReturn DBBrightnessSetEDID(id avService,NSData *edid);

@protocol DBBrightnessTransport <NSObject>
- (NSData*)brightnessEDID;
- (IOReturn)setBrightnessEDID:(NSData*)edid; // nil restores factory EDID in RAM
@end
@protocol DBBrightnessEndpoint <NSObject>
- (BOOL)startWithContainer:(NSString*)uuid name:(NSString*)name percent:(double)percent handler:(void(^)(double))handler error:(NSError**)error;
- (void)setConfirmedPercent:(double)percent;
- (void)stop;
@end
@interface DBHIDBrightnessEndpoint:NSObject<DBBrightnessEndpoint>
@end

// AppKit/HID state belongs to the main thread. EDID and DDC work shares the
// display controller's serial I/O queue, so exit restore follows pending writes.
@interface DBNativeBrightnessBinding:NSObject
@property(nonatomic,copy) void(^onPercent)(double percent);
@property(nonatomic,copy) void(^onState)(NSDictionary *state);
@property(nonatomic,readonly) NSDictionary *state;
- (instancetype)initWithIdentity:(NSString*)identity displayID:(uint32_t)displayID name:(NSString*)name preferences:(NSUserDefaults*)preferences queue:(dispatch_queue_t)queue endpoint:(id<DBBrightnessEndpoint>)endpoint;
- (void)startWithEDID:(NSData*)edid transport:(id<DBBrightnessTransport>)transport percent:(double)percent;
- (void)updateTransport:(id<DBBrightnessTransport>)transport edid:(NSData*)edid displayID:(uint32_t)displayID;
- (void)acknowledgePercent:(double)percent success:(BOOL)success;
- (void)stopWithCompletion:(void(^)(BOOL restored))completion;
@end
