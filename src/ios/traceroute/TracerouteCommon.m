//
//  TracerouteCommon.m
//  TracerouteDemo
//
//  Created by LZephyr on 2018/2/7.
//  Copyright © 2018 LZephyr. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AssertMacros.h>
#import "TracerouteCommon.h"

// IPv4 Packet Content
typedef struct IPv4Header {
    uint8_t versionAndHeaderLength;
    uint8_t serviceType;
    uint16_t totalLength;
    uint16_t identifier;
    uint16_t flagsAndFragmentOffset;
    uint8_t timeToLive;
    uint8_t protocol; // 1: ICMP: https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
    uint16_t checksum;
    uint8_t sourceAddress[4];
    uint8_t destAddress[4];
    // options...
    // data...
} IPv4Header;

// IPv6 Packet Content
typedef struct IPv6Header {
    uint32_t padding;
    uint16_t payloadLength;
    uint8_t nextHeader;
    uint8_t hopLimit;
    uint8_t sourceAddress[16]; // 128 bits source address
    uint8_t destAddress[16]; // 128 bits source address
    // data
} IPv6Header;

// IPv4Header Compile Check
__Check_Compile_Time(sizeof(IPv4Header) == 20);
__Check_Compile_Time(offsetof(IPv4Header, versionAndHeaderLength) == 0);
__Check_Compile_Time(offsetof(IPv4Header, serviceType) == 1);
__Check_Compile_Time(offsetof(IPv4Header, totalLength) == 2);
__Check_Compile_Time(offsetof(IPv4Header, identifier) == 4);
__Check_Compile_Time(offsetof(IPv4Header, flagsAndFragmentOffset) == 6);
__Check_Compile_Time(offsetof(IPv4Header, timeToLive) == 8);
__Check_Compile_Time(offsetof(IPv4Header, protocol) == 9);
__Check_Compile_Time(offsetof(IPv4Header, checksum) == 10);
__Check_Compile_Time(offsetof(IPv4Header, sourceAddress) == 12);
__Check_Compile_Time(offsetof(IPv4Header, destAddress) == 16);
__Check_Compile_Time(sizeof(ICMPPacket) == 8);
__Check_Compile_Time(offsetof(ICMPPacket, type) == 0);
__Check_Compile_Time(offsetof(ICMPPacket, code) == 1);
__Check_Compile_Time(offsetof(ICMPPacket, checksum) == 2);
__Check_Compile_Time(offsetof(ICMPPacket, identifier) == 4);
__Check_Compile_Time(offsetof(ICMPPacket, sequenceNumber) == 6);

// IPv6Header Compile Check
__Check_Compile_Time(offsetof(IPv6Header, padding) == 0);
__Check_Compile_Time(offsetof(IPv6Header, payloadLength) == 4);
__Check_Compile_Time(offsetof(IPv6Header, nextHeader) == 6);
__Check_Compile_Time(offsetof(IPv6Header, hopLimit) == 7);
__Check_Compile_Time(offsetof(IPv6Header, sourceAddress) == 8);
__Check_Compile_Time(offsetof(IPv6Header, destAddress) == 24);

@implementation TracerouteCommon

#pragma mark - Public

// Offical Sample：https://developer.apple.com/library/content/samplecode/SimplePing/Introduction/Intro.html
+ (uint16_t)makeChecksumFor:(const void *)buffer len:(size_t)bufferLen {
    size_t bytesLeft;
    int32_t sum;
    const uint16_t *cursor;
    union {
        uint16_t us;
        uint8_t uc[2];
    } last;
    uint16_t answer;
    
    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;
    
    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = *(const uint8_t *)cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16); /* add carry */
    answer = (uint16_t)~sum; /* truncate to 16 bits */
    
    return answer;
}

+ (struct sockaddr *)makeSockaddrWithAddress:(NSString *)address port:(int)port isIPv6:(BOOL)isIPv6 {
    NSData *addrData = nil;
    if (isIPv6) {
        struct sockaddr_in6 addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin6_family = AF_INET6;
        addr.sin6_len = sizeof(addr);
        addr.sin6_port = htons(port);
        if (inet_pton(AF_INET6, address.UTF8String, &addr.sin6_addr) < 0) {
            NSLog(@"Create sockaddr failure");
            return NULL;
        }
        addrData = [NSData dataWithBytes:&addr length:sizeof(addr)];
    } else {
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);
        if (inet_pton(AF_INET, address.UTF8String, &addr.sin_addr.s_addr) < 0) {
            NSLog(@"Create sockaddr failure");
            return NULL;
        }
        addrData = [NSData dataWithBytes:&addr length:sizeof(addr)];
    }
    return (struct sockaddr *)[addrData bytes];
}

+ (NSData *)makeICMPPacketWithID:(uint16_t)identifier
                        sequence:(uint16_t)seq
                        isICMPv6:(BOOL)isICMPv6 {
    NSMutableData *packet;
    ICMPPacket *icmpPtr;
    
    packet = [NSMutableData dataWithLength:sizeof(*icmpPtr)];
    
    icmpPtr = packet.mutableBytes;
    icmpPtr->type = isICMPv6 ? kICMPv6TypeEchoRequest : kICMPv4TypeEchoRequest;
    icmpPtr->code = 0;
    
    if (isICMPv6) {
        icmpPtr->identifier     = 0;
        icmpPtr->sequenceNumber = 0;
    } else {
        icmpPtr->identifier     = OSSwapHostToBigInt16(identifier);
        icmpPtr->sequenceNumber = OSSwapHostToBigInt16(seq);
    }
    
    // validation of checkSum and length of ICMPv6 are handled by kernel
    if (!isICMPv6) {
        icmpPtr->checksum = 0;
        icmpPtr->checksum = [TracerouteCommon makeChecksumFor:packet.bytes len:packet.length];
    }
    
    return packet;
}

+ (NSArray<NSString *> *)resolveHost:(NSString *)hostname {
    NSMutableArray<NSString *> *resolve = [NSMutableArray array];
    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostname);
    if (hostRef != NULL) {
        Boolean result = CFHostStartInfoResolution(hostRef, kCFHostAddresses, NULL); // start resolve DNS
        if (result == true) {
            CFArrayRef addresses = CFHostGetAddressing(hostRef, &result);
            for(int i = 0; i < CFArrayGetCount(addresses); i++){
                CFDataRef saData = (CFDataRef)CFArrayGetValueAtIndex(addresses, i);
                struct sockaddr *addressGeneric = (struct sockaddr *)CFDataGetBytePtr(saData);
                
                if (addressGeneric != NULL) {
                    if (addressGeneric->sa_family == AF_INET) {
                        struct sockaddr_in *remoteAddr = (struct sockaddr_in *)CFDataGetBytePtr(saData);
                        [resolve addObject:[self formatIPv4Address:remoteAddr->sin_addr]];
                    } else if (addressGeneric->sa_family == AF_INET6) {
                        struct sockaddr_in6 *remoteAddr = (struct sockaddr_in6 *)CFDataGetBytePtr(saData);
                        [resolve addObject:[self formatIPv6Address:remoteAddr->sin6_addr]];
                    }
                }
            }
        }
    }
    
    return [resolve copy];
}

+ (BOOL)isEchoReplyPacket:(char *)packet len:(int)len isIPv6:(BOOL)isIPv6 {
    ICMPPacket *icmpPacket = NULL;
    
    if (isIPv6) {
        icmpPacket = [TracerouteCommon unpackICMPv6Packet:packet len:len];
        if (icmpPacket != NULL && icmpPacket->type == kICMPv6TypeEchoReply) {
            return YES;
        }
    } else {
        icmpPacket = [TracerouteCommon unpackICMPv4Packet:packet len:len];
        if (icmpPacket != NULL && icmpPacket->type == kICMPv4TypeEchoReply) {
            return YES;
        }
    }
    
    return NO;
}

+ (BOOL)isTimeoutPacket:(char *)packet len:(int)len isIPv6:(BOOL)isIPv6 {
    ICMPPacket *icmpPacket = NULL;
    
    if (isIPv6) {
        icmpPacket = [TracerouteCommon unpackICMPv6Packet:packet len:len];
        if (icmpPacket != NULL && icmpPacket->type == kICMPv6TypeTimeOut) {
            return YES;
        }
    } else {
        icmpPacket = [TracerouteCommon unpackICMPv4Packet:packet len:len];
        if (icmpPacket != NULL && icmpPacket->type == kICMPv4TypeTimeOut) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Helper

// Extract ICMP from IPv4 Packet
+ (ICMPPacket *)unpackICMPv4Packet:(char *)packet len:(int)len {
    if (len < (sizeof(IPv4Header) + sizeof(ICMPPacket))) {
        return NULL;
    }
    const struct IPv4Header *ipPtr = (const IPv4Header *)packet;
    if ((ipPtr->versionAndHeaderLength & 0xF0) != 0x40 || // IPv4
        ipPtr->protocol != 1) { //ICMP
        return NULL;
    }
    
    size_t ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t); // IPv4 Head legnth
    if (len < ipHeaderLength + sizeof(ICMPPacket)) {
        return NULL;
    }
    
    return (ICMPPacket *)((char *)packet + ipHeaderLength);
}

// Extract ICMP from IPv6 Packet
// https://tools.ietf.org/html/rfc2463
+ (ICMPPacket *)unpackICMPv6Packet:(char *)packet len:(int)len {
//    if (len < (sizeof(IPv6Header) + sizeof(ICMPPacket))) {
//        return NULL;
//    }
//    const struct IPv6Header *ipPtr = (const IPv6Header *)packet;
//    if (ipPtr->nextHeader != 58) { // ICMPv6
//        return NULL;
//    }
//
//    size_t ipHeaderLength = sizeof(uint8_t) * 40; //IPv6 Head length is 40 bytes
//    if (len < ipHeaderLength + sizeof(ICMPPacket)) {
//        return NULL;
//    }
//
//    return (ICMPPacket *)((char *)packet + ipHeaderLength);
    return (ICMPPacket *)packet;
}

+ (NSUInteger)isValidIPAddress:(NSString *)inputAddr {
    
    const char *utf8 = [inputAddr UTF8String];
    char buf[16];
    if (inet_pton(AF_INET, utf8, buf)) {
        return 4;
    } else if (inet_pton(AF_INET6, utf8, buf)) {
        return 6;
    }
    return -1;
}

+ (NSString *)formatIPv6Address:(struct in6_addr)ipv6Addr {
    NSString *address = nil;
    
    char dstStr[INET6_ADDRSTRLEN];
    char srcStr[INET6_ADDRSTRLEN];
    memcpy(srcStr, &ipv6Addr, sizeof(struct in6_addr));
    if(inet_ntop(AF_INET6, srcStr, dstStr, INET6_ADDRSTRLEN) != NULL){
        address = [NSString stringWithUTF8String:dstStr];
    }
    
    return address;
}

+ (NSString *)formatIPv4Address:(struct in_addr)ipv4Addr {
    NSString *address = nil;
    
    char dstStr[INET_ADDRSTRLEN];
    char srcStr[INET_ADDRSTRLEN];
    memcpy(srcStr, &ipv4Addr, sizeof(struct in_addr));
    if(inet_ntop(AF_INET, srcStr, dstStr, INET_ADDRSTRLEN) != NULL) {
        address = [NSString stringWithUTF8String:dstStr];
    }
    
    return address;
}

@end
