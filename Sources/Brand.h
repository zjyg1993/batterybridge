#import <Cocoa/Cocoa.h>
// One shared mark for the full-colour application icon and its menu-bar template.
static inline void BBPaintBrand(BOOL monochrome){
    NSColor*accent=monochrome?NSColor.blackColor:[NSColor colorWithRed:0.29 green:0.85 blue:0.70 alpha:1];
    [accent setStroke];NSBezierPath*b=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(205,300,570,330) xRadius:58 yRadius:58];b.lineWidth=36;[b stroke];
    [accent setFill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(794,403,36,120) xRadius:12 yRadius:12]fill];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(247,342,360,246) xRadius:24 yRadius:24]fill];
    [(monochrome?NSColor.blackColor:NSColor.whiteColor)setStroke];for(int i=0;i<2;i++){NSBezierPath*p=[NSBezierPath bezierPath];[p appendBezierPathWithArcWithCenter:NSMakePoint(512,634) radius:90+i*78 startAngle:45 endAngle:135 clockwise:NO];p.lineWidth=26;p.lineCapStyle=NSLineCapStyleRound;[p stroke];}
}
static inline NSImage*BBStatusIcon(void){
    NSImage*icon=[NSImage imageWithSize:NSMakeSize(20,20) flipped:NO drawingHandler:^BOOL(NSRect rect){
        [NSGraphicsContext saveGraphicsState];NSAffineTransform*t=[NSAffineTransform transform];[t translateXBy:1 yBy:1];[t scaleBy:18.0/700.0];[t translateXBy:-160 yBy:-220];[t concat];BBPaintBrand(YES);[NSGraphicsContext restoreGraphicsState];return YES;
    }];icon.template=YES;icon.accessibilityDescription=@"BatteryBridge";return icon;
}
