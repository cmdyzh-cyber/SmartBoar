#import <AppKit/AppKit.h>
@interface Canvas : NSView @end
@implementation Canvas
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect { [NSColor.windowBackgroundColor setFill]; NSRectFill(rect); }
@end
static NSString *control=@"/Library/Printers/LegacyPrint/Core/legacyprintctl";
@interface App : NSObject <NSApplicationDelegate>
@property NSWindow *window; @property NSTextField *status; @property NSPopUpButton *picker;
@property NSTextView *detail; @property NSArray<NSDictionary *> *rows;
@property NSMutableArray<NSButton *> *buttons; @property NSButton *setupButton,*testButton,*clearButton,*restoreButton;
@property NSString *previewPath; @property BOOL busy; @property NSDate *holdUntil;
@end
@implementation App
- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *v=[NSTextField wrappingLabelWithString:text]; v.font=bold ? [NSFont systemFontOfSize:size weight:NSFontWeightSemibold]:[NSFont systemFontOfSize:size]; return v;
}
- (NSButton *)button:(NSString *)text action:(SEL)action stack:(NSStackView *)stack {
    NSButton *b=[NSButton buttonWithTitle:text target:self action:action]; b.bezelStyle=NSBezelStyleRounded; [self.buttons addObject:b]; [stack addArrangedSubview:b]; return b;
}
- (NSDictionary *)selected { NSInteger i=self.picker.indexOfSelectedItem; return i>=0 && i<(NSInteger)self.rows.count ? self.rows[i]:nil; }
- (void)updateButtons {
    for(NSButton *b in self.buttons) b.enabled=!self.busy; self.picker.enabled=!self.busy;
    if(self.busy) return; NSDictionary *d=[self selected];
    self.setupButton.enabled=[d[@"canConfigure"] boolValue];
    self.testButton.enabled=[d[@"configured"] boolValue] && [d[@"enabled"] boolValue];
    self.clearButton.enabled=[d[@"canConfigure"] boolValue] && [d[@"queue"] length];
    self.restoreButton.enabled=[d[@"canRestore"] boolValue];
}
- (NSString *)supportLabel:(NSDictionary *)d {
    if([d[@"configured"] boolValue]) return [d[@"enabled"] boolValue] ? @"已设置":@"队列已暂停";
    if([d[@"canConfigure"] boolValue]) return @"可自动设置";
    if([d[@"support"] isEqual:@"catalog-only"]) return @"已识别 · 待适配";
    if([d[@"support"] isEqual:@"unknown"]) return @"尚未适配";
    return @"需要确认设备信息";
}
- (void)selectionChanged {
    NSDictionary *d=[self selected]; [self updateButtons];
    if(!d) { self.detail.string=@"接好 USB 并打开打印机后，软件会自动重新检测。\n\n适配库可以独立扩展；点击“查看适配库”查看当前机型和验证状态。"; return; }
    self.detail.string=[NSString stringWithFormat:@"%@\n%@\n\n%@\n\n%@",d[@"model"],[self supportLabel:d],d[@"message"], [d[@"canConfigure"] boolValue] ? @"点击“自动设置”安装对应方案，再打印一页确认。\n原设置会先备份，可在此恢复。":@"此版本不会为该设备自动尝试其他型号的驱动。\n可保存诊断信息，用于下一步适配。"];
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    (void)n; NSApp.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua]; self.buttons=[NSMutableArray new]; self.rows=@[];
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,550) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"聪明的野猪 · 老打印机助手"; self.window.contentView=[[Canvas alloc] initWithFrame:NSMakeRect(0,0,760,550)]; [self.window center];
    NSTextField *title=[self label:@"聪明的野猪" size:27 bold:YES];
    NSTextField *subtitle=[self label:@"让老打印机在 Mac 上继续打印\n试用版 0.2 · 自动识别 USB 打印机 · 按型号匹配适配方案" size:13 bold:NO]; subtitle.textColor=NSColor.secondaryLabelColor;
    self.status=[self label:@"正在识别打印机…" size:14 bold:YES];
    self.picker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; self.picker.target=self; self.picker.action=@selector(selectionChanged);
    NSStackView *actions=[NSStackView new]; actions.orientation=NSUserInterfaceLayoutOrientationHorizontal; actions.spacing=10;
    [self button:@"重新检测" action:@selector(refresh) stack:actions]; self.setupButton=[self button:@"自动设置" action:@selector(configure) stack:actions]; self.testButton=[self button:@"打印一页测试" action:@selector(test) stack:actions];
    NSStackView *extras=[NSStackView new]; extras.orientation=NSUserInterfaceLayoutOrientationHorizontal; extras.spacing=8;
    self.clearButton=[self button:@"清除旧任务" action:@selector(clearJobs) stack:extras]; self.restoreButton=[self button:@"恢复原设置" action:@selector(rollback) stack:extras];
    [self button:@"查看适配库" action:@selector(showCatalog) stack:extras]; [self button:@"保存诊断信息" action:@selector(saveReport) stack:extras];
    self.detail=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,708,230)]; self.detail.verticallyResizable=YES; self.detail.horizontallyResizable=NO; self.detail.textContainer.widthTracksTextView=YES; self.detail.editable=NO; self.detail.font=[NSFont systemFontOfSize:13]; self.detail.textContainerInset=NSMakeSize(12,12); self.detail.autoresizingMask=NSViewWidthSizable;
    NSScrollView *scroll=[NSScrollView new]; scroll.hasVerticalScroller=YES; scroll.borderType=NSBezelBorder; scroll.documentView=self.detail;
    NSTextField *footer=[self label:@"设置时由 macOS 申请管理员授权。测试需确认真实出纸；诊断信息不会自动上传。" size:12 bold:NO]; footer.textColor=NSColor.secondaryLabelColor;
    NSStackView *stack=[NSStackView stackViewWithViews:@[title,subtitle,self.status,self.picker,actions,extras,scroll,footer]]; stack.orientation=NSUserInterfaceLayoutOrientationVertical; stack.alignment=NSLayoutAttributeLeading; stack.spacing=14; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:26],[stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-26],[stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24],[stack.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-24],[scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],[scroll.heightAnchor constraintGreaterThanOrEqualToConstant:150],[self.picker.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor]]];
    [self.window makeKeyAndOrderFront:nil];
    if(self.previewPath) {
        self.rows=@[@{@"id":@"preview",@"model":@"HP Laser 108a",@"support":@"verified",@"canConfigure":@YES,@"configured":@NO,@"enabled":@NO,@"canRestore":@NO,@"queue":@"",@"message":@"已匹配 HP 108a 方案：SpliX 驱动与 USB 通信修复。\n驱动方案已在 M3 / macOS 14.6 实际打印验证。"},@{@"id":@"preview2",@"model":@"Samsung ML-2010",@"support":@"catalog-only"}];
        [self.picker addItemWithTitle:@"HP Laser 108a · 可自动设置"]; [self.picker addItemWithTitle:@"Samsung ML-2010 · 已识别，待适配"]; self.status.stringValue=@"界面示例 · 已识别 2 台打印机"; [self selectionChanged];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,700*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            [self.window.contentView layoutSubtreeIfNeeded]; NSBitmapImageRep *rep=[self.window.contentView bitmapImageRepForCachingDisplayInRect:self.window.contentView.bounds]; [self.window.contentView cacheDisplayInRect:self.window.contentView.bounds toBitmapImageRep:rep];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:self.previewPath atomically:YES]; [NSApp terminate:nil];
        }); return;
    }
    [NSApp activateIgnoringOtherApps:YES]; [self refresh];
    [NSTimer scheduledTimerWithTimeInterval:10 repeats:YES block:^(NSTimer *timer) { (void)timer; if(!self.busy && (!self.holdUntil || self.holdUntil.timeIntervalSinceNow<0)) [self refresh]; }];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { (void)app; return YES; }
- (NSDictionary *)invoke:(NSString *)command identity:(NSString *)identity admin:(BOOL)admin {
    NSTask *p=[NSTask new]; NSPipe *pipe=[NSPipe pipe]; p.standardOutput=pipe; p.standardError=pipe;
    NSMutableArray *args=[@[command] mutableCopy]; if(identity) [args addObject:identity];
    if(admin) {
        NSMutableArray *words=[NSMutableArray new];
        for(NSString *s in [@[control] arrayByAddingObjectsFromArray:args]) [words addObject:[NSString stringWithFormat:@"'%@'",[s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]];
        NSString *shell=[words componentsJoinedByString:@" "]; shell=[shell stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]; shell=[shell stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        p.executableURL=[NSURL fileURLWithPath:@"/usr/bin/osascript"]; p.arguments=@[@"-e",[NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges with prompt \"聪明的野猪：仅设置或恢复您选中的打印机。\"",shell]];
    } else { p.executableURL=[NSURL fileURLWithPath:control]; p.arguments=args; }
    NSError *e=nil; if(![p launchAndReturnError:&e]) return @{@"code":@1,@"text":e.localizedDescription};
    NSData *data=[pipe.fileHandleForReading readDataToEndOfFile]; [p waitUntilExit];
    return @{@"code":@(p.terminationStatus),@"text":[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @""};
}
- (void)refresh {
    if(self.busy) return; NSString *selected=[self selected][@"id"]; self.busy=YES; [self updateButtons];
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSDictionary *r=[self invoke:@"inventory" identity:nil admin:NO]; id j=[NSJSONSerialization JSONObjectWithData:[r[@"text"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO; [self.picker removeAllItems]; self.rows=@[];
            if([r[@"code"] intValue]==0 && [j isKindOfClass:NSDictionary.class] && [j[@"devices"] isKindOfClass:NSArray.class]) {
                self.rows=j[@"devices"]; NSUInteger available=0;
                for(NSDictionary *d in self.rows) { [self.picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@ · %@",d[@"model"],[self supportLabel:d],[d[@"serial"] length] ? d[@"serial"]:@"无序列号"]]; if([d[@"id"] isEqual:selected]) [self.picker selectItemAtIndex:self.picker.numberOfItems-1]; if([d[@"canConfigure"] boolValue]) available++; }
                self.status.stringValue=self.rows.count ? [NSString stringWithFormat:@"已识别 %lu 台打印机，%lu 台有可自动设置的方案。",(unsigned long)self.rows.count,(unsigned long)available]:@"未检测到 USB 打印机。连接后将自动重新检测。";
                [self selectionChanged];
            } else { self.status.stringValue=@"检测未完成"; self.detail.string=r[@"text"]; [self updateButtons]; }
        });
    });
}
- (BOOL)confirm:(NSString *)title message:(NSString *)message {
    NSAlert *a=[NSAlert new]; a.messageText=title; a.informativeText=message; [a addButtonWithTitle:@"继续"]; [a addButtonWithTitle:@"取消"]; return [a runModal]==NSAlertFirstButtonReturn;
}
- (void)action:(NSString *)command admin:(BOOL)admin {
    NSDictionary *d=[self selected]; if(!d || self.busy) return;
    self.busy=YES; [self updateButtons]; self.status.stringValue=@"正在处理所选打印机…";
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSDictionary *r=[self invoke:command identity:d[@"id"] admin:admin];
        NSDictionary *inventory=[self invoke:@"inventory" identity:nil admin:NO]; id j=[NSJSONSerialization JSONObjectWithData:[inventory[@"text"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        dispatch_async(dispatch_get_main_queue(),^{
            if([j isKindOfClass:NSDictionary.class] && [j[@"devices"] isKindOfClass:NSArray.class]) {
                self.rows=j[@"devices"]; [self.picker removeAllItems];
                for(NSDictionary *row in self.rows) { [self.picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",row[@"model"],[self supportLabel:row]]]; if([row[@"id"] isEqual:d[@"id"]]) [self.picker selectItemAtIndex:self.picker.numberOfItems-1]; }
            }
            self.busy=NO; [self updateButtons]; self.holdUntil=[NSDate dateWithTimeIntervalSinceNow:60];
            self.status.stringValue=[r[@"code"] intValue]==0 ? @"操作完成":@"操作未完成"; self.detail.string=r[@"text"];
            if([command isEqual:@"test"] && [r[@"code"] intValue]==0) {
                NSAlert *a=[NSAlert new]; a.messageText=@"已提交一页测试"; a.informativeText=@"请确认是否完整打印一页、没有重复出纸。电脑显示完成并不能确认真实出纸。"; [a addButtonWithTitle:@"知道了"]; [a runModal];
            }
        });
    });
}
- (void)configure { [self action:@"configure" admin:YES]; }
- (void)test { if([self confirm:@"打印一页测试？" message:@"请放好一张 A4 纸，并确认旧任务已结束。"] ) [self action:@"test" admin:NO]; }
- (void)clearJobs { if([self confirm:@"取消所选打印机的旧任务？" message:@"队列会暂停。如仍重复走纸，请关闭再开启打印机，清除机内已接收的数据。"] ) [self action:@"clear-jobs" admin:YES]; }
- (void)rollback { if([self confirm:@"恢复所选打印机的原设置？" message:@"会恢复本软件首次设置前的驱动、连接和 USB 桥接状态。"] ) [self action:@"rollback" admin:YES]; }
- (void)showCatalog {
    if(self.busy) return; self.busy=YES; [self updateButtons];
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSDictionary *r=[self invoke:@"catalog" identity:nil admin:NO]; id j=[NSJSONSerialization JSONObjectWithData:[r[@"text"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        NSMutableString *text=[NSMutableString stringWithString:@"适配库 · 本地内置版本\n\n"];
        if([j isKindOfClass:NSDictionary.class]) {
            for(NSDictionary *p in j[@"profiles"]) [text appendFormat:@"%@ — %@\n%@\n\n",p[@"model"],[p[@"support"] isEqual:@"verified"] ? @"可自动设置":@"已识别，Mac 适配待验证",p[@"notes"]];
            [text appendString:@"其他设备也会尝试识别，但暂不安装驱动。\n此版本尚未接入在线驱动下载；适配库随软件版本更新。"];
        } else [text appendString:r[@"text"]];
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; [self updateButtons]; self.status.stringValue=@"当前适配库"; self.detail.string=text; self.holdUntil=[NSDate dateWithTimeIntervalSinceNow:300]; });
    });
}
- (void)saveReport {
    if(self.busy) return; NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"打印机诊断.json"; panel.message=@"仅保存设备型号、USB 标识和系统版本，不自动上传。";
    if([panel runModal]!=NSModalResponseOK) return; NSURL *url=panel.URL;
    self.busy=YES; [self updateButtons];
    dispatch_async(dispatch_get_global_queue(0,0),^{
        NSDictionary *r=[self invoke:@"report" identity:nil admin:NO]; NSError *e=nil; BOOL ok=[r[@"code"] intValue]==0 && [r[@"text"] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&e];
        dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; [self updateButtons]; self.status.stringValue=ok ? @"诊断信息已保存":@"诊断信息未保存"; self.detail.string=ok ? @"文件已保存在您选择的位置。\n未包含序列号、队列地址或用户名，也没有自动上传。":(e.localizedDescription ?: r[@"text"]); self.holdUntil=[NSDate dateWithTimeIntervalSinceNow:60]; });
    });
}
@end
int main(int argc,const char **argv) { @autoreleasepool {
    NSApplication *app=NSApplication.sharedApplication; App *delegate=[App new];
    if(argc==3 && !strcmp(argv[1],"--render-preview")) delegate.previewPath=@(argv[2]);
    app.delegate=delegate; [app setActivationPolicy:NSApplicationActivationPolicyRegular]; [app run]; return 0;
} }
