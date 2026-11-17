#import "NativeBrightnessBridge.h"
#import "DisplayDDC.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/hid/IOHIDManager.h>
#import <dlfcn.h>
#import <math.h>

BOOL DBBrightnessEDIDValid(NSData *data){
    if(data.length<128||data.length%128||data.length>32768||!BBEDIDIdentity(data))return NO;
    const uint8_t *p=data.bytes;if(data.length!=128*((NSUInteger)p[126]+1))return NO;
    for(NSUInteger block=0;block<data.length;block+=128){uint8_t sum=0;for(NSUInteger i=0;i<128;i++)sum+=p[block+i];if(sum)return NO;}return YES;
}
static NSRange DBContainerRange(NSData *data){
    const uint8_t *p=data.bytes;
    for(NSUInteger base=128;base+128<=data.length;base+=128){
        if(p[base]!=0x70)continue;NSUInteger end=base+5+p[base+2];if(end>=base+127)continue;
        uint8_t sum=0;for(NSUInteger i=base+1;i<=end;i++)sum+=p[i];if(sum)continue;
        for(NSUInteger cursor=base+5;cursor+3<=end;){NSUInteger n=p[cursor+2];if(cursor+3+n>end)break;
            if(p[cursor]==0x29&&p[cursor+1]==0&&n==16)return NSMakeRange(cursor+3,16);cursor+=3+n;
        }
    }return NSMakeRange(NSNotFound,0);
}
NSData *DBBrightnessContainer(NSData *edid){if(!DBBrightnessEDIDValid(edid))return nil;NSRange r=DBContainerRange(edid);return r.location==NSNotFound?nil:[edid subdataWithRange:r];}
static void DBChecksum(uint8_t *p,NSUInteger start,NSUInteger end){uint8_t sum=0;for(NSUInteger i=start;i<end;i++)sum+=p[i];p[end]=(uint8_t)-sum;}
NSData *DBBrightnessEDIDWithContainer(NSData *edid,NSData *container){
    if(!DBBrightnessEDIDValid(edid)||container.length!=16)return nil;
    NSData *existing=DBBrightnessContainer(edid);
    // An existing association may belong to an Apple display or another app.
    // Do not replace it. A previous DeviceBridge association is adopted as-is.
    if(existing)return [existing isEqual:container]?edid:nil;
    const uint8_t *original=edid.bytes;if(original[126]>=254)return nil;
    NSMutableData *result=[edid mutableCopy];[result increaseLengthBy:128];uint8_t *p=result.mutableBytes;NSUInteger b=edid.length;
    p[b]=0x70;p[b+1]=0x20;p[b+2]=19;p[b+3]=0;p[b+4]=0;
    p[b+5]=0x29;p[b+6]=0;p[b+7]=16;memcpy(p+b+8,container.bytes,16);
    DBChecksum(p,b+1,b+24);DBChecksum(p,b,b+127);p[126]++;DBChecksum(p,0,127);
    return DBBrightnessEDIDValid(result)?result:nil;
}
NSData *DBBrightnessHIDDescriptor(void){
    // USB HID Monitor Control / VESA brightness. Logical range 0..60000
    // centi-nits, physical 0..600 cd/m²; 32-bit feature payload, report ID 1.
    const uint8_t bytes[]={0x05,0x80,0x09,0x01,0xa1,0x01,0x85,1,0x05,0x82,0x09,0x10,
        0x15,0,0x27,0x60,0xea,0,0,0x35,0,0x46,0x58,0x02,0x67,0xe1,0,0,1,
        0x55,0,0x75,0x20,0x95,1,0xb1,0x02,0x65,0,0xc0};
    return [NSData dataWithBytes:bytes length:sizeof bytes];
}
NSNumber *DBBrightnessDecodeFeature(NSData *report){
    if(report.length!=4&&report.length!=5)return nil;const uint8_t *p=report.bytes;
    if(report.length==5){if(*p!=1)return nil;p++;}
    uint32_t raw=(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
    return raw<=60000?@(raw/600.0):nil;
}
NSDictionary *DBBrightnessSystemCapability(uint32_t displayID){
    static void *framework;static bool(*canChange)(uint32_t);static int(*read)(uint32_t,float*);static dispatch_once_t once;
    dispatch_once(&once,^{framework=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY|RTLD_LOCAL);if(framework){canChange=dlsym(framework,"DisplayServicesCanChangeBrightness");read=dlsym(framework,"DisplayServicesGetBrightness");}});
    float value=0;int status=read?read(displayID,&value):-1;
    return @{@"available":@(canChange&&canChange(displayID)),@"readStatus":@(status),@"level":status==0&&isfinite(value)?@(value):NSNull.null};
}
NSData *DBBrightnessCopyEDID(id avService){
    IOReturn(*copy)(CFTypeRef,CFDataRef*)=dlsym(RTLD_DEFAULT,"IOAVServiceCopyEDID");CFDataRef data=NULL;
    if(!avService||!copy)return nil;IOReturn result=copy((__bridge CFTypeRef)avService,&data);
    NSData *edid=CFBridgingRelease(data);return result==kIOReturnSuccess&&DBBrightnessEDIDValid(edid)?edid:nil;
}
IOReturn DBBrightnessSetEDID(id avService,NSData *edid){
    IOReturn(*set)(CFTypeRef,uint32_t,CFDataRef)=dlsym(RTLD_DEFAULT,"IOAVServiceSetVirtualEDIDMode");
    if(!avService||!set)return kIOReturnUnsupported;if(edid&&!DBBrightnessEDIDValid(edid))return kIOReturnBadArgument;
    return set((__bridge CFTypeRef)avService,edid?1:0,(__bridge CFDataRef)edid);
}
BOOL DBBrightnessHIDEntitled(void){
    void *security=dlopen("/System/Library/Frameworks/Security.framework/Security",RTLD_LAZY|RTLD_LOCAL);if(!security)return NO;
    CFTypeRef(*taskCreate)(CFAllocatorRef)=dlsym(security,"SecTaskCreateFromSelf");
    CFTypeRef(*entitlement)(CFTypeRef,CFStringRef,CFErrorRef*)=dlsym(security,"SecTaskCopyValueForEntitlement");
    CFTypeRef task=taskCreate?taskCreate(kCFAllocatorDefault):NULL;
    CFTypeRef value=task&&entitlement?entitlement(task,CFSTR("com.apple.developer.hid.virtual.device"),NULL):NULL;
    BOOL allowed=value&&CFGetTypeID(value)==CFBooleanGetTypeID()&&CFBooleanGetValue(value);
    if(value)CFRelease(value);if(task)CFRelease(task);dlclose(security);return allowed;
}
@interface DBHIDBrightnessEndpoint ()
@property id device;
@property uint32_t value;
@property(copy) void(^handler)(double);
@end
@implementation DBHIDBrightnessEndpoint
- (BOOL)startWithContainer:(NSString*)uuid name:(NSString*)name percent:(double)percent handler:(void(^)(double))handler error:(NSError**)error {
    if(_device)return YES;
    if(!DBBrightnessHIDEntitled()){if(error)*error=[NSError errorWithDomain:@"DeviceBridge.NativeBrightness" code:3 userInfo:@{NSLocalizedDescriptionKey:@"当前签名未包含有效虚拟 HID entitlement，原生亮度未启用；未修改屏幕 EDID。需要具备该能力的 Apple 签名及描述文件构建。"}];return NO;}
    CFTypeRef(*create)(CFAllocatorRef,CFDictionaryRef,IOOptionBits)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceCreateWithProperties");
    void(*get)(CFTypeRef,IOReturn(^)(IOHIDReportType,uint32_t,uint8_t*,CFIndex*))=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceRegisterGetReportBlock");
    void(*set)(CFTypeRef,IOReturn(^)(IOHIDReportType,uint32_t,const uint8_t*,CFIndex))=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceRegisterSetReportBlock");
    void(*queue)(CFTypeRef,dispatch_queue_t)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceSetDispatchQueue");
    void(*activate)(CFTypeRef)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceActivate");
    void(*cancelHandler)(CFTypeRef,dispatch_block_t)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceSetCancelHandler");
    void(*cancel)(CFTypeRef)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceCancel");
    NSString *reason=nil;
    if(!create||!get||!set||!queue||!activate||!cancelHandler||!cancel)reason=@"系统缺少虚拟亮度 HID 接口";
    else if(![[NSUUID alloc]initWithUUIDString:uuid]||!isfinite(percent)||percent<0||percent>100)reason=@"虚拟亮度参数无效";
    if(reason){if(error)*error=[NSError errorWithDomain:@"DeviceBridge.NativeBrightness" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];return NO;}
    NSDictionary *properties=@{@"ReportDescriptor":DBBrightnessHIDDescriptor(),@"VendorID":@0xffff,@"ProductID":@0xdb03,@"Product":[@"DeviceBridge Brightness — " stringByAppendingString:name?:@"Display"],@"Manufacturer":@"DeviceBridge",@"Transport":@"USB",@"kUSBContainerID":uuid};
    CFTypeRef device=create(kCFAllocatorDefault,(__bridge CFDictionaryRef)properties,0);
    if(!device){if(error)*error=[NSError errorWithDomain:@"DeviceBridge.NativeBrightness" code:2 userInfo:@{NSLocalizedDescriptionKey:@"虚拟亮度设备创建被系统拒绝；请检查 HID entitlement、签名和设备控制权限。未修改屏幕 EDID。"}];return NO;}
    self.device=CFBridgingRelease(device);self.handler=handler;[self setConfirmedPercent:percent];__weak DBHIDBrightnessEndpoint *weak=self;
    get(device,^IOReturn(IOHIDReportType type,uint32_t reportID,uint8_t *buffer,CFIndex *length){
        DBHIDBrightnessEndpoint *strong=weak;if(!strong||type!=kIOHIDReportTypeFeature||reportID!=1||!length||*length<4)return kIOReturnUnsupported;
        uint32_t raw=strong.value;for(int i=0;i<4;i++)buffer[i]=(raw>>(8*i))&255;*length=4;return kIOReturnSuccess;
    });
    set(device,^IOReturn(IOHIDReportType type,uint32_t reportID,const uint8_t *buffer,CFIndex length){
        if(type!=kIOHIDReportTypeFeature||reportID!=1||length<0)return kIOReturnUnsupported;
        NSNumber *level=DBBrightnessDecodeFeature([NSData dataWithBytes:buffer length:(NSUInteger)length]);if(!level)return kIOReturnBadArgument;
        DBHIDBrightnessEndpoint *strong=weak;if(!strong)return kIOReturnNotReady;
        if(fabs(level.doubleValue-strong.value/600.0)>.05&&strong.handler)strong.handler(level.doubleValue);return kIOReturnSuccess;
    });
    cancelHandler(device,^{});queue(device,dispatch_get_main_queue());activate(device);return YES;
}
- (void)setConfirmedPercent:(double)percent {if(isfinite(percent))_value=(uint32_t)llround(fmax(0,fmin(100,percent))*600);}
- (void)stop {if(!_device)return;void(*cancel)(CFTypeRef)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceCancel");if(cancel)cancel((__bridge CFTypeRef)_device);_device=nil;_handler=nil;}
- (void)dealloc {[self stop];}
@end

@interface DBNativeBrightnessBinding ()
@property NSString *identity;
@property NSString *name;
@property uint32_t displayID;
@property NSUserDefaults *preferences;
@property dispatch_queue_t queue;
@property id<DBBrightnessEndpoint> endpoint;
@property id<DBBrightnessTransport> transport;
@property NSData *originalEDID;
@property NSData *container;
@property NSString *containerUUID;
@property NSData *patchedEDID;
@property(nonatomic,readwrite) NSDictionary *state;
@property BOOL started;
@property BOOL touched;
@property BOOL ready;
@property BOOL stopping;
@property BOOL stopped;
@property BOOL retried;
@property NSUInteger verifyToken;
@property NSUInteger verifyAttempts;
@property NSNumber *pendingPercent;
@property NSString *failure;
@property NSMutableArray *stopCallbacks;
@end
@implementation DBNativeBrightnessBinding
- (instancetype)initWithIdentity:(NSString*)identity displayID:(uint32_t)displayID name:(NSString*)name preferences:(NSUserDefaults*)preferences queue:(dispatch_queue_t)queue endpoint:(id<DBBrightnessEndpoint>)endpoint {
    if((self=[super init])){_identity=[identity copy];_displayID=displayID;_name=[name copy];_preferences=preferences;_queue=queue;_endpoint=endpoint;_state=@{@"phase":@"idle",@"available":@NO};_stopCallbacks=[NSMutableArray new];}return self;
}
- (void)emit:(NSString*)phase reason:(NSString*)reason {
    NSMutableDictionary *state=[_state mutableCopy];state[@"phase"]=phase;state[@"available"]=@(_ready);state[@"reason"]=reason?:@"";
    state[@"edidApplied"]=@(_touched);state[@"containerID"]=_containerUUID?:@"";state[@"displayID"]=@(_displayID);
    self.state=state;if(_onState)_onState(state);
}
- (NSDictionary*)systemCapability {return DBBrightnessSystemCapability(_displayID);}
- (NSTimeInterval)verificationDelay {return 2;}
- (BOOL)saveJournal {
    NSMutableDictionary *journal=[[_preferences objectForKey:@"NativeBrightnessJournal"] mutableCopy]?:[NSMutableDictionary new];
    journal[_identity]=@{@"originalEDID":_originalEDID,@"containerID":_containerUUID};[_preferences setObject:journal forKey:@"NativeBrightnessJournal"];
    return [_preferences synchronize];
}
- (void)clearJournal {
    NSMutableDictionary *journal=[[_preferences objectForKey:@"NativeBrightnessJournal"] mutableCopy]?:[NSMutableDictionary new];
    // A later session must not have its recovery checkpoint removed by an old one.
    if([journal[_identity][@"containerID"] isEqual:_containerUUID]){[journal removeObjectForKey:_identity];[_preferences setObject:journal forKey:@"NativeBrightnessJournal"];[_preferences synchronize];}
}
- (void)startWithEDID:(NSData*)edid transport:(id<DBBrightnessTransport>)transport percent:(double)percent {
    if(_started||_stopping||_stopped)return;_transport=transport;
    if(!DBBrightnessEDIDValid(edid)||!isfinite(percent)||percent<0||percent>100){[self emit:@"failed" reason:@"缺少完整有效 EDID 或硬件亮度读数"];return;}
    NSDictionary *saved=[_preferences objectForKey:@"NativeBrightnessContainers"];
    NSDictionary *journal=[_preferences objectForKey:@"NativeBrightnessJournal"][_identity];
    NSUUID *uuid=[[NSUUID alloc]initWithUUIDString:journal[@"containerID"]?:saved[_identity]]?:NSUUID.UUID;
    uuid_t bytes;[uuid getUUIDBytes:bytes];_container=[NSData dataWithBytes:bytes length:16];_containerUUID=uuid.UUIDString;
    NSData *existing=DBBrightnessContainer(edid);
    if(existing&&![existing isEqual:_container]){[self emit:@"failed" reason:@"屏幕已有其他原生亮度绑定，未覆盖"];return;}
    if(existing){
        NSData *original=journal[@"originalEDID"];
        if(!DBBrightnessEDIDValid(original)||!BBDisplayIdentityMatches(BBEDIDIdentity(edid),BBEDIDIdentity(original))){[self emit:@"failed" reason:@"已有绑定缺少有效恢复记录，未覆盖"];return;}
        _originalEDID=original;
    }else _originalEDID=[edid copy];
    _touched=existing!=nil;
    _patchedEDID=DBBrightnessEDIDWithContainer(edid,_container);
    if(!_patchedEDID){[self emit:@"failed" reason:@"无法安全加入屏幕 ContainerID"];return;}
    NSMutableDictionary *containers=[saved mutableCopy]?:[NSMutableDictionary new];containers[_identity]=_containerUUID;[_preferences setObject:containers forKey:@"NativeBrightnessContainers"];
    __weak DBNativeBrightnessBinding *weak=self;NSError *error=nil;
    BOOL created=[_endpoint startWithContainer:_containerUUID name:_name percent:percent handler:^(double value){
        DBNativeBrightnessBinding *strong=weak;if(!strong||strong.stopping||strong.stopped)return;
        NSMutableDictionary *state=[strong.state mutableCopy];state[@"lastSystemRequest"]=@(value);strong.state=state;
        if(!strong.ready){strong.pendingPercent=@(value);return;}
        if(strong.onPercent)strong.onPercent(value);
    } error:&error];
    if(!created){NSMutableDictionary *state=[_state mutableCopy];state[@"failureStage"]=@"hid";_state=state;[self failAndRestore:error.localizedDescription?:@"系统拒绝创建虚拟亮度设备"];return;}
    if(![self saveJournal]){[_endpoint stop];[self emit:@"failed" reason:@"无法保存屏幕恢复记录，未修改 EDID"];return;}
    _started=YES;_touched=existing!=nil;
    if(existing){[self emit:@"binding" reason:@"接管上次保存的屏幕绑定"];[self scheduleVerification];}
    else [self applyEDID];
}
- (void)applyEDID {
    if(_stopping||_stopped)return;_touched=YES;[self emit:@"binding" reason:@"正在绑定系统亮度；屏幕可能短暂黑屏"];
    id<DBBrightnessTransport> transport=_transport;NSData *patched=_patchedEDID;
    dispatch_async(_queue,^{IOReturn result=[transport setBrightnessEDID:patched];
        dispatch_async(dispatch_get_main_queue(),^{if(self.stopping||self.stopped)return;
            if(result!=kIOReturnSuccess){[self failAndRestore:[NSString stringWithFormat:@"EDID 绑定失败（0x%08x）",result]];return;}
            [self scheduleVerification];
        });
    });
}
- (void)scheduleVerification {
    NSUInteger token=++_verifyToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)([self verificationDelay]*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        if(self.stopping||self.stopped||token!=self.verifyToken)return;
        id<DBBrightnessTransport> transport=self.transport;
        dispatch_async(self.queue,^{NSData *live=[transport brightnessEDID];
            dispatch_async(dispatch_get_main_queue(),^{
                if(self.stopping||self.stopped||token!=self.verifyToken)return;
                self.verifyAttempts++;
                NSData *container=DBBrightnessContainer(live);NSDictionary *capability=[self systemCapability];
                if([container isEqual:self.container]&&[capability[@"available"] boolValue]){
                    self.ready=YES;[self emit:@"active" reason:@"系统亮度接口已绑定，等待硬件调节确认"];
                    NSNumber *pending=self.pendingPercent;self.pendingPercent=nil;if(pending&&self.onPercent)self.onPercent(pending.doubleValue);return;
                }
                if(container&&![container isEqual:self.container]){[self failAndRestore:@"屏幕绑定已被其他程序更改，停止接管"];return;}
                if(self.verifyAttempts>=6){[self failAndRestore:@"系统未确认原生亮度绑定，已尝试恢复屏幕"];return;}
                if(live&&!container&&self.verifyAttempts==2&&!self.retried){
                    self.retried=YES;NSData *retry=DBBrightnessEDIDWithContainer(live,self.container);
                    if(retry){self.patchedEDID=retry;[self applyEDID];return;}
                }
                [self scheduleVerification];
            });
        });
    });
}
- (void)updateTransport:(id<DBBrightnessTransport>)transport edid:(NSData*)edid displayID:(uint32_t)displayID {
    if(_stopped)return;_transport=transport;_displayID=displayID;
    if(_ready&&![DBBrightnessContainer(edid) isEqual:_container]){
        _ready=NO;_verifyAttempts=0;_retried=NO;[self emit:@"binding" reason:@"屏幕重新连接，正在恢复原生亮度绑定"];[self scheduleVerification];
    }
}
- (void)acknowledgePercent:(double)percent success:(BOOL)success {
    if(_stopping||_stopped)return;
    if(!success){[self failAndRestore:@"系统亮度请求的 DDC 写入或回读失败，停止原生绑定"];return;}
    [_endpoint setConfirmedPercent:percent];NSMutableDictionary *state=[_state mutableCopy];state[@"confirmedPercent"]=@(percent);state[@"hardwareWriteConfirmed"]=@YES;_state=state;
    [self emit:_ready?@"active":@"binding" reason:@"系统亮度请求已写入显示器并回读确认"];
}
- (void)failAndRestore:(NSString*)reason {
    _failure=[reason copy];_ready=NO;[self emit:@"failed" reason:reason];[self stopWithCompletion:nil];
}
- (void)stopWithCompletion:(void(^)(BOOL))completion {
    if(completion)[_stopCallbacks addObject:[completion copy]];
    if(_stopping)return;
    if(_stopped){[self finishStop:YES];return;}
    _stopping=YES;_ready=NO;_verifyToken++;_pendingPercent=nil;[_endpoint stop];
    if(!_touched){[self clearJournal];[self finishStop:YES];return;}
    [self emit:_failure?@"failed":@"restoring" reason:_failure?:@"正在恢复屏幕原始识别信息"];
    id<DBBrightnessTransport> transport=_transport;NSData *ours=_container,*original=_originalEDID;
    dispatch_async(_queue,^{
        NSData *live=[transport brightnessEDID],*container=DBBrightnessContainer(live);BOOL restored=NO;
        if(live&&![container isEqual:ours]){
            // Do not remove another app's binding. An unplug/reset can also
            // have restored the display already.
            restored=YES;
        }else if(live){
            IOReturn result=[transport setBrightnessEDID:nil];
            NSData *after=result==kIOReturnSuccess?[transport brightnessEDID]:nil;
            if(result==kIOReturnSuccess&&[after isEqual:original])restored=YES;
            else if(result==kIOReturnSuccess&&after&&!DBBrightnessContainer(after)){
                // Preserve any pre-existing custom EDID instead of silently
                // replacing it with factory timing/color/HDR information.
                result=[transport setBrightnessEDID:original];after=result==kIOReturnSuccess?[transport brightnessEDID]:nil;restored=[after isEqual:original];
            }
        }
        dispatch_async(dispatch_get_main_queue(),^{if(restored)[self clearJournal];[self finishStop:restored];});
    });
}
- (void)finishStop:(BOOL)restored {
    _stopping=NO;_stopped=restored;
    if(restored)_touched=NO;
    [self emit:_failure?@"failed":(restored?@"stopped":@"restoreFailed") reason:_failure?:(restored?@"屏幕识别信息已恢复":@"屏幕恢复未通过回读确认；保留恢复记录，可重试退出")];
    NSArray *callbacks=[_stopCallbacks copy];[_stopCallbacks removeAllObjects];for(void(^callback)(BOOL) in callbacks)callback(restored);
}
@end
