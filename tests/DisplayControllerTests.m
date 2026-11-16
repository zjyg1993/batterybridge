#import <Cocoa/Cocoa.h>
#import "Display.h"
@interface BBFakeDDC:NSObject
@property NSDictionary*identity;
@property int writes;
@property uint16_t value;
@property BOOL failedRead;
@property BOOL ignoreWrite;
@property BOOL noVolume;
@property BOOL failedWrite;
- (NSDictionary*)read:(uint8_t)code;
- (BOOL)write:(uint8_t)code value:(uint16_t)value;
@end
@implementation BBFakeDDC
- (NSDictionary*)read:(uint8_t)code {return (_failedRead||(_noVolume&&code==0x62))?nil:@{@"current":@(_value),@"maximum":@255,@"percent":@(100.0*_value/255)};}
- (BOOL)write:(uint8_t)code value:(uint16_t)value {_writes++;if(_failedWrite)return NO;if(!_ignoreWrite)_value=value;return YES;}
@end
@interface BBMemoryDisplayDefaults:NSUserDefaults
@property NSMutableDictionary*values;
@end
@implementation BBMemoryDisplayDefaults
- (instancetype)init {if((self=[super init]))_values=[NSMutableDictionary new];return self;}
- (id)objectForKey:(NSString*)key {return _values[key];}
- (void)setObject:(id)value forKey:(NSString*)key {_values[key]=value;}
@end
@interface BBQuietDisplayController:BBDisplayController
@property NSArray*fixtureScreens;
@property NSArray*fixtureChannels;
@end
@interface BBDisplayController (Testing)
- (void)adjustKey:(int)key record:(NSDictionary*)record;
@end
@implementation BBQuietDisplayController
- (NSArray*)connectedScreens {return _fixtureScreens?:@[];}
- (NSArray*)displayChannels {return _fixtureChannels?:@[];}
- (void)showHUD:(NSString*)name feature:(NSString*)feature percent:(double)percent {}
@end
static void check(BOOL ok,const char*message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static void settle(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.25]];}
int main(void){@autoreleasepool{
    BBMemoryDisplayDefaults*preferences=[BBMemoryDisplayDefaults new];
    BBQuietDisplayController*c=[[BBQuietDisplayController alloc]initWithDefaults:preferences];[c setValue:@YES forKey:@"running"];
    BBFakeDDC*bus=[BBFakeDDC new];bus.value=128;
    NSMutableDictionary*record=[@{@"identity":@"display:test",@"name":@"DELL S2725QS",@"brightness":[bus read:0x10]} mutableCopy];
    NSMutableDictionary*channels=[c valueForKey:@"channels"],*records=[c valueForKey:@"records"];channels[@"display:test"]=bus;records[@"display:test"]=record;
    [c setPercent:10 code:0x10 identity:@"display:test"];[c setPercent:80 code:0x10 identity:@"display:test"];settle();
    check(bus.writes==1&&bus.value==204,"coalesce rapid slider changes and respect maximum 255");
    check([c.snapshot.firstObject[@"brightness"][@"current"] intValue]==204,"publish confirmed reading");
    NSDictionary*previous=c.snapshot.firstObject;
    [c setPercent:200 code:0x10 identity:@"display:test"];settle();
    check(bus.value==255,"clamp out-of-range request");
    check([previous[@"brightness"][@"current"] intValue]==204,"published snapshots stay immutable");
    int before=bus.writes;
    [c setPercent:20 code:0x62 identity:@"display:test"];[c setPercent:20 code:0x10 identity:@"missing"];[c setPercent:NAN code:0x10 identity:@"display:test"];settle();
    check(bus.writes==before,"unsupported controls, unknown displays and NaN never write");
    [c setPercent:10 code:0x10 identity:@"display:test"];[c setValue:@1 forKey:@"generation"];settle();
    check(bus.writes==before,"topology change cancels queued writes");
    bus.ignoreWrite=YES;[c setPercent:20 code:0x10 identity:@"display:test"];settle();
    check([c.snapshot.firstObject[@"status"] containsString:@"未应用"],"do not claim success when panel ignores write");
    check(!c.snapshot.firstObject[@"brightness"],"ignored write disables the feature");
    before=bus.writes;[c setPercent:30 code:0x10 identity:@"display:test"];settle();check(bus.writes==before,"blocked control cannot write again");
    record[@"brightness"]=[bus read:0x10];[record removeObjectForKey:@"brightnessError"];
    bus.failedRead=YES;[c setPercent:20 code:0x10 identity:@"display:test"];settle();
    check(!c.snapshot.firstObject[@"brightness"]&&[c.snapshot.firstObject[@"status"] containsString:@"失败"],"failed readback disables stale control");
    BBDisplayRow*row=[[BBDisplayRow alloc]initWithFrame:NSMakeRect(0,0,510,96) record:@{@"name":@"Dell",@"brightness":@{@"percent":@40}}];
    NSEvent *rightClick=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
    NSMenu *injected=[NSMenu new];[injected addItemWithTitle:@"删除" action:NULL keyEquivalent:@""];row.menu=injected;
    check([row menuForEvent:rightClick]==nil,"online display never exposes a deletion menu");
    BBDisplayRow *offline=[[BBDisplayRow alloc]initWithFrame:NSMakeRect(0,0,510,96) record:@{@"connected":@NO,@"identity":@"display:test"}];offline.menu=injected;
    check([offline menuForEvent:rightClick]==nil,"disconnected display never exposes a deletion menu");
    check(row.brightnessSlider.enabled&&!row.volumeSlider.enabled,"brightness and volume capabilities are independent");
    // Reload through the same in-memory preference store; never modify real preferences.
    check(![c mappingEnabledForIdentity:@"display:test"],"new displays default to mapping disabled");
    [c setMappingEnabled:YES identity:@"display:test"];settle();
    BBDisplayController*reloaded=[[BBQuietDisplayController alloc]initWithDefaults:preferences];
    check([reloaded mappingEnabledForIdentity:@"display:test"],"mapping choice persists across controller restarts");
    bus.failedRead=NO;bus.ignoreWrite=NO;bus.identity=@{@"name":@"DELL S2725QS"};
    c.fixtureScreens=@[@{@"identity":@"display:test",@"name":@"DELL S2725QS",@"displayID":@1}];c.fixtureChannels=@[bus];
    [c refreshControls];check(c.snapshot.count==1,"refresh never clears the visible row");settle();
    check(c.snapshot.count==1&&[c.snapshot.firstObject[@"connected"] boolValue]&&c.snapshot.firstObject[@"volume"],"scan refreshes both capabilities in place");
    [c rescan];[c rescan];check(c.snapshot.count==1,"overlapping reconfiguration scans keep rows visible");settle();settle();
    check(c.snapshot.count==1&&[c.snapshot.firstObject[@"mappingEnabled"] boolValue],"overlapping scans finish with the current mapping");
    c.fixtureScreens=@[];[c rescan];check(c.snapshot.count==1,"empty enumeration does not immediately hide a known display");settle();
    check(c.snapshot.count==1&&![c.snapshot.firstObject[@"connected"] boolValue]&&!c.snapshot.firstObject[@"brightness"],"offline row is retained without writable stale values");
    before=bus.writes;[c setPercent:50 code:0x10 identity:@"display:test"];settle();check(bus.writes==before,"offline retained row cannot write");
    c.fixtureScreens=@[@{@"identity":@"display:test",@"name":@"DELL S2725QS",@"displayID":@1}];[c rescan];settle();
    check(c.snapshot.count==1&&[c.snapshot.firstObject[@"connected"] boolValue]&&[c mappingEnabledForIdentity:@"display:test"],"reconnection restores the same row and mapping choice");
    before=bus.writes;[c adjustKey:3 record:c.snapshot.firstObject];[c setMappingEnabled:NO identity:@"display:test"];settle();
    check(bus.writes==before,"disabling mapping cancels pending media-key writes");
    [c adjustKey:3 record:c.snapshot.firstObject];settle();check(bus.writes==before,"disabled mapping never forwards media-key commands");
    [c setPercent:30 code:0x10 identity:@"display:test"];settle();check(bus.writes==before+1,"manual control stays available with mapping off");
    [c setMappingEnabled:YES identity:@"display:test"];settle();before=bus.writes;[c adjustKey:3 record:c.snapshot.firstObject];settle();
    check(bus.writes==before+1,"enabled mapping forwards media-key commands");
    // A brand with no volume VCP remains fully usable for brightness.
    bus.noVolume=YES;[c refreshControls];settle();
    BBDisplayRow *partial=[[BBDisplayRow alloc]initWithFrame:NSMakeRect(0,0,510,96) record:c.snapshot.firstObject];
    check(partial.brightnessSlider.enabled&&!partial.volumeSlider.enabled,"unsupported volume is visibly disabled");
    before=bus.writes;[c setPercent:80 code:0x62 identity:@"display:test"];[c adjustKey:0 record:c.snapshot.firstObject];[c adjustKey:7 record:c.snapshot.firstObject];settle();
    check(bus.writes==before,"no volume VCP blocks slider, media volume and mute");
    bus.noVolume=NO;[c refreshControls];settle();
    bus.ignoreWrite=YES;[c setPercent:95 code:0x62 identity:@"display:test"];settle();
    check(!c.snapshot.firstObject[@"volume"]&&c.snapshot.firstObject[@"volumeError"],"ignored volume SET removes control");
    before=bus.writes;[c rescan];settle();
    check(c.snapshot.firstObject[@"volumeError"]!=nil,"automatic scan preserves rejected-write lockout");
    partial=[[BBDisplayRow alloc]initWithFrame:NSMakeRect(0,0,510,96) record:c.snapshot.firstObject];
    check(!partial.volumeSlider.enabled&&partial.brightnessSlider.enabled,"readable but rejected volume stays disabled independently");
    [c setPercent:50 code:0x62 identity:@"display:test"];[c adjustKey:1 record:c.snapshot.firstObject];[c adjustKey:7 record:c.snapshot.firstObject];settle();
    check(bus.writes==before,"all volume entry points respect write lockout");
    bus.ignoreWrite=NO;[c refreshControls];settle();
    check(!c.snapshot.firstObject[@"volumeError"],"explicit refresh retries rejected feature");
    bus.failedWrite=YES;[c setPercent:25 code:0x62 identity:@"display:test"];settle();
    check(!c.snapshot.firstObject[@"volume"]&&c.snapshot.firstObject[@"volumeError"],"transport write failure blocks volume");
    bus.failedWrite=NO;[c refreshControls];settle();
    bus.failedRead=YES;[c setPercent:70 code:0x62 identity:@"display:test"];settle();
    check(!c.snapshot.firstObject[@"volume"],"failed volume readback disables volume");
    before=bus.writes;[c setPercent:30 code:0x62 identity:@"display:test"];[c adjustKey:7 record:c.snapshot.firstObject];settle();
    check(bus.writes==before,"failed readback blocks subsequent volume and mute writes");
    bus.failedRead=NO;[c refreshControls];
    partial=[[BBDisplayRow alloc]initWithFrame:NSMakeRect(0,0,510,96) record:c.snapshot.firstObject];
    check(!partial.volumeSlider.enabled&&!partial.brightnessSlider.enabled,"scan visibly disables stale controls");settle();
    // Anonymous fallback cannot override a known physical identity conflict.
    bus.identity=@{@"serial":@99};c.fixtureScreens=@[@{@"identity":@"display:test",@"serial":@42}];[c rescan];settle();
    check(!records[@"display:test"][@"volume"],"single port fallback rejects conflicting serial");
    // Identical models are controllable only with unique physical locations.
    BBFakeDDC *second=[BBFakeDDC new];second.identity=@{@"name":@"Generic Monitor",@"location":@"port-B"};
    bus.identity=@{@"name":@"Generic Monitor",@"location":@"port-A"};
    c.fixtureScreens=@[@{@"identity":@"display:A",@"name":@"Generic Monitor",@"location":@"port-A"},@{@"identity":@"display:B",@"name":@"Generic Monitor",@"location":@"port-B"}];
    c.fixtureChannels=@[second,bus];[c rescan];settle();
    check(records[@"display:A"][@"brightness"]&&records[@"display:B"][@"brightness"],"identical models matched by location regardless of port order");
    bus.identity=@{@"name":@"Generic Monitor"};second.identity=bus.identity;[c rescan];settle();
    check(!records[@"display:A"][@"brightness"]&&!records[@"display:B"][@"brightness"],"ambiguous identical monitors never acquire writable channels");
    [c setValue:@NO forKey:@"running"];
    puts("Display controller tests passed");return 0;
}}
