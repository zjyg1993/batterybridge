#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <signal.h>
#import <dlfcn.h>
#import <IOKit/IOKitLib.h>
#import "NativeProxyAudio.h"
#import "NativeBrightness.h"
#import "NativeBrightnessBridge.h"
static volatile sig_atomic_t stopped=0;
static void stopSession(int signal){stopped=1;}
static void json(id value){NSError*error=nil;NSData*d=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];if(!d){fprintf(stderr,"JSON error: %s\n",error.localizedDescription.UTF8String);return;}puts([[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding].UTF8String);}
static NSArray*displays(void){
    uint32_t count=0;if(CGGetOnlineDisplayList(0,NULL,&count)||!count)return @[];NSMutableData*buffer=[NSMutableData dataWithLength:count*sizeof(CGDirectDisplayID)];if(CGGetOnlineDisplayList(count,buffer.mutableBytes,&count))return @[];
    void*f=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY|RTLD_LOCAL);bool(*canChange)(uint32_t)=f?dlsym(f,"DisplayServicesCanChangeBrightness"):NULL;
    NSMutableArray*rows=[NSMutableArray new];CGDirectDisplayID*ids=buffer.mutableBytes;
    for(uint32_t i=0;i<count;i++)[rows addObject:@{@"displayID":@(ids[i]),@"vendor":@(CGDisplayVendorNumber(ids[i])),@"product":@(CGDisplayModelNumber(ids[i])),@"serial":@(CGDisplaySerialNumber(ids[i])),@"builtIn":@(CGDisplayIsBuiltin(ids[i])),@"nativeBrightnessSupported":canChange?@(canChange(ids[i])):NSNull.null}];if(f)dlclose(f);return rows;
}
int main(int argc,const char*argv[]){@autoreleasepool{
    if(argc==2&&!strcmp(argv[1],"brightness-readiness")){
        CFTypeRef(*avCreate)(CFAllocatorRef,io_service_t)=dlsym(RTLD_DEFAULT,"IOAVServiceCreateWithService");
        NSMutableArray *ports=[NSMutableArray new];io_iterator_t iterator=0;
        IOReturn enumeration=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPAVServiceProxy"),&iterator);
        if(enumeration==kIOReturnSuccess){io_service_t entry;
            while((entry=IOIteratorNext(iterator))){
                NSString *location=CFBridgingRelease(IORegistryEntryCreateCFProperty(entry,CFSTR("Location"),kCFAllocatorDefault,0));
                if([location isEqual:@"External"]){
                    CFTypeRef service=avCreate?avCreate(kCFAllocatorDefault,entry):NULL;
                    NSData *edid=service?DBBrightnessCopyEDID((__bridge id)service):nil;
                    NSData *container=DBBrightnessContainer(edid);
                    [ports addObject:@{@"location":location,@"avServiceCreated":@(service!=NULL),@"validEDID":@(edid!=nil),@"edidBytes":@(edid.length),@"existingContainerID":@(container!=nil)}];
                    if(service)CFRelease(service);
                }IOObjectRelease(entry);
            }IOObjectRelease(iterator);
        }
        json(@{@"displays":displays(),@"externalPorts":ports,@"enumerationStatus":@(enumeration),@"copyEDIDAPIAvailable":@(dlsym(RTLD_DEFAULT,"IOAVServiceCopyEDID")!=NULL),@"setVirtualEDIDAPIAvailable":@(dlsym(RTLD_DEFAULT,"IOAVServiceSetVirtualEDIDMode")!=NULL),@"processHIDEntitled":@(DBBrightnessHIDEntitled()),@"edidModified":@NO,@"ddcWrites":@0,@"displayBindingVerified":@NO});return 0;
    }
    if(argc==2&&!strcmp(argv[1],"hid-capability")){
        // Deliberately test the actual API, independently of the app's signing
        // preflight. A fresh random ContainerID cannot bind an existing screen.
        io_service_t resource=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOHIDResource"));
        BOOL resourceFound=resource!=IO_OBJECT_NULL;
        // Opening a client without creating a device separates access failures
        // from report-descriptor rejection. Always release the diagnostic client.
        io_connect_t connection=IO_OBJECT_NULL;
        IOReturn openStatus=resource?IOServiceOpen(resource,mach_task_self(),0,&connection):kIOReturnNoDevice;
        if(connection)IOServiceClose(connection);
        if(resource)IOObjectRelease(resource);
        CFTypeRef(*create)(CFAllocatorRef,CFDictionaryRef,IOOptionBits)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceCreateWithProperties");
        NSDictionary *properties=@{@"ReportDescriptor":DBBrightnessHIDDescriptor(),@"VendorID":@0xffff,@"ProductID":@0xdb03,@"Product":@"DeviceBridge HID Capability Probe",@"Transport":@"USB",@"kUSBContainerID":NSUUID.UUID.UUIDString};
        CFTypeRef device=create?create(kCFAllocatorDefault,(__bridge CFDictionaryRef)properties,0):NULL;
        BOOL created=device!=NULL;if(device)CFRelease(device);
        json(@{@"processHIDEntitled":@(DBBrightnessHIDEntitled()),@"IOHIDResourceFound":@(resourceFound),@"IOHIDResourceOpenStatus":@(openStatus),@"IOHIDResourceOpenStatusHex":[NSString stringWithFormat:@"0x%08x",openStatus],@"IOHIDResourceOpenError":@(mach_error_string(openStatus)),@"IOHIDCreateAPIAvailable":@(create!=NULL),@"IOHIDDeviceCreated":@(created),@"brightnessHIDDescriptorBase64":[DBBrightnessHIDDescriptor() base64EncodedStringWithOptions:0],@"edidModified":@NO,@"displayBindingVerified":@NO});return 0;
    }
    DBNativeProxyAudio*audio=[[DBNativeProxyAudio alloc]initWithBackend:[DBSystemAudioBackend new]];
    if(argc==2&&!strcmp(argv[1],"status")){json(@{@"audio":audio.status,@"displays":displays(),@"nativeBrightnessBridgeCodePresent":@YES,@"nativeBrightnessHIDEntitled":@(DBBrightnessHIDEntitled()),@"nativeBrightnessHardwareVerified":@NO,@"proxyDriverBundled":@([NSFileManager.defaultManager fileExistsAtPath:[[[[@(argv[0]) stringByStandardizingPath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Resources/ProxyAudioDevice.zip"]])});return 0;}
    if(argc>=4&&!strcmp(argv[1],"proxy-session")){
        BOOL confirmed=argc==5&&!strcmp(argv[4],"--route-confirmed");NSError*error=nil;
        if(![audio activateProxy:@(argv[2]) physicalOutput:@(argv[3]) routeConfirmed:confirmed error:&error]){json(@{@"activated":@NO,@"error":error.localizedDescription});return 2;}
        signal(SIGINT,stopSession);signal(SIGTERM,stopSession);fprintf(stderr,"Proxy selected. System volume uses the upstream driver's software volume; no DDC volume changes. Ctrl-C restores the prior output.\n");
        while(!stopped){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
            NSDictionary*status=audio.status;BOOL targetAlive=NO,proxyAlive=NO;for(NSDictionary*r in status[@"outputs"]){if([r[@"uid"] isEqual:status[@"physicalUID"]])targetAlive=[r[@"alive"] boolValue];if([r[@"uid"] isEqual:status[@"activeProxyUID"]])proxyAlive=[r[@"alive"] boolValue];}
            if(!targetAlive||!proxyAlive||![status[@"defaultOutputUID"] isEqual:status[@"activeProxyUID"]])break;
        }
        BOOL restored=[audio deactivate:&error];json(@{@"sessionEnded":@YES,@"restoredOrPreservedUserSelection":@(restored),@"error":error.localizedDescription?:@""});return restored?0:3;
    }
    if(argc==5&&!strcmp(argv[1],"brightness-probe")){
        char*end=NULL;unsigned long id=strtoul(argv[2],&end,10);if(!end||*end||id>UINT32_MAX)return 2;
        end=NULL;double percent=strtod(argv[4],&end);if(!end||*end)return 2;
        NSData*edid=[NSData dataWithContentsOfFile:@(argv[3])];NSDictionary*result=DBProbeNativeBrightness((uint32_t)id,edid,percent,10);json(result);return result[@"error"]?2:0;
    }
    fprintf(stderr,"Usage:\n  native-bridge status\n  native-bridge brightness-readiness\n  native-bridge hid-capability\n  native-bridge proxy-session PROXY_UID PHYSICAL_UID --route-confirmed\n  native-bridge brightness-probe DISPLAY_ID EDID_FILE INITIAL_PERCENT\n");return 2;
}}
