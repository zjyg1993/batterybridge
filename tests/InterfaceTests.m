// Offscreen AppKit checks. Uses in-memory preferences and never installs or registers login items.
#define main BBApplicationMain
#import "../Sources/main.m"
#undef main
static void ensure(BOOL ok,const char*message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
int main(int argc,const char*argv[]){@autoreleasepool{
    BBTestingUI=YES;[NSApplication sharedApplication];[BBPreferences() registerDefaults:@{@"ReportInterval":@3600,@"AutoStartEnabled":@YES}];
    // A USB mouse/keyboard usage alone must never qualify as a 2.4G receiver.
    NSMutableDictionary*hid=[@{@"Transport":@"USB",@"VendorID":@0x056a,@"ProductID":@0x0357,@"Product":@"Wacom Intuos Pro M",@"PrimaryUsagePage":@1,@"PrimaryUsage":@2} mutableCopy];
    ensure(receiverKind(hid)==BBReceiverNone,"wired Wacom mouse interface excluded");
    hid[@"PrimaryUsage"]=@6;ensure(receiverKind(hid)==BBReceiverNone,"generic USB keyboard excluded");
    hid[@"VendorID"]=@0x046d;hid[@"PrimaryUsagePage"]=@0xff00;hid[@"PrimaryUsage"]=@1;hid[@"Product"]=@"G502 HERO Gaming Mouse";
    ensure(receiverKind(hid)==BBReceiverNone,"wired Logitech vendor interface excluded");
    hid[@"Product"]=@"USB Receiver";ensure(receiverKind(hid)==BBReceiverLogitech,"Logitech USB receiver retained");
    hid[@"Product"]=@"LIGHTSPEED Receiver";ensure(receiverKind(hid)==BBReceiverLogitech,"LIGHTSPEED receiver retained");
    hid[@"Transport"]=@"Bluetooth";ensure(receiverKind(hid)==BBReceiverNone,"Bluetooth excluded even with receiver-like name");
    hid[@"Transport"]=@"USB";hid[@"VendorID"]=@0x3837;hid[@"ProductID"]=@0x1015;hid[@"PrimaryUsagePage"]=@0xff80;hid[@"Product"]=@"MCHOSE K87 V3 2.4G";
    ensure(receiverKind(hid)==BBReceiverQHW,"MCHOSE 2.4G receiver retained");
    hid[@"Product"]=@"MCHOSE K87 V3";ensure(receiverKind(hid)==BBReceiverNone,"MCHOSE wired mode excluded");
    hid[@"VendorID"]=@0xa8a5;hid[@"ProductID"]=@0x2255;hid[@"PrimaryUsagePage"]=@1;hid[@"PrimaryUsage"]=@2;hid[@"Product"]=@"USB Receiver";
    ensure(receiverKind(hid)==BBReceiverNone,"shared YJX identifier requires verified descriptor");
    hid[@"ReportDescriptor"]=[[NSData alloc]initWithBase64EncodedString:@"BQEJAqEBCQGhAIUFBQkZASkQFQAlAZUQdQGBAgUBCTAJMRYBgCb/f5UCdRCBBgk4FYElf5UBdQiBBgUMCjgClQGBBsDABQEJBqEBhQKVcHUBFQAlAQUHGQAq/wCBAsAFDAkBoQGFAxkBKv8DFQEm/wOVAXUQgQDABQEJgKEBhQQZgSmDFQAlAZUDdQGBApUFgQHABqv/CQChAYWrFQAm/wAZACr/AJU9dQiBAhkAKv8AlT11CJECwAYB/wkQoQGF8BUAJv8AGQEpCJU/dQiBAhkBKQiRAsA=" options:0];
    ensure(receiverKind(hid)==BBReceiverYJX,"verified YJX 2.4G receiver retained");
    uint8_t f75Descriptor[]={0x85,0x13,0x75,8,0x95,19,0x81,2,0x91,2};
    hid[@"VendorID"]=@0x3554;hid[@"ProductID"]=@0xfa09;hid[@"PrimaryUsagePage"]=@0xff02;hid[@"PrimaryUsage"]=@1;
    hid[@"ReportDescriptor"]=[NSData dataWithBytes:f75Descriptor length:sizeof f75Descriptor];
    ensure(receiverKind(hid)==BBReceiverAulaF75,"F75 receiver with battery collection accepted");
    hid[@"PrimaryUsagePage"]=@1;ensure(receiverKind(hid)==BBReceiverNone,"F75 normal keyboard interface excluded");
    hid[@"PrimaryUsagePage"]=@0xff02;hid[@"ProductID"]=@0xfa08;ensure(receiverKind(hid)==BBReceiverNone,"F75 other connection identifier excluded");
    hid[@"ProductID"]=@0xfa09;hid[@"Transport"]=@"Bluetooth";ensure(receiverKind(hid)==BBReceiverNone,"F75 Bluetooth excluded");
    uint8_t sc580Descriptor[]={0x85,0x0f,0x75,8,0x95,32,0xb1,2};
    hid[@"Transport"]=@"USB";hid[@"VendorID"]=@0x089d;hid[@"ProductID"]=@0x062f;hid[@"PrimaryUsagePage"]=@0xff00;
    hid[@"ReportDescriptor"]=[NSData dataWithBytes:sc580Descriptor length:sizeof sc580Descriptor];
    ensure(receiverKind(hid)==BBReceiverAulaSC580,"SC580 wireless feature collection accepted");
    hid[@"VendorID"]=@0x088d;hid[@"ProductID"]=@0x062e;ensure(receiverKind(hid)==BBReceiverNone,"SC580 wired device excluded");
    hid[@"VendorID"]=@0x089d;hid[@"ProductID"]=@0x062f;[hid removeObjectForKey:@"ReportDescriptor"];
    ensure(receiverKind(hid)==BBReceiverNone,"SC580 missing feature report excluded");
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSArray*fixtures=@[@{@"name":@"G304 X LIGHTSPEED",@"identity":@"test.mouse",@"category":@"Mouse",@"connected":@YES,@"fresh":@YES,@"percent":@94,@"charging":@NO,@"full":@NO,@"updated":@(now),@"mapped":@YES,@"published":@YES,@"status":@"已映射到系统电量",@"selectable":@YES},@{@"name":@"MCHOSE K87 V3",@"identity":@"test.keyboard",@"category":@"Keyboard",@"connected":@YES,@"fresh":@YES,@"percent":@92,@"charging":@NO,@"full":@NO,@"updated":@(now),@"mapped":@YES,@"published":@YES,@"status":@"已映射到系统电量",@"selectable":@YES}];
    BBApp*app=[BBApp new];app.engine=[BBEngine new];app.engine.snapshot=fixtures;app.statusMenu=[NSMenu new];app.statusMenu.autoenablesItems=NO;[app menuNeedsUpdate:app.statusMenu];
    ensure(app.statusMenu.numberOfItems==2,"status menu has exactly two commands");
    ensure([[app.statusMenu itemAtIndex:0].title isEqual:@"显示主界面"]&&[app.statusMenu itemAtIndex:0].action==@selector(showSettings:),"first command opens main window");
    ensure([[app.statusMenu itemAtIndex:1].title isEqual:@"退出 BatteryBridge"]&&[app.statusMenu itemAtIndex:1].action==@selector(quit:)&&[[app.statusMenu itemAtIndex:1].keyEquivalent isEqual:@"q"],"second command quits with keyboard shortcut");
    NSMenuItem*three=[NSMenuItem new];three.representedObject=@10800;[app changeInterval:three];ensure(BBInterval([BBPreferences() objectForKey:@"ReportInterval"])==10800,"interval menu saves three hours");
    NSMenuItem*mapping=[NSMenuItem new];mapping.representedObject=@"test.mouse";[app toggleMapping:mapping];ensure(mappingEnabled(@"test.mouse"),"mapping can be enabled");[app toggleMapping:mapping];ensure(!mappingEnabled(@"test.mouse"),"mapping can be disabled");
    ensure(![app applicationShouldTerminateAfterLastWindowClosed:NSApp],"closing window does not terminate app");
    BBDeviceRow*card=[[BBDeviceRow alloc]initWithFrame:NSMakeRect(0,0,640,96) record:fixtures[0]];card.menuTarget=app;
    NSEvent*rightClick=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
    ensure([card menuForEvent:rightClick]==nil,"device row has no context menu");
    BOOL hasMappingLabel=NO;
    for(NSView*v in card.subviews){
        ensure(![v.accessibilityIdentifier isEqual:@"DeviceActions"],"device row has no more-actions button");
        if([v isKindOfClass:NSTextField.class]&&[[(NSTextField*)v stringValue] isEqual:@"电量映射到mac系统"])hasMappingLabel=YES;
    }
    ensure(hasMappingLabel,"mapping label uses requested wording");
    app.engine.forcePoll=NO;
    BBDeviceRow*unknown=[[BBDeviceRow alloc]initWithFrame:NSMakeRect(0,0,640,96) record:@{@"name":@"Unknown",@"connected":@YES,@"selectable":@NO}];unknown.menuTarget=app;
    [card performDeviceAction:card.refreshButton];
    ensure([app.engine.refreshTargets containsObject:@"test.mouse"]&&app.engine.refreshTargets.count==1,"row refresh button targets its own device");
    ensure(!unknown.refreshButton.enabled,"unsupported row disables refresh");
    ensure(card.mappingSwitch.enabled&&!unknown.mappingSwitch.enabled,"mapping switch respects protocol support");
    card.mappingSwitch.state=NSControlStateValueOn;[card mappingChanged:card.mappingSwitch];ensure(mappingEnabled(@"test.mouse"),"card switch enables mapping");
    card.mappingSwitch.state=NSControlStateValueOff;[card mappingChanged:card.mappingSwitch];ensure(!mappingEnabled(@"test.mouse"),"card switch disables mapping");
    NSMutableDictionary*offline=[fixtures[0] mutableCopy];offline[@"connected"]=@NO;offline[@"physical"]=@"test.receiver";
    BBDeviceRow*offlineCard=[[BBDeviceRow alloc]initWithFrame:NSMakeRect(0,0,640,96) record:offline];offlineCard.menuTarget=app;
    ensure(!offlineCard.refreshButton.enabled&&[offlineCard menuForEvent:rightClick]==nil,"offline row disables refresh and has no context menu");
    NSMenuItem*delete=[NSMenuItem new];delete.representedObject=@"test.mouse";
    app.engine.known[@"test.mouse"]=offline;app.engine.samples[@"test.mouse"]=@{@"updated":@(now)};
    app.engine.snapshot=@[offline];[app deleteDevice:delete];[app.engine applyDeletions:[NSSet setWithObject:@"test.receiver"]];
    ensure(app.engine.known[@"test.mouse"]!=nil,"reconnected device is protected from queued deletion");
    [app deleteDevice:delete];[app.engine applyDeletions:[NSSet set]];
    ensure(!app.engine.known[@"test.mouse"]&&!app.engine.samples[@"test.mouse"],"deletion clears saved identity and sample");
    app.engine.snapshot=fixtures;
    NSImage*brand=BBStatusIcon();ensure(brand.isTemplate&&brand.size.width==20,"brand menu bar icon is a monochrome system template");
    [app buildWindow];
    BOOL hasListTitle=NO;for(NSView*v in app.window.contentView.subviews)if([v isKindOfClass:NSTextField.class]&&[[(NSTextField*)v stringValue] isEqual:@"设备列表"])hasListTitle=YES;
    ensure(hasListTitle,"main window title uses device list wording");
    ensure(app.intervalPicker.numberOfItems==4,"main window offers four update intervals");
    [app.intervalPicker selectItemAtIndex:0];app.engine.forcePoll=NO;[app pickInterval:app.intervalPicker];
    ensure(BBInterval([BBPreferences() objectForKey:@"ReportInterval"])==1800&&app.engine.forcePoll,"interval change immediately requests a fresh reading");
    app.autoStartSwitch.state=NSControlStateValueOn;[app toggleAutoStart:app.autoStartSwitch];ensure([BBPreferences() boolForKey:@"AutoStartEnabled"],"main window startup switch persists enabled state");
    app.autoStartSwitch.state=NSControlStateValueOff;[app toggleAutoStart:app.autoStartSwitch];ensure(![BBPreferences() boolForKey:@"AutoStartEnabled"],"main window startup switch persists disabled state");
    [app showWindow];[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];ensure(app.window.visible,"opening main window displays it");
    [app.window performClose:nil];[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];ensure(!app.window.visible,"closing main window hides it");
    [app showWindow];[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];ensure(app.window.visible,"main window can reopen after close");[app.window orderOut:nil];
    ensure([app.window.title containsString:Version],"window title exposes the running version");
    ensure((app.window.styleMask&NSWindowStyleMaskResizable)!=0,"window allows both dimensions to resize");
    NSMutableArray*many=[fixtures mutableCopy];for(int i=0;i<7;i++)[many addObject:fixtures[i%2]];app.engine.snapshot=many;
    for(NSNumber*legacy in @[@YES,@NO]){
        app.devicesScroll.scrollerStyle=legacy.boolValue?NSScrollerStyleLegacy:NSScrollerStyleOverlay;
        for(NSValue*size in @[[NSValue valueWithSize:NSMakeSize(560,420)],[NSValue valueWithSize:NSMakeSize(660,330)],[NSValue valueWithSize:NSMakeSize(900,620)],[NSValue valueWithSize:NSMakeSize(1400,700)]]){
            [app.window setContentSize:size.sizeValue];app.devicesSignature=nil;[app refresh];
            CGFloat available=app.devicesScroll.contentSize.width;
            ensure(app.devicesView.subviews.count==many.count,"all device cards remain present after resize");
            for(NSView*v in app.devicesView.subviews)ensure(NSMinX(v.frame)>=0&&NSMaxX(v.frame)<=available+0.5,"card stays within viewport including legacy scrollbar");
            ensure(app.devicesView.frame.size.width<=available+0.5&&!app.devicesScroll.hasHorizontalScroller,"no horizontal document overflow");
            NSUInteger cols=0;for(NSView*v in app.devicesView.subviews)if(NSMinY(v.frame)==0)cols++;
            for(BBDeviceRow*row in app.devicesView.subviews){
                ensure(fabs(row.frame.size.width-available)<0.5,"each device row fills the list width");
                for(NSView*control in row.subviews)ensure(NSMinX(control.frame)>=0&&NSMaxX(control.frame)<=available,"row content stays inside narrow and wide windows");
            }
            ensure(cols==1,"devices stay in a single list at every window width");
            ensure(app.devicesScroll.frame.size.height==size.sizeValue.height-292,"card viewport grows with window height");
        }
    }
    app.engine.snapshot=fixtures;[app.window setContentSize:NSMakeSize(660,330)];app.devicesSignature=nil;[app refresh];
    NSDictionary*deniedMouse=@{@"name":@"YJX",@"identity":@"test.yjx",@"connected":@YES,@"selectable":@YES,@"status":@"设备访问被拒绝 0xe00002e2"};
    app.engine.snapshot=@[fixtures[1],deniedMouse];app.devicesSignature=nil;[app refresh];
    ensure(!app.authorizeButton.hidden,"a readable keyboard must not hide the mouse permission action");
    BBDeviceRow*deniedCard=[[BBDeviceRow alloc]initWithFrame:NSMakeRect(0,0,640,96) record:deniedMouse];deniedCard.menuTarget=app;
    ensure(deniedCard.refreshButton.enabled&&[deniedCard.refreshButton.toolTip isEqual:@"授权读取此设备电量"],"denied device retains its direct authorization button");
    // Exercise the device-response -> macOS publication path, not just labels.
    uint8_t chargingFrame[]={0xf0,0x30,0xa5,0x95,0x2e,1,1,1,78,1};
    NSDictionary*reading=BBYJXDecode([NSData dataWithBytes:chargingFrame length:sizeof chargingFrame],0xf0);
    NSDictionary*details=BBPowerDetails(@"test.yjx",@"YJX",@"Mouse",reading);
    ensure([details[@"Is Charging"] boolValue]&&![details[@"Is Charged"] boolValue]&&[details[@"Power Source State"] isEqual:@"AC Power"]&&[details[@"Current Capacity"] intValue]==78,"YJX charging response becomes charging AC accessory source");
    NSMutableDictionary*chargingRecord=[@{@"connected":@YES,@"fresh":@YES,@"charging":reading[@"charging"],@"full":reading[@"full"]} mutableCopy];
    ensure([BBChargeStatus(chargingRecord) isEqual:@"正在充电"],"charging shown independently of connection");
    chargingRecord[@"fresh"]=@NO;ensure([BBChargeStatus(chargingRecord) isEqual:@"充电状态未知"],"stale sample cannot claim a current charging state");
    chargingRecord[@"fresh"]=@YES;chargingRecord[@"connected"]=@NO;ensure([BBChargeStatus(chargingRecord) isEqual:@"充电状态未知"],"disconnected receiver cannot claim not charging");
    chargingFrame[8]=100;chargingFrame[9]=0;reading=BBYJXDecode([NSData dataWithBytes:chargingFrame length:sizeof chargingFrame],0xf0);
    details=BBPowerDetails(@"test.yjx",@"YJX",@"Mouse",reading);
    ensure(![details[@"Is Charging"] boolValue]&&[details[@"Is Charged"] boolValue]&&[details[@"Power Source State"] isEqual:@"Battery Power"],"real observed full/not-charging frame has correct macOS flags");
    chargingRecord[@"connected"]=@YES;chargingRecord[@"charging"]=reading[@"charging"];chargingRecord[@"full"]=reading[@"full"];
    ensure([BBChargeStatus(chargingRecord) isEqual:@"未充电 · 已充满"],"full and charging are distinct states");
    NSMutableDictionary*contradictory=[reading mutableCopy];contradictory[@"charging"]=@YES;
    ensure(![BBPowerDetails(@"test.yjx",@"YJX",@"Mouse",contradictory)[@"Is Charged"] boolValue],"macOS never receives charging and charged simultaneously");
    if(argc>1){
        NSDictionary*pending=@{@"name":@"USB Receiver（YJX 鼠标）",@"identity":@"test.yjx",@"category":@"Mouse",@"connected":@NO,@"selectable":@YES,@"status":@"接收器未连接"};
        app.engine.snapshot=[fixtures arrayByAddingObject:pending];[app.window setContentSize:NSMakeSize(660,600)];app.devicesSignature=nil;[app refresh];
        if(argc>2)app.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSView*root=app.window.contentView;
        NSBitmapImageRep*rep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:1320 pixelsHigh:1200 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];rep.size=NSMakeSize(660,600);
        NSGraphicsContext*ctx=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];[NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:ctx];[root.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(root.bounds);[root displayRectIgnoringOpacity:root.bounds inContext:ctx];}];[NSGraphicsContext restoreGraphicsState];
        NSData*png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];ensure([png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES],"offscreen preview saved");
    }
    puts("PASS: menu, device list, lifecycle and responsive window checks (8 resize scenarios)");
}}
