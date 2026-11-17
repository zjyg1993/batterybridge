#import "NativeProxyAudio.h"
#import <CoreAudio/AudioServerPlugIn.h>
#import <unistd.h>
static NSError*DBAudioError(NSString*message){return [NSError errorWithDomain:@"DeviceBridge.NativeProxyAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
@interface DBNativeProxyAudio ()
@property id<DBNativeAudioBackend> backend;
@property NSString*previousUID;
@property NSString*proxyUID;
@property NSString*physicalUID;
@property BOOL routeConfigurationVerified;
@property BOOL adoptedExistingProxy;
@end
@implementation DBNativeProxyAudio
- (instancetype)initWithBackend:(id<DBNativeAudioBackend>)backend {if((self=[super init]))_backend=backend;return self;}
- (NSDictionary*)status {return @{@"outputs":[_backend outputs],@"defaultOutputUID":[_backend defaultOutputUID]?:@"",@"activeProxyUID":_proxyUID?:@"",@"physicalUID":_physicalUID?:@"",@"restoreOutputUID":_previousUID?:@"",@"usesExistingUpstreamDriver":@YES,@"routeConfigurationVerified":@(_routeConfigurationVerified),@"audioPlaybackVerified":@NO,@"adoptedExistingProxy":@(_adoptedExistingProxy),@"diagnostics":[_backend respondsToSelector:@selector(diagnostics)]?([_backend diagnostics]?:@{}):@{}};}
- (BOOL)activateProxy:(NSString*)proxyUID physicalOutput:(NSString*)physicalUID routeConfirmed:(BOOL)confirmed error:(NSError**)error {
    NSString*reason=nil;NSDictionary*proxy=nil,*physical=nil;NSUInteger proxies=0,physicalMatches=0;
    if(_proxyUID.length)reason=@"已有活动实验会话，请先退出该会话。";
    else if(!proxyUID.length||!physicalUID.length||[proxyUID isEqual:physicalUID])reason=@"代理与物理输出必须是两个不同的、明确指定的 UID。";
    else if(!confirmed)reason=@"请先在 Proxy Audio Device Settings 中配置该物理输出并确认声音路由；或使用应用内自动配置入口。";
    for(NSDictionary*r in [_backend outputs]){if([r[@"uid"] isEqual:proxyUID]){proxy=r;proxies++;}if([r[@"uid"] isEqual:physicalUID]){physical=r;physicalMatches++;}}
    if(!reason&&(proxies!=1||physicalMatches!=1))reason=@"必须唯一找到两个输出，不能按名称或枚举顺序猜测。";
    if(!reason&&(![proxy[@"alive"] boolValue]||![proxy[@"channels"] unsignedIntValue]||![proxy[@"volumeWritable"] boolValue]||![proxy[@"muteWritable"] boolValue]||![proxy[@"virtual"] boolValue]||![proxy[@"recognizedProxyBundle"] boolValue]))reason=@"代理必须属于已安装的 Proxy Audio Device 插件，且在线、具有输出声道以及可写的系统音量和静音属性。";
    if(!reason&&(![physical[@"alive"] boolValue]||![physical[@"channels"] unsignedIntValue]||[physical[@"virtual"] boolValue]||![physical[@"displayTransport"] boolValue]))reason=@"目标必须是在线的 HDMI / DisplayPort 物理音频输出。";
    if(reason){if(error)*error=DBAudioError(reason);return NO;}
    NSString*previous=[_backend defaultOutputUID];if(!previous.length){if(error)*error=DBAudioError(@"无法读取原输出，拒绝执行无法回退的切换。");return NO;}
    if([previous isEqual:proxyUID]){if(error)*error=DBAudioError(@"代理已是默认输出，请先选择可恢复的物理输出再开始实验。");return NO;}
    if(![_backend setDefaultOutputUID:proxyUID error:error])return NO;
    if(![[_backend defaultOutputUID] isEqual:proxyUID]){
        [_backend setDefaultOutputUID:previous error:nil];if(error)*error=DBAudioError(@"默认输出回读不符合目标，已尝试恢复原输出。");return NO;
    }
    _previousUID=[previous copy];_proxyUID=[proxyUID copy];_physicalUID=[physicalUID copy];return YES;
}
- (BOOL)activateConfiguredProxy:(NSString*)proxyUID physicalOutput:(NSString*)physicalUID error:(NSError**)error {
    NSDictionary *proxy=nil,*physical=nil;NSUInteger pc=0,hc=0;
    for(NSDictionary *r in [_backend outputs]){if([r[@"uid"] isEqual:proxyUID]){proxy=r;pc++;}if([r[@"uid"] isEqual:physicalUID]){physical=r;hc++;}}
    NSString *previous=[_backend defaultOutputUID],*reason=nil;
    if(_proxyUID.length)reason=@"已有活动音量会话。";
    else if(!previous.length)reason=@"无法读取当前默认音频输出。";
    else if(pc!=1||hc!=1||[proxyUID isEqual:physicalUID])reason=@"没有唯一找到代理和物理显示器输出。";
    else if(![proxy[@"recognizedProxyBundle"] boolValue]||![proxy[@"virtual"] boolValue])reason=@"代理身份未通过校验。";
    else if(![proxy[@"alive"] boolValue]||![proxy[@"channels"] unsignedIntValue])reason=@"代理不在线或没有有效输出声道。";
    else if(![proxy[@"volumeWritable"] boolValue]||![proxy[@"muteWritable"] boolValue])reason=[NSString stringWithFormat:@"代理音量／静音属性尚不可写（音量 %@，静音 %@）。",proxy[@"volumeWritable"],proxy[@"muteWritable"]];
    else if(![physical[@"alive"] boolValue]||![physical[@"displayTransport"] boolValue]||[physical[@"virtual"] boolValue]||![physical[@"channels"] unsignedIntValue])reason=@"目标不是有效的在线显示器音频输出。";
    else if(![_backend respondsToSelector:@selector(configureProxyUID:physicalUID:error:)])reason=@"当前后端不支持自动配置代理。";
    if(reason){if(error)*error=DBAudioError(reason);return NO;}
    if(![_backend configureProxyUID:proxyUID physicalUID:physicalUID error:error])return NO;
    if([previous isEqual:proxyUID]){
        // The user may have selected the proxy in Sound settings already. Adopt
        // only after route readback; do not toggle outputs or overwrite a newer choice.
        if(![[_backend defaultOutputUID] isEqual:proxyUID]){if(error)*error=DBAudioError(@"配置期间系统输出已改变，已保留新的输出选择。");return NO;}
        _previousUID=[previous copy];_proxyUID=[proxyUID copy];_physicalUID=[physicalUID copy];_routeConfigurationVerified=YES;_adoptedExistingProxy=YES;return YES;
    }
    BOOL ok=[self activateProxy:proxyUID physicalOutput:physicalUID routeConfirmed:YES error:error];
    _routeConfigurationVerified=ok;return ok;
}
- (BOOL)activateAutomaticProxy:(NSString*)proxyUID physicalOutput:(NSString*)physicalUID restoreOutput:(NSString*)restoreUID error:(NSError**)error {
    // The automatic app session always has a non-proxy exit destination, even
    // when a previous run or a manual choice left the proxy selected at launch.
    NSString *target=nil;
    for(NSDictionary *r in [_backend outputs])if([r[@"uid"] isEqual:restoreUID]&&![restoreUID isEqual:proxyUID]&&[r[@"alive"] boolValue]&&[r[@"channels"] unsignedIntValue]){target=[restoreUID copy];break;}
    if(![self activateConfiguredProxy:proxyUID physicalOutput:physicalUID error:error])return NO;
    if(!target&&_previousUID.length&&![_previousUID isEqual:proxyUID])target=_previousUID;
    _previousUID=[(target?:physicalUID) copy];_adoptedExistingProxy=NO;return YES;
}
- (BOOL)deactivate:(NSError**)error {
    if(!_proxyUID.length)return YES;BOOL ok=YES;
    if(!_adoptedExistingProxy&&[[_backend defaultOutputUID] isEqual:_proxyUID]){
        NSString*target=nil;for(NSDictionary*r in [_backend outputs])if([r[@"alive"] boolValue]&&[r[@"channels"] unsignedIntValue]&&[r[@"uid"] isEqual:_previousUID]){target=_previousUID;break;}
        if(!target)for(NSDictionary*r in [_backend outputs])if([r[@"alive"] boolValue]&&[r[@"channels"] unsignedIntValue]&&[r[@"uid"] isEqual:_physicalUID]){target=_physicalUID;break;}
        if(target){ok=[_backend setDefaultOutputUID:target error:error];if(ok&&![[self.backend defaultOutputUID] isEqual:target]){ok=NO;if(error)*error=DBAudioError(@"退出时输出恢复未通过回读确认。");}}
        else{ok=NO;if(error)*error=DBAudioError(@"原输出和物理目标均已离线，未猜测其他输出设备。");}
    }
    if(ok){_adoptedExistingProxy=NO;_routeConfigurationVerified=NO;_previousUID=nil;_proxyUID=nil;_physicalUID=nil;}return ok;
}
@end
static BOOL DBGet(AudioObjectID d,UInt32 selector,UInt32 scope,UInt32 size,void*out){AudioObjectPropertyAddress a={selector,scope,0};return AudioObjectGetPropertyData(d,&a,0,NULL,&size,out)==noErr;}
static NSString*DBString(AudioObjectID d,UInt32 selector){CFStringRef s=NULL;if(!DBGet(d,selector,kAudioObjectPropertyScopeGlobal,sizeof s,&s))return nil;return CFBridgingRelease(s);}
static NSString *DBAudioNameKey(NSString *name){return [[[name?:@"" lowercaseString] componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];}
NSString *DBDisplayAudioOutputUID(NSDictionary *display,NSArray<NSDictionary*> *displays,NSArray<NSDictionary*> *outputs){
    if([display[@"connected"] isEqual:@NO])return nil;
    NSString *identity=display[@"identity"]?:@"";NSString *uuid=[identity hasPrefix:@"display:"]?[identity substringFromIndex:8]:@"";
    NSString *name=DBAudioNameKey(display[@"name"]);NSMutableArray *exact=[NSMutableArray new],*named=[NSMutableArray new];
    for(NSDictionary *output in outputs){
        if(![output[@"alive"] boolValue]||![output[@"channels"] unsignedIntValue]||![output[@"displayTransport"] boolValue]||[output[@"virtual"] boolValue]||![output[@"uid"] length])continue;
        if(uuid.length&&[uuid caseInsensitiveCompare:output[@"uid"]]==NSOrderedSame)[exact addObject:output];
        if(name.length&&[name isEqual:DBAudioNameKey(output[@"name"])])[named addObject:output];
    }
    if(exact.count==1)return exact.firstObject[@"uid"];if(exact.count)return nil;
    NSUInteger sameName=0;for(NSDictionary *screen in displays)if(![screen[@"connected"] isEqual:@NO]&&[name isEqual:DBAudioNameKey(screen[@"name"])])sameName++;
    return named.count==1&&sameName==1?named.firstObject[@"uid"]:nil;
}
BOOL DBNativeProxyIdentityMatches(NSDictionary *record,AudioObjectID pluginID,NSArray<NSNumber*> *pluginDevices) {
    if(![record[@"uid"] isEqual:@"ProxyAudioDevice_UID"]||![record[@"virtual"] boolValue])return NO;
    if([record[@"ownerBundleID"] isEqual:@"net.briankendall.ProxyAudioDevice"])return YES;
    // AudioServerPlugIn does not necessarily implement BundleID as a readable
    // plug-in property. Resolve the installed bundle through the HAL instead.
    return pluginID&&([record[@"ownerChain"] containsObject:@(pluginID)]||[pluginDevices containsObject:record[@"id"]]);
}
static AudioObjectID DBTranslate(AudioObjectID object,UInt32 selector,NSString *identity) {
    CFStringRef qualifier=(__bridge CFStringRef)identity;AudioObjectID result=0;UInt32 size=sizeof result;
    AudioObjectPropertyAddress a={selector,kAudioObjectPropertyScopeGlobal,0};
    return AudioObjectGetPropertyData(object,&a,sizeof qualifier,&qualifier,&size,&result)==noErr?result:0;
}
static NSArray<NSNumber*> *DBObjects(AudioObjectID object,UInt32 selector,UInt32 scope) {
    if(!object)return @[];AudioObjectPropertyAddress a={selector,scope,0};UInt32 size=0;
    if(AudioObjectGetPropertyDataSize(object,&a,0,NULL,&size)||size%sizeof(AudioObjectID)||size>65536)return @[];
    NSMutableData *data=[NSMutableData dataWithLength:size];
    if(size&&AudioObjectGetPropertyData(object,&a,0,NULL,&size,data.mutableBytes))return @[];
    NSMutableArray *result=[NSMutableArray new];AudioObjectID *ids=data.mutableBytes;
    for(UInt32 i=0;i<size/sizeof(AudioObjectID);i++)[result addObject:@(ids[i])];return result;
}
@interface DBSystemAudioBackend ()
@property(nonatomic,readwrite) NSDictionary *diagnostics;
@end
@implementation DBSystemAudioBackend
- (NSArray*)outputs {
    AudioObjectPropertyAddress a={kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,0};UInt32 length=0;
    OSStatus enumerationStatus=AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,NULL,&length);
    if(enumerationStatus||length%sizeof(AudioDeviceID)||length>65536){self.diagnostics=@{@"enumerationStatus":@(enumerationStatus),@"devices":@[]};return @[];}
    NSMutableData*storage=[NSMutableData dataWithLength:length];
    if(length&&(enumerationStatus=AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&length,storage.mutableBytes))){self.diagnostics=@{@"enumerationStatus":@(enumerationStatus),@"devices":@[]};return @[];}
    AudioObjectID proxyPlugin=DBTranslate(kAudioObjectSystemObject,kAudioHardwarePropertyTranslateBundleIDToPlugIn,@"net.briankendall.ProxyAudioDevice");
    NSArray *pluginDevices=DBObjects(proxyPlugin,kAudioPlugInPropertyDeviceList,kAudioObjectPropertyScopeGlobal);
    NSMutableArray *raw=[NSMutableArray new],*result=[NSMutableArray new];AudioDeviceID*ids=storage.mutableBytes;
    for(UInt32 i=0;i<length/sizeof(AudioDeviceID);i++){
        AudioDeviceID d=ids[i];UInt32 alive=0,type=0;DBGet(d,kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,sizeof alive,&alive);DBGet(d,kAudioDevicePropertyTransportType,kAudioObjectPropertyScopeGlobal,sizeof type,&type);
        a=(AudioObjectPropertyAddress){kAudioDevicePropertyStreamConfiguration,kAudioObjectPropertyScopeOutput,0};UInt32 size=0,channels=0;
        if(!AudioObjectGetPropertyDataSize(d,&a,0,NULL,&size)&&size>=offsetof(AudioBufferList,mBuffers)&&size<=65536){
            NSMutableData*b=[NSMutableData dataWithLength:size];if(!AudioObjectGetPropertyData(d,&a,0,NULL,&size,b.mutableBytes)&&size>=offsetof(AudioBufferList,mBuffers)){
                AudioBufferList*buffers=b.mutableBytes;NSUInteger capacity=(size- offsetof(AudioBufferList,mBuffers))/sizeof(AudioBuffer);
                if(buffers->mNumberBuffers<=capacity)for(UInt32 j=0;j<buffers->mNumberBuffers;j++)channels+=buffers->mBuffers[j].mNumberChannels;
            }
        }
        if(!channels)for(NSNumber *stream in DBObjects(d,kAudioDevicePropertyStreams,kAudioObjectPropertyScopeOutput)){
            AudioStreamBasicDescription format={0};if(DBGet(stream.unsignedIntValue,kAudioStreamPropertyVirtualFormat,kAudioObjectPropertyScopeGlobal,sizeof format,&format))channels+=format.mChannelsPerFrame;
        }
        Boolean volume=NO,mute=NO;a=(AudioObjectPropertyAddress){kAudioDevicePropertyVolumeScalar,kAudioObjectPropertyScopeOutput,0};AudioObjectIsPropertySettable(d,&a,&volume);a.mSelector=kAudioDevicePropertyMute;AudioObjectIsPropertySettable(d,&a,&mute);
        if(!volume&&channels&&channels<=32){volume=YES;for(UInt32 ch=1;ch<=channels;ch++){Boolean writable=NO;a=(AudioObjectPropertyAddress){kAudioDevicePropertyVolumeScalar,kAudioObjectPropertyScopeOutput,ch};if(AudioObjectIsPropertySettable(d,&a,&writable)||!writable){volume=NO;break;}}}
        NSMutableArray *owners=[NSMutableArray new];AudioObjectID owner=d;NSString *ownerID=@"";
        for(int depth=0;depth<8;depth++){
            AudioObjectID next=0;if(!DBGet(owner,kAudioObjectPropertyOwner,kAudioObjectPropertyScopeGlobal,sizeof next,&next)||!next||[owners containsObject:@(next)])break;
            [owners addObject:@(next)];owner=next;NSString *bundle=DBString(owner,kAudioPlugInPropertyBundleID);if(bundle.length)ownerID=bundle;
        }
        NSMutableDictionary *record=[@{@"id":@(d),@"uid":DBString(d,kAudioDevicePropertyDeviceUID)?:@"",@"name":DBString(d,kAudioObjectPropertyName)?:@"",@"ownerBundleID":ownerID,@"ownerChain":owners,@"alive":@(alive!=0),@"channels":@(channels),@"virtual":@(type==kAudioDeviceTransportTypeVirtual),@"displayTransport":@(type==kAudioDeviceTransportTypeHDMI||type==kAudioDeviceTransportTypeDisplayPort),@"builtIn":@(type==kAudioDeviceTransportTypeBuiltIn),@"volumeWritable":@(volume),@"muteWritable":@(mute)} mutableCopy];
        record[@"recognizedProxyBundle"]=@(DBNativeProxyIdentityMatches(record,proxyPlugin,pluginDevices));[raw addObject:record];if(channels)[result addObject:record];
    }
    self.diagnostics=@{@"enumerationStatus":@(enumerationStatus),@"proxyPluginID":@(proxyPlugin),@"proxyPluginDevices":pluginDevices,@"devices":raw};return result;
}
- (BOOL)setProxyPublished:(BOOL)published error:(NSError**)error {
    AudioObjectID box=DBTranslate(kAudioObjectSystemObject,kAudioHardwarePropertyTranslateUIDToBox,@"ProxyAudioBox_UID");
    if(!box){if(!published)return YES;if(error)*error=DBAudioError(@"代理配置接口尚未加载。");return NO;}
    if(![DBString(box,kAudioBoxPropertyBoxUID) isEqual:@"ProxyAudioBox_UID"]){if(error)*error=DBAudioError(@"代理配置接口身份不符。");return NO;}
    if(!published&&[[self defaultOutputUID] isEqual:@"ProxyAudioDevice_UID"]){if(error)*error=DBAudioError(@"默认输出仍是代理，必须先恢复物理输出才能移除代理。");return NO;}
    UInt32 value=published?1:0,readback=UINT32_MAX;AudioObjectPropertyAddress a={kAudioBoxPropertyAcquired,kAudioObjectPropertyScopeGlobal,0};
    OSStatus status=AudioObjectSetPropertyData(box,&a,0,NULL,sizeof value,&value);
    if(status||!DBGet(box,kAudioBoxPropertyAcquired,kAudioObjectPropertyScopeGlobal,sizeof readback,&readback)||readback!=value){if(error)*error=DBAudioError(@"代理注册状态写入或回读失败。");return NO;}return YES;
}
- (BOOL)configureProxyUID:(NSString*)proxyUID physicalUID:(NSString*)physicalUID error:(NSError**)error {
    // Official upstream configuration protocol, revision d3d8c8c03438:
    // translate box UID, register configurator PID, write outputDevice=UID,
    // select ConfigType::outputDevice (-1), then read the box name as UID.
    if(![proxyUID isEqual:@"ProxyAudioDevice_UID"]||!physicalUID.length){if(error)*error=DBAudioError(@"不支持的代理 UID。");return NO;}
    CFStringRef uid=CFSTR("ProxyAudioBox_UID");AudioObjectID box=0;UInt32 size=sizeof box;
    AudioObjectPropertyAddress address={kAudioHardwarePropertyTranslateUIDToBox,kAudioObjectPropertyScopeGlobal,0};
    OSStatus result=AudioObjectGetPropertyData(kAudioObjectSystemObject,&address,sizeof uid,&uid,&size,&box);
    if(result||!box){if(error)*error=DBAudioError(@"Proxy Audio Device 的配置接口未加载。");return NO;}
    if(![DBString(box,kAudioBoxPropertyBoxUID) isEqual:@"ProxyAudioBox_UID"]){if(error)*error=DBAudioError(@"代理配置接口身份不符。");return NO;}
    SInt32 pid=getpid();address=(AudioObjectPropertyAddress){kAudioObjectPropertyIdentify,kAudioObjectPropertyScopeGlobal,0};
    result=AudioObjectSetPropertyData(box,&address,0,NULL,sizeof pid,&pid);
    if(!result){CFStringRef command=(__bridge CFStringRef)[@"outputDevice=" stringByAppendingString:physicalUID];address.mSelector=kAudioObjectPropertyName;result=AudioObjectSetPropertyData(box,&address,0,NULL,sizeof command,&command);}
    SInt32 setting=-1;address.mSelector=kAudioObjectPropertyIdentify;
    if(!result)result=AudioObjectSetPropertyData(box,&address,0,NULL,sizeof setting,&setting);
    NSString *readback=result?nil:DBString(box,kAudioObjectPropertyName);
    if(result||![readback isEqual:physicalUID]){if(error)*error=DBAudioError(@"配置代理输出失败或路由 UID 回读不符；未切换默认输出。");return NO;}
    return YES;
}
- (NSString*)defaultOutputUID {AudioDeviceID d=0;if(!DBGet(kAudioObjectSystemObject,kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,sizeof d,&d)||!d)return nil;return DBString(d,kAudioDevicePropertyDeviceUID);}
- (BOOL)setDefaultOutputUID:(NSString*)uid error:(NSError**)error {
    NSArray*matches=[[self outputs] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary*r,NSDictionary*bindings){return [r[@"uid"] isEqual:uid]&&[r[@"alive"] boolValue];}]];
    if(matches.count!=1){if(error)*error=DBAudioError(@"指定 UID 的在线音频输出不存在或不唯一。");return NO;}
    AudioDeviceID d=[matches.firstObject[@"id"] unsignedIntValue];AudioObjectPropertyAddress a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,0};OSStatus status=AudioObjectSetPropertyData(kAudioObjectSystemObject,&a,0,NULL,sizeof d,&d);
    if(status&&error)*error=[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];return status==noErr;
}
@end
