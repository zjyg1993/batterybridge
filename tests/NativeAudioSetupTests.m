#import "NativeAudioSetup.h"
#import "NativeProxyAudio.h"
@interface DBNativeAudioSetup (Testing)
- (BOOL)driverInstalled;
- (void)requestInstallation;
- (void)waitForDriver;
- (void)configureProxy:(NSDictionary*)proxy physical:(NSArray*)physical;
- (void)checkDriver;
@end
@interface DBFakeSetup:DBNativeAudioSetup
@property BOOL installed;
@property NSUInteger prompts;
@property NSUInteger waits;
@end
@implementation DBFakeSetup
- (instancetype)init {if((self=[super init])){id backend=[NSClassFromString(@"DBAutomaticBackend") new];[self setValue:backend forKey:@"backend"];[self setValue:[[DBNativeProxyAudio alloc]initWithBackend:backend] forKey:@"session"];[self setValue:[NSClassFromString(@"DBMemoryAudioDefaults") new] forKey:@"preferences"];}return self;}
- (BOOL)driverInstalled{return _installed;}
- (void)requestInstallation{_prompts++;}
- (void)waitForDriver{_waits++;id<DBNativeAudioBackend> backend=[self valueForKey:@"backend"];if([backend respondsToSelector:@selector(setProxyPublished:error:)])[backend setProxyPublished:YES error:nil];}
@end
@interface DBMemoryAudioDefaults:NSUserDefaults
@property NSMutableDictionary *values;
@end
@implementation DBMemoryAudioDefaults
- (instancetype)init {if((self=[super init]))_values=[NSMutableDictionary new];return self;}
- (NSString*)stringForKey:(NSString*)key {return _values[key];}
- (void)setObject:(id)value forKey:(NSString*)key {_values[key]=value;}
@end
@interface DBAutomaticBackend:NSObject<DBNativeAudioBackend>
@property NSArray *rows;
@property NSString *selected;
@property NSUInteger switches;
@property BOOL published;
@property BOOL refuseSwitch;
@property BOOL refuseWithdraw;
@property NSMutableArray *events;
@end
@implementation DBAutomaticBackend
- (instancetype)init {if((self=[super init])){_published=YES;_events=[NSMutableArray new];}return self;}
- (NSArray*)outputs {if(_published)return _rows?:@[];return [_rows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row,NSDictionary *bindings){return ![row[@"uid"] isEqual:@"ProxyAudioDevice_UID"];}]]?:@[];}
- (BOOL)setProxyPublished:(BOOL)published error:(NSError**)error {if(!published&&(_refuseWithdraw||[_selected isEqual:@"ProxyAudioDevice_UID"]))return NO;_published=published;[_events addObject:published?@"publish":@"withdraw"];return YES;}

- (NSString*)defaultOutputUID{return _selected;}
- (BOOL)setDefaultOutputUID:(NSString*)uid error:(NSError**)error {if(_refuseSwitch)return NO;_selected=uid;_switches++;[_events addObject:[@"select:" stringByAppendingString:uid]];return YES;}
- (BOOL)configureProxyUID:(NSString*)proxyUID physicalUID:(NSString*)physicalUID error:(NSError**)error {return YES;}
@end
static DBFakeSetup *automaticSetup(DBAutomaticBackend *backend,DBMemoryAudioDefaults *preferences){
    DBFakeSetup *setup=[DBFakeSetup new];setup.installed=YES;
    [setup setValue:backend forKey:@"backend"];
    [setup setValue:[[DBNativeProxyAudio alloc]initWithBackend:backend] forKey:@"session"];
    [setup setValue:preferences forKey:@"preferences"];
    return setup;
}
static void check(BOOL ok,const char*message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(void){@autoreleasepool{
    DBFakeSetup *missing=[DBFakeSetup new];[missing beginOnboarding];[missing beginOnboarding];
    check(missing.prompts==1&&missing.waits==0,"missing driver prompts once per app launch, without a manual button");
    DBFakeSetup *retry=[DBFakeSetup new];[retry beginOnboarding];
    check(retry.prompts==1,"failed or deferred onboarding can retry on the next launch");
    DBFakeSetup *installed=[DBFakeSetup new];installed.installed=YES;[installed beginOnboarding];[installed beginOnboarding];
    check(installed.prompts==0&&installed.waits==1,"installed driver skips installation and continues to readiness/configuration");
    DBFakeSetup *stopped=[DBFakeSetup new];[stopped stop];[stopped beginOnboarding];
    check(stopped.prompts==0&&stopped.waits==0,"termination cannot start onboarding");
    [missing stop];[retry stop];[installed stop];
    DBAutomaticBackend *backend=[DBAutomaticBackend new];
    NSDictionary *proxy=@{@"uid":@"ProxyAudioDevice_UID",@"alive":@YES,@"channels":@2,@"virtual":@YES,@"recognizedProxyBundle":@YES,@"volumeWritable":@YES,@"muteWritable":@YES};
    NSDictionary *hdmi=@{@"uid":@"hdmi",@"alive":@YES,@"channels":@2,@"virtual":@NO,@"displayTransport":@YES};
    backend.rows=@[proxy,hdmi,@{@"uid":@"headphones",@"alive":@YES,@"channels":@2},@{@"uid":@"built-in",@"alive":@YES,@"channels":@2}];
    DBMemoryAudioDefaults *preferences=[DBMemoryAudioDefaults new];[preferences setObject:@"hdmi" forKey:@"NativeAudioPhysicalOutputUID"];
    backend.selected=@"headphones";
    DBFakeSetup *automatic=automaticSetup(backend,preferences);[automatic beginOnboarding];[automatic configureProxy:proxy physical:@[hdmi]];
    check([backend.selected isEqual:@"ProxyAudioDevice_UID"],"startup switches to proxy even when saved HDMI differs from current headphones");
    [automatic stop];check([backend.selected isEqual:@"headphones"],"normal exit restores exact output from before app startup");
    backend.selected=@"built-in";automatic=automaticSetup(backend,preferences);[automatic beginOnboarding];backend.selected=@"headphones";
    [automatic configureProxy:proxy physical:@[hdmi]];[automatic stop];
    check([backend.selected isEqual:@"built-in"],"driver-loading delay cannot replace the startup output snapshot");
    backend.selected=@"ProxyAudioDevice_UID";[preferences setObject:@"headphones" forKey:@"NativeAudioPreviousOutputUID"];
    automatic=automaticSetup(backend,preferences);[automatic beginOnboarding];[automatic configureProxy:proxy physical:@[hdmi]];[automatic stop];
    check([backend.selected isEqual:@"headphones"],"already selected proxy exits to remembered physical default instead of remaining on proxy");
    DBMemoryAudioDefaults *freshPreferences=[DBMemoryAudioDefaults new];[freshPreferences setObject:@"hdmi" forKey:@"NativeAudioPhysicalOutputUID"];
    backend.selected=@"ProxyAudioDevice_UID";automatic=automaticSetup(backend,freshPreferences);[automatic beginOnboarding];[automatic configureProxy:proxy physical:@[hdmi]];[automatic stop];
    check([backend.selected isEqual:@"hdmi"],"missing earlier default falls back to verified physical HDMI output");
    NSDictionary *managedDisplay=@{@"identity":@"display:hdmi",@"connected":@YES,@"audioOutputUID":@"hdmi",@"volumeBridgeEnabled":@YES};
    backend.selected=@"headphones";automatic=automaticSetup(backend,preferences);[automatic updateDisplayBridges:@[managedDisplay] userInitiated:NO];[automatic beginOnboarding];[automatic checkDriver];
    check([backend.selected isEqual:@"ProxyAudioDevice_UID"],"enabled per-display volume bridge automatically activates proxy");
    NSMutableDictionary *volumeOff=[managedDisplay mutableCopy];volumeOff[@"volumeBridgeEnabled"]=@NO;[automatic updateDisplayBridges:@[volumeOff] userInitiated:YES];
    check(!backend.published&&[backend.selected isEqual:@"headphones"],"turning volume bridge off restores physical output and withdraws proxy");
    [automatic updateDisplayBridges:@[managedDisplay] userInitiated:YES];[automatic checkDriver];
    check(backend.published&&[backend.selected isEqual:@"ProxyAudioDevice_UID"],"re-enabling volume bridge republishes and activates proxy");
    __block BOOL terminated=NO;[backend.events removeAllObjects];[automatic prepareForTermination:^(BOOL ok){terminated=ok;}];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:.3];while(deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    check(terminated&&!backend.published&&[backend.selected isEqual:@"headphones"]&&[backend.events.firstObject isEqual:@"select:headphones"]&&[backend.events.lastObject isEqual:@"withdraw"],"exit restores output before withdrawing and confirms proxy disappears");
    automatic=automaticSetup(backend,preferences);[automatic updateDisplayBridges:@[@{@"identity":@"silent",@"connected":@YES,@"volumeBridgeEnabled":@NO}] userInitiated:NO];[automatic beginOnboarding];
    check(automatic.waits==0&&automatic.prompts==0&&!backend.published,"non-audio display never registers proxy or prompts for audio driver");[automatic stop];
    backend.selected=@"headphones";automatic=automaticSetup(backend,preferences);[automatic beginOnboarding];[automatic configureProxy:proxy physical:@[hdmi]];backend.refuseSwitch=YES;__block BOOL refused=NO;
    [automatic prepareForTermination:^(BOOL ok){refused=!ok;}];
    check(refused&&backend.published&&[backend.selected isEqual:@"ProxyAudioDevice_UID"],"failed physical restoration prevents withdrawal and rejects exit");backend.refuseSwitch=NO;[automatic stop];
    puts("PASS: first-launch prompt, automatic proxy startup, exact exit restoration, independent bridge gating and proxy withdrawal");
}}
