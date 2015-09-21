//
//  ViewController.m
//  EasyPush
//
//  Created by Haven on 9/16/15.
//  Copyright (c) 2015 Haven. All rights reserved.
//

#import "ViewController.h"
@import CocoaAsyncSocket;

@interface ViewController() {
    dispatch_queue_t queue;
}

@property (nonatomic, strong) GCDAsyncSocket *sock;
@property (nonatomic, strong) NSString *deviceToken;
@property (nonatomic, strong) NSString *certificatePath;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSAttributedString *payload;

@property (weak) IBOutlet NSButton *ibConnectBtn;
@property (weak) IBOutlet NSButton *ibPushBtn;

@property (weak) IBOutlet NSTextField *ibTokenField;
@property (weak) IBOutlet NSTextField *ibP12PathField;
@property (weak) IBOutlet NSTextField *ibPasswordField;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.deviceToken = @"";
    self.payload = [[NSAttributedString alloc] initWithString:@"{\"aps\":{\"alert\":\"This is a push message.\",\"badge\":1}}"];
    
    // Do any additional setup after loading the view.
    queue = dispatch_queue_create("cc.ifun.socket.queue", 0);
    self.sock = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:queue];
    
    NSUserDefaultsController * theDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    self.certificatePath = [[theDefaultsController values] valueForKey:@"certificatePath"];
    self.password = [[theDefaultsController values] valueForKey:@"password"];
    self.deviceToken = [[theDefaultsController values] valueForKey:@"deviceToken"];
    self.ibConnectBtn.enabled = self.certificatePath ? YES : NO;
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#pragma mark - Private
- (void)startConnect {
    NSError *err = nil;
    NSString *host = @"gateway.sandbox.push.apple.com";
    if (![_sock connectToHost:host  onPort:2195 error:&err]) {
        NSLog(@"连接错误原因: %@",err);
    } else {
        err = nil;
    }
}

- (void)startSSL {
    
    NSMutableDictionary *sslSettings = [[NSMutableDictionary alloc] init];
    NSString *p12FilePath = self.certificatePath;
    NSURL *url = [NSURL URLWithString:p12FilePath];
    NSData *pkcs12data = [[NSData alloc] initWithContentsOfURL:url];
    CFDataRef inPKCS12Data = (CFDataRef)CFBridgingRetain(pkcs12data);
    CFStringRef password = (__bridge CFStringRef)self.password;
    const void *keys[] = { kSecImportExportPassphrase };
    const void *values[] = { password };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    
    CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
    
    OSStatus securityError = SecPKCS12Import(inPKCS12Data, options, &items);
    CFRelease(options);
    CFRelease(password);
    
    if(securityError == errSecSuccess)
        NSLog(@"Success opening p12 certificate.");
    
    CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
    SecIdentityRef myIdent = (SecIdentityRef)CFDictionaryGetValue(identityDict,
                                                                  kSecImportItemIdentity);
    
    SecIdentityRef  certArray[1] = { myIdent };
    CFArrayRef myCerts = CFArrayCreate(NULL, (void *)certArray, 1, NULL);
    
    [sslSettings setObject:(id)CFBridgingRelease(myCerts) forKey:(NSString *)kCFStreamSSLCertificates];
    [sslSettings setObject:@"gateway.sandbox.push.apple.com" forKey:(NSString *)kCFStreamSSLPeerName];
    [self.sock startTLS:sslSettings];
}

#pragma mark - Action
- (IBAction)connectApns:(id)sender {
    self.password = self.ibPasswordField.stringValue;
    self.certificatePath = self.ibP12PathField.stringValue;
    NSUserDefaultsController * theDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    [[theDefaultsController values] setValue:self.certificatePath
                                      forKey:@"certificatePath"];
    [[theDefaultsController values] setValue:self.password
                                      forKey:@"password"];
    [self startConnect];
}

- (IBAction)startPush:(id)sender {
    self.deviceToken = self.ibTokenField.stringValue;
    NSUserDefaultsController * theDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    [[theDefaultsController values] setValue:self.deviceToken
                                      forKey:@"deviceToken"];
    [self push];
}

- (IBAction)Browse:(id)sender {
    NSString *defaultPath = self.certificatePath;
    defaultPath = defaultPath ?: NSHomeDirectory();
    NSString *path = [defaultPath stringByDeletingLastPathComponent];
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setCanChooseDirectories:NO];
    [oPanel setCanChooseFiles:YES];
    [oPanel setDirectoryURL:[NSURL URLWithString:path]];
    if ([oPanel runModal] == NSModalResponseOK) {  //如果用户点OK
    }
}

- (void)push {
    
    // Convert string into device token data.
    NSMutableData *deviceToken = [NSMutableData data];
    if ([self.deviceToken length] > 64) {
        unsigned value;
        NSScanner *scanner = [NSScanner scannerWithString:self.deviceToken];
        while(![scanner isAtEnd]) {
            [scanner scanHexInt:&value];
            value = htonl(value);
            [deviceToken appendBytes:&value length:sizeof(value)];
        }
    }
    else {
        unsigned char whole_byte;
        char byte_chars[3] = {'\0','\0','\0'};
        for (int i = 0; i < ([self.deviceToken length] / 2); i++) {
            byte_chars[0] = [self.deviceToken characterAtIndex:i*2];
            byte_chars[1] = [self.deviceToken characterAtIndex:i*2+1];
            whole_byte = strtol(byte_chars, NULL, 16);
            [deviceToken appendBytes:&whole_byte length:1];
        }
    }
    
    
    // Create C input variables.
    char *deviceTokenBinary = (char *)[deviceToken bytes];
    char *payloadBinary = (char *)[[self.payload string] UTF8String];
    size_t payloadLength = strlen(payloadBinary);
    
    // Define some variables.
    uint8_t command = 0;
    char message[293];
    char *pointer = message;
    uint16_t networkTokenLength = htons(32);
    uint16_t networkPayloadLength = htons(payloadLength);
    
    // Compose message.
    memcpy(pointer, &command, sizeof(uint8_t));
    pointer += sizeof(uint8_t);
    memcpy(pointer, &networkTokenLength, sizeof(uint16_t));
    pointer += sizeof(uint16_t);
    memcpy(pointer, deviceTokenBinary, 32);
    pointer += 32;
    memcpy(pointer, &networkPayloadLength, sizeof(uint16_t));
    pointer += sizeof(uint16_t);
    memcpy(pointer, payloadBinary, payloadLength);
    pointer += payloadLength;
    
    // Send message over SSL.
    size_t len = pointer - message;
    
    NSData *data = [NSData dataWithBytes:message length:len];
    [_sock writeData:data withTimeout:30 tag:1];
    
}

#pragma mark - NSTextFieldDelegate

#pragma mark - GCDAsyncSocketDelegate
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    [self startSSL];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock {
    self.ibPushBtn.enabled = YES;
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveTrust:(SecTrustRef)trust
completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler {
    
}
@end
