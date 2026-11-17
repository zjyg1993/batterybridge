#import "NativeBrightness.h"
#import "DisplayDDC.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/hid/IOHIDManager.h>
#import <dlfcn.h>
#import <unistd.h>
#import <math.h>
BOOL DBNativeEDIDValid(NSData*edid){
    if(!edid.length||edid.length%128||edid.length>512||!BBEDIDIdentity(edid))return NO;
    const uint8_t*p=edid.bytes;if(((NSUInteger)p[126]+1)*128!=edid.length)return NO;
    for(NSUInteger offset=0;offset<edid.length;offset+=128){uint8_t sum=0;for(NSUInteger i=0;i<128;i++)sum+=p[offset+i];if(sum)return NO;}return YES;
}
NSData*DBNativeBrightnessDescriptor(NSUInteger edidLength){
    if(edidLength!=128&&edidLength!=256&&edidLength!=384&&edidLength!=512)return nil;
    // Monitor Control; VESA brightness in 0.01 cd/m²; 32-bit Feature and Input.
    // A separate read-only EDID Feature associates metadata with this endpoint.
    // Whether macOS binds this metadata is explicitly measured, never assumed.
    uint8_t p[]={0x05,0x80,0x09,0x01,0xa1,0x01,0x85,0x01,0x06,0x82,0x00,0x09,0x10,0x16,0x90,0x01,0x27,0x60,0xea,0,0,0x67,0xe1,0,0,0x01,0x55,0x0e,0x75,0x20,0x95,0x01,0xb1,0x42,
        0x09,0x10,0x81,0x02,0x85,0x02,0x05,0x80,0x09,0x02,0x15,0x00,0x26,0xff,0x00,0x65,0x00,0x55,0x00,0x75,0x08,0x96,(uint8_t)(edidLength&255),(uint8_t)(edidLength>>8),0xb1,0x02,0xc0};
    return [NSData dataWithBytes:p length:sizeof p];
}
NSData*DBNativeBrightnessReport(double percent){
    if(!isfinite(percent)||percent<0||percent>100)return nil;uint32_t raw=(uint32_t)llround(400+(60000-400)*percent/100);
    uint8_t p[]={1,raw&255,(raw>>8)&255,(raw>>16)&255,(raw>>24)&255};return [NSData dataWithBytes:p length:5];
}
NSNumber*DBNativeBrightnessDecode(NSData*report){
    if(report.length!=5)return nil;const uint8_t*p=report.bytes;if(p[0]!=1)return nil;
    uint32_t raw=(uint32_t)p[1]|((uint32_t)p[2]<<8)|((uint32_t)p[3]<<16)|((uint32_t)p[4]<<24);
    return raw<400||raw>60000?nil:@((raw-400)*100.0/(60000-400));
}
@interface DBHIDContext:NSObject
@property NSData*edid;
@property NSData*level;
@property NSMutableArray*requests;
@end
@implementation DBHIDContext
@end
static IOReturn DBGetHID(void*context,IOHIDReportType type,uint32_t reportID,uint8_t*report,CFIndex capacity){
    DBHIDContext*c=(__bridge DBHIDContext*)context;if(type!=kIOHIDReportTypeFeature)return kIOReturnUnsupported;
    NSData*data=reportID==1?c.level:nil;
    if(reportID==2){NSMutableData*d=[NSMutableData dataWithBytes:(uint8_t[]){2} length:1];[d appendData:c.edid];data=d;}
    if(!data||capacity<(CFIndex)data.length)return kIOReturnBadArgument;memset(report,0,capacity);memcpy(report,data.bytes,data.length);[c.requests addObject:@{@"kind":@"get",@"reportID":@(reportID)}];return kIOReturnSuccess;
}
static IOReturn DBSetHID(void*context,IOHIDReportType type,uint32_t reportID,uint8_t*report,CFIndex length){
    DBHIDContext*c=(__bridge DBHIDContext*)context;if(type!=kIOHIDReportTypeFeature||reportID!=1||length!=5)return kIOReturnUnsupported;
    NSData*data=[NSData dataWithBytes:report length:length];NSNumber*p=DBNativeBrightnessDecode(data);if(!p)return kIOReturnBadArgument;
    c.level=data;[c.requests addObject:@{@"kind":@"set",@"percent":p,@"forwardedToDDC":@NO}];return kIOReturnSuccess;
}
static NSDictionary*DBNativeCapability(uint32_t displayID){
    void*f=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY|RTLD_LOCAL);
    bool(*canChange)(uint32_t)=f?dlsym(f,"DisplayServicesCanChangeBrightness"):NULL;
    int(*get)(uint32_t,float*)=f?dlsym(f,"DisplayServicesGetBrightness"):NULL;float value=0;int result=get?get(displayID,&value):-1;
    NSDictionary*r=@{@"displayID":@(displayID),@"online":@(CGDisplayIsOnline(displayID)),@"canChangeBrightness":canChange?@(canChange(displayID)):NSNull.null,@"readStatus":@(result),@"level":result==0?@(value):NSNull.null};if(f)dlclose(f);return r;
}
NSDictionary*DBProbeNativeBrightness(uint32_t displayID,NSData*edid,double initialPercent,NSTimeInterval duration){
    NSMutableDictionary*r=[@{@"nativeBrightnessVerified":@NO,@"ddcWrites":@0,@"edidOverrideApplied":@NO,@"virtualDeviceCreated":@NO,@"euid":@(geteuid())} mutableCopy];
    NSDictionary*identity=BBEDIDIdentity(edid);NSData*level=DBNativeBrightnessReport(initialPercent);
    if(!DBNativeEDIDValid(edid)||!level||!displayID||!CGDisplayIsOnline(displayID)||CGDisplayIsBuiltin(displayID)||[identity[@"vendor"] unsignedIntValue]!=CGDisplayVendorNumber(displayID)||[identity[@"product"] unsignedIntValue]!=CGDisplayModelNumber(displayID)||([identity[@"serial"] unsignedIntValue]&&[identity[@"serial"] unsignedIntValue]!=CGDisplaySerialNumber(displayID))){r[@"error"]=@"需要在线外接屏幕、匹配该屏幕身份的完整有效 EDID 和明确的初始亮度。未创建设备。";return r;}
    r[@"before"]=DBNativeCapability(displayID);r[@"identity"]=identity;
    CFTypeRef(*create)(CFAllocatorRef,CFDictionaryRef)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceCreate");
    void(*schedule)(CFTypeRef,CFRunLoopRef,CFStringRef)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceScheduleWithRunLoop");
    void(*unschedule)(CFTypeRef,CFRunLoopRef,CFStringRef)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceUnscheduleFromRunLoop");
    typedef IOReturn(*Callback)(void*,IOHIDReportType,uint32_t,uint8_t*,CFIndex);
    void(*onGet)(CFTypeRef,Callback,void*)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceRegisterGetReportCallback");
    void(*onSet)(CFTypeRef,Callback,void*)=dlsym(RTLD_DEFAULT,"IOHIDUserDeviceRegisterSetReportCallback");
    if(!create||!schedule||!unschedule||!onGet||!onSet){r[@"error"]=@"当前系统缺少虚拟 HID 所需函数。";return r;}
    NSDictionary*properties=@{@"ReportDescriptor":DBNativeBrightnessDescriptor(edid.length),@"Product":identity[@"name"]?:@"DeviceBridge Brightness Probe",@"Manufacturer":@"DeviceBridge",@"SerialNumber":identity[@"textSerial"]?:[identity[@"serial"] stringValue],@"Transport":@"Virtual",@"VendorID":@0xffff,@"ProductID":@0xdb02,@"PrimaryUsagePage":@0x80,@"PrimaryUsage":@1};
    CFTypeRef device=create(kCFAllocatorDefault,(__bridge CFDictionaryRef)properties);r[@"virtualDeviceCreated"]=@(device!=NULL);
    if(!device){r[@"error"]=@"IOHIDUserDeviceCreate 返回 NULL；沙箱、权限与驱动拒绝的具体原因尚未定位。";return r;}
    DBHIDContext*c=[DBHIDContext new];c.edid=edid;c.level=level;c.requests=[NSMutableArray new];onGet(device,DBGetHID,(__bridge void*)c);onSet(device,DBSetHID,(__bridge void*)c);schedule(device,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,fmax(.1,fmin(30,duration)),false);r[@"during"]=DBNativeCapability(displayID);r[@"requests"]=[c.requests copy];unschedule(device,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);CFRelease(device);r[@"after"]=DBNativeCapability(displayID);
    r[@"note"]=@"此探针只测量系统识别和请求，不应用尚未核实的 EDID 覆盖，也不把虚拟读数当作物理背光变化。";return r;
}
