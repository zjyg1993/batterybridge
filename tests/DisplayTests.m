#import <Foundation/Foundation.h>
#import "DisplayDDC.h"
static void check(BOOL ok,const char*message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);exit(1);}}
static NSData*reply(uint8_t code,uint16_t current,uint16_t maximum){
    uint8_t p[]={0x6e,0x88,0x02,0,code,0,maximum>>8,maximum&255,current>>8,current&255,0};
    uint8_t sum=0x50;for(int i=0;i<10;i++)sum^=p[i];p[10]=sum;return [NSData dataWithBytes:p length:11];
}
int main(void){@autoreleasepool{
    const uint8_t get[]={0x51,0x82,0x01,0x10,0xac};
    check([BBDDCRequest(0x10,nil) isEqual:[NSData dataWithBytes:get length:5]],"GET brightness wire checksum");
    const uint8_t set[]={0x51,0x84,0x03,0x62,0x00,0x32,0xe8};
    check([BBDDCRequest(0x62,@50) isEqual:[NSData dataWithBytes:set length:7]],"SET volume wire checksum");
    check([BBDDCParseReply(reply(0x10,128,255),0x10)[@"maximum"] intValue]==255,"preserve panel maximum 255");
    check(fabs([BBDDCParseReply(reply(0x10,128,255),0x10)[@"percent"] doubleValue]-50.196)<.001,"normalize non-100 range");
    check(BBDDCParseReply(reply(0x62,0,100),0x62)!=nil,"zero is a valid reading");
    check(!BBDDCParseReply(reply(0x62,0,0),0x62),"reject zero maximum");
    check(!BBDDCParseReply(reply(0x62,101,100),0x62),"reject current above maximum");
    check(!BBDDCParseReply(reply(0x10,50,100),0x62),"reject another feature response");
    NSMutableData*bad=[reply(0x10,50,100) mutableCopy];((uint8_t*)bad.mutableBytes)[3]=1;
    check(!BBDDCParseReply(bad,0x10),"reject malformed response");
    check(!BBDDCParseReply([bad subdataWithRange:NSMakeRange(0,10)],0x10),"reject short response");
    uint8_t edid[128]={0,255,255,255,255,255,255,0};edid[8]=0x10;edid[9]=0xac;edid[10]=0x25;edid[11]=0x27;edid[12]=42;
    edid[57]=0xfc;memcpy(edid+59,"DELL S2725QS\n ",13);uint8_t checksum=0;for(int i=0;i<127;i++)checksum+=edid[i];edid[127]=-checksum;
    NSDictionary*identity=BBEDIDIdentity([NSData dataWithBytes:edid length:128]);
    check([identity[@"name"] isEqual:@"DELL S2725QS"]&&[identity[@"vendor"] intValue]==0x10ac&&[identity[@"serial"] intValue]==42,"read Dell model and EDID identity");
    edid[20]^=1;check(!BBEDIDIdentity([NSData dataWithBytes:edid length:128]),"reject corrupt EDID");
    check(BBDisplayIdentityMatches(@{@"name":@"DELL S2725QS",@"serial":@42},@{@"name":@"Dell S2725QS",@"serial":@42}),"model match");
    check(!BBDisplayIdentityMatches(@{@"name":@"DELL S2725QS",@"serial":@42},@{@"name":@"DELL S2725QS",@"serial":@43}),"reject a different physical monitor of same model");
    check(!BBDisplayIdentityMatches(@{@"name":@"DELL S2725QS"},@{@"name":@"DELL S2725SQ"}),"do not interchange similar Dell model names");
    check(!BBDisplayIdentityMatches(@{},@{}),"never match anonymous ports by enumeration order");
    check(!BBDisplayIdentityMatches(@{@"name":@"Generic",@"location":@"A"},@{@"name":@"Generic",@"location":@"B"}),"model does not override conflicting locations");
    check(BBDisplayIdentityMatches(@{@"serial":@42},@{@"serial":@42}),"serial-only identity supported");
    check(!BBDisplayIdentityMatches(@{@"name":@"Generic",@"textSerial":@"ABC"},@{@"name":@"Generic",@"textSerial":@"XYZ"}),"text serial conflict rejected");
    check(!BBDisplayControlAvailable(@{@"volume":@{},@"volumeError":@"failed"},0x62),"error state overrides a readable feature");
    check(!BBDisplayControlAvailable(@{@"volume":@{},@"connected":@NO},0x62),"offline never controllable");
    check(!BBDisplayControlAvailable(@{@"volume":@{},@"scanning":@YES},0x62),"discovery disables old controls");
    puts("Display protocol tests passed");return 0;
}}
