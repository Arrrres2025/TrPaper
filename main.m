#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const TrPaperVersion = @"3.2.0";
static NSString *const TrPaperKeychainService = @"com.essaypod.trpaper.deepseek";

static NSString *LoadDeepSeekAPIKey(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: TrPaperKeychainService,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSData *data = CFBridgingRelease(result);
        NSString *key = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (key.length) return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    NSString *environmentKey = NSProcessInfo.processInfo.environment[@"DEEPSEEK_API_KEY"];
    return [environmentKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

@protocol TrPaperDropDelegate <NSObject>
- (void)didDropPDFAtURL:(NSURL *)url;
@end

@interface DropZoneView : NSView <NSDraggingDestination>
@property(nonatomic, weak) id<TrPaperDropDelegate> dropDelegate;
@property(nonatomic, strong) NSTextField *headline;
@property(nonatomic, strong) NSTextField *detail;
@property(nonatomic, assign) BOOL highlighted;
@end

@implementation DropZoneView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 18.0;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [NSColor colorWithWhite:0.82 alpha:1].CGColor;
    self.layer.backgroundColor = [NSColor colorWithWhite:0.975 alpha:1].CGColor;
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

    self.headline = [NSTextField labelWithString:@"拖入论文 PDF"];
    self.headline.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    self.headline.textColor = [NSColor colorWithWhite:0.15 alpha:1];
    self.headline.alignment = NSTextAlignmentCenter;
    [self addSubview:self.headline];

    self.detail = [NSTextField labelWithString:@"或点击下方按钮选择文件"];
    self.detail.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    self.detail.textColor = [NSColor colorWithWhite:0.48 alpha:1];
    self.detail.alignment = NSTextAlignmentCenter;
    [self addSubview:self.detail];
    return self;
}

- (void)layout {
    [super layout];
    CGFloat width = self.bounds.size.width;
    self.headline.frame = NSMakeRect(20, self.bounds.size.height / 2 + 3, width - 40, 28);
    self.detail.frame = NSMakeRect(20, self.bounds.size.height / 2 - 25, width - 40, 20);
}

- (BOOL)containsPDF:(id<NSDraggingInfo>)sender {
    NSURL *url = [NSURL URLFromPasteboard:sender.draggingPasteboard];
    return url && [url.pathExtension.lowercaseString isEqualToString:@"pdf"];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (![self containsPDF:sender]) return NSDragOperationNone;
    self.highlighted = YES;
    self.layer.borderColor = [NSColor colorWithRed:0.18 green:0.55 blue:0.72 alpha:1].CGColor;
    self.layer.backgroundColor = [NSColor colorWithRed:0.93 green:0.97 blue:0.99 alpha:1].CGColor;
    return NSDragOperationCopy;
}

- (void)draggingExited:(nullable id<NSDraggingInfo>)sender {
    self.highlighted = NO;
    self.layer.borderColor = [NSColor colorWithWhite:0.82 alpha:1].CGColor;
    self.layer.backgroundColor = [NSColor colorWithWhite:0.975 alpha:1].CGColor;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSURL *url = [NSURL URLFromPasteboard:sender.draggingPasteboard];
    [self draggingExited:nil];
    if (!url || ![url.pathExtension.lowercaseString isEqualToString:@"pdf"]) return NO;
    [self.dropDelegate didDropPDFAtURL:url];
    return YES;
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, TrPaperDropDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) DropZoneView *dropZone;
@property(nonatomic, strong) NSButton *chooseButton;
@property(nonatomic, strong) NSButton *translateButton;
@property(nonatomic, strong) NSButton *revealButton;
@property(nonatomic, strong) NSButton *resetButton;
@property(nonatomic, strong) NSTextField *fileLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *usageLabel;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURL *selectedPDF;
@property(nonatomic, strong) NSURL *outputPDF;
@property(nonatomic, copy) NSString *apiKey;
@property(nonatomic, strong) NSTask *workerTask;
@property(nonatomic, strong) NSMutableData *workerBuffer;
@property(nonatomic, copy) NSString *pendingWorkerError;
@property(nonatomic, assign) BOOL working;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 120;
    configuration.timeoutIntervalForResource = 60 * 60;
    configuration.HTTPAdditionalHeaders = @{@"User-Agent": [NSString stringWithFormat:@"TrPaper/%@", TrPaperVersion]};
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                 delegate:self
                                            delegateQueue:NSOperationQueue.mainQueue];
    self.apiKey = [self loadAPIKey];
    if (self.apiKey.length == 0) {
        [self setStatus:@"未找到 DeepSeek API 密钥，请重新运行构建脚本。" error:YES];
        self.chooseButton.enabled = NO;
    } else {
        [self checkUsage];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action primary:(BOOL)primary {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeLarge;
    if (@available(macOS 11.0, *)) {
        button.bezelColor = primary ? [NSColor colorWithRed:0.12 green:0.34 blue:0.48 alpha:1] : nil;
    }
    button.keyEquivalent = primary ? @"\r" : @"";
    return button;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 720, 570);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"TrPaper";
    self.window.titlebarAppearsTransparent = YES;
    self.window.movableByWindowBackground = YES;
    self.window.backgroundColor = [NSColor colorWithWhite:0.965 alpha:1];
    [self.window center];

    NSView *content = self.window.contentView;
    NSTextField *eyebrow = [self label:@"TRPAPER · DEEPSEEK FLASH" size:11 weight:NSFontWeightBold color:[NSColor colorWithRed:0.18 green:0.55 blue:0.72 alpha:1]];
    eyebrow.frame = NSMakeRect(48, 505, 180, 18);
    [content addSubview:eyebrow];
    NSTextField *title = [self label:@"论文翻译，就这一件事。" size:28 weight:NSFontWeightSemibold color:[NSColor colorWithWhite:0.10 alpha:1]];
    title.frame = NSMakeRect(48, 461, 500, 40);
    [content addSubview:title];
    NSTextField *subtitle = [self label:@"识别论文版面，DeepSeek 分段翻译，并写回原始 PDF。" size:13 weight:NSFontWeightRegular color:[NSColor colorWithWhite:0.44 alpha:1]];
    subtitle.frame = NSMakeRect(49, 434, 590, 22);
    [content addSubview:subtitle];

    self.dropZone = [[DropZoneView alloc] initWithFrame:NSMakeRect(48, 205, 624, 205)];
    self.dropZone.dropDelegate = self;
    [content addSubview:self.dropZone];

    self.chooseButton = [self button:@"选择 PDF" action:@selector(choosePDF:) primary:NO];
    self.chooseButton.frame = NSMakeRect(48, 151, 132, 38);
    [content addSubview:self.chooseButton];
    self.fileLabel = [self label:@"尚未选择文件" size:12 weight:NSFontWeightMedium color:[NSColor colorWithWhite:0.38 alpha:1]];
    self.fileLabel.frame = NSMakeRect(196, 157, 475, 22);
    [content addSubview:self.fileLabel];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(48, 121, 624, 6)];
    self.progress.style = NSProgressIndicatorStyleBar;
    self.progress.indeterminate = NO;
    self.progress.minValue = 0;
    self.progress.maxValue = 100;
    self.progress.doubleValue = 0;
    [content addSubview:self.progress];

    self.statusLabel = [self label:@"准备就绪" size:12 weight:NSFontWeightRegular color:[NSColor colorWithWhite:0.42 alpha:1]];
    self.statusLabel.frame = NSMakeRect(48, 87, 470, 22);
    [content addSubview:self.statusLabel];
    self.usageLabel = [self label:@"正在连接 DeepSeek…" size:10 weight:NSFontWeightRegular color:[NSColor colorWithWhite:0.55 alpha:1]];
    self.usageLabel.alignment = NSTextAlignmentRight;
    self.usageLabel.frame = NSMakeRect(420, 88, 252, 18);
    [content addSubview:self.usageLabel];

    self.translateButton = [self button:@"开始翻译" action:@selector(startTranslation:) primary:YES];
    self.translateButton.frame = NSMakeRect(48, 32, 160, 42);
    self.translateButton.enabled = NO;
    [content addSubview:self.translateButton];
    self.revealButton = [self button:@"在 Finder 中显示" action:@selector(revealOutput:) primary:NO];
    self.revealButton.frame = NSMakeRect(222, 32, 168, 42);
    self.revealButton.hidden = YES;
    [content addSubview:self.revealButton];
    self.resetButton = [self button:@"翻译另一篇" action:@selector(reset:) primary:NO];
    self.resetButton.frame = NSMakeRect(404, 32, 132, 42);
    self.resetButton.hidden = YES;
    [content addSubview:self.resetButton];

    NSTextField *billing = [self label:@"本机版面识别 · 3 路并行翻译 · 保留图片与公式" size:9 weight:NSFontWeightRegular color:[NSColor colorWithWhite:0.62 alpha:1]];
    billing.alignment = NSTextAlignmentRight;
    billing.frame = NSMakeRect(430, 43, 242, 16);
    [content addSubview:billing];
}

- (NSString *)loadAPIKey {
    return LoadDeepSeekAPIKey();
}

- (NSString *)apiBaseURL {
    return @"https://api.deepseek.com";
}

- (NSMutableURLRequest *)requestForPath:(NSString *)path method:(NSString *)method {
    NSURL *URL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", self.apiBaseURL, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.HTTPMethod = method;
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];
    return request;
}

- (void)checkUsage {
    NSMutableURLRequest *request = [self requestForPath:@"/models" method:@"GET"];
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *HTTP = (NSHTTPURLResponse *)response;
        if (error || HTTP.statusCode != 200) {
            self.usageLabel.stringValue = @"DeepSeek 连接失败";
            return;
        }
        NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *models = JSON[@"data"];
        BOOL found = NO;
        for (NSDictionary *model in models) if ([model[@"id"] isEqualToString:@"deepseek-flash"]) found = YES;
        self.usageLabel.stringValue = found ? @"DeepSeek Flash 已连接" : @"DeepSeek 已连接";
    }];
    [task resume];
}

- (void)choosePDF:(id)sender {
    if (self.working) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowedContentTypes = @[UTTypePDF];
    panel.prompt = @"选择论文";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) [self selectPDF:panel.URL];
    }];
}

- (void)didDropPDFAtURL:(NSURL *)url { [self selectPDF:url]; }

- (void)selectPDF:(NSURL *)url {
    if (self.working) return;
    NSNumber *size = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (![url.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        [self setStatus:@"请选择 PDF 文件。" error:YES];
        return;
    }
    NSUInteger maxBytes = 200 * 1024 * 1024;
    if (size.unsignedIntegerValue > maxBytes) {
        [self setStatus:[NSString stringWithFormat:@"文件过大：当前账户单个 PDF 上限为 %lu MB。", maxBytes / 1024 / 1024] error:YES];
        return;
    }
    NSData *prefix = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (prefix.length < 5 || memcmp(prefix.bytes, "%PDF-", 5) != 0) {
        [self setStatus:@"这个文件不是有效的 PDF。" error:YES];
        return;
    }
    self.selectedPDF = url;
    self.outputPDF = nil;
    self.fileLabel.stringValue = [NSString stringWithFormat:@"%@ · %.1f MB", url.lastPathComponent, size.doubleValue / 1024.0 / 1024.0];
    self.dropZone.headline.stringValue = @"论文已就绪";
    self.dropZone.detail.stringValue = @"可重新拖入另一份 PDF 替换";
    self.translateButton.enabled = YES;
    self.revealButton.hidden = YES;
    self.resetButton.hidden = YES;
    self.progress.doubleValue = 0;
    [self setStatus:@"点击“开始翻译”后进行本地版面识别和分段翻译。" error:NO];
}

- (void)startTranslation:(id)sender {
    if (!self.selectedPDF || self.working) return;
    self.working = YES;
    self.translateButton.enabled = NO;
    self.chooseButton.enabled = NO;
    self.progress.indeterminate = NO;
    self.progress.doubleValue = 2;
    self.workerBuffer = [NSMutableData data];
    self.pendingWorkerError = nil;
    [self setStatus:@"正在启动原版式翻译引擎…" error:NO];

    NSString *resources = NSBundle.mainBundle.resourcePath;
    NSString *worker = [resources stringByAppendingPathComponent:@"TrPaperWorker/TrPaperWorker"];
    NSString *model = [resources stringByAppendingPathComponent:@"TranslationResources/doclayout.onnx"];
    NSString *font = [resources stringByAppendingPathComponent:@"TranslationResources/SourceHanSerifCN-Regular.ttf"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:worker] ||
        ![NSFileManager.defaultManager fileExistsAtPath:model] ||
        ![NSFileManager.defaultManager fileExistsAtPath:font]) {
        [self finishWithError:@"翻译引擎资源不完整，请重新安装 TrPaper。"];
        return;
    }

    NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *stem = self.selectedPDF.lastPathComponent.stringByDeletingPathExtension;
    NSString *name = [NSString stringWithFormat:@"%@-deepseek-layout-zh.pdf", stem];
    NSURL *destination = [downloads URLByAppendingPathComponent:name];
    NSInteger suffix = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) {
        name = [NSString stringWithFormat:@"%@-deepseek-layout-zh-%ld.pdf", stem, (long)suffix++];
        destination = [downloads URLByAppendingPathComponent:name];
    }
    self.outputPDF = destination;

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:worker];
    task.arguments = @[@"--input", self.selectedPDF.path,
                       @"--output", destination.path,
                       @"--model", model,
                       @"--font", font,
                       @"--threads", @"3"];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"DEEPSEEK_API_KEY"] = self.apiKey;
    task.environment = environment;

    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;
    __weak typeof(self) weakSelf = self;
    outputPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) return;
        [weakSelf consumeWorkerData:data];
    };
    errorPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) return;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length) NSLog(@"TrPaper worker: %@", text);
    };
    task.terminationHandler = ^(NSTask *finishedTask) {
        outputPipe.fileHandleForReading.readabilityHandler = nil;
        errorPipe.fileHandleForReading.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf flushWorkerBuffer];
            strongSelf.workerTask = nil;
            if (finishedTask.terminationStatus == 0 && [strongSelf isValidPDF:strongSelf.outputPDF]) {
                [strongSelf finishWorkerSuccess];
            } else {
                NSString *message = strongSelf.pendingWorkerError ?: [NSString stringWithFormat:@"原版式翻译失败（代码 %d）。", finishedTask.terminationStatus];
                [strongSelf finishWithError:message];
            }
        });
    };
    self.workerTask = task;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        self.workerTask = nil;
        [self finishWithError:[NSString stringWithFormat:@"无法启动翻译引擎：%@", launchError.localizedDescription]];
    }
}

- (void)consumeWorkerData:(NSData *)data {
    @synchronized (self.workerBuffer) {
        [self.workerBuffer appendData:data];
        while (YES) {
            const void *bytes = self.workerBuffer.bytes;
            NSUInteger length = self.workerBuffer.length;
            const void *newline = memchr(bytes, '\n', length);
            if (!newline) break;
            NSUInteger lineLength = (const uint8_t *)newline - (const uint8_t *)bytes;
            NSData *lineData = [self.workerBuffer subdataWithRange:NSMakeRange(0, lineLength)];
            [self.workerBuffer replaceBytesInRange:NSMakeRange(0, lineLength + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line.length) dispatch_async(dispatch_get_main_queue(), ^{ [self processWorkerLine:line]; });
        }
    }
}

- (void)flushWorkerBuffer {
    @synchronized (self.workerBuffer) {
        if (self.workerBuffer.length == 0) return;
        NSString *line = [[NSString alloc] initWithData:self.workerBuffer encoding:NSUTF8StringEncoding];
        [self.workerBuffer setLength:0];
        if (line.length) [self processWorkerLine:line];
    }
}

- (void)processWorkerLine:(NSString *)line {
    if (![line hasPrefix:@"TRPAPER_EVENT "]) return;
    NSData *data = [[line substringFromIndex:14] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *event = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![event isKindOfClass:NSDictionary.class]) return;
    NSString *kind = event[@"kind"];
    NSString *message = event[@"message"];
    NSNumber *progress = event[@"progress"];
    if (progress) self.progress.doubleValue = progress.doubleValue;
    if ([kind isEqualToString:@"stage"] || [kind isEqualToString:@"progress"]) {
        [self setStatus:message ?: @"正在翻译…" error:NO];
    } else if ([kind isEqualToString:@"error"]) {
        self.pendingWorkerError = message ?: @"原版式翻译失败。";
    }
}

- (BOOL)isValidPDF:(NSURL *)URL {
    if (!URL) return NO;
    NSData *prefix = [NSData dataWithContentsOfURL:URL options:NSDataReadingMappedIfSafe error:nil];
    return prefix.length >= 5 && memcmp(prefix.bytes, "%PDF-", 5) == 0;
}

- (void)finishWorkerSuccess {
    self.working = NO;
    self.progress.indeterminate = NO;
    [self.progress stopAnimation:nil];
    self.progress.doubleValue = 100;
    self.revealButton.hidden = NO;
    self.resetButton.hidden = NO;
    self.chooseButton.enabled = YES;
    [self setStatus:[NSString stringWithFormat:@"已保存原版式译文：%@", self.outputPDF.lastPathComponent] error:NO];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.outputPDF]];
}

- (void)failWithData:(NSData *)data response:(NSHTTPURLResponse *)response error:(NSError *)error fallback:(NSString *)fallback {
    NSString *message = error.localizedDescription;
    if (!message && data.length) {
        NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        message = JSON[@"error"][@"message"] ?: JSON[@"message"] ?: JSON[@"detail"];
    }
    switch (response.statusCode) {
        case 401: message = @"DeepSeek API 密钥无效，请检查密钥。"; break;
        case 402: message = @"DeepSeek 账户余额不足，请先充值。"; break;
        case 408: message = @"PDF 上传或解析超时，请重试。"; break;
        case 413: message = @"PDF 超过 DeepSeek 的 100 MB 或页数限制。"; break;
        case 429: message = @"DeepSeek 当前请求过多，请稍后重试。"; break;
        case 503: message = @"DeepSeek 服务繁忙，请稍后重试。"; break;
        case 504: message = @"DeepSeek 文档解析超时，请重试。"; break;
        default: break;
    }
    NSString *trace = response.allHeaderFields[@"x-trace-id"] ?: response.allHeaderFields[@"X-Trace-ID"];
    if (trace.length) message = [NSString stringWithFormat:@"%@（Trace: %@）", message ?: fallback, trace];
    [self finishWithError:message ?: fallback];
}

- (void)finishWithError:(NSString *)message {
    self.working = NO;
    self.progress.indeterminate = NO;
    [self.progress stopAnimation:nil];
    self.progress.doubleValue = 0;
    self.chooseButton.enabled = YES;
    self.translateButton.enabled = self.selectedPDF != nil;
    [self setStatus:message error:YES];
}

- (void)setStatus:(NSString *)message error:(BOOL)error {
    self.statusLabel.stringValue = message ?: @"";
    self.statusLabel.textColor = error ? [NSColor colorWithRed:0.72 green:0.18 blue:0.18 alpha:1] : [NSColor colorWithWhite:0.42 alpha:1];
}

- (void)revealOutput:(id)sender {
    if (self.outputPDF) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.outputPDF]];
}

- (void)reset:(id)sender {
    if (self.working) return;
    self.selectedPDF = nil;
    self.outputPDF = nil;
    self.pendingWorkerError = nil;
    self.workerBuffer = nil;
    self.fileLabel.stringValue = @"尚未选择文件";
    self.dropZone.headline.stringValue = @"拖入论文 PDF";
    self.dropZone.detail.stringValue = @"或点击下方按钮选择文件";
    self.translateButton.enabled = NO;
    self.revealButton.hidden = YES;
    self.resetButton.hidden = YES;
    self.progress.doubleValue = 0;
    [self setStatus:@"准备就绪" error:NO];
}
@end

static int RunSelfTest(void) {
    NSString *key = LoadDeepSeekAPIKey();
    if (key.length == 0) {
        fprintf(stderr, "TrPaper self-test: missing API key\n");
        return 2;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.deepseek.com/models"]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block int result = 1;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *HTTP = (NSHTTPURLResponse *)response;
        if (!error && HTTP.statusCode == 200 && data.length > 0) {
            NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            BOOL found = NO;
            for (NSDictionary *model in JSON[@"data"]) if ([model[@"id"] isEqualToString:@"deepseek-flash"]) found = YES;
            printf("TrPaper self-test: DeepSeek connected, deepseek-flash %s\n", found ? "available" : "not listed");
            result = found ? 0 : 3;
        } else {
            fprintf(stderr, "TrPaper self-test: DeepSeek connection failed (%ld)\n", (long)HTTP.statusCode);
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return RunSelfTest();
        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyRegular;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}

