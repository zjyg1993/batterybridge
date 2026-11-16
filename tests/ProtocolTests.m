#import "Protocol.h"
static unsigned checks=0;
static void require(BOOL pass,NSString *name){checks++;if(!pass){fprintf(stderr,"FAIL %s\n",name.UTF8String);exit(1);}}
int main(){@autoreleasepool{
NSData*aq=BBAulaF75Query();const uint8_t*ab=aq.bytes;
require(aq.length==19&&ab[0]==0x4a&&ab[18]==0x5d,@"F75 read-only battery request");
// Captured F75 reply from sanshoku spec 013: 97 percent on battery.
uint8_t af[]={0x13,0x4a,1,0,2,0x61,1,0,0,0,0,0,0,0,0,0,0,0,0,0xc2};
NSDictionary*ar=BBAulaF75Decode([NSData dataWithBytes:af length:20],0x13);
require([ar[@"percent"] intValue]==97,@"F75 captured battery reply");
require([BBAulaF75Decode([NSData dataWithBytes:af+1 length:19],0x13)[@"percent"] intValue]==97,@"F75 report ID excluded");
af[1]=0xca;af[19]=0x42;require(BBAulaF75Decode([NSData dataWithBytes:af length:20],0x13)!=nil,@"F75 high-bit command echo");
af[1]=0x4a;af[5]=100;af[6]=0x10;af[19]=0xd4;ar=BBAulaF75Decode([NSData dataWithBytes:af length:20],0x13);
require(ar&&!ar[@"percent"]&&[ar[@"charging"] boolValue],@"F75 cable placeholder 100 is never a percentage");
af[19]++;require(!BBAulaF75Decode([NSData dataWithBytes:af length:20],0x13),@"F75 corrupt checksum rejected");
require(!BBAulaF75Decode([NSData dataWithBytes:af length:6],0x13),@"F75 short report rejected");
require(!BBAulaF75Decode([NSData dataWithBytes:af length:20],0x10),@"F75 wrong report ID rejected");
af[5]=0;af[6]=1;af[19]=0x61;require(!BBAulaF75Decode([NSData dataWithBytes:af length:20],0x13),@"F75 unavailable zero rejected");
af[5]=97;af[6]=2;af[19]=0xc3;require(!BBAulaF75Decode([NSData dataWithBytes:af length:20],0x13),@"F75 unknown power state rejected");
NSData*sq=BBAulaSC580Query(42);const uint8_t*sb=sq.bytes;
require(sq.length==33&&sb[0]==0x0f&&sb[1]==1&&sb[2]==0x30&&sb[4]==42&&sb[5]==1&&sb[6]==0,@"SC580 official read-only getter framing");
// Synthetic response fixture based on official CDevSprime/MS.ini; not a hardware capture.
NSMutableData*sr=[sq mutableCopy];uint8_t*sp=sr.mutableBytes;memcpy(sp+7,"M137",4);sp[18]=83;
require([BBAulaSC580Decode(sr,42)[@"percent"] intValue]==83,@"SC580 percentage offset");
sp[19]=1;require([BBAulaSC580Decode(sr,42)[@"charging"] boolValue],@"SC580 charging offset");
require(!BBAulaSC580Decode(sr,41),@"SC580 stale sequence rejected");
sp[3]=1;require(!BBAulaSC580Decode(sr,42),@"SC580 busy response rejected");sp[3]=0;
sp[7]='X';require(!BBAulaSC580Decode(sr,42),@"SC580 wrong model rejected");sp[7]='M';
sp[18]=255;require(!BBAulaSC580Decode(sr,42),@"SC580 invalid level rejected");sp[18]=83;
sp[19]=2;require(!BBAulaSC580Decode(sr,42),@"SC580 unknown charge state rejected");
require(!BBAulaSC580Decode([sr subdataWithRange:NSMakeRange(0,20)],42),@"SC580 short report rejected");
uint8_t desc[]={0x85,0x13,0x75,8,0x95,19,0x81,2,0x91,2};
NSData*aulaDescriptor=[NSData dataWithBytes:desc length:sizeof desc];
require(BBHIDReportMatches(aulaDescriptor,0x13,9,19)&&BBHIDReportMatches(aulaDescriptor,0x13,8,19),@"HID declared input and output sizes");
require(!BBHIDReportMatches(aulaDescriptor,0x0f,11,32),@"HID wrong report excluded");
require(!BBHIDReportMatches([aulaDescriptor subdataWithRange:NSMakeRange(0,9)],0x13,9,19),@"HID truncated aulaDescriptor excluded");
NSData*q=BBQHWQuery(201);const uint8_t*b=q.bytes;require(q.length==8&&b[7]==199,@"QHW request framing and checksum");
uint8_t response[32]={0x4d,1,3,2,4,9,0,201,0,92,0};for(int i=2;i<10;i++)response[10]^=response[i];
NSData*r=[NSData dataWithBytes:response length:32];NSDictionary*d=BBQHWDecode(r,0x4d,201);require([d[@"percent"] intValue]==92&&! [d[@"charging"] boolValue],@"valid QHW battery");
require(!BBQHWDecode(r,0x4d,200),@"reject unrelated sequence");response[10]^=1;require(!BBQHWDecode([NSData dataWithBytes:response length:32],0x4d,201),@"reject bad checksum");
require(!BBQHWDecode([NSData dataWithBytes:response length:4],0x4d,201),@"reject short report");
uint8_t unified[]={94,8,0};d=BBLogitechDecodeBattery([NSData dataWithBytes:unified length:3],0x1004);require([d[@"percent"] intValue]==94,@"unified percent");
unified[2]=1;require([BBLogitechDecodeBattery([NSData dataWithBytes:unified length:3],0x1004)[@"charging"] boolValue],@"charging");
unified[0]=255;require(!BBLogitechDecodeBattery([NSData dataWithBytes:unified length:3],0x1004),@"reject invalid percent");
unified[0]=0;require(!BBLogitechDecodeBattery([NSData dataWithBytes:unified length:3],0x1000),@"legacy unknown is not zero");
uint8_t h[]={0x11,1,6,0x1d,94,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0};d=BBLogitechEnvelope([NSData dataWithBytes:h length:20],0x11);require([d[@"slot"] intValue]==1&&[d[@"feature"] intValue]==6&&[d[@"function"] intValue]==0x1d,@"HID++ native framing");
require(!BBLogitechEnvelope([NSData dataWithBytes:h length:4],0x11),@"reject incomplete HID++");

uint8_t bad[]={0,8,0};require(!BBLogitechDecodeBattery([NSData dataWithBytes:bad length:3],0x1004),@"discrete-only level is not precise zero");
bad[0]=40;bad[2]=4;require(!BBLogitechDecodeBattery([NSData dataWithBytes:bad length:3],0x1004),@"invalid battery status is not published");
response[10]^=1;response[9]=101;response[10]=0;for(int i=2;i<10;i++)response[10]^=response[i];require(!BBQHWDecode([NSData dataWithBytes:response length:32],0x4d,201),@"QHW invalid battery rejected");
require(!BBQHWDecode(r,0x4e,201),@"wrong QHW report ID ignored");
// Official XUNSHE/YJX event format, not the unrelated G7 AA/55 framing.
uint8_t y[]={0xab,0x30,0,0,0,0,0,0,46,0};
d=BBYJXDecode([NSData dataWithBytes:y length:sizeof y],0xab);require([d[@"percent"] intValue]==46&&![d[@"charging"] boolValue],@"YJX native report framing");
y[9]=1;require([BBYJXDecode([NSData dataWithBytes:y+1 length:9],0xf0)[@"charging"] boolValue],@"YJX WebHID payload charging");
y[8]=101;require(!BBYJXDecode([NSData dataWithBytes:y length:sizeof y],0xab),@"YJX rejects out-of-range percent");
y[8]=0;y[9]=0;require([BBYJXDecode([NSData dataWithBytes:y length:sizeof y],0xab)[@"percent"] isEqual:@0],@"YJX accepts explicit zero in valid status frame");
y[9]=255;require(!BBYJXDecode([NSData dataWithBytes:y length:sizeof y],0xab),@"YJX rejects unknown charging flag");
y[9]=0;require(!BBYJXDecode([NSData dataWithBytes:y length:8],0xab),@"YJX rejects truncated status");
require(!BBYJXDecode([NSData dataWithBytes:y length:sizeof y],5),@"mouse input reports never become battery readings");
y[1]=0xed;require(!BBYJXDecode([NSData dataWithBytes:y length:sizeof y],0xab),@"online status is not battery");
uint8_t aa[]={0xaa,0x30,0xa5,0x0b,0x0a,1,1,1,46,0};require(!BBYJXDecode([NSData dataWithBytes:aa length:sizeof aa],0xab),@"other YJX firmware framing is not assumed compatible");
q=BBYJXOnlineQuery();b=q.bytes;require(q.length==63&&b[0]==0xed&&b[1]==1&&b[62]==0,@"official read-only online request");
NSData*descriptor=[[NSData alloc]initWithBase64EncodedString:@"BQEJAqEBCQGhAIUFBQkZASkQFQAlAZUQdQGBAgUBCTAJMRYBgCb/f5UCdRCBBgk4FYElf5UBdQiBBgUMCjgClQGBBsDABQEJBqEBhQKVcHUBFQAlAQUHGQAq/wCBAsAFDAkBoQGFAxkBKv8DFQEm/wOVAXUQgQDABQEJgKEBhQQZgSmDFQAlAZUDdQGBApUFgQHABqv/CQChAYWrFQAm/wAZACr/AJU9dQiBAhkAKv8AlT11CJECwAYB/wkQoQGF8BUAJv8AGQEpCJU/dQiBAhkBKQiRAsA=" options:0];
require(BBYJXDescriptorMatches(descriptor),@"confirmed receiver descriptor matches");
require(!BBYJXDescriptorMatches([NSData data])&&!BBYJXDescriptorMatches(nil),@"shared USB identifier without exact transport is refused");
q=BBYJXBatteryQuery();b=q.bytes;uint8_t expected[]={0x30,0xa5,0x0b,0x2e,1,1,1,0,0};
require(q.length==63&&!memcmp(b,expected,sizeof expected),@"F0 battery query matches documented read-only command");
BOOL padding=YES;for(NSUInteger i=sizeof expected;i<q.length;i++)padding=padding&&b[i]==0;require(padding,@"battery request contains no trailing configuration data");
printf("PASS: %u protocol checks\n",checks);
}}
