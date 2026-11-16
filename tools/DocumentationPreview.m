// Isolated documentation preview: production AppKit views, explicit demo data.
// No HID worker, display scanning, DDC writes, system publication or login items.
#define main BBProductionMain
#import "../Sources/main.m"
#undef main

@interface BBDocumentationApp:BBApp
@end
@implementation BBDocumentationApp
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    self.lockFD=-1;
    [BBPreferences() registerDefaults:@{@"ReportInterval":@1800,@"AutoStartEnabled":@YES}];
    [BBPreferences() setObject:@{@"docs.mouse":@YES,@"docs.keyboard":@YES} forKey:@"MappedDevices"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    self.engine=[BBEngine new];
    self.engine.snapshot=@[
        @{@"identity":@"docs.mouse",@"name":@"G304 X LIGHTSPEED",@"category":@"Mouse",@"connected":@YES,@"selectable":@YES,@"fresh":@YES,@"percent":@91,@"charging":@NO,@"full":@NO,@"updated":@(now),@"status":@"演示数据 · 仅用于文档截图"},
        @{@"identity":@"docs.keyboard",@"name":@"MCHOSE K87 V3",@"category":@"Keyboard",@"connected":@YES,@"selectable":@YES,@"fresh":@YES,@"percent":@92,@"charging":@NO,@"full":@NO,@"updated":@(now),@"status":@"演示数据 · 仅用于文档截图"}];
    self.displays=[BBDisplayController new];
    [self.displays setValue:@[@{@"identity":@"docs.display",@"name":@"DELL S2725QS",@"category":@"Display",@"connected":@YES,@"mappingEnabled":@NO,@"brightness":@{@"percent":@81,@"current":@81,@"maximum":@100},@"volume":@{@"percent":@9,@"current":@9,@"maximum":@100},@"updated":@(now),@"status":@"演示数据 · 不读写真实设备"}] forKey:@"snapshot"];
    NSMenu *main=[NSMenu new],*applicationMenu=[NSMenu new];NSMenuItem *application=[NSMenuItem new];application.submenu=applicationMenu;[main addItem:application];
    NSMenuItem *open=[[NSMenuItem alloc]initWithTitle:@"状态栏菜单" action:@selector(openDocumentationMenu:) keyEquivalent:@"m"];open.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;open.target=self;[applicationMenu addItem:open];
    NSMenuItem *quit=[[NSMenuItem alloc]initWithTitle:@"退出文档预览" action:@selector(quit:) keyEquivalent:@"q"];quit.target=self;[applicationMenu addItem:quit];NSApp.mainMenu=main;
    [self createStatusItem];[self showWindow];
    [self.window setContentSize:NSMakeSize(760,610)];[self.window center];[self refresh];
}
- (void)openDocumentationMenu:(id)sender {
    // Same production NSMenu; anchor inside the shared documentation window so
    // window-scoped screenshot services can capture it without the desktop.
    [self menuNeedsUpdate:self.statusMenu];
    [self.statusMenu popUpMenuPositioningItem:nil atLocation:NSMakePoint(self.window.contentView.bounds.size.width-360,self.window.contentView.bounds.size.height-24) inView:self.window.contentView];
}
@end
int main(void){@autoreleasepool{
    BBTestingUI=YES;
    NSApplication *application=NSApplication.sharedApplication;
    BBDocumentationApp *delegate=[BBDocumentationApp new];application.delegate=delegate;
    [application run];
}}
