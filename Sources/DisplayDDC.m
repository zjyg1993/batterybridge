#import "DisplayDDC.h"

NSData *BBDDCRequest(uint8_t code, NSNumber *value) {
    uint16_t v=value.unsignedShortValue;
    uint8_t p[]={0x51,value?0x84:0x82,value?0x03:0x01,code,v>>8,v&255,0};
    NSUInteger n=value?7:5;uint8_t checksum=0x6e;
    for(NSUInteger i=0;i<n-1;i++)checksum^=p[i];p[n-1]=checksum;
    return [NSData dataWithBytes:p length:n];
}
NSDictionary *BBDDCParseReply(NSData *data,uint8_t code) {
    if(data.length!=11)return nil;const uint8_t*p=data.bytes;
    uint8_t checksum=0x50;for(NSUInteger i=0;i<data.length;i++)checksum^=p[i];
    if(checksum||p[0]!=0x6e||p[1]!=0x88||p[2]!=0x02||p[3]!=0||p[4]!=code||p[5]!=0)return nil;
    uint16_t maximum=(p[6]<<8)|p[7],current=(p[8]<<8)|p[9];
    if(!maximum||current>maximum)return nil;
    return @{@"current":@(current),@"maximum":@(maximum),@"percent":@(100.0*current/maximum)};
}
NSDictionary *BBEDIDIdentity(NSData *data) {
    const uint8_t header[]={0,255,255,255,255,255,255,0};
    if(data.length<128||memcmp(data.bytes,header,8))return nil;
    const uint8_t*p=data.bytes;uint8_t sum=0;for(int i=0;i<128;i++)sum+=p[i];if(sum)return nil;
    NSMutableDictionary*d=[@{@"vendor":@((p[8]<<8)|p[9]),@"product":@(p[10]|(p[11]<<8)),@"serial":@((uint32_t)p[12]|((uint32_t)p[13]<<8)|((uint32_t)p[14]<<16)|((uint32_t)p[15]<<24))} mutableCopy];
    for(int i=54;i<=108;i+=18)if(!p[i]&&!p[i+1]&&!p[i+2]&&(p[i+3]==0xfc||p[i+3]==0xff)){
        NSString*s=[[NSString alloc]initWithBytes:p+i+5 length:13 encoding:NSASCIIStringEncoding];
        s=[[s componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet].firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if(s.length)d[p[i+3]==0xfc?@"name":@"textSerial"]=s;
    }
    return d;
}
NSString *BBDisplayNameKey(NSString *name) {
    return [[[name?:@"" lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet alphanumericCharacterSet].invertedSet] componentsJoinedByString:@""];
}
BOOL BBDisplayIdentityMatches(NSDictionary *screen,NSDictionary *port) {
    NSString*a=screen[@"location"],*b=port[@"location"];
    if(screen[@"vendor"]&&port[@"vendor"]&&![screen[@"vendor"] isEqual:port[@"vendor"]])return NO;
    if(screen[@"product"]&&port[@"product"]&&![screen[@"product"] isEqual:port[@"product"]])return NO;
    if([screen[@"serial"] unsignedIntValue]&&[port[@"serial"] unsignedIntValue]&&![screen[@"serial"] isEqual:port[@"serial"]])return NO;
    NSString *textA=screen[@"textSerial"],*textB=port[@"textSerial"];
    if(textA.length&&textB.length&&![textA isEqual:textB])return NO;
    // Two known physical locations disambiguate identical models. Never let
    // a weaker model match override conflicting location information.
    if(a.length&&b.length)return [a isEqual:b];
    if([screen[@"serial"] unsignedIntValue]&&[screen[@"serial"] isEqual:port[@"serial"]])return YES;
    if(textA.length&&[textA isEqual:textB])return YES;
    NSString*x=BBDisplayNameKey(screen[@"name"]),*y=BBDisplayNameKey(port[@"name"]);
    return (x.length&&[x isEqual:y])||([screen[@"vendor"] unsignedIntValue]&&[screen[@"vendor"] isEqual:port[@"vendor"]]&&[screen[@"product"] isEqual:port[@"product"]]);
}

BOOL BBDisplayControlAvailable(NSDictionary *record,uint8_t code) {
    if(code!=0x10&&code!=0x62)return NO;
    NSString *feature=code==0x10?@"brightness":@"volume";
    return record&&![record[@"connected"] isEqual:@NO]&&![record[@"scanning"] boolValue]&&
        [record[feature] isKindOfClass:NSDictionary.class]&&!record[[feature stringByAppendingString:@"Error"]];
}
