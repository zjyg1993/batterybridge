// Receiver profiles researched through 2026-11-16. Included after BBReceiverKind.
// Require a known RF receiver ID AND its battery-control collection; never match
// an entire vendor or use a mouse/keyboard input collection as protocol evidence.
static NSDictionary *BBModernReceiverProfile(NSDictionary*p){
    if(![p[@"Transport"] isEqual:@"USB"])return nil;
    unsigned vid=[p[@"VendorID"] intValue],pid=[p[@"ProductID"] intValue];
    unsigned page=[p[@"PrimaryUsagePage"] intValue],usage=[p[@"PrimaryUsage"] intValue];
    NSData*desc=p[@"ReportDescriptor"];NSNumber*interface=p[@"USBInterfaceNumber"];
    NSString*name=nil;
    if(page==0xff02&&usage==2&&BBHIDReportMatches(desc,8,9,16)&&BBHIDReportMatches(desc,8,8,16)){
        if(vid==0x3554){switch(pid){
            case 0xf508:case 0xf509:name=@"Pulsar X2 V2 / X2H / X2A / Xlite V3 Receiver";break;
            case 0xf58a:name=@"VXE R1 Pro Max";break;
            case 0xf505:name=@"VGN Dragonfly 4K Receiver";break;
            case 0xf523:name=@"Teevolution Terra Pro";break;
        }}
        if(vid==0x373b){switch(pid){
            case 0x1085:name=@"ATK VXE R1 SE+";break;
            case 0x101a:name=@"ATK X1 Pro 1K";break;
            case 0x101b:name=@"ATK Fire X 8K";break;
        }}
        if(vid==0x3710&&pid==0x5406)name=@"Pulsar X2 CrazyLight Mini";
        if(vid==0x1b1c&&pid==0x2b2a)name=@"Corsair SABRE v2 PRO ULTRALIGHT";
        if(vid==0x3770&&pid==0x0200)name=@"Hitscan Hyperlight";
        if(name)return @{@"kind":@(BBReceiverCompx),@"name":name,@"category":@"Mouse"};
    }
    if(((vid==0x5253&&pid==0x1020)||(vid==0x3837&&pid==0x100b))&&page==0xff01&&usage==1){
        unsigned rid=BBHIDReportMatches(desc,0x11,11,20)?0x11:(BBHIDReportMatches(desc,0x12,11,64)?0x12:0);
        // 5253:1020 is shared by L7/M7 and other paired models: retain family name.
        if(rid)return @{@"kind":@(BBReceiverMchose),@"name":pid==0x100b?@"MCHOSE A7 V2 Ultra Receiver":@"MCHOSE L7 / M7 Receiver",@"category":@"Mouse",@"reportID":@(rid)};
    }
    if(page==0xffff&&BBHIDReportMatches(desc,0,11,64)){
        if(vid==0x373e&&pid==0x001e&&interface&&interface.intValue==2)name=@"LAMZU Maya X 8K";
        if(vid==0x36a7){switch(pid){case 0xa880:name=@"WLmouse Beast X Max";break;case 0xa887:name=@"WLmouse Beast X";break;case 0xa868:name=@"WLmouse Beast X Mini Pro";break;}}
        if(vid==0x2023&&(pid==0xf013||pid==0xf015))name=@"MCHOSE A5 Pro Max";
        if(name)return @{@"kind":@(BBReceiverGlorious),@"name":name,@"category":@"Mouse"};
    }
    if(vid==0x320f&&pid==0x5088&&[p[@"Product"] isEqual:@"ATK V75X 2.4G Dongle"]&&page==0xff1c&&usage==0x92&&BBHIDReportMatches(desc,4,9,31)&&BBHIDReportMatches(desc,4,8,31))
        return @{@"kind":@(BBReceiverATKKeyboard),@"name":@"ATK V75X",@"category":@"Keyboard"};
    if(vid==0x0b05&&interface&&interface.intValue==2){
        if(pid==0x1ad0&&page==0xff01&&usage==3&&BBHIDReportMatches(desc,3,9,63)&&BBHIDReportMatches(desc,3,8,63))
            return @{@"kind":@(BBReceiverASUSMouse),@"name":@"ASUS ROG Harpe II Ace / Extreme Receiver",@"category":@"Mouse"};
        if(pid==0x1ace&&p[@"LocationID"]&&page==0xff02&&usage==1&&BBHIDReportMatches(desc,1,9,63)&&BBHIDReportMatches(desc,1,8,63))
            return @{@"kind":@(BBReceiverASUSOmni),@"name":@"ASUS ROG OMNI Keyboard",@"category":@"Keyboard"};
    }
    return nil;
}
