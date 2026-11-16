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
