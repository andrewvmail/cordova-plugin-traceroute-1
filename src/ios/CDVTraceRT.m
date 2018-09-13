#import "CDVTraceRT.h"
#import "Traceroute.h"

@interface CDVTraceRT()

@property (nonatomic, strong) NSString *host;
@property NSInteger maxTtl;


@property (nonatomic, strong) CDVPluginResult* pluginResult;
@property (nonatomic, strong) CDVInvokedUrlCommand* cmd;

@end

@implementation CDVTraceRT

- (void)startTrace:(CDVInvokedUrlCommand*)cmd
{
    self.cmd = cmd;
    self.host = [cmd.arguments objectAtIndex:0];
    self.maxTtl = [[cmd.arguments objectAtIndex:1] integerValue];
    
    [Traceroute startTracerouteWithHost:self.host
                                 maxTtl:self.maxTtl
                                  queue:dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)
                           stepCallback:^(TracerouteRecord *record) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:record.description];
                                   [self.pluginResult setKeepCallbackAsBool:YES];
                                   [self.commandDelegate sendPluginResult: self.pluginResult callbackId: self.cmd.callbackId];
                               });
                           } finish:^(NSArray<TracerouteRecord *> *results, BOOL succeed) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   // NSString *prettyResult = [self toPrettyResult:results];
                                   if (succeed) {
                                       NSLog(@"> Traceroute Success!");
                                       // NSString *output = [NSString stringWithFormat:@"%@", prettyResult];
                                       self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"> Traceroute Success!"];
                                   } else {
                                       NSLog(@"> Traceroute Failure!");
                                       //  NSString *output = [NSString stringWithFormat:@"%@", prettyResult];
                                       self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"> Traceroute Failure!"];
                                   }
                                   [self.pluginResult setKeepCallbackAsBool:NO];
                                   [self.commandDelegate sendPluginResult: self.pluginResult callbackId: self.cmd.callbackId];
                               });
                           }];
}

- (NSString *)toPrettyResult:(NSArray<TracerouteRecord *>*) results
{
    NSUInteger max = results.count;
    
    NSMutableString *output = [NSMutableString string];
    [output appendString:@"\n"];
    
    for (int i = 0; i < max; i++) {
        [output appendString:results[i].description];
        [output appendString:@"\n"];
    }
    
    return [NSString stringWithString:output];
}

@end
