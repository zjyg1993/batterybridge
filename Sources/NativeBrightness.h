#import <Foundation/Foundation.h>
FOUNDATION_EXPORT BOOL DBNativeEDIDValid(NSData*edid);
FOUNDATION_EXPORT NSData*DBNativeBrightnessDescriptor(NSUInteger edidLength);
FOUNDATION_EXPORT NSData*DBNativeBrightnessReport(double percent);
FOUNDATION_EXPORT NSNumber*DBNativeBrightnessDecode(NSData*report);
// Probe creation and capture native report requests only. It never writes DDC
// or applies an unverified system EDID override.
FOUNDATION_EXPORT NSDictionary*DBProbeNativeBrightness(uint32_t displayID,NSData*edid,double initialPercent,NSTimeInterval duration);
