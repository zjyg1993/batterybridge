#import "Display.h"
#import "DisplayDDC.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <CoreAudio/CoreAudio.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <unistd.h>
#import <math.h>

// IOAVService is an undocumented userspace IOKit SPI. Resolve at runtime so an
// OS without these symbols still launches and reports an unavailable channel.
typedef CFTypeRef (*BBAVCreate)(CFAllocatorRef,io_service_t);
typedef IOReturn (*BBAVI2C)(CFTypeRef,uint32_t,uint32_t,void*,uint32_t);
static BBAVCreate avCreate;static BBAVI2C avRead,avWrite;
static CFDictionaryRef (*displayInfo)(CGDirectDisplayID);
static int (*nativeBrightness)(CGDirectDisplayID,float*);
static void BBLoadDisplayAPIs(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        avCreate=(BBAVCreate)dlsym(RTLD_DEFAULT,"IOAVServiceCreateWithService");
        avRead=(BBAVI2C)dlsym(RTLD_DEFAULT,"IOAVServiceReadI2C");avWrite=(BBAVI2C)dlsym(RTLD_DEFAULT,"IOAVServiceWriteI2C");
        void*core=dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",RTLD_LAZY|RTLD_LOCAL);
        if(core)displayInfo=dlsym(core,"CoreDisplay_DisplayCreateInfoDictionary");
        void*services=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY|RTLD_LOCAL);
        if(services)nativeBrightness=dlsym(services,"DisplayServicesGetBrightness");
    });
}
#if defined(__arm64__)
static id BBRegistryProperty(io_registry_entry_t entry,NSString*key) {
    return CFBridgingRelease(IORegistryEntryCreateCFProperty(entry,(__bridge CFStringRef)key,kCFAllocatorDefault,0));
}
static NSDictionary *BBRegistryIdentity(io_registry_entry_t entry) {
    NSDictionary*attrs=BBRegistryProperty(entry,@"DisplayAttributes");NSDictionary*p=attrs[@"ProductAttributes"];
    NSMutableDictionary*d=[NSMutableDictionary new];
    NSDictionary*edid=BBEDIDIdentity(BBRegistryProperty(entry,@"IODisplayEDID"));if(edid)[d addEntriesFromDictionary:edid];
    if([p[@"ProductName"] isKindOfClass:NSString.class])d[@"name"]=p[@"ProductName"];
    if([p[@"SerialNumber"] isKindOfClass:NSNumber.class])d[@"serial"]=p[@"SerialNumber"];
    if([p[@"AlphanumericSerialNumber"] isKindOfClass:NSString.class])d[@"textSerial"]=p[@"AlphanumericSerialNumber"];
    io_string_t path;if(IORegistryEntryGetPath(entry,kIOServicePlane,path)==KERN_SUCCESS)d[@"location"]=@(path);
    return d;
}

#endif

@interface BBDDCChannel:NSObject
@property id avService;
@property io_service_t framebuffer;
@property NSDictionary*identity;
@property CFTimeInterval lastOperation;
- (NSDictionary*)read:(uint8_t)code;
- (BOOL)write:(uint8_t)code value:(uint16_t)value;
@end
@implementation BBDDCChannel
- (void)dealloc {if(_framebuffer)IOObjectRelease(_framebuffer);}
- (void)gap {CFTimeInterval remaining=.05-(CFAbsoluteTimeGetCurrent()-_lastOperation);if(remaining>0)usleep((useconds_t)(remaining*1000000));}
- (BOOL)exchange:(NSData*)packet reply:(NSMutableData*)reply {
    [self gap];BOOL ok=NO;
    if(_avService&&avWrite&&avRead){
        // IOAVService's offset carries the source address (0x51). The GET
        // checksum omits 0x51 on this transport; SET includes it (MonitorControl).
        NSMutableData*payload=[[packet subdataWithRange:NSMakeRange(1,packet.length-1)] mutableCopy];
        if(reply.length)((uint8_t*)payload.mutableBytes)[payload.length-1]^=0x51;
        ok=avWrite((__bridge CFTypeRef)_avService,0x37,0x51,payload.mutableBytes,(uint32_t)payload.length)==KERN_SUCCESS;
        if(ok&&reply.length){usleep(50000);ok=avRead((__bridge CFTypeRef)_avService,0x37,0,reply.mutableBytes,(uint32_t)reply.length)==KERN_SUCCESS;}
    }else if(_framebuffer){
        IOItemCount count=0;IOFBGetI2CInterfaceCount(_framebuffer,&count);
        for(IOItemCount i=0;i<count&&!ok;i++){
            io_service_t bus=0;if(IOFBCopyI2CInterfaceForBus(_framebuffer,i,&bus)!=KERN_SUCCESS)continue;
            IOI2CConnectRef connection=NULL;
            if(IOI2CInterfaceOpen(bus,0,&connection)==KERN_SUCCESS){
                IOI2CRequest request={0};request.sendAddress=0x6e;request.sendTransactionType=kIOI2CSimpleTransactionType;
                request.sendBuffer=(vm_address_t)packet.bytes;request.sendBytes=(uint32_t)packet.length;
                request.replyTransactionType=kIOI2CNoTransactionType;
                ok=IOI2CSendRequest(connection,0,&request)==KERN_SUCCESS&&request.result==KERN_SUCCESS;
                if(ok&&reply.length){
                    usleep(50000);IOI2CRequest response={0};response.replyAddress=0x6f;response.replyTransactionType=kIOI2CDDCciReplyTransactionType;
                    response.replyBuffer=(vm_address_t)reply.mutableBytes;response.replyBytes=(uint32_t)reply.length;
                    ok=IOI2CSendRequest(connection,0,&response)==KERN_SUCCESS&&response.result==KERN_SUCCESS&&response.replyBytes==reply.length;
                    if(ok)ok=BBDDCParseReply(reply,((const uint8_t*)packet.bytes)[3])!=nil;
                }
                IOI2CInterfaceClose(connection,0);
            }IOObjectRelease(bus);
        }
    }
    _lastOperation=CFAbsoluteTimeGetCurrent();return ok;
}
- (NSDictionary*)read:(uint8_t)code {
    for(int i=0;i<3;i++){
        NSMutableData*reply=[NSMutableData dataWithLength:11];
        if([self exchange:BBDDCRequest(code,nil) reply:reply]){NSDictionary*r=BBDDCParseReply(reply,code);if(r)return r;}
    }return nil;
}
- (BOOL)write:(uint8_t)code value:(uint16_t)value {return [self exchange:BBDDCRequest(code,@(value)) reply:nil];}
@end

static NSArray<BBDDCChannel*> *BBDisplayChannels(void) {
    NSMutableArray*channels=[NSMutableArray new];
#if defined(__arm64__)
    if(!avCreate||!avRead||!avWrite)return channels;
    // Walk the actual registry hierarchy. Metadata belongs to the containing
    // framebuffer, never to an arbitrary first monitor or a USB receiver.
    io_registry_entry_t root=IORegistryGetRootEntry(kIOMainPortDefault);io_iterator_t it=0;
    if(IORegistryEntryCreateIterator(root,kIOServicePlane,kIORegistryIterateRecursively,&it)==KERN_SUCCESS){
        io_registry_entry_t entry;NSDictionary*metadata=@{};
        while((entry=IOIteratorNext(it))){
            io_name_t name;IORegistryEntryGetName(entry,name);
            if(strstr(name,"AppleCLCD2")||strstr(name,"IOMobileFramebufferShim"))metadata=BBRegistryIdentity(entry);
            if(IOObjectConformsTo(entry,"DCPAVServiceProxy")&&[BBRegistryProperty(entry,@"Location") isEqual:@"External"]){
                CFTypeRef service=avCreate(kCFAllocatorDefault,entry);
                if(service){BBDDCChannel*c=[BBDDCChannel new];c.avService=CFBridgingRelease(service);c.identity=metadata;[channels addObject:c];}
                metadata=@{};
            }IOObjectRelease(entry);
        }IOObjectRelease(it);
    }IOObjectRelease(root);
#else
    io_iterator_t it=0;if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOFramebuffer"),&it)==KERN_SUCCESS){
        io_service_t entry;while((entry=IOIteratorNext(it))){
            NSDictionary*info=CFBridgingRelease(IODisplayCreateInfoDictionary(entry,kIODisplayOnlyPreferredName));
            if(info[@"DisplayVendorID"]&&info[@"DisplayProductID"]){
                BBDDCChannel*c=[BBDDCChannel new];IOObjectRetain(entry);c.framebuffer=entry;
                NSDictionary*names=info[@"DisplayProductName"];
                c.identity=@{@"vendor":info[@"DisplayVendorID"],@"product":info[@"DisplayProductID"],@"serial":info[@"DisplaySerialNumber"]?:@0,@"name":names.allValues.firstObject?:@"",@"location":info[@"IODisplayLocation"]?:@""};[channels addObject:c];
            }IOObjectRelease(entry);
        }IOObjectRelease(it);
    }
#endif
    return channels;
}

// Screen enumeration and AppKit stay on the main thread; all I2C runs on queue.
static NSArray<NSDictionary*> *BBConnectedScreens(void) {
    NSMutableArray*result=[NSMutableArray new];
    uint32_t count=0;if(CGGetOnlineDisplayList(0,NULL,&count)!=kCGErrorSuccess||!count)return result;
    NSMutableData*storage=[NSMutableData dataWithLength:count*sizeof(CGDirectDisplayID)];
    if(CGGetOnlineDisplayList(count,storage.mutableBytes,&count)!=kCGErrorSuccess)return result;
    CGDirectDisplayID*displays=storage.mutableBytes;
    for(uint32_t i=0;i<count;i++){
        CGDirectDisplayID display=displays[i];
        if(CGDisplayIsBuiltin(display)||CGDisplayVendorNumber(display)==0x610)continue;
        NSDictionary*info=displayInfo?CFBridgingRelease(displayInfo(display)):@{};
        CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);NSString*key=uuid?CFBridgingRelease(CFUUIDCreateString(NULL,uuid)):[NSString stringWithFormat:@"session-%u",display];if(uuid)CFRelease(uuid);
        NSDictionary*names=info[@"DisplayProductName"];NSString*model=names[@"en_US"]?:names.allValues.firstObject;
        NSDictionary *edid=BBEDIDIdentity(info[@"IODisplayEDID"]);
        if(!model.length)model=edid[@"name"];
        [result addObject:@{@"identity":[@"display:" stringByAppendingString:key],@"displayID":@(display),@"name":model?:@"外接显示器",@"vendor":@(CGDisplayVendorNumber(display)),@"product":@(CGDisplayModelNumber(display)),@"serial":@(CGDisplaySerialNumber(display)),@"location":info[@"IODisplayLocation"]?:@"",@"textSerial":edid[@"textSerial"]?:@""}];
    }return result;
}

static NSString *BBDefaultDisplayAudioName(void) {
    AudioObjectPropertyAddress a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    AudioDeviceID device=0;UInt32 size=sizeof device;if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&size,&device)!=noErr||!device)return nil;
    a.mSelector=kAudioDevicePropertyTransportType;UInt32 transport=0;size=sizeof transport;
    if(AudioObjectGetPropertyData(device,&a,0,NULL,&size,&transport)!=noErr||(transport!=kAudioDeviceTransportTypeHDMI&&transport!=kAudioDeviceTransportTypeDisplayPort))return nil;
    a.mSelector=kAudioDevicePropertyVolumeScalar;a.mScope=kAudioDevicePropertyScopeOutput;
    // A natively controllable output should keep the system's normal handling.
    for(UInt32 element=0;element<=2;element++){a.mElement=element;Boolean settable=false;if(AudioObjectIsPropertySettable(device,&a,&settable)==noErr&&settable)return nil;}
    a=(AudioObjectPropertyAddress){kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    CFStringRef name=NULL;size=sizeof name;if(AudioObjectGetPropertyData(device,&a,0,NULL,&size,&name)!=noErr)return nil;return CFBridgingRelease(name);
}

@interface BBDisplayController ()
@property(nonatomic,copy,readwrite) NSArray<NSDictionary*> *snapshot;
@property dispatch_queue_t queue;
@property NSMutableDictionary<NSString*,BBDDCChannel*>*channels;
@property NSMutableDictionary<NSString*,NSMutableDictionary*>*records;
@property NSMutableDictionary<NSString*,NSDictionary*>*pending;
@property NSMutableDictionary<NSString*,NSNumber*>*unmuted;
@property NSMutableDictionary<NSString*,NSMutableDictionary*>*controlErrors;
@property NSUserDefaults*preferences;
@property NSMutableDictionary<NSString*,NSNumber*>*mappingChoices;
@property NSTimer*discoveryTimer;
@property NSTimer*systemTimer;
@property BOOL scanning;
@property BOOL readOnly;
@property(nonatomic,readwrite) BOOL discoveryFinished;
@property(atomic) BOOL running;
@property BOOL needsRescan;
@property(atomic) NSUInteger generation;
@property CFMachPortRef eventTap;
@property CFTimeInterval lastEventTapAttempt;
@property CFRunLoopSourceRef eventSource;
@property NSMutableSet<NSNumber*>*consumedKeys;
@property CGDirectDisplayID nativeSource;
@property float nativeLevel;
@property NSPanel*hud;
@property NSTimer*hudTimer;
@end
static CGEventRef BBDisplayKeyEvent(CGEventTapProxy proxy,CGEventType type,CGEventRef event,void*context);
static void BBDisplayReconfigured(CGDirectDisplayID display,CGDisplayChangeSummaryFlags flags,void*context) {
    if(flags&kCGDisplayBeginConfigurationFlag)return;
    BBDisplayController*controller=(__bridge BBDisplayController*)context;
    dispatch_async(dispatch_get_main_queue(),^{[controller rescan];});
}
@implementation BBDisplayController
- (instancetype)init {return [self initWithDefaults:NSUserDefaults.standardUserDefaults];}
- (instancetype)initWithDefaults:(NSUserDefaults*)defaults {
    if((self=[super init])){BBLoadDisplayAPIs();_snapshot=@[];_queue=dispatch_queue_create("local.devicebridge.ddc",DISPATCH_QUEUE_SERIAL);_channels=[NSMutableDictionary new];_records=[NSMutableDictionary new];_pending=[NSMutableDictionary new];_unmuted=[NSMutableDictionary new];_controlErrors=[NSMutableDictionary new];_consumedKeys=[NSMutableSet new];_nativeLevel=-1;_preferences=defaults;
        id stored=[defaults objectForKey:@"MappedDisplays"];_mappingChoices=[stored isKindOfClass:NSDictionary.class]?[stored mutableCopy]:[NSMutableDictionary new];
    }return self;
}
- (BOOL)mappingEnabledForIdentity:(NSString*)identity {return [_mappingChoices[identity] boolValue];}
- (void)setMappingEnabled:(BOOL)enabled identity:(NSString*)identity {
    if(_readOnly||!identity.length)return;
    _mappingChoices[identity]=@(enabled);[_preferences setObject:[_mappingChoices copy] forKey:@"MappedDisplays"];
    // Change targeting immediately, including while a slow scan is finishing.
    NSMutableArray*rows=[NSMutableArray new];for(NSDictionary*r in _snapshot){NSMutableDictionary*copy=[r mutableCopy];if([r[@"identity"] isEqual:identity])copy[@"mappingEnabled"]=@(enabled);[rows addObject:copy];}self.snapshot=rows;
    dispatch_async(_queue,^{
        self.records[identity][@"mappingEnabled"]=@(enabled);
        if(!enabled)for(NSString*key in self.pending.allKeys.copy)if([self.pending[key][@"identity"] isEqual:identity]&&[self.pending[key][@"bridged"] boolValue])[self.pending removeObjectForKey:key];
        [self publish];
    });
}
- (NSArray*)connectedScreens {return BBConnectedScreens();}
- (NSArray*)displayChannels {return BBDisplayChannels();}
- (BOOL)accessibilityAuthorized {return AXIsProcessTrusted();}
- (BOOL)inputMonitoringAuthorized {return CGPreflightListenEventAccess();}
- (BOOL)hasActiveMediaKeyTap {return _eventTap&&CFMachPortIsValid(_eventTap)&&CGEventTapIsEnabled(_eventTap);}
- (BOOL)mediaKeysAuthorized {
    // Input Monitoring may already permit a working filtering tap. Its success
    // is stronger evidence than a separate Accessibility preflight alone.
    // Never count preflight for a listen-only tap as permission to filter keys.
    return [self accessibilityAuthorized]||[self hasActiveMediaKeyTap];
}
- (void)refreshMediaKeyAuthorization {if(_running&&!_readOnly)[self updateSystemControls];}
- (void)publish {[self publishForGeneration:self.generation];}
- (void)publishForGeneration:(NSUInteger)generation {
    NSMutableArray*copies=[NSMutableArray new];for(NSDictionary*r in _records.allValues)[copies addObject:[r copy]];
    NSArray*rows=[copies sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return [a[@"name"] compare:b[@"name"]];}];
    dispatch_async(dispatch_get_main_queue(),^{if(self.running&&generation==self.generation){
        NSMutableArray*published=[NSMutableArray new];for(NSDictionary*r in rows){NSMutableDictionary*copy=[r mutableCopy];copy[@"mappingEnabled"]=@([self mappingEnabledForIdentity:r[@"identity"]]);[published addObject:copy];}
        self.snapshot=published;self.discoveryFinished=YES;
    }});
}
- (void)startReadOnly {if(_running)return;_readOnly=YES;_running=YES;[self rescan];}
- (void)start {
    if(_running)return;_running=YES;
    CGDisplayRegisterReconfigurationCallback(BBDisplayReconfigured,(__bridge void*)self);
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:) name:NSWorkspaceScreensDidWakeNotification object:nil];
    self.discoveryTimer=[NSTimer timerWithTimeInterval:30 target:self selector:@selector(rescan) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_discoveryTimer forMode:NSRunLoopCommonModes];
    if(!_readOnly){self.systemTimer=[NSTimer timerWithTimeInterval:.25 target:self selector:@selector(updateSystemControls) userInfo:nil repeats:YES];[NSRunLoop.mainRunLoop addTimer:_systemTimer forMode:NSRunLoopCommonModes];}
    [self rescan];if(!_readOnly)[self updateSystemControls];
}
- (void)woke:(NSNotification*)n {_nativeSource=0;_nativeLevel=-1;[self rescan];}
- (void)stop {
    if(!_running)return;_running=NO;_generation++;[_discoveryTimer invalidate];[_systemTimer invalidate];[_hudTimer invalidate];[_hud orderOut:nil];
    if(!_readOnly){CGDisplayRemoveReconfigurationCallback(BBDisplayReconfigured,(__bridge void*)self);[NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];}
    if(_eventTap){CGEventTapEnable(_eventTap,false);CFRunLoopRemoveSource(CFRunLoopGetMain(),_eventSource,kCFRunLoopCommonModes);CFRelease(_eventSource);CFRelease(_eventTap);_eventSource=NULL;_eventTap=NULL;}
    dispatch_async(_queue,^{[self.pending removeAllObjects];[self.channels removeAllObjects];[self.records removeAllObjects];});self.snapshot=@[];
}
- (void)authorizeMediaKeys {
    [self refreshMediaKeyAuthorization];
    if(!self.mediaKeysAuthorized)AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString*)kAXTrustedCheckOptionPrompt:@YES});
    [self refreshMediaKeyAuthorization];
}
- (void)refreshControls {
    // Only an explicit refresh retries features whose writes were rejected.
    dispatch_async(_queue,^{[self.controlErrors removeAllObjects];});
    [self rescan];
}
- (void)rescan {
    if(!_running)return;
    // Keep visible identities during discovery. Generation invalidates writes;
    // presentation must not be emptied by the 30-second read-only refresh.
    _generation++;self.discoveryFinished=NO;
    NSMutableArray *busy=[NSMutableArray new];for(NSDictionary *row in _snapshot){NSMutableDictionary *copy=[row mutableCopy];copy[@"scanning"]=@YES;[busy addObject:copy];}self.snapshot=busy;
    if(_scanning){_needsRescan=YES;return;}_scanning=YES;
    NSUInteger generation=_generation;NSArray*screens=[self connectedScreens];NSDictionary*choices=[_mappingChoices copy];
    dispatch_async(_queue,^{
        [self.pending removeAllObjects];[self.channels removeAllObjects];
        // Keep known rows even if enumeration is transiently empty. Old control
        // capabilities are removed, so a retained row never writes stale data.
        for(NSMutableDictionary*r in self.records.allValues){r[@"connected"]=@NO;r[@"status"]=@"显示器未连接 · 等待重新发现";[r removeObjectForKey:@"brightness"];[r removeObjectForKey:@"volume"];}
        NSArray<BBDDCChannel*>*ports=[self displayChannels];NSMutableSet*used=[NSMutableSet new];
        for(NSDictionary*s in screens){
            NSMutableDictionary*r=[s mutableCopy];r[@"category"]=@"Display";r[@"connected"]=@YES;r[@"mappingEnabled"]=choices[s[@"identity"]]?:@NO;
            NSMutableArray*candidates=[NSMutableArray new];
            for(BBDDCChannel*c in ports)if(![used containsObject:c]&&BBDisplayIdentityMatches(s,c.identity))[candidates addObject:c];
            BBDDCChannel*channel=nil;
            if(candidates.count==1){
                // Reject a port that matches multiple active screens (identical
                // monitors without distinct serials). Never fall back to order.
                BBDDCChannel*c=candidates.firstObject;NSUInteger matches=0;for(NSDictionary*other in screens)if(BBDisplayIdentityMatches(other,c.identity))matches++;
                if(matches==1)channel=c;
            }else if(screens.count==1&&ports.count==1&&!candidates.count){
                NSDictionary *port=ports.firstObject.identity;
                // Anonymous single-channel fallback must never bypass known
                // serial or location conflicts.
                BOOL anonymous=![port[@"name"] length]&&!port[@"vendor"]&&!port[@"product"]&&![port[@"serial"] unsignedIntValue]&&![port[@"textSerial"] length];
                BOOL locationConflict=[s[@"location"] length]&&[port[@"location"] length]&&![s[@"location"] isEqual:port[@"location"]];
                if(anonymous&&!locationConflict)channel=ports.firstObject;
            }
            if(channel){
                [used addObject:channel];self.channels[s[@"identity"]]=channel;
                if([channel.identity[@"name"] length])r[@"name"]=channel.identity[@"name"];
                for(NSNumber*code in @[@0x10,@0x62]){NSDictionary*v=[channel read:code.unsignedCharValue];if(v)r[code.intValue==0x10?@"brightness":@"volume"]=v;}
                for(NSString *feature in self.controlErrors[s[@"identity"]])r[[feature stringByAppendingString:@"Error"]]=self.controlErrors[s[@"identity"]][feature];
                if(!r[@"brightness"])r[@"brightnessError"]=@"亮度不可用 · 未取得有效 DDC 读数";
                if(!r[@"volume"])r[@"volumeError"]=@"音量不可用 · 未取得有效 DDC 读数";
                if(r[@"brightness"]||r[@"volume"])r[@"updated"]=@(NSDate.date.timeIntervalSince1970);
                r[@"status"]=(r[@"brightness"]||r[@"volume"])?@"DDC 已读取":@"DDC 无响应 · 请开启显示器 DDC/CI，检查线缆或转接器";
                NSDictionary *errors=self.controlErrors[s[@"identity"]];
                if(errors.count)r[@"status"]=errors[@"volume"]?:errors[@"brightness"];
            }else r[@"status"]=@"未找到可唯一匹配的 DDC 通道 · 可尝试直连后刷新";
            self.records[s[@"identity"]]=r;
        }
        [self publishForGeneration:generation];
        dispatch_async(dispatch_get_main_queue(),^{
            self.scanning=NO;
            if(self.needsRescan&&self.running){self.needsRescan=NO;[self rescan];}
        });
    });
}
- (void)enqueuePercent:(double)percent code:(uint8_t)code identity:(NSString*)identity generation:(NSUInteger)generation bridged:(BOOL)bridged {
    NSString*key=[NSString stringWithFormat:@"%@/%u",identity,code];
    BOOL scheduled=self.pending[key]!=nil;self.pending[key]=@{@"percent":@(percent),@"generation":@(generation),@"bridged":@(bridged),@"identity":identity};
    if(scheduled)return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),self.queue,^{
        NSDictionary*request=self.pending[key];[self.pending removeObjectForKey:key];
        if(!request||!self.running||[request[@"generation"] unsignedIntegerValue]!=self.generation)return;
        if([request[@"bridged"] boolValue]&&![self.records[identity][@"mappingEnabled"] boolValue])return;
        [self applyPercent:[request[@"percent"] doubleValue] code:code identity:identity];
    });
}
- (void)setPercent:(double)percent code:(uint8_t)code identity:(NSString*)identity {
    if(_scanning||_readOnly||!_running||!isfinite(percent)||(code!=0x10&&code!=0x62)||!identity.length)return;
    percent=fmax(0,fmin(100,percent));NSUInteger generation=_generation;
    dispatch_async(_queue,^{if(self.running&&generation==self.generation)[self enqueuePercent:percent code:code identity:identity generation:generation bridged:NO];});
}
- (void)applyPercent:(double)percent code:(uint8_t)code identity:(NSString*)identity {
    if(_readOnly)return;NSUInteger generation=self.generation;
    BBDDCChannel*c=_channels[identity];NSMutableDictionary*r=_records[identity];NSString*feature=code==0x10?@"brightness":@"volume";
    NSDictionary*before=r[feature];if(!c||!BBDisplayControlAvailable(r,code)||![before[@"maximum"] unsignedIntValue])return;
    uint16_t value=(uint16_t)lround(percent*[before[@"maximum"] doubleValue]/100.0);
    BOOL sent=[c write:code value:value];NSDictionary*after=sent?[c read:code]:nil;
    BOOL verified=after&&abs([after[@"current"] intValue]-value)<=1;
    // Some panels apply SET asynchronously. Retry readback once, never send a
    // second write merely because the first read returned the old value.
    if(sent&&after&&!verified){usleep(100000);after=[c read:code];verified=after&&abs([after[@"current"] intValue]-value)<=1;}
    if(verified){
        r[feature]=after;r[@"status"]=@"DDC 调节已确认";r[@"updated"]=@(NSDate.date.timeIntervalSince1970);
        NSString *name=r[@"name"];double confirmed=[after[@"percent"] doubleValue];
        dispatch_async(dispatch_get_main_queue(),^{if(self.running&&self.generation==generation)[self showHUD:name feature:feature percent:confirmed];});
    }else{
        NSString *reason=after?@"显示器未应用目标值 · 请检查 HDR / 显示模式，刷新后重试":@"DDC 写入或回读失败 · 请刷新后重试";
        if(!self.controlErrors[identity])self.controlErrors[identity]=[NSMutableDictionary new];
        self.controlErrors[identity][feature]=reason;r[[feature stringByAppendingString:@"Error"]]=reason;
        [r removeObjectForKey:feature];r[@"status"]=reason;
        if(code==0x62)[self.unmuted removeObjectForKey:identity];
    }
    [self publishForGeneration:generation];
}
- (void)showHUD:(NSString*)name feature:(NSString*)feature percent:(double)percent {
    if(!_hud){self.hud=[[NSPanel alloc]initWithContentRect:NSMakeRect(0,0,310,64) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];_hud.level=NSStatusWindowLevel;_hud.ignoresMouseEvents=YES;_hud.backgroundColor=NSColor.windowBackgroundColor;_hud.hasShadow=YES;_hud.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;}
    for(NSView*v in _hud.contentView.subviews.copy)[v removeFromSuperview];
    NSTextField*l=[NSTextField labelWithString:[NSString stringWithFormat:@"%@\n%@ %.0f%%",name,[feature isEqual:@"brightness"]?@"亮度":@"音量",percent]];l.frame=NSMakeRect(16,10,278,44);l.alignment=NSTextAlignmentCenter;[_hud.contentView addSubview:l];
    NSRect area=NSScreen.mainScreen.visibleFrame;[_hud setFrameOrigin:NSMakePoint(NSMidX(area)-155,NSMinY(area)+80)];[_hud orderFrontRegardless];[_hudTimer invalidate];
    __weak BBDisplayController*weak=self;self.hudTimer=[NSTimer scheduledTimerWithTimeInterval:1.2 repeats:NO block:^(NSTimer*t){[weak.hud orderOut:nil];}];
}
- (void)updateSystemControls {
    if(!_running)return;
    if(_eventTap&&!CFMachPortIsValid(_eventTap)){
        CFRunLoopRemoveSource(CFRunLoopGetMain(),_eventSource,kCFRunLoopCommonModes);CFRelease(_eventSource);CFRelease(_eventTap);_eventSource=NULL;_eventTap=NULL;
    }
    CFTimeInterval now=CFAbsoluteTimeGetCurrent();
    if(!_eventTap&&([self accessibilityAuthorized]||[self inputMonitoringAuthorized])&&now-_lastEventTapAttempt>=2){
        _lastEventTapAttempt=now;
        _eventTap=CGEventTapCreate(kCGSessionEventTap,kCGHeadInsertEventTap,kCGEventTapOptionDefault,CGEventMaskBit(NX_SYSDEFINED),BBDisplayKeyEvent,(__bridge void*)self);
        if(_eventTap){_eventSource=CFMachPortCreateRunLoopSource(NULL,_eventTap,0);CFRunLoopAddSource(CFRunLoopGetMain(),_eventSource,kCFRunLoopCommonModes);CGEventTapEnable(_eventTap,true);}
    }
    // Follow changes from an EXISTING native built-in slider. Establish a
    // baseline at startup/wake without overwriting the external monitor.
    CGDirectDisplayID source=0;float level=-1;
    if(nativeBrightness)for(NSScreen*s in NSScreen.screens){CGDirectDisplayID d=[s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];if(CGDisplayIsBuiltin(d)&&nativeBrightness(d,&level)==0&&isfinite(level)&&level>=0&&level<=1){source=d;break;}}
    if(source&&source==_nativeSource&&_nativeLevel>=0&&fabsf(level-_nativeLevel)>.002){for(NSDictionary*r in _snapshot)if(!_scanning&&BBDisplayControlAvailable(r,0x10)&&[self mappingEnabledForIdentity:r[@"identity"]]){
        NSString*identity=r[@"identity"];NSUInteger generation=self.generation;
        dispatch_async(_queue,^{if(self.running&&generation==self.generation&&[self.records[identity][@"mappingEnabled"] boolValue])[self enqueuePercent:level*100 code:0x10 identity:identity generation:generation bridged:YES];});
    }}
    _nativeSource=source;_nativeLevel=level;
}
- (NSDictionary*)targetForKey:(int)key {
    if(_scanning)return nil;
    if(key==0||key==1||key==7){
        // Read output routing at the moment of the key event, not a stale timer.
        NSString*name=BBDisplayNameKey(BBDefaultDisplayAudioName());NSMutableArray*matches=[NSMutableArray new];
        for(NSDictionary*r in _snapshot)if(BBDisplayControlAvailable(r,0x62)&&[self mappingEnabledForIdentity:r[@"identity"]]&&[BBDisplayNameKey(r[@"name"]) isEqual:name])[matches addObject:r];return matches.count==1?matches.firstObject:nil;
    }
    if(key!=2&&key!=3)return nil;
    // On a MacBook the OS handles the built-in brightness; synchronization above
    // follows it. On a desktop use the screen under the pointer, then main.
    if(_nativeSource)return nil;
    NSPoint mouse=NSEvent.mouseLocation;CGDirectDisplayID selected=CGMainDisplayID();
    for(NSScreen*s in NSScreen.screens)if(NSPointInRect(mouse,s.frame)){selected=[s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];break;}
    for(NSDictionary*r in _snapshot)if([r[@"displayID"] unsignedIntValue]==selected&&BBDisplayControlAvailable(r,0x10)&&[self mappingEnabledForIdentity:r[@"identity"]])return r;return nil;
}
- (void)adjustKey:(int)key record:(NSDictionary*)record {
    NSString*identity=record[@"identity"];uint8_t code=(key==2||key==3)?0x10:0x62;NSUInteger generation=_generation;
    dispatch_async(_queue,^{
        if(!self.running||generation!=self.generation)return;
        NSDictionary*r=self.records[identity];NSString*feature=code==0x10?@"brightness":@"volume";
        if(!BBDisplayControlAvailable(r,code)||![r[@"mappingEnabled"] boolValue])return;NSString*pendingKey=[NSString stringWithFormat:@"%@/%u",identity,code];
        NSNumber*pendingValue=self.pending[pendingKey][@"percent"];
        double current=pendingValue?pendingValue.doubleValue:[r[feature][@"percent"] doubleValue],next=current;
        if(key==7){if(current>0){self.unmuted[identity]=@(current);next=0;}else{NSNumber*restore=self.unmuted[identity];if(!restore)return;next=restore.doubleValue;}}
        else next=fmax(0,fmin(100,current+((key==0||key==2)?6.25:-6.25)));
        [self enqueuePercent:next code:code identity:identity generation:generation bridged:YES];
    });
}
@end
static CGEventRef BBDisplayKeyEvent(CGEventTapProxy proxy,CGEventType type,CGEventRef event,void*context) {
    BBDisplayController*c=(__bridge BBDisplayController*)context;
    if(type==kCGEventTapDisabledByTimeout||type==kCGEventTapDisabledByUserInput){if(c.running&&c.eventTap)CGEventTapEnable(c.eventTap,true);return event;}
    if(type!=NX_SYSDEFINED)return event;NSEvent*e=[NSEvent eventWithCGEvent:event];if(e.subtype!=8)return event;
    int key=(int)((e.data1>>16)&0xffff),state=(int)((e.data1>>8)&0xff);
    if(state==0x0b){if([c.consumedKeys containsObject:@(key)]){[c.consumedKeys removeObject:@(key)];return NULL;}return event;}
    if(state!=0x0a)return event;NSDictionary*r=[c targetForKey:key];if(!r)return event;
    [c.consumedKeys addObject:@(key)];[c adjustKey:key record:r];return NULL;
}

static NSTextField *BBDisplayLabel(NSString*text,NSRect frame,CGFloat size,NSColor*color) {
    NSTextField*l=[NSTextField labelWithString:text];l.frame=frame;l.font=[NSFont systemFontOfSize:size];l.textColor=color;l.lineBreakMode=NSLineBreakByTruncatingTail;return l;
}
@implementation BBDisplayRow
- (instancetype)initWithFrame:(NSRect)frame record:(NSDictionary*)record {
    if((self=[super initWithFrame:frame])){
        _record=record;CGFloat w=frame.size.width;BOOL connected=![record[@"connected"] isEqual:@NO];
        NSImageView*icon=[[NSImageView alloc]initWithFrame:NSMakeRect(16,28,40,40)];icon.image=[NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"显示器"];icon.symbolConfiguration=[NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightRegular];icon.contentTintColor=connected?NSColor.secondaryLabelColor:NSColor.tertiaryLabelColor;[self addSubview:icon];
        NSTextField*name=BBDisplayLabel(record[@"name"]?:@"外接显示器",NSMakeRect(72,56,MAX(1,w-418),20),13,NSColor.labelColor);name.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];name.toolTip=name.stringValue;[self addSubview:name];
        [self addSubview:BBDisplayLabel(!connected?@"未连接":((record[@"brightness"]||record[@"volume"])?@"已连接":@"显示器在线 · 等待读取"),NSMakeRect(72,35,MAX(1,w-418),17),11,NSColor.secondaryLabelColor)];
        NSString*time=@"尚未读取";if([record[@"updated"] doubleValue]>0)time=[NSString stringWithFormat:@"%@ %@",connected?@"更新于":@"上次读取",[NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[record[@"updated"] doubleValue]] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle]];
        [self addSubview:BBDisplayLabel(time,NSMakeRect(72,16,MAX(1,w-418),15),10,NSColor.tertiaryLabelColor)];
        for(NSUInteger i=0;i<2;i++){
            NSString*f=i?@"volume":@"brightness";NSDictionary*v=record[f];CGFloat y=i?24:52;
            NSImageView*symbol=[[NSImageView alloc]initWithFrame:NSMakeRect(w-336,y+2,16,16)];symbol.image=[NSImage imageWithSystemSymbolName:i?@"speaker.wave.2":@"sun.max" accessibilityDescription:i?@"音量":@"亮度"];symbol.contentTintColor=NSColor.secondaryLabelColor;[self addSubview:symbol];
            NSSlider*slider=[NSSlider sliderWithValue:[v[@"percent"] doubleValue] minValue:0 maxValue:100 target:self action:i?@selector(volumeChanged:):@selector(brightnessChanged:)];slider.frame=NSMakeRect(w-316,y,76,20);slider.controlSize=NSControlSizeSmall;slider.enabled=BBDisplayControlAvailable(record,i?0x62:0x10);slider.continuous=NO;slider.accessibilityLabel=[NSString stringWithFormat:@"%@%@",name.stringValue,i?@"音量":@"亮度"];slider.toolTip=slider.enabled?slider.accessibilityLabel:(record[[f stringByAppendingString:@"Error"]]?:([record[@"scanning"] boolValue]?@"正在探测显示器，请稍候":@"此控制不可用 · 请启用 DDC/CI 后刷新"));[self addSubview:slider];
            if(i)_volumeSlider=slider;else _brightnessSlider=slider;
            NSTextField*value=BBDisplayLabel(slider.enabled?[NSString stringWithFormat:@"%.0f%%",[v[@"percent"] doubleValue]]:@"—",NSMakeRect(w-238,y,34,20),11,NSColor.labelColor);value.alignment=NSTextAlignmentRight;value.font=[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];[self addSubview:value];
        }
        NSTextField*mapLabel=BBDisplayLabel(@"媒体键与亮度同步",NSMakeRect(w-190,60,134,15),10,NSColor.secondaryLabelColor);mapLabel.alignment=NSTextAlignmentCenter;[self addSubview:mapLabel];
        self.mappingSwitch=[[NSSwitch alloc]initWithFrame:NSMakeRect(w-144,29,44,24)];_mappingSwitch.controlSize=NSControlSizeSmall;_mappingSwitch.target=self;_mappingSwitch.action=@selector(mappingChanged:);_mappingSwitch.state=[record[@"mappingEnabled"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;_mappingSwitch.enabled=[record[@"identity"] length]>0&&([record[@"mappingEnabled"] boolValue]||BBDisplayControlAvailable(record,0x10)||BBDisplayControlAvailable(record,0x62));_mappingSwitch.accessibilityLabel=[NSString stringWithFormat:@"%@的媒体键与亮度同步",name.stringValue];_mappingSwitch.toolTip=@"开启后将系统媒体键和已有的内建屏幕亮度变化转发到此显示器；关闭不影响手动调节。原生控制中心滑块尚未接入。";[self addSubview:_mappingSwitch];
        self.refreshButton=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"刷新显示器"] target:self action:@selector(refreshDisplay:)];_refreshButton.frame=NSMakeRect(w-50,33,30,28);_refreshButton.bezelStyle=NSBezelStyleRounded;_refreshButton.toolTip=@"重新发现显示器并读取亮度、音量";_refreshButton.accessibilityIdentifier=@"DisplayRefresh";[self addSubview:_refreshButton];
        self.toolTip=record[@"status"];
    }return self;
}
// Display discovery owns these rows, including retained disconnected rows.
// Do not inherit an injected context menu from a parent view.
- (NSMenu*)menuForEvent:(NSEvent*)event {return nil;}
- (void)mappingChanged:(NSSwitch*)sender {[_controller setMappingEnabled:sender.state==NSControlStateValueOn identity:_record[@"identity"]];}
- (void)refreshDisplay:(id)sender {[_controller refreshControls];}
- (void)brightnessChanged:(NSSlider*)sender {[_controller setPercent:sender.doubleValue code:0x10 identity:_record[@"identity"]];}
- (void)volumeChanged:(NSSlider*)sender {[_controller setPercent:sender.doubleValue code:0x62 identity:_record[@"identity"]];}
- (void)drawRect:(NSRect)dirty {if(_showsSeparator){[[NSColor separatorColor] setFill];NSRectFill(NSMakeRect(72,0,MAX(0,self.bounds.size.width-88),.5));}}
@end
