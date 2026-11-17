#import "NativeAudioSetup.h"
#import "NativeProxyAudio.h"
static NSString *const DBPhysicalOutputPreference=@"NativeAudioPhysicalOutputUID";
static NSString *const DBPreviousOutputPreference=@"NativeAudioPreviousOutputUID";
@interface DBNativeAudioSetup ()
@property DBSystemAudioBackend *backend;
@property NSUserDefaults *preferences;
@property NSString *launchOutputUID;
@property DBNativeProxyAudio *session;
@property NSTimer *monitor;
@property NSTimer *loadTimer;
@property NSDate *loadDeadline;
@property BOOL onboardingStarted;
@property BOOL stopped;
@property BOOL bridgesManaged;
@property BOOL installationRequested;
@property BOOL userOverride;
@property NSArray<NSDictionary*> *displayBridges;
@property NSString *preferredBridgeUID;
@property BOOL terminationPrepared;
@end
@implementation DBNativeAudioSetup
- (instancetype)init {if((self=[super init])){_preferences=NSUserDefaults.standardUserDefaults;_backend=[DBSystemAudioBackend new];_session=[[DBNativeProxyAudio alloc]initWithBackend:_backend];}return self;}
- (void)message:(NSString*)title detail:(NSString*)detail {NSAlert*a=[NSAlert new];a.messageText=title;a.informativeText=detail;[a runModal];}
- (BOOL)driverInstalled {return [NSFileManager.defaultManager fileExistsAtPath:@"/Library/Audio/Plug-Ins/HAL/ProxyAudioDevice.driver"];}
- (void)beginOnboarding {
    if(_onboardingStarted||_stopped)return;_onboardingStarted=YES;
    self.launchOutputUID=[_backend defaultOutputUID];
    [self ensureBridgeStartup];
}
- (NSSet<NSString*>*)enabledAudioUIDs {
    NSMutableSet *uids=[NSMutableSet new];for(NSDictionary *row in _displayBridges)if([row[@"connected"] boolValue]&&[row[@"volumeBridgeEnabled"] boolValue]&&[row[@"audioOutputUID"] length])[uids addObject:row[@"audioOutputUID"]];return uids;
}
- (void)ensureBridgeStartup {
    if(_stopped||!_onboardingStarted||_userOverride||(_bridgesManaged&&![self enabledAudioUIDs].count))return;
    if([_session.status[@"activeProxyUID"] length]||_loadTimer)return;
    if([self driverInstalled])[self waitForDriver];else if(!_installationRequested){_installationRequested=YES;[self requestInstallation];}
}
- (void)updateDisplayBridges:(NSArray<NSDictionary*>*)rows userInitiated:(BOOL)userInitiated {
    if(_stopped)return;
    NSSet *old=[self enabledAudioUIDs];_displayBridges=[rows copy];_bridgesManaged=YES;NSSet *enabled=[self enabledAudioUIDs];
    if(userInitiated){_userOverride=NO;_installationRequested=NO;for(NSString *uid in enabled)if(![old containsObject:uid])_preferredBridgeUID=uid;}
    NSString *active=_session.status[@"physicalUID"];
    if(!enabled.count||(active.length&&![enabled containsObject:active])){
        [_loadTimer invalidate];_loadTimer=nil;NSError *error=nil;
        if(![self withdrawProxy:&error]){[self message:@"音频输出恢复未完成" detail:error.localizedDescription?:@"暂未撤下代理，请重试关闭音量桥接。"];return;}
    }
    [self ensureBridgeStartup];
}
- (BOOL)withdrawProxy:(NSError**)error {
    if(![_session deactivate:error])return NO;
    // Also recover a manually selected/orphaned proxy if activation never
    // completed. Never withdraw the currently selected endpoint before fallback.
    if([[_backend defaultOutputUID] isEqual:@"ProxyAudioDevice_UID"]){
        NSArray *outputs=[_backend outputs];NSString *fallback=nil;
        for(NSString *candidate in @[_launchOutputUID?:@"",[_preferences stringForKey:DBPreviousOutputPreference]?:@"",[_preferences stringForKey:DBPhysicalOutputPreference]?:@""]){
            if([candidate isEqual:@"ProxyAudioDevice_UID"])continue;
            for(NSDictionary *row in outputs)if([row[@"uid"] isEqual:candidate]&&[row[@"alive"] boolValue]&&[row[@"channels"] unsignedIntValue]&&![row[@"virtual"] boolValue]){fallback=candidate;break;}
            if(fallback)break;
        }
        if(!fallback)for(NSDictionary *row in outputs)if([row[@"builtIn"] boolValue]&&[row[@"alive"] boolValue]&&[row[@"channels"] unsignedIntValue]){fallback=row[@"uid"];break;}
        if(!fallback||![_backend setDefaultOutputUID:fallback error:error]||![[_backend defaultOutputUID] isEqual:fallback]){
            if(error&&!*error)*error=[NSError errorWithDomain:@"DeviceBridge.NativeAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:@"未找到可恢复的物理输出，代理暂未移除，避免中断当前输出。"}];return NO;
        }
    }
    return ![_backend respondsToSelector:@selector(setProxyPublished:error:)]||[_backend setProxyPublished:NO error:error];
}
- (void)requestInstallation {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *a=[NSAlert new];a.messageText=@"启用显示器系统音量";
    a.informativeText=@"需要安装随应用附带的音量代理。安装会请求 macOS 管理员授权，并短暂中断声音；完成后会自动连接显示器音频输出。原生亮度滑块仍未接通。";
    [a addButtonWithTitle:@"继续安装…"];[a addButtonWithTitle:@"稍后"];
    if([a runModal]!=NSAlertFirstButtonReturn||_stopped)return;
    NSString *resource=NSBundle.mainBundle.resourcePath;
    NSString *(^quote)(NSString*)=^NSString*(NSString*s){return [NSString stringWithFormat:@"'%@'",[s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];};
    NSString *command=[NSString stringWithFormat:@"/bin/zsh %@ %@",quote([resource stringByAppendingPathComponent:@"install-proxy-driver.sh"]),quote([resource stringByAppendingPathComponent:@"ProxyAudioDevice.zip"])];
    NSString *escaped=[[command stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSAppleScript *script=[[NSAppleScript alloc]initWithSource:[NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",escaped]];
    NSDictionary *error=nil;
    if(![script executeAndReturnError:&error]){
        if([error[NSAppleScriptErrorNumber] integerValue]!=-128)[self message:@"音量代理未安装" detail:[NSString stringWithFormat:@"%@\n\n下次打开应用会重新提示安装。",error[NSAppleScriptErrorMessage]?:@"安装未完成。"]];
        return;
    }
    [self waitForDriver];
}
- (void)waitForDriver {
    if(_stopped||_loadTimer)return;
    _loadDeadline=[NSDate dateWithTimeIntervalSinceNow:20];
    __weak DBNativeAudioSetup *weak=self;
    _loadTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer*t){[weak checkDriver];}];
    [self checkDriver];
}
- (void)checkDriver {
    if(_stopped)return;
    if([_backend respondsToSelector:@selector(setProxyPublished:error:)])[_backend setProxyPublished:YES error:nil];
    NSArray *outputs=[_backend outputs];NSDictionary *proxy=nil;NSMutableArray *physical=[NSMutableArray new];
    for(NSDictionary*r in outputs){if([r[@"recognizedProxyBundle"] boolValue]&&[r[@"uid"] isEqual:@"ProxyAudioDevice_UID"]&&[r[@"alive"] boolValue])proxy=r;else if([r[@"displayTransport"] boolValue]&&[r[@"alive"] boolValue]&&![r[@"virtual"] boolValue])[physical addObject:r];}
    if(proxy&&physical.count){[_loadTimer invalidate];_loadTimer=nil;[self configureProxy:proxy physical:physical];return;}
    if(_loadDeadline.timeIntervalSinceNow<=0){
        [_loadTimer invalidate];_loadTimer=nil;
        // A previously configured display may simply be disconnected at login.
        if([_preferences stringForKey:DBPhysicalOutputPreference].length)return;
        NSDictionary *diagnostics=_backend.diagnostics?:@{};NSMutableArray *lines=[NSMutableArray new];BOOL candidateSeen=NO;
        for(NSDictionary *r in diagnostics[@"devices"]){
            if([r[@"uid"] isEqual:@"ProxyAudioDevice_UID"]){candidateSeen=YES;[lines addObject:[NSString stringWithFormat:@"代理：%@\n在线：%@，输出声道：%@，身份校验：%@\n音量可写：%@，静音可写：%@\n所属对象：%@，插件对象：%@",r[@"name"],r[@"alive"],r[@"channels"],r[@"recognizedProxyBundle"],r[@"volumeWritable"],r[@"muteWritable"],r[@"ownerChain"],diagnostics[@"proxyPluginID"]]];}
        }
        if(!lines.count)[lines addObject:[NSString stringWithFormat:@"音频枚举状态：%@；已枚举设备：%lu。",diagnostics[@"enumerationStatus"]?:@0,(unsigned long)[diagnostics[@"devices"] count]]];
        NSString *title=proxy?@"未发现显示器音频输出":(candidateSeen?@"音量代理识别未通过":@"暂未枚举到音量代理");
        [self message:title detail:[NSString stringWithFormat:@"%@\n\n%@",proxy?@"代理已识别，请检查 HDMI / DisplayPort 输出连接。":@"驱动文件已存在，但当前识别未完成；此结果不能判断需要重启 Mac。",[lines componentsJoinedByString:@"\n"]]]; 
    }
}
- (void)configureProxy:(NSDictionary*)proxy physical:(NSArray*)physical {
    if(_bridgesManaged){NSSet *enabled=[self enabledAudioUIDs];physical=[physical filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row,NSDictionary *bindings){return [enabled containsObject:row[@"uid"]];}]];if(!physical.count)return;}
    NSString *current=[_backend defaultOutputUID],*saved=[_preferences stringForKey:DBPhysicalOutputPreference];
    NSString *target=nil;
    for(NSDictionary *r in physical)if([r[@"uid"] isEqual:_preferredBridgeUID]){target=_preferredBridgeUID;break;}
    if(!target)for(NSDictionary *r in physical)if([r[@"uid"] isEqual:saved]){target=saved;break;}
    if(!target)for(NSDictionary *r in physical)if([r[@"uid"] isEqual:current]){target=current;break;}
    if(!target&&physical.count==1)target=physical.firstObject[@"uid"];
    if(!target){
        NSPopUpButton *picker=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,0,320,28) pullsDown:NO];
        for(NSDictionary*r in physical){[picker addItemWithTitle:r[@"name"]?:@"显示器音频"];picker.lastItem.representedObject=r[@"uid"];}
        NSAlert *a=[NSAlert new];a.messageText=@"选择显示器音频输出";a.informativeText=@"发现多个显示器音频输出，请选择音量代理实际连接的设备。";a.accessoryView=picker;[a addButtonWithTitle:@"继续"];[a addButtonWithTitle:@"稍后"];if([a runModal]!=NSAlertFirstButtonReturn)return;
        target=picker.selectedItem.representedObject;
    }
    if(_stopped)return;
    NSError *error=nil;
    NSString *restore=_launchOutputUID;
    if(!restore.length||[restore isEqual:proxy[@"uid"]])restore=[_preferences stringForKey:DBPreviousOutputPreference];
    if(![_session activateAutomaticProxy:proxy[@"uid"] physicalOutput:target restoreOutput:restore error:&error]){[self message:@"系统音量未启用" detail:error.localizedDescription?:@"代理配置失败。请在系统声音设置选择物理显示器输出，然后重新打开应用重试。"];return;}
    [_preferences setObject:target forKey:DBPhysicalOutputPreference];
    [_preferences setObject:_session.status[@"restoreOutputUID"] forKey:DBPreviousOutputPreference];
    __weak DBNativeAudioSetup *weak=self;_monitor=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer*t){[weak checkSession];}];
    if(!saved.length)[self message:@"已切换到音量代理" detail:@"路由及音量属性已通过校验。请播放声音并拖动系统音量滑块，确认实际效果；显示器自身音量不能为 0。原生亮度仍未接通。"];
}
- (void)checkSession {
    NSDictionary *status=_session.status;NSString *proxy=status[@"activeProxyUID"],*physical=status[@"physicalUID"];
    BOOL proxyAlive=NO,physicalAlive=NO;for(NSDictionary*r in status[@"outputs"]){if([r[@"uid"] isEqual:proxy])proxyAlive=[r[@"alive"] boolValue];if([r[@"uid"] isEqual:physical])physicalAlive=[r[@"alive"] boolValue];}
    if(![status[@"defaultOutputUID"] isEqual:proxy])_userOverride=YES;
    if(!proxyAlive||!physicalAlive||![status[@"defaultOutputUID"] isEqual:proxy]){NSError *error=nil;if([self withdrawProxy:&error]){[_monitor invalidate];_monitor=nil;}else NSLog(@"Native audio restore failed: %@",error);}
}
- (void)prepareForTermination:(void(^)(BOOL))completion {
    _stopped=YES;[_loadTimer invalidate];_loadTimer=nil;[_monitor invalidate];_monitor=nil;
    NSError *error=nil;if(![self withdrawProxy:&error]){_stopped=NO;NSLog(@"Native audio exit recovery failed: %@",error);if(completion)completion(NO);return;}
    if(![_backend respondsToSelector:@selector(setProxyPublished:error:)]){_terminationPrepared=YES;if(completion)completion(YES);return;}
    // HAL removes the endpoint asynchronously after Box.Acquired changes.
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    [NSTimer scheduledTimerWithTimeInterval:.1 repeats:YES block:^(NSTimer *tick){
        BOOL present=NO;for(NSDictionary *row in [self.backend outputs])if([row[@"uid"] isEqual:@"ProxyAudioDevice_UID"]){present=YES;break;}
        if(!present||deadline.timeIntervalSinceNow<=0){[tick invalidate];self.terminationPrepared=!present;if(present)self.stopped=NO;if(completion)completion(!present);}
    }];
}
- (void)stop {
    _stopped=YES;[_loadTimer invalidate];_loadTimer=nil;[_monitor invalidate];_monitor=nil;
    if(_terminationPrepared)return;NSError *error=nil;if(![self withdrawProxy:&error])NSLog(@"Native audio restore/withdraw failed: %@",error);
}
@end
