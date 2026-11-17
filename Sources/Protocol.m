#import "Protocol.h"
BOOL BBHIDReportMatches(NSData *descriptor,uint8_t rid,uint8_t tag,NSUInteger length) {
    if(![descriptor isKindOfClass:NSData.class])return NO;
    const uint8_t*p=descriptor.bytes;NSUInteger n=descriptor.length,bits=0;
    struct {uint32_t size,count,id;} state={0},stack[16];NSUInteger depth=0;
    for(NSUInteger i=0;i<n;){
        uint8_t prefix=p[i++];if(prefix==0xfe)return NO;
        NSUInteger size=prefix&3;if(size==3)size=4;if(size>n-i)return NO;
        uint32_t v=0;for(NSUInteger j=0;j<size;j++)v|=(uint32_t)p[i+j]<<(8*j);i+=size;
        uint8_t type=(prefix>>2)&3,t=prefix>>4;
        if(type==1){switch(t){case 7:state.size=v;break;case 8:state.id=v;break;case 9:state.count=v;break;
            case 10:if(depth==16)return NO;stack[depth++]=state;break;
            case 11:if(!depth)return NO;state=stack[--depth];break;}}
        if(type==0&&t==tag&&state.id==rid){
            if(state.size>4096||state.count>4096)return NO;
            bits+=(NSUInteger)state.size*state.count;if(bits>4096*8)return NO;
        }
    }
    return bits==length*8&&bits>0;
}
NSData *BBAulaF75Query(void) {
    uint8_t b[19]={0x4a};b[18]=0x5d;return [NSData dataWithBytes:b length:sizeof b];
}
NSDictionary *BBAulaF75Decode(NSData *report,uint8_t rid) {
    if(rid!=0x13)return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==20&&p[0]==rid){p++;n--;}
    if(n!=19||(p[0]&0x7f)!=0x4a||p[1]!=1||p[2]!=0||p[3]!=2)return nil;
    uint8_t sum=rid;for(NSUInteger i=0;i<18;i++)sum+=p[i];if(sum!=p[18])return nil;
    // Cable mode pins the reported level at 100; expose the state without a level.
    if(p[5]==0x10)return @{@"charging":@YES,@"hasLevel":@NO};
    if(p[5]!=1||p[4]<1||p[4]>100)return nil;
    return @{@"percent":@(p[4]),@"charging":@NO,@"full":@NO,@"approximate":@NO};
}
NSData *BBAulaSC580Query(uint8_t sequence) {
    // Official CDevSprime getter: feature 0x0f, wireless target, command 0x30.
    uint8_t b[33]={0x0f,1,0x30,0,sequence,1,0};return [NSData dataWithBytes:b length:sizeof b];
}
NSDictionary *BBAulaSC580Decode(NSData *report,uint8_t sequence) {
    const uint8_t*p=report.bytes;
    if(report.length!=33||p[0]!=0x0f||p[1]!=1||p[2]!=0x30||p[3]!=0||p[4]!=sequence)return nil;
    // Official MS.ini Identify=M137. The getter returns 26 bytes at offset 7.
    if(memcmp(p+7,"M137",4)!=0||p[18]>100||p[19]>1)return nil;
    return @{@"percent":@(p[18]),@"charging":@(p[19]==1),@"full":@(p[18]==100&&p[19]==0),@"approximate":@NO};
}
BOOL BBYJXDescriptorMatches(NSData *descriptor) {
    // Exact vendor collection signatures observed on this receiver. Same VID/PID
    // is reused by incompatible YJX products; never probe those by USB ID alone.
    const uint8_t input[]={0x06,0xab,0xff,0x09,0x00,0xa1,0x01,0x85,0xab};
    const uint8_t output[]={0x06,0x01,0xff,0x09,0x10,0xa1,0x01,0x85,0xf0};
    if(![descriptor isKindOfClass:NSData.class])return NO;
    return [descriptor rangeOfData:[NSData dataWithBytes:input length:sizeof input] options:0 range:NSMakeRange(0,descriptor.length)].location!=NSNotFound &&
        [descriptor rangeOfData:[NSData dataWithBytes:output length:sizeof output] options:0 range:NSMakeRange(0,descriptor.length)].location!=NSNotFound;
}
NSData *BBYJXOnlineQuery(void) {
    // Official getDeviceOnline: sendReport(0xF0, [0xED, 1, ...]).
    // This is an online-status read, NOT a fabricated battery command.
    uint8_t payload[63]={0xed,1};return [NSData dataWithBytes:payload length:sizeof payload];
}
NSData *BBYJXBatteryQuery(void) {
    // Same F0/63-byte transport as XUNSHE. Read-only 0x30 query documented
    // by mimuruu/EWEADN-GS02-Pro-Control; no AA/55 transport guessing.
    uint8_t payload[63]={0x30,0xa5,0x0b,0x2e,1,1,1,0,0};
    return [NSData dataWithBytes:payload length:sizeof payload];
}
NSDictionary *BBYJXDecode(NSData *report,uint8_t rid) {
    if(rid!=0xab&&rid!=0xf0)return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n&&p[0]==rid){p++;n--;}
    // Official oninputreport parser: command 0x30, battery[7], charge_flag[8].
    // Only these vendor reports are inspected; mouse/key input is discarded.
    if(n<9||p[0]!=0x30||p[7]>100||p[8]>1)return nil;
    return @{@"percent":@(p[7]),@"charging":@(p[8]==1),@"full":@(p[7]==100&&p[8]==0),@"approximate":@NO};
}
NSData *BBQHWQuery(uint8_t sequence) {
    // QHW getBattery 0x0904; WebHID payload excludes the report ID.
    uint8_t b[8]={1,3,0,4,9,0,sequence,0};
    for(int i=1;i<7;i++)b[7]^=b[i];
    return [NSData dataWithBytes:b length:sizeof b];
}
NSDictionary *BBQHWDecode(NSData *report,uint8_t rid,uint8_t sequence) {
    if(rid!=0x4d)return nil;
    const uint8_t *p=report.bytes;NSUInteger n=report.length;
    if(n&&p[0]==rid){p++;n--;}
    if(n<10||p[0]!=1||p[1]!=3||p[2]!=2||p[3]!=4||p[4]!=9||p[5]!=0||p[6]!=sequence)return nil;
    uint8_t checksum=0;for(NSUInteger i=1;i<9;i++)checksum^=p[i];
    if(checksum!=p[9]||p[7]>2||p[8]>100)return nil;
    return @{ @"percent":@(p[8]),@"charging":@(p[7]==1),@"full":@(p[7]==2),@"approximate":@NO };
}
NSDictionary *BBLogitechEnvelope(NSData *report,uint8_t rid) {
    if(rid!=0x10&&rid!=0x11)return nil;
    const uint8_t *p=report.bytes;NSUInteger n=report.length;
    if(n&&p[0]==rid){p++;n--;}
    if(n<(rid==0x10?6:19))return nil;
    return @{@"slot":@(p[0]),@"feature":@(p[1]),@"function":@(p[2]),@"payload":[NSData dataWithBytes:p+3 length:n-3]};
}
NSDictionary *BBLogitechDecodeBattery(NSData *payload,uint16_t feature) {
    const uint8_t *p=payload.bytes;if(payload.length<3)return nil;
    if(feature!=0x1004&&feature!=0x1000)return nil;
    // 1004: state-of-charge, discrete level, charging status. 1000: level, next level, status.
    if(p[0]>100 || p[2]>=4)return nil;
    if(feature==0x1004 && p[0]==0 && p[1]!=0)return nil;
    // 1000 uses zero for an unavailable level. Do not publish a fictitious empty battery.
    if(feature==0x1000&&p[0]==0)return nil;
    return @{@"percent":@(p[0]),@"charging":@(p[2]==1||p[2]==2),@"full":@(p[2]==3),@"approximate":@NO};
}

NSData *BBRazerQuery(uint8_t transaction,uint8_t command) {
    if(command!=0x80&&command!=0x84)return nil;
    uint8_t p[90]={0};p[1]=transaction;p[5]=2;p[6]=7;p[7]=command;
    for(NSUInteger i=2;i<88;i++)p[88]^=p[i];
    return [NSData dataWithBytes:p length:sizeof p];
}
NSNumber *BBRazerDecode(NSData *report,uint8_t transaction,uint8_t command) {
    if(command!=0x80&&command!=0x84)return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==91&&p[0]==0){p++;n--;}
    if(n!=90||p[0]!=2||p[1]!=transaction||p[2]||p[3]||p[4]||p[5]!=2||p[6]!=7||p[7]!=command)return nil;
    uint8_t sum=0;for(NSUInteger i=2;i<88;i++)sum^=p[i];if(sum!=p[88])return nil;
    if(command==0x84)return p[9]<=1?@(p[9]):nil;
    return @((p[9]*100+127)/255);
}
NSData *BBKeychronQuery(void) {
    // Current upstream keychron-battery-dkms uses SET_OUTPUT, not SET_FEATURE.
    uint8_t p[63]={6};return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBKeychronDecode(NSData *report,uint8_t rid) {
    if(rid!=0xb4)return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==64&&p[0]==rid){p++;n--;}
    if(n!=63||p[0]!=6||(p[19]&0x7f)>100)return nil;
    int percent=p[19]&0x7f;BOOL charging=(p[19]&0x80)!=0;
    return @{@"percent":@(percent),@"charging":@(charging),@"full":@(percent==100&&!charging),@"approximate":@NO};
}
NSData *BBGloriousQuery(void) {
    uint8_t p[64]={0,0,2,2,0,0x83};return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBGloriousDecode(NSData *report) {
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==65&&p[0]==0){p++;n--;}
    // A2 is waking; A4 asleep. Neither is a current battery sample.
    if(n!=64||p[0]!=0xa1||p[1]!=0||p[2]!=2||p[3]!=2||p[4]!=0||p[5]!=0x83||p[7]>100)return nil;
    return @{@"percent":@(p[7]),@"charging":@(p[6]!=0),@"full":@(p[7]==100&&p[6]==0),@"approximate":@NO};
}
NSData *BBSteelSeriesQuery(void) {
    uint8_t p[64]={0xd2};return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBSteelSeriesDecode(NSData *report) {
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==65&&p[0]==0){p++;n--;}
    if(n<2||n>64||p[0]!=0xd2)return nil;
    // Aerox protocol uses 1..21 in five-percent steps. Reject other scales.
    int level=p[1]&0x7f;if(level<1||level>21)return nil;
    int percent=(level-1)*5;BOOL charging=(p[1]&0x80)!=0;
    return @{@"percent":@(percent),@"charging":@(charging),@"full":@(percent==100&&!charging),@"approximate":@YES};
}

static NSDictionary *BBPercentage(uint8_t level,BOOL charging,NSString *name) {
    if(level>100)return nil;
    NSMutableDictionary*r=[@{@"percent":@(level),@"charging":@(charging),@"full":@(level==100&&!charging),@"approximate":@NO} mutableCopy];
    if(name)r[@"name"]=name;return r;
}
NSData *BBCompxQuery(uint8_t command) {
    if(command!=3&&command!=4)return nil;
    // The 17-byte wire frame includes ID 08; IOHID payload excludes that ID.
    uint8_t p[16]={command};p[15]=(uint8_t)(0x55-8-command);
    return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBCompxDecode(NSData *report,uint8_t rid,uint8_t command) {
    if(rid!=8||(command!=3&&command!=4))return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==17&&p[0]==8){p++;n--;}
    if(n!=16||p[0]!=command||p[1]||p[2]||p[3]||p[4]!=(command==3?1:2))return nil;
    uint8_t sum=8;for(NSUInteger i=0;i<16;i++)sum+=p[i];if(sum!=0x55)return nil;
    if(command==3)return p[5]<=1?@{@"online":@(p[5]==1)}:nil;
    if(p[6]>1)return nil;
    return BBPercentage(p[5],p[6]==1,nil);
}
NSData *BBMchoseQuery(NSUInteger payloadLength) {
    if(payloadLength!=20&&payloadLength!=64)return nil;
    NSMutableData*d=[NSMutableData dataWithLength:payloadLength];uint8_t*p=d.mutableBytes;
    memset(p,0xff,payloadLength);p[0]=(uint8_t)~6;return d;
}
NSDictionary *BBMchoseDecode(NSData *report,uint8_t rid) {
    if(rid!=0x11&&rid!=0x12)return nil;
    NSUInteger expected=rid==0x11?20:64,n=report.length;const uint8_t*p=report.bytes;
    if(n==expected+1&&p[0]==rid){p++;n--;}
    if(n!=expected)return nil;
    uint8_t decoded[64];for(NSUInteger i=0;i<n;i++)decoded[i]=p[i]^0xff;
    uint16_t vendor=decoded[1]|(decoded[2]<<8);
    // Exact command echo, supported vendor, and the live RF status bit required.
    if(decoded[0]!=6||(vendor!=0x5253&&vendor!=0x3837)||!(decoded[9]&8)||decoded[11]>1)return nil;
    return BBPercentage(decoded[10],decoded[11]==1,nil);
}
NSData *BBATKKeyboardQuery(uint16_t sequence) {
    uint8_t p[31]={sequence&255,sequence>>8,0x1a};return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBATKKeyboardDecode(NSData *report,uint8_t rid,uint16_t sequence) {
    if(rid!=4)return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==32&&p[0]==rid){p++;n--;}
    if(n!=31||p[0]!=(sequence&255)||p[1]!=(sequence>>8)||p[2]!=0x1a||p[3]||p[4]||p[5]||p[6]||p[8]>2)return nil;
    return BBPercentage(p[7],p[8]==1||p[8]==2,nil);
}
NSData *BBASUSQuery(BOOL keyboard) {
    uint8_t p[63]={0x12,keyboard?1:7};return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBASUSDecode(NSData *report,uint8_t rid,BOOL keyboard) {
    if(rid!=(keyboard?2:3))return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==64&&p[0]==rid){p++;n--;}
    if(n!=63||p[0]!=0x12||p[1]!=(keyboard?1:7)||p[2]||p[3])return nil;
    uint8_t level=p[keyboard?5:4],charge=p[keyboard?8:9];
    if(charge>1||(!level&&!charge))return nil; // zero on standby is not empty
    return BBPercentage(level,charge==1,nil);
}
NSData *BBASUSPairQuery(void) {
    uint8_t p[63]={0xa0};return [NSData dataWithBytes:p length:sizeof p];
}
NSDictionary *BBASUSPairedKeyboard(NSData *report,uint8_t rid) {
    if(rid!=1)return nil;
    const uint8_t*p=report.bytes;NSUInteger n=report.length;
    if(n==64&&p[0]==1){p++;n--;}
    if(n!=63||p[0]!=0xa0||p[1]||p[2]||p[3])return nil;
    // Pair records identify the peripheral, independent of its cable/BT PID.
    // Only known byte-6 keyboard layouts are accepted; Falchion uses another layout.
    NSDictionary*models=@{@0x1a83:@"ROG Azoth",@0x1a85:@"ROG Azoth",
        @0x1aae:@"ROG Strix Scope II 96 Wireless",@0x1aaf:@"ROG Strix Scope II 96 Wireless",@0x1ab0:@"ROG Strix Scope II 96 Wireless",
        @0x1b3f:@"ROG Azoth Extreme",@0x1b40:@"ROG Azoth Extreme",@0x1b42:@"ROG Azoth Extreme",
        @0x1c10:@"ROG Azoth 96 HE / Lite",@0x1c11:@"ROG Azoth 96 HE / Lite",@0x1c12:@"ROG Azoth 96 HE / Lite",
        @0x1c24:@"ROG Azoth X",@0x1c25:@"ROG Azoth X",@0x1c26:@"ROG Azoth X",
        @0x1c2f:@"ROG Falcata",@0x1c30:@"ROG Falcata",@0x1c31:@"ROG Falcata",
        @0x1ce8:@"ROG Strix Morph 96 Wireless",@0x1ce9:@"ROG Strix Morph 96 Wireless",@0x1cea:@"ROG Strix Morph 96 Wireless",
        @0x1cef:@"ROG Azoth Extreme Special Edition",@0x1cf0:@"ROG Azoth Extreme Special Edition",@0x1cf1:@"ROG Azoth Extreme Special Edition"};
    NSDictionary*found=nil;
    for(NSUInteger i=4;i+3<n;i+=4){
        uint16_t pid=p[i]|(p[i+1]<<8);if(!pid)break;NSString*name=models[@(pid)];if(!name)continue;
        if(found)return nil; // Ambiguous routing must never merge two keyboards.
        found=@{@"name":name,@"pid":@(pid)};
    }
    return found;
}
