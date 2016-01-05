//
//  ViewController.m
//  EasyPush
//
//  Created by Haven on 9/16/15.
//  Copyright (c) 2015 Haven. All rights reserved.
// https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/Introduction.html

#import "ViewController.h"
@import CocoaAsyncSocket;

#define Product 0

@interface ViewController() {
    dispatch_queue_t apnsQueue;
    dispatch_queue_t feedBackQueue;
    
    dispatch_source_t timer;
    NSMutableData *apnsData;
    NSMutableData *feedBackData;
}

@property (nonatomic, strong) GCDAsyncSocket *apnsSocket;
@property (nonatomic, strong) NSString *deviceToken;
@property (nonatomic, strong) NSString *certificatePath;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSAttributedString *payload;

@property (weak) IBOutlet NSButton *ibConnectBtn;
@property (weak) IBOutlet NSButton *ibPushBtn;

@property (weak) IBOutlet NSTextField *ibTokenField;
@property (weak) IBOutlet NSTextField *ibP12PathField;
@property (weak) IBOutlet NSTextField *ibPasswordField;
@property (unsafe_unretained) IBOutlet NSTextView *ibPayloadView;


@property (nonatomic, strong) NSString *apnsHost;
@property (nonatomic, assign) NSInteger apnsPort;
@property (weak) IBOutlet NSButton *ibProductCheckBox;

//status
@property (unsafe_unretained) IBOutlet NSTextView *statusView;
@property (nonatomic, strong) GCDAsyncSocket *feedBackSocket;
@property (nonatomic, strong) NSString *feedBackHost;
@property (nonatomic) NSInteger feedBackPort;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
#if Product
    self.host = @"gateway.push.apple.com";
    self.port = 2195;
    self.ibProductCheckBox.state = NSOnState;
    self.feedBackHost = @"feedback.push.apple.com";
    self.feedBackPort = 2196;
#else
    self.apnsHost = @"gateway.sandbox.push.apple.com";
    self.apnsPort = 2195;
    self.ibProductCheckBox.state = NSOffState;
    self.feedBackHost = @"feedback.sandbox.push.apple.com";
    self.feedBackPort = 2196;
#endif

    self.deviceToken = @"";
    self.payload = [[NSAttributedString alloc] initWithString:@"{\"aps\":{\"category\":\"NEW_MESSAGE_CATEGORY\",\"alert\":\"This is a push message.\",\"badge\":1}}"];
    
    // Do any additional setup after loading the view.
    apnsQueue = dispatch_queue_create("cc.ifun.socket.queue", 0);
    self.apnsSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:apnsQueue];
    
    feedBackQueue = dispatch_queue_create("cc.ifun.feedback.socket.queue", 0);
    self.feedBackSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:feedBackQueue];
    
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

- (IBAction)isProduct:(id)sender {
    NSButton *btn = (NSButton *)sender;
    if (btn.state == NSOnState) {
        self.apnsHost = @"gateway.push.apple.com";
        self.apnsPort = 2195;
        self.feedBackHost = @"feedback.push.apple.com";
        self.feedBackPort = 2196;
    }
    else {
        self.apnsHost = @"gateway.sandbox.push.apple.com";
        self.apnsPort = 2195;
        self.feedBackHost = @"feedback.sandbox.push.apple.com";
        self.feedBackPort = 2196;
    }
}

#pragma mark - Private
- (void)start {
    [self startConnectApns];
    [self setupTimer];
}

- (IBAction)connectFeedback:(id)sender {
    [self startConnectFeedback];
}

- (void)startConnectApns {
    NSError *err = nil;
    if (![_apnsSocket connectToHost:_apnsHost  onPort:_apnsPort error:&err]) {
        NSLog(@"连接Apns错误原因: %@",err);
    } else {
        err = nil;
    }
}

- (void)startConnectFeedback {
    NSError *err = nil;
    if (![_feedBackSocket connectToHost:_feedBackHost  onPort:_feedBackPort error:&err]) {
        NSLog(@"连接Feedback错误原因: %@",err);
    } else {
        err = nil;
    }
}

- (void)startSSL1 {
    
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
    [sslSettings setObject:_apnsHost forKey:(NSString *)kCFStreamSSLPeerName];
    [self.apnsSocket startTLS:sslSettings];
}

- (NSDictionary *)getSSLSetting:(NSString *)host {
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
    [sslSettings setObject:host forKey:(NSString *)kCFStreamSSLPeerName];
    
    return sslSettings;
}

- (void)startApnsSSL {
    NSDictionary *sslSettings = [self getSSLSetting:_apnsHost];
    [self.apnsSocket startTLS:sslSettings];
}

- (void)startFeedbackSSL {
    NSDictionary *sslSettings = [self getSSLSetting:_feedBackHost];
    [self.feedBackSocket startTLS:sslSettings];
}

//建立定时器接收socket
- (void)setupTimer {
    uint64_t interval = 1 * NSEC_PER_SEC;
    dispatch_queue_t timeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timeQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, 0);
    dispatch_source_set_event_handler(timer, ^()
                                      {
                                          if ([_feedBackSocket isConnected])
                                              [_feedBackSocket readDataWithTimeout:-1 tag:100];
                                          
                                          if ([_apnsSocket isConnected])
                                              [_apnsSocket readDataWithTimeout:-1 tag:100];
                                      });
    dispatch_resume(timer);
}

#pragma mark - Status
- (void)appendToStatusView:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableAttributedString *originalText = [[NSMutableAttributedString alloc] initWithAttributedString:_statusView.attributedString];
        NSAttributedString *appendText = [[NSAttributedString alloc] initWithString:text
                                                                         attributes:@{NSForegroundColorAttributeName:[NSColor redColor]}];
        

        
        if (originalText.length) {
            NSAttributedString *last = [originalText attributedSubstringFromRange:NSMakeRange(originalText.length - 1, 1)];
            if (![[last string] isEqualToString:@"\n"]) {
                [originalText appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            }
        }
        
        [originalText appendAttributedString:appendText];
        [[_statusView textStorage] setAttributedString:originalText];
    });
}

#pragma mark - Action
- (IBAction)connect:(id)sender {
    self.password = self.ibPasswordField.stringValue;
    self.certificatePath = self.ibP12PathField.stringValue;
    NSUserDefaultsController * theDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    [[theDefaultsController values] setValue:self.certificatePath forKey:@"certificatePath"];
    [[theDefaultsController values] setValue:self.password forKey:@"password"];
    [self start];
}

- (IBAction)close:(id)sender {
    [self.apnsSocket disconnect];
    [self.feedBackSocket disconnect];
}

- (IBAction)startPush:(id)sender {
    self.deviceToken = self.ibTokenField.stringValue;
    NSUserDefaultsController * theDefaultsController = [NSUserDefaultsController sharedUserDefaultsController];
    [[theDefaultsController values] setValue:self.deviceToken
                                      forKey:@"deviceToken"];
    
    NSString *s = self.ibPayloadView.string;
    self.payload = [[NSAttributedString alloc] initWithString:s];
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
        self.ibP12PathField.stringValue = [[[oPanel URLs] objectAtIndex:0] absoluteString];
        self.ibConnectBtn.enabled = YES;
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
    [_apnsSocket writeData:data withTimeout:30 tag:1];
    
}

#pragma mark - NSTextFieldDelegate

#pragma mark - GCDAsyncSocketDelegate
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    if (sock == _apnsSocket) {
        [self startApnsSSL];
        [self appendToStatusView:@"连接APNS服务器成功"];
    }
    else {
        [self startFeedbackSSL];
        [self appendToStatusView:@"连接Feedback服务器成功"];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (sock == _apnsSocket) {
        self.ibPushBtn.enabled = NO;
        [self appendToStatusView:@"与APNS服务器连接断开"];
    }
    else {
        [self appendToStatusView:@"与Feedback服务器连接断开"];
    }
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock {
    if (sock == _apnsSocket) {
        self.ibPushBtn.enabled = YES;
        [self appendToStatusView:@"Apns SSL连接成功"];
    }
    else {
        [self appendToStatusView:@"Feedback SSL连接成功"];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    if (sock == _apnsSocket) {
        [self appendToStatusView:@"推送消息发送到Apns成功"];
    }
}

-(void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (sock == _feedBackSocket) {
        UInt32 timeStamp;
        NSInteger location = 0;
        [data getBytes:&timeStamp range:NSMakeRange(location, sizeof(UInt32))];
        location += sizeof(UInt32);
        NSInteger timestamp = CFSwapInt32BigToHost(timeStamp);
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:timeStamp];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
        NSString *formatTime = [dateFormatter stringFromDate:date];
        
        UInt16 length;
        [data getBytes:&length range:NSMakeRange(location, sizeof(UInt16))];
        location += sizeof(UInt16);
        NSInteger deviceTokenLen = CFSwapInt16BigToHost(length);
        
        NSData *device = [data subdataWithRange:NSMakeRange(location, deviceTokenLen)];
        NSString* deviceToken = [[device description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
        deviceToken = [deviceToken stringByReplacingOccurrencesOfString:@" " withString:@""];
        NSLog(@"Recv failed token:%@", deviceToken);
    }
    else if (_apnsSocket == sock) {
        NSInteger location = 0;
        UInt8 command;
        [data getBytes:&command range:NSMakeRange(location, sizeof(UInt8))];
        location += sizeof(UInt8);
        
        NSInteger cmd = command;
        if (8 == cmd) {
            //error package
            UInt8 code;
            [data getBytes:&code range:NSMakeRange(location, sizeof(UInt8))];
            location += sizeof(UInt8);
            NSInteger status = code;
            NSString *msg;
            switch (status) {
                case 0:
                    msg = @"No errors encountered";
                    break;
                case 1:
                    msg = @"Processing error";
                    break;
                case 2:
                    msg = @"Missing device token";
                    break;
                case 3:
                    msg = @"Missing topic";
                    break;
                case 4:
                    msg = @"Missing payload";
                    break;
                case 5:
                    msg = @"Invalid token size";
                    break;
                case 6:
                    msg = @"Invalid topic size";
                    break;
                case 7:
                    msg = @"Invalid payload size";
                    break;
                case 8:
                    msg = @"Invalid token";
                    break;
                case 10:
                    msg = @"Shutdown";
                    break;
                case 255:
                    msg = @"None (unknown)";
                    break;
                default:
                    break;
            }
            if (msg) {
                [self appendToStatusView:msg];
            }
            
            NSData *identifierData = [data subdataWithRange:NSMakeRange(location, 4)];
            NSString *identifier = [[NSString alloc] initWithData:identifierData encoding:NSUTF8StringEncoding];
            
        }
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveTrust:(SecTrustRef)trust
completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler {
    
}
@end
