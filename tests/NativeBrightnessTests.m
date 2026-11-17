#import "NativeBrightnessBridge.h"
#import "DisplayDDC.h"
#import <math.h>
@interface DBBrightnessMemory:NSUserDefaults
@property NSMutableDictionary *values;
@property BOOL rejectCheckpoint;
@end
@implementation DBBrightnessMemory
- (instancetype)init {if((self=[super init]))_values=[NSMutableDictionary new];return self;}
- (id)objectForKey:(NSString*)key{return _values[key];}
- (void)setObject:(id)value forKey:(NSString*)key{_values[key]=value;}
- (BOOL)synchronize{return !_rejectCheckpoint;}
@end
@interface DBFakeBrightnessEndpoint:NSObject<DBBrightnessEndpoint>
@property BOOL refuse;
@property BOOL stopped;
@property double confirmed;
@property(copy) void(^handler)(double);
@end
@implementation DBFakeBrightnessEndpoint
- (BOOL)startWithContainer:(NSString*)uuid name:(NSString*)name percent:(double)percent handler:(void(^)(double))handler error:(NSError**)error {
    _confirmed=percent;_handler=[handler copy];return !_refuse;
}
- (void)setConfirmedPercent:(double)percent{_confirmed=percent;}
- (void)stop{_stopped=YES;_handler=nil;}
@end
@interface DBFakeBrightnessTransport:NSObject<DBBrightnessTransport>
@property NSData *live;
@property NSData *factory;
@property NSMutableArray *writes;
@property BOOL rejectApply;
@property BOOL rejectRestore;
@end
@implementation DBFakeBrightnessTransport
- (instancetype)init {if((self=[super init]))_writes=[NSMutableArray new];return self;}
- (NSData*)brightnessEDID{return _live;}
- (IOReturn)setBrightnessEDID:(NSData*)edid {
    [_writes addObject:edid?:NSNull.null];if((edid&&_rejectApply)||(!edid&&_rejectRestore))return kIOReturnError;
    _live=edid?:_factory;return kIOReturnSuccess;
}
@end
@interface DBNativeBrightnessBinding (Testing)
- (NSDictionary*)systemCapability;
- (NSTimeInterval)verificationDelay;
@end
@interface DBTestBrightnessBinding:DBNativeBrightnessBinding
@end
@implementation DBTestBrightnessBinding
- (NSDictionary*)systemCapability{return @{@"available":@YES};}
- (NSTimeInterval)verificationDelay{return .01;}
@end
static void check(BOOL ok,const char *message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static void settle(void){NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.12];while(until.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static NSData *edid(void){uint8_t p[256]={0,255,255,255,255,255,255,0};p[8]=0x10;p[9]=0xac;p[10]=0xa2;p[11]=0x76;p[12]=42;p[126]=1;p[128]=2;for(int base=0;base<256;base+=128){uint8_t sum=0;for(int i=0;i<127;i++)sum+=p[base+i];p[base+127]=-sum;}return [NSData dataWithBytes:p length:256];}
static DBTestBrightnessBinding *binding(DBBrightnessMemory *preferences,DBFakeBrightnessEndpoint *endpoint){return [[DBTestBrightnessBinding alloc]initWithIdentity:@"display:test" displayID:99 name:@"Test Monitor" preferences:preferences queue:dispatch_queue_create("brightness.tests",DISPATCH_QUEUE_SERIAL) endpoint:endpoint];}
int main(void){@autoreleasepool{
    NSData *original=edid();uuid_t bytes;[NSUUID.UUID getUUIDBytes:bytes];NSData *container=[NSData dataWithBytes:bytes length:16];
    check(DBBrightnessEDIDValid(original),"fixture has valid base and CTA checksums");
    NSData *patched=DBBrightnessEDIDWithContainer(original,container);
    check(patched.length==384&&DBBrightnessEDIDValid(patched)&&[DBBrightnessContainer(patched) isEqual:container],"ContainerID extension and all block checksums round trip");
    check([[patched subdataWithRange:NSMakeRange(8,118)] isEqual:[original subdataWithRange:NSMakeRange(8,118)]]&&[[patched subdataWithRange:NSMakeRange(128,128)] isEqual:[original subdataWithRange:NSMakeRange(128,128)]],"physical identity, timings and CTA HDR/color data preserved");
    check([DBBrightnessEDIDWithContainer(patched,container) isEqual:patched],"reapplication is idempotent");
    NSMutableData *other=[container mutableCopy];((uint8_t*)other.mutableBytes)[0]^=1;
    check(!DBBrightnessEDIDWithContainer(patched,other),"another app's existing ContainerID is never overwritten");
    NSMutableData *broken=[original mutableCopy];((uint8_t*)broken.mutableBytes)[140]^=1;
    check(!DBBrightnessEDIDWithContainer(broken,container)&&!DBBrightnessContainer(broken),"corrupt EDID cannot be patched or paired");
    for(NSUInteger length=0;length<256;length++)check(!DBBrightnessEDIDValid([original subdataWithRange:NSMakeRange(0,length)]),"truncated EDID and extension rejected");
    const uint8_t half[]={0x30,0x75,0,0},numbered[]={1,0x30,0x75,0,0},tooLarge[]={0xff,0xff,0xff,0xff};
    check(fabs(DBBrightnessDecodeFeature([NSData dataWithBytes:half length:4]).doubleValue-50)<.01&&DBBrightnessDecodeFeature([NSData dataWithBytes:numbered length:5]).intValue==50,"32-bit HID values support payload with and without report ID");
    check(!DBBrightnessDecodeFeature([NSData dataWithBytes:tooLarge length:4])&&!DBBrightnessDecodeFeature([NSData dataWithBytes:half length:3]),"out-of-range and truncated HID requests rejected");
    DBBrightnessMemory *preferences=[DBBrightnessMemory new];DBFakeBrightnessEndpoint *endpoint=[DBFakeBrightnessEndpoint new];endpoint.refuse=YES;
    DBFakeBrightnessTransport *transport=[DBFakeBrightnessTransport new];transport.live=transport.factory=original;
    DBTestBrightnessBinding *session=binding(preferences,endpoint);[session startWithEDID:original transport:transport percent:81];settle();
    check(transport.writes.count==0&&[session.state[@"phase"] isEqual:@"failed"],"HID creation refusal causes no EDID mutation");
    endpoint=[DBFakeBrightnessEndpoint new];session=binding(preferences,endpoint);__block double received=-1;
    session.onPercent=^(double percent){received=percent;};[session startWithEDID:original transport:transport percent:81];settle();
    check([session.state[@"available"] boolValue]&&DBBrightnessContainer(transport.live)&&preferences.values[@"NativeBrightnessJournal"][@"display:test"],"binding becomes available only after EDID and system capability confirmation");
    endpoint.handler(37);check(received==37,"system HID request reaches DDC forwarding handler");
    [session acknowledgePercent:37 success:YES];check(endpoint.confirmed==37&&[session.state[@"hardwareWriteConfirmed"] boolValue],"hardware readback updates the confirmed HID value");
    __block BOOL restored=NO;[session stopWithCompletion:^(BOOL ok){restored=ok;}];settle();
    check(restored&&endpoint.stopped&&[transport.live isEqual:original]&&!preferences.values[@"NativeBrightnessJournal"][@"display:test"],"normal exit restores original EDID and clears only completed checkpoint");
    // A failed DDC write must withdraw the native association, not fake success.
    endpoint=[DBFakeBrightnessEndpoint new];session=binding(preferences,endpoint);[session startWithEDID:original transport:transport percent:81];settle();[session acknowledgePercent:30 success:NO];settle();
    check(endpoint.stopped&&[transport.live isEqual:original]&&[session.state[@"phase"] isEqual:@"failed"],"DDC failure removes HID and restores EDID");
    endpoint=[DBFakeBrightnessEndpoint new];session=binding(preferences,endpoint);[session startWithEDID:original transport:transport percent:81];settle();transport.rejectRestore=YES;restored=YES;
    [session stopWithCompletion:^(BOOL ok){restored=ok;}];settle();check(!restored&&preferences.values[@"NativeBrightnessJournal"][@"display:test"],"failed restore retains recovery checkpoint");
    transport.rejectRestore=NO;[session stopWithCompletion:^(BOOL ok){restored=ok;}];settle();check(restored&&[transport.live isEqual:original],"exit restore can be retried");
    // Simulate process death: a later binding adopts the same checkpoint and UUID.
    endpoint=[DBFakeBrightnessEndpoint new];session=binding(preferences,endpoint);[session startWithEDID:original transport:transport percent:81];settle();
    DBFakeBrightnessEndpoint *replacement=[DBFakeBrightnessEndpoint new];DBTestBrightnessBinding *recovery=binding(preferences,replacement);[recovery startWithEDID:transport.live transport:transport percent:81];settle();
    check([recovery.state[@"available"] boolValue],"a prior incomplete session can be recovered without appending another extension");
    [endpoint stop];[recovery stopWithCompletion:^(BOOL ok){restored=ok;}];settle();check(restored&&[transport.live isEqual:original],"recovered session restores original EDID");
    puts("PASS: EDID identity/checksums, HID forwarding, permission failure gating, DDC confirmation, exit restore and recovery");
}}
