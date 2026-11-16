#import <Cocoa/Cocoa.h>
#import "Brand.h"
int main(int argc,const char*argv[]){@autoreleasepool{
NSString*folder=[NSString stringWithUTF8String:argv[1]];
for(NSNumber*n in @[@16,@32,@64,@128,@256,@512,@1024]){
int size=n.intValue;NSBitmapImageRep*rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];NSGraphicsContext*ctx=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];[NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:ctx];
NSAffineTransform*t=[NSAffineTransform transform];[t scaleBy:size/1024.];[t concat];
[[NSColor colorWithRed:0.07 green:0.16 blue:0.24 alpha:1]setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(40,40,944,944) xRadius:215 yRadius:215]fill];
BBPaintBrand(NO);
[NSGraphicsContext restoreGraphicsState];NSData*png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];[png writeToFile:[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"size%d.png",size]] atomically:YES];
}
}}
