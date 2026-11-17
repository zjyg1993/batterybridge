#import "NativeProxyAudio.h"
#import "NativeBrightness.h"
#import <math.h>
@interface DBFakeAudio:NSObject<DBNativeAudioBackend>
@property NSArray*rows;
@property NSString*selected;
@property NSUInteger changes;
@property BOOL refuse;
@property BOOL ignoreFirst;
@property BOOL configurationRefused;
@property NSUInteger configurations;
@end
@implementation DBFakeAudio
- (BOOL)configureProxyUID:(NSString*)proxyUID physicalUID:(NSString*)physicalUID error:(NSError**)error {_configurations++;return !_configurationRefused;}
- (NSArray*)outputs{return _rows;}
- (NSString*)defaultOutputUID{return _selected;}
- (BOOL)setDefaultOutputUID:(NSString*)uid error:(NSError**)error{_changes++;if(_refuse)return NO;if(_ignoreFirst&&_changes==1)return YES;_selected=uid;return YES;}
@end
static void check(BOOL yes,const char*message){if(!yes){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static NSData*edid(void){uint8_t p[256]={0,255,255,255,255,255,255,0};p[8]=0x10;p[9]=0xac;p[126]=1;p[128]=2;for(int block=0;block<2;block++){uint8_t sum=0;for(int i=0;i<127;i++)sum+=p[block*128+i];p[block*128+127]=-sum;}return [NSData dataWithBytes:p length:256];}
int main(void){@autoreleasepool{
    DBFakeAudio*b=[DBFakeAudio new];b.rows=@[@{@"uid":@"proxy",@"alive":@YES,@"channels":@2,@"volumeWritable":@YES,@"muteWritable":@YES,@"virtual":@YES,@"recognizedProxyBundle":@YES},@{@"uid":@"hdmi",@"alive":@YES,@"channels":@2,@"virtual":@NO,@"displayTransport":@YES},@{@"uid":@"built-in",@"alive":@YES,@"channels":@2}];b.selected=@"built-in";
    DBNativeProxyAudio*a=[[DBNativeProxyAudio alloc]initWithBackend:b];NSError*error=nil;
    check(![a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:NO error:&error]&&b.changes==0,"unknown upstream routing never changes output");
    check(![a activateProxy:@"proxy" physicalOutput:@"proxy" routeConfirmed:YES error:&error]&&b.changes==0,"no self-routing");
    check(![a activateProxy:@"missing" physicalOutput:@"hdmi" routeConfirmed:YES error:&error]&&b.changes==0,"missing proxy is rejected");
    check([a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error]&&[b.selected isEqual:@"proxy"],"adopt installed proxy output");
    check([a deactivate:&error]&&[b.selected isEqual:@"built-in"],"restore previous output");
    check([a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error],"reactivate proxy");b.selected=@"hdmi";NSUInteger changes=b.changes;check([a deactivate:&error]&&b.changes==changes,"preserve user's later route choice");
    b.selected=@"built-in";b.changes=0;b.ignoreFirst=YES;check(![a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error]&&b.changes==2&&[b.selected isEqual:@"built-in"],"readback mismatch rolls back");b.ignoreFirst=NO;
    NSMutableDictionary*invalid=[b.rows[0] mutableCopy];invalid[@"recognizedProxyBundle"]=@NO;NSArray*validRows=b.rows;b.rows=@[invalid,validRows[1],validRows[2]];
    check(![a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error],"other virtual devices are not misidentified as upstream proxy");
    invalid[@"recognizedProxyBundle"]=@YES;invalid[@"volumeWritable"]=@NO;check(![a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error],"no false volume-control claim");
    b.rows=validRows;check([a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error],"enable recovery scenario");b.rows=@[validRows[0],validRows[1]];check([a deactivate:&error]&&[b.selected isEqual:@"hdmi"],"fall back to configured physical endpoint if previous output disappeared");
    b.rows=validRows;b.selected=@"built-in";check([a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error],"begin failed-restore scenario");b.refuse=YES;
    check(![a deactivate:&error]&&[a.status[@"activeProxyUID"] isEqual:@"proxy"],"failed restore is retained for retry, not reported as success");b.refuse=NO;check([a deactivate:&error],"retry output restore");
    b.rows=[validRows arrayByAddingObject:validRows[0]];check(![a activateProxy:@"proxy" physicalOutput:@"hdmi" routeConfirmed:YES error:&error],"duplicate UIDs cannot select an arbitrary endpoint");b.rows=validRows;
    b.selected=@"built-in";b.configurationRefused=YES;changes=b.changes;
    check(![a activateConfiguredProxy:@"proxy" physicalOutput:@"hdmi" error:&error]&&b.changes==changes,"failed upstream route confirmation never changes default output");
    b.configurationRefused=NO;
    check([a activateConfiguredProxy:@"proxy" physicalOutput:@"hdmi" error:&error]&&[b.selected isEqual:@"proxy"]&&[a.status[@"routeConfigurationVerified"] boolValue],"configured proxy switches only after verified upstream route");
    check([a deactivate:&error]&&[b.selected isEqual:@"built-in"]&&![a.status[@"routeConfigurationVerified"] boolValue],"configured proxy session restores previous output");
    b.selected=@"proxy";NSUInteger configurations=b.configurations;
    changes=b.changes;
    check([a activateConfiguredProxy:@"proxy" physicalOutput:@"hdmi" error:&error]&&b.configurations==configurations+1&&b.changes==changes&&[a.status[@"adoptedExistingProxy"] boolValue],"already selected proxy is adopted after route verification without toggling outputs");
    check([a deactivate:&error]&&[b.selected isEqual:@"proxy"]&&b.changes==changes,"ending adopted session preserves the user's existing proxy selection");
    b.selected=@"built-in";configurations=b.configurations;
    check(![a activateConfiguredProxy:@"proxy" physicalOutput:@"missing" error:&error]&&b.configurations==configurations,"invalid target cannot modify persisted upstream route");
    NSDictionary *endpoint=@{@"id":@42,@"uid":@"ProxyAudioDevice_UID",@"virtual":@YES,@"ownerBundleID":@"",@"ownerChain":@[@31,@7]};
    check(DBNativeProxyIdentityMatches(endpoint,7,@[]),"proxy recognized through HAL plugin object when BundleID property unavailable");
    check(DBNativeProxyIdentityMatches(endpoint,7,@[@42]),"plugin device list confirms proxy membership");
    check(!DBNativeProxyIdentityMatches(endpoint,8,@[]),"unrelated plugin does not authenticate a matching UID");
    check(!DBNativeProxyIdentityMatches(@{@"id":@42,@"uid":@"other",@"virtual":@YES,@"ownerChain":@[@7]},7,@[@42]),"plugin membership cannot authenticate another UID");
    check(!DBNativeProxyIdentityMatches(@{@"id":@42,@"uid":@"ProxyAudioDevice_UID",@"virtual":@NO,@"ownerChain":@[@7]},7,@[@42]),"physical device cannot impersonate proxy");
    NSDictionary *audioScreen=@{@"identity":@"display:screen-uuid",@"name":@"DELL S2725QS",@"connected":@YES};
    NSDictionary *audioOutput=@{@"uid":@"screen-uuid",@"name":@"DELL S2725QS",@"alive":@YES,@"channels":@2,@"displayTransport":@YES,@"virtual":@NO};
    check([DBDisplayAudioOutputUID(audioScreen,@[audioScreen],@[audioOutput]) isEqual:@"screen-uuid"],"audio endpoint UUID uniquely identifies display capability");
    check(!DBDisplayAudioOutputUID(audioScreen,@[audioScreen],@[]),"DDC volume alone cannot enable audio bridging without an audio output");
    check(!DBDisplayAudioOutputUID(@{@"identity":@"display:silent",@"name":@"Silent Monitor"},@[audioScreen,@{@"name":@"Silent Monitor"}],@[audioOutput]),"non-audio display cannot borrow another monitor's audio endpoint");
    NSDictionary *sameName=@{@"identity":@"display:another",@"name":@"DELL S2725QS"};
    check(!DBDisplayAudioOutputUID(sameName,@[audioScreen,sameName],@[audioOutput]),"identical monitor names cannot falsely imply audio support");
    const uint8_t minimum[]={1,0x90,1,0,0},maximum[]={1,0x60,0xea,0,0};
    check([DBNativeBrightnessReport(0) isEqual:[NSData dataWithBytes:minimum length:5]]&&[DBNativeBrightnessReport(100) isEqual:[NSData dataWithBytes:maximum length:5]],"32-bit little-endian HID brightness boundaries");
    NSData*descriptor=DBNativeBrightnessDescriptor(256);const uint8_t input[]={0x09,0x10,0x81,0x02},feature[]={0x95,0x01,0xb1,0x42};
    check([descriptor rangeOfData:[NSData dataWithBytes:input length:sizeof input] options:0 range:NSMakeRange(0,descriptor.length)].location!=NSNotFound&&[descriptor rangeOfData:[NSData dataWithBytes:feature length:sizeof feature] options:0 range:NSMakeRange(0,descriptor.length)].location!=NSNotFound,"HID descriptor publishes both brightness input and feature");
    check(DBNativeEDIDValid(edid()),"full EDID extension checksum validation");NSMutableData*broken=[edid() mutableCopy];((uint8_t*)broken.mutableBytes)[140]^=1;check(!DBNativeEDIDValid(broken),"reject corrupt EDID extension");
    check(!DBNativeEDIDValid([edid() subdataWithRange:NSMakeRange(0,128)]),"reject missing EDID extension");
    check(DBNativeBrightnessDescriptor(256).length>40&&!DBNativeBrightnessDescriptor(129),"brightness descriptor includes 32-bit input, feature and bounded EDID report");
    for(NSNumber*p in @[@0,@25,@50,@75,@100])check(fabs([DBNativeBrightnessDecode(DBNativeBrightnessReport(p.doubleValue)) doubleValue]-p.doubleValue)<.01,"brightness report round trip");
    check(!DBNativeBrightnessReport(NAN)&&!DBNativeBrightnessReport(101),"invalid brightness cannot become a report");
    check(!DBNativeBrightnessDecode([NSData dataWithBytes:(uint8_t[]){1,0,0,0,0} length:5]),"reject raw brightness outside advertised range");
    NSDictionary*probe=DBProbeNativeBrightness(0,edid(),50,.1);check(probe[@"error"]&&![probe[@"nativeBrightnessVerified"] boolValue]&&[probe[@"ddcWrites"] intValue]==0,"no device identity means no virtual device or hardware mutation");
    puts("PASS: proxy routing/rollback, user-choice preservation, HID report and EDID validation");
}}
