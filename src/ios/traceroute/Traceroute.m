//
//  Traceroute.m
//  TracerouteDemo
//
//  Created by LZephyr on 2018/2/8.
//  Copyright © 2018 LZephyr. All rights reserved.
//

#import "Traceroute.h"
#import "TracerouteCommon.h"

#define kTraceStepMaxAttempts 3 // max attempts for each node
#define kTraceRoutePort 20000 // port no of traceroute
#define kTraceMaxJump 30 // default max hops

@interface Traceroute()

@property (nonatomic) NSString *ipAddress; // IP address to be resolved
@property (nonatomic) NSString *hostname;
@property (nonatomic) NSInteger maxTtl; // max time-to-live
@property (nonatomic) NSMutableArray<TracerouteRecord *>* results;

@property (nonatomic) TracerouteStepCallback stepCallback;
@property (nonatomic) TracerouteFinishCallback finishCallback;

@end

@implementation Traceroute

+ (instancetype)startTracerouteWithHost:(NSString *)host
                                  maxTtl:(NSInteger)maxTtl
                           stepCallback:(TracerouteStepCallback)stepCallback
                                 finish:(TracerouteFinishCallback)finish {
    return [Traceroute startTracerouteWithHost:host
                                        maxTtl:maxTtl
                                         queue:nil
                                  stepCallback:stepCallback
                                        finish:finish];
}

+ (instancetype)startTracerouteWithHost:(NSString *)host
                                  maxTtl:(NSInteger)maxTtl
                                  queue:(dispatch_queue_t)queue
                           stepCallback:(TracerouteStepCallback)stepCallback
                                 finish:(TracerouteFinishCallback)finish {
    Traceroute *traceroute = [[Traceroute alloc] initWithHost:host maxTtl:maxTtl stepCallback:stepCallback finish:finish];
    if (queue != nil) {
        dispatch_async(queue, ^{
            [traceroute run];
        });
    } else {
        [traceroute run];
    }
    return traceroute;
}

- (instancetype)initWithHost:(NSString*)host
                      maxTtl:(NSInteger)maxTtl
                stepCallback:(TracerouteStepCallback)stepCallback
                      finish:(TracerouteFinishCallback)finish {
    if (self = [super init]) {
        _hostname = host;
        _maxTtl = maxTtl;
        _stepCallback = stepCallback;
        _finishCallback = finish;
        _results = [[NSMutableArray alloc] init];
    }
    return self;
}

#pragma mark - Private

- (void)run {
    NSLog(@"HostName is: %@", _hostname);
    
    NSUInteger isValidIp = [TracerouteCommon isValidIPAddress:_hostname];
    if (isValidIp != -1) {
        NSLog(@"Input address is %@", (isValidIp == 4 ? @"IPv4" : @"IPv6"));
        _ipAddress = _hostname;
        
    } else {
        NSArray *addresses = [TracerouteCommon resolveHost:_hostname];
        if (addresses.count == 0) {
            NSLog(@"DNS resolve failed");
            return;
        }
        
        _ipAddress = [addresses firstObject];
        // get the first IP if domain contains multiple IPs
        if (addresses.count > 0) {
            NSLog(@"%@ has multiple addresses, using %@", _hostname, _ipAddress);
        }
    }
    
    BOOL isIPv6 = [_ipAddress rangeOfString:@":"].location != NSNotFound;
    // resolve destination IP address
    struct sockaddr *remoteAddr = [TracerouteCommon makeSockaddrWithAddress:_ipAddress
                                                                       port:(int)kTraceRoutePort
                                                                     isIPv6:isIPv6];
    
    
    if (remoteAddr == NULL) {
        return;
    }
    
    // create socket
    int send_sock;
    if ((send_sock = socket(remoteAddr->sa_family,
                            SOCK_DGRAM,
                            isIPv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)) < 0) {
        NSLog(@"Create socket failure");
        return;
    }
    
    // set timeout to 3 sec
    struct timeval timeout;
    timeout.tv_sec = 3;
    timeout.tv_usec = 0;
    setsockopt(send_sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    
    int ttl = 1;
    BOOL succeed = NO;
    do {
        // set TTL for each packet, increament by 1
        if (setsockopt(send_sock,
                       isIPv6 ? IPPROTO_IPV6 : IPPROTO_IP,
                       isIPv6 ? IPV6_UNICAST_HOPS : IP_TTL,
                       &ttl,
                       sizeof(ttl)) < 0) {
            NSLog(@"setsockopt failure");
        }
        succeed = [self sendAndRecv:send_sock addr:remoteAddr ttl:ttl];
    } while (++ttl <= _maxTtl && !succeed);
    
    close(send_sock);
    
    // traceroute finished，callback result
    if (_finishCallback) {
        _finishCallback([_results copy], succeed);
    }
}

/**
 Send 3 packets to each node

 @param sendSock socket for sending
 @param addr     each node address
 @param ttl      time-to-live
 @return Boolean, YES if reached destination, otherwise NO
 */
- (BOOL)sendAndRecv:(int)sendSock
               addr:(struct sockaddr *)addr
                ttl:(int)ttl {
    char buff[200];
    BOOL finished = NO;
    BOOL isIPv6 = [_ipAddress rangeOfString:@":"].location != NSNotFound;
    socklen_t addrLen = isIPv6 ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
    
    // construct ICMP packet
    uint16_t identifier = (uint16_t)ttl;
    NSData *packetData = [TracerouteCommon makeICMPPacketWithID:identifier
                                                       sequence:ttl
                                                       isICMPv6:isIPv6];
    
    // record result
    TracerouteRecord *record = [[TracerouteRecord alloc] init];
    record.ttl = ttl;
    
    BOOL receiveReply = NO;
    NSMutableArray *durations = [[NSMutableArray alloc] init];
    
    // send 3 ICMP packet, and record round-trip time
    for (int try = 0; try < kTraceStepMaxAttempts; try ++) {
        NSDate* startTime = [NSDate date];
        // send packet
        ssize_t sent = sendto(sendSock,
                              packetData.bytes,
                              packetData.length,
                              0,
                              addr,
                              addrLen);
        if (sent < 0) {
            NSLog(@"Send failed: %s", strerror(errno));
            [durations addObject:[NSNull null]];
            continue;
        }
        
        // receive ICMP packet
        struct sockaddr remoteAddr;
        ssize_t resultLen = recvfrom(sendSock, buff, sizeof(buff), 0, (struct sockaddr*)&remoteAddr, &addrLen);
        if (resultLen < 0) {
            // fail and retry
            [durations addObject:[NSNull null]];
            continue;
        } else {
            receiveReply = YES;
            NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
            
            // resolve IP address
            NSString* remoteAddress = nil;
            if (!isIPv6) {
                char ip[INET_ADDRSTRLEN] = {0};
                inet_ntop(AF_INET, &((struct sockaddr_in *)&remoteAddr)->sin_addr.s_addr, ip, sizeof(ip));
                remoteAddress = [NSString stringWithUTF8String:ip];
            } else {
                char ip[INET6_ADDRSTRLEN] = {0};
                inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&remoteAddr)->sin6_addr, ip, INET6_ADDRSTRLEN);
                remoteAddress = [NSString stringWithUTF8String:ip];
            }
            
            // determine result
            if ([TracerouteCommon isTimeoutPacket:buff len:(int)resultLen isIPv6:isIPv6]) {
                // reached node
                [durations addObject:@(duration)];
                record.ip = remoteAddress;
            } else if ([TracerouteCommon isEchoReplyPacket:buff len:(int)resultLen isIPv6:isIPv6] && [remoteAddress isEqualToString:_ipAddress]) {
                // reached destination
                [durations addObject:@(duration)];
                record.ip = remoteAddress;
                finished = YES;
            } else {
                // failure
                [durations addObject:[NSNull null]];
            }
        }
    }
    record.recvDurations = [durations copy];
    [_results addObject:record];
    
    // callBack for each result
    if (_stepCallback) {
        _stepCallback(record);
    }
    NSLog(@"%@", record);
    
    return finished;
}

- (BOOL)validateReply {
    return YES;
}

@end
