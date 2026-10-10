#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#ifndef LP_BASE
#define LP_BASE @"/Library/Printers/LegacyPrint/Core"
#endif
#ifndef LP_STATE
#define LP_STATE @"/Library/Printers/LegacyPrint/StateV2"
#endif
static NSString *base=LP_BASE, *state=LP_STATE;
static NSFileManager *fm;
static NSDictionary *catalog;
static void fail(NSString *s) { @throw [NSException exceptionWithName:@"LegacyPrint" reason:s userInfo:nil]; }
static BOOL safeToken(NSString *s) {
    if(![s isKindOfClass:NSString.class] || !s.length || s.length>64) return NO;
    NSCharacterSet *ok=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    return [s rangeOfCharacterFromSet:ok.invertedSet].location==NSNotFound;
}
static NSString *normalize(NSString *s) {
    NSMutableString *result=[NSMutableString new];
    NSCharacterSet *ok=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
    for(NSUInteger i=0;i<s.length;i++) { unichar c=[s.lowercaseString characterAtIndex:i]; if([ok characterIsMember:c]) [result appendFormat:@"%C",c]; }
    return result;
}
static NSString *digest(NSData *data) {
    if(!data || data.length>UINT32_MAX) fail(@"文件无法校验。"); unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,bytes); NSMutableString *s=[NSMutableString new];
    for(unsigned i=0;i<sizeof(bytes);i++) [s appendFormat:@"%02x",bytes[i]]; return s;
}
static NSString *run(NSString *path,NSArray *arguments,BOOL allow) {
#ifdef LP_TEST_MODE
    path=[[base stringByAppendingPathComponent:@"Mocks"] stringByAppendingPathComponent:path.lastPathComponent];
#endif
    NSTask *p=[NSTask new]; p.executableURL=[NSURL fileURLWithPath:path]; p.arguments=arguments;
    p.environment=@{@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin",@"LANG":@"C",@"LC_ALL":@"C"};
    NSPipe *pipe=[NSPipe pipe]; p.standardOutput=pipe; p.standardError=pipe; NSError *e=nil;
    if(![p launchAndReturnError:&e]) fail(e.localizedDescription);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_global_queue(0,0),^{ if(p.running) [p terminate]; });
    NSData *data=[pipe.fileHandleForReading readDataToEndOfFile]; [p waitUntilExit];
    NSString *s=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if(p.terminationStatus && !allow) {
        if([path.lastPathComponent isEqual:@"lpstat"] && [arguments isEqual:@[@"-v"]] && [s containsString:@"No destinations added."]) return @"";
        fail([NSString stringWithFormat:@"操作失败：%@\n%@",path.lastPathComponent,s]);
    }
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static void requireAdmin(void) {
#ifndef LP_TEST_MODE
    if(geteuid()!=0) fail(@"设置或恢复打印机需要通过 macOS 管理员授权。");
#endif
}
static void printJSON(id o) {
    NSError *e=nil; NSData *data=[NSJSONSerialization dataWithJSONObject:o options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&e];
    if(!data) fail(e.localizedDescription); puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
static void writeData(NSData *data,NSString *path) {
    NSError *e=nil; if(!data || ![data writeToFile:path options:NSDataWritingAtomic error:&e]) fail(e.localizedDescription ?: @"无法保存备份。");
    [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:&e]; if(e) fail(e.localizedDescription);
}
static NSDictionary *jsonFile(NSString *path) {
    NSData *d=[NSData dataWithContentsOfFile:path]; id o=d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]:nil;
    if(![o isKindOfClass:NSDictionary.class]) fail(@"适配库或备份无法读取。"); return o;
}
static NSString *asset(NSString *relative) {
    if(![relative isKindOfClass:NSString.class] || !relative.length || relative.isAbsolutePath || [relative.pathComponents containsObject:@".."])
        fail(@"驱动模块路径无效。");
    NSString *path=[base stringByAppendingPathComponent:relative];
    NSString *resolved=path.stringByResolvingSymlinksInPath;
    if(![resolved hasPrefix:[base.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]) fail(@"驱动模块越过了安装目录。");
    return path;
}
static void trusted(NSString *path) {
#ifndef LP_TEST_MODE
    for(NSString *p=path; p.length>1; p=p.stringByDeletingLastPathComponent) {
        struct stat st;
        if(lstat(p.fileSystemRepresentation,&st) || S_ISLNK(st.st_mode) || st.st_uid!=0 || (st.st_mode&0022)) fail(@"安装文件权限异常，请重新安装软件后再设置打印机。");
    }
#else
    (void)path;
#endif
}
static void loadCatalog(void) {
    catalog=jsonFile([base stringByAppendingPathComponent:@"catalog.json"]);
    if([catalog[@"schema"] intValue]!=1 || ![catalog[@"profiles"] isKindOfClass:NSArray.class] || ![catalog[@"modules"] isKindOfClass:NSDictionary.class]) fail(@"此版本不支持该适配库。");
    NSMutableSet *ids=[NSMutableSet new];
    for(id p in catalog[@"profiles"]) {
        if(![p isKindOfClass:NSDictionary.class] || !safeToken(p[@"id"]) || [ids containsObject:p[@"id"]] || ![p[@"model"] isKindOfClass:NSString.class] || ![p[@"match"] isKindOfClass:NSDictionary.class]) fail(@"适配库包含无效或重复的机型。");
        [ids addObject:p[@"id"]];
    }
}
static NSArray *devices(void) {
    NSString *s=run([base stringByAppendingPathComponent:@"legacyprint-usb"],@[],NO);
    id raw=[NSPropertyListSerialization propertyListWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:NSPropertyListImmutable format:NULL error:NULL];
    if(![raw isKindOfClass:NSArray.class]) fail(@"无法读取 USB 设备信息。");
    NSMutableArray *rows=[NSMutableArray new];
    for(id item in raw) {
        if(![item isKindOfClass:NSDictionary.class]) fail(@"USB 设备信息无效。");
        NSMutableDictionary *d=[item mutableCopy];
        for(NSString *key in @[@"serial",@"manufacturer",@"product"]) if(![d[key] isKindOfClass:NSString.class]) d[key]=@"";
        if([d[@"vid"] intValue]<1 || [d[@"vid"] intValue]>65535 || [d[@"pid"] intValue]<0 || [d[@"pid"] intValue]>65535) fail(@"USB 设备标识无效。");
        NSString *identity=[NSString stringWithFormat:@"%04x:%04x:%@",[d[@"vid"] intValue],[d[@"pid"] intValue],[d[@"serial"] length] ? d[@"serial"]:[NSString stringWithFormat:@"location-%@",d[@"location"] ?: @0]];
        d[@"id"]=digest([identity dataUsingEncoding:NSUTF8StringEncoding]); [rows addObject:d];
    }
    return rows;
}
static NSDictionary *match(NSDictionary *d) {
    NSMutableArray *matches=[NSMutableArray new]; BOOL sharedID=NO;
    for(NSDictionary *p in catalog[@"profiles"]) {
        NSDictionary *m=p[@"match"]; BOOL vendor=NO,usb=NO,product=NO;
        for(NSNumber *vid in m[@"vendorIds"]) if(vid.intValue==[d[@"vid"] intValue]) vendor=YES;
        for(NSDictionary *pair in m[@"usbIds"]) if([pair[@"vid"] intValue]==[d[@"vid"] intValue] && [pair[@"pid"] intValue]==[d[@"pid"] intValue]) usb=YES;
        sharedID|=usb;
        for(NSString *alias in m[@"products"]) if(normalize(d[@"product"]).length && [normalize(alias) isEqual:normalize(d[@"product"])]) product=YES;
        // A shared USB ID alone never proves an exact model.
        if(product && (vendor || usb) && (![m[@"requireUsbId"] boolValue] || usb)) [matches addObject:p];
    }
    if(matches.count==1) return @{@"status":matches[0][@"support"],@"profile":matches[0]};
    if(matches.count>1) return @{@"status":@"ambiguous",@"message":@"型号对应多个方案，需要完善适配库后才能自动安装。"};
    return @{@"status":sharedID ? @"identity-mismatch":@"unknown",@"message":sharedID ? @"USB 标识相同，但完整型号不匹配，暂不自动套用驱动。":@"已识别设备，适配库暂时没有此型号的已验证方案。"};
}
static NSDictionary *selectDevice(NSString *identity) {
    NSMutableArray *found=[NSMutableArray new];
    for(NSDictionary *d in devices()) if(!identity || [d[@"id"] isEqual:identity]) [found addObject:d];
    if(found.count!=1) fail(found.count ? @"检测到多台打印机，请在软件中选择一台。":@"未找到所选打印机，请接好 USB、打开电源后刷新。");
    return found[0];
}
static NSDictionary *verifiedProfile(NSDictionary *d) {
    NSDictionary *m=match(d),*p=m[@"profile"];
    if(![m[@"status"] isEqual:@"verified"]) fail(p ? @"已识别型号，但 Mac 适配方案尚未验证，未修改打印机。":m[@"message"]);
    if(!safeToken(d[@"serial"]) || ![d[@"manufacturer"] length] || ![d[@"product"] length]) fail(@"设备缺少可安全区分的序列号或 USB 名称，暂不自动设置。");
    NSUInteger same=0; for(NSDictionary *other in devices()) if([other[@"id"] isEqual:d[@"id"]]) same++;
    if(same!=1) fail(@"设备标识重复，暂不自动设置。");
    if(![p[@"architectures"] containsObject:@"arm64"] || NSProcessInfo.processInfo.operatingSystemVersion.majorVersion<[p[@"minimumMacOS"] intValue]) fail(@"该驱动不适用于当前系统。");
    return p;
}
static NSDictionary *module(NSDictionary *p,BOOL privileged) {
    NSDictionary *m=catalog[@"modules"][p[@"module"]];
    if(![m isKindOfClass:NSDictionary.class] || ![m[@"engine"] isEqual:@"cups-raster"] || ![m[@"assets"] isKindOfClass:NSDictionary.class]) fail(@"匹配到了机型，但所需驱动模块尚未安装。");
    if(privileged) { trusted([base stringByAppendingPathComponent:@"catalog.json"]); trusted([base stringByAppendingPathComponent:@"legacyprint-usb"]); }
    for(NSString *relative in m[@"assets"]) {
        NSString *path=asset(relative); if(privileged) trusted(path);
        if(![digest([NSData dataWithContentsOfFile:path]) isEqual:m[@"assets"][relative]]) fail(@"驱动模块校验失败，请重新安装软件。");
    }
    if(!m[@"assets"][p[@"ppd"]] || !m[@"assets"][m[@"filter"]]) fail(@"机型与驱动模块不一致。");
    return m;
}
static NSString *driver(NSDictionary *p) { return asset(catalog[@"modules"][p[@"module"]][@"filter"]); }
static NSArray *queues(void) {
    NSMutableArray *rows=[NSMutableArray new];
    for(NSString *line in [run(@"/usr/bin/lpstat",@[@"-v"],NO) componentsSeparatedByString:@"\n"]) {
        NSRange split=[line rangeOfString:@": "]; if(![line hasPrefix:@"device for "] || split.location==NSNotFound) continue;
        NSString *name=[line substringWithRange:NSMakeRange(11,split.location-11)];
        if(!safeToken(name)) continue;
        [rows addObject:@{@"name":name,@"uri":[line substringFromIndex:NSMaxRange(split)]}];
    } return rows;
}
static NSString *nativeURI(NSDictionary *d,NSDictionary *p) {
    NSString *uri=p[@"uriTemplate"]; if(![uri hasPrefix:@"usb://"] || ![uri containsString:@"{serial}"] || !safeToken(d[@"serial"])) fail(@"机型连接方案无效。");
    return [uri stringByReplacingOccurrencesOfString:@"{serial}" withString:d[@"serial"]];
}
static BOOL sameUSB(NSString *a,NSString *b) {
    NSURLComponents *x=[NSURLComponents componentsWithString:a],*y=[NSURLComponents componentsWithString:b];
    if(![x.scheme isEqual:@"usb"] || ![y.scheme isEqual:@"usb"] || ![normalize(x.host) isEqual:normalize(y.host)] || ![normalize(x.path) isEqual:normalize(y.path)]) return NO;
    NSString *xs=nil,*ys=nil; NSUInteger nx=0,ny=0;
    for(NSURLQueryItem *i in x.queryItems) if([i.name isEqual:@"serial"]) { xs=i.value; nx++; }
    for(NSURLQueryItem *i in y.queryItems) if([i.name isEqual:@"serial"]) { ys=i.value; ny++; }
    return nx==1 && ny==1 && xs.length && [xs isEqual:ys];
}
static NSDictionary *queue(NSDictionary *d,NSDictionary *p) {
    NSMutableArray *found=[NSMutableArray new]; NSString *uri=nativeURI(d,p);
    for(NSDictionary *q in queues()) if(sameUSB(q[@"uri"],uri)) [found addObject:q];
    if(found.count>1) fail(@"所选打印机有多个 USB 队列，暂不自动修改。请在系统中保留一个目标队列。");
    return found.firstObject;
}
static NSString *ppdPath(NSString *q) {
#ifdef LP_TEST_MODE
    return [[[base stringByAppendingPathComponent:@"PPDs"] stringByAppendingPathComponent:q] stringByAppendingString:@".ppd"];
#else
    return [@"/etc/cups/ppd/" stringByAppendingString:[q stringByAppendingString:@".ppd"]];
#endif
}
static BOOL enabled(NSString *q) { return ![run(@"/usr/bin/lpstat",@[@"-p",q],NO) containsString:@" disabled "]; }
static BOOL pending(NSString *q) { return run(@"/usr/bin/lpstat",@[@"-W",@"not-completed",@"-o",q],NO).length>0; }
static NSString *directory(NSString *identity) { if(!safeToken(identity) || identity.length!=64) fail(@"无效的设备标识。"); return [state stringByAppendingPathComponent:identity]; }
static NSString *snapshotPath(NSString *identity) { return [directory(identity) stringByAppendingPathComponent:@"snapshot.json"]; }
static NSString *markerPath(NSString *identity) { (void)directory(identity); return [[state stringByAppendingPathComponent:identity] stringByAppendingString:@".available"]; }
static BOOL bridgeDisabled(NSString *label) {
    if(!label.length) return NO;
    for(NSString *line in [run(@"/bin/launchctl",@[@"print-disabled",@"system"],NO) componentsSeparatedByString:@"\n"])
        if([line containsString:[NSString stringWithFormat:@"\"%@\"",label]] && ([line containsString:@"disabled"] || [line containsString:@"=> true"])) return YES;
    return NO;
}
static NSString *bridge(NSDictionary *d,NSDictionary *p) {
    NSString *action=p[@"usbAction"] ?: @"none";
    if([action isEqual:@"none"]) return @"";
    // A module may request only an implemented, narrowly scoped action.
    if(![action isEqual:@"hp108a-classic"] || [d[@"vid"] intValue]!=0x03f0 || [d[@"pid"] intValue]!=0xe82a || ![d[@"product"] isEqual:@"HP Laser 108a"]) fail(@"未实现此机型的 USB 修复方式。");
    for(NSString *key in @[@"manufacturer",@"product"]) if([d[key] rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) fail(@"USB 名称无效。");
    return [NSString stringWithFormat:@"com.apple.print.ippusb.%@.%@.%@",d[@"manufacturer"],d[@"product"],d[@"serial"]];
}
static NSDictionary *capture(NSDictionary *d,NSDictionary *p,NSDictionary *q,NSString *name) {
    NSData *ppd=q ? [NSData dataWithContentsOfFile:ppdPath(name)]:nil;
    if(q && !ppd) fail(@"原打印机设置无法备份，未修改设置。"); NSString *label=bridge(d,p);
    return @{@"schema":@1,@"id":d[@"id"],@"serial":d[@"serial"],@"vid":d[@"vid"],@"pid":d[@"pid"],@"profile":p[@"id"],@"model":p[@"model"],@"queue":name,@"existed":@(q!=nil),@"uri":q ? q[@"uri"]:nativeURI(d,p),@"ppd":ppd ? [ppd base64EncodedStringWithOptions:0]:@"",@"enabled":@(q ? enabled(name):NO),@"bridge":label,@"bridgeDisabled":@(bridgeDisabled(label))};
}
static NSDictionary *readSnapshot(NSString *identity) {
    NSDictionary *s=jsonFile(snapshotPath(identity));
    if([s[@"schema"] intValue]!=1 || ![s[@"id"] isEqual:identity] || !safeToken(s[@"queue"]) || !safeToken(s[@"serial"]) || ![s[@"uri"] hasPrefix:@"usb://"]) fail(@"打印机备份无效。");
    return s;
}
static void restore(NSDictionary *snap) {
    NSString *q=snap[@"queue"]; BOOL exists=NO;
    for(NSDictionary *current in queues()) if([current[@"name"] isEqual:q]) {
        exists=YES; if(![current[@"uri"] isEqual:snap[@"uri"]]) fail(@"队列连接已被修改，停止恢复以保护其他设备。");
    }
    if([snap[@"existed"] boolValue]) {
        NSData *data=[[NSData alloc] initWithBase64EncodedString:snap[@"ppd"] options:0]; if(!data.length) fail(@"原驱动配置备份缺失。");
        NSString *path=[directory(snap[@"id"]) stringByAppendingPathComponent:@"restore.ppd"]; writeData(data,path);
        run(@"/usr/sbin/cupsdisable",@[@"-r",@"LegacyPrint rollback",q],YES);
        run(@"/usr/sbin/lpadmin",@[@"-p",q,@"-v",snap[@"uri"],@"-P",path],NO);
        if([snap[@"enabled"] boolValue]) run(@"/usr/sbin/cupsenable",@[q],NO);
    } else if(exists) run(@"/usr/sbin/lpadmin",@[@"-x",q],NO);
    if([snap[@"bridge"] length]) run(@"/bin/launchctl",@[[snap[@"bridgeDisabled"] boolValue] ? @"disable":@"enable",[@"system/" stringByAppendingString:snap[@"bridge"]]],NO);
}
static int lockDevice(NSString *identity) {
    requireAdmin(); NSError *e=nil;
    if(![fm createDirectoryAtPath:state withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&e]) fail(e.localizedDescription);
    if(![fm createDirectoryAtPath:directory(identity) withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&e]) fail(e.localizedDescription);
    trusted(directory(identity)); NSString *path=[directory(identity) stringByAppendingPathComponent:@"lock"];
    int fd=open(path.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(fd<0 || flock(fd,LOCK_EX|LOCK_NB)) { if(fd>=0) close(fd); fail(@"此打印机正在进行另一项设置，请稍后重试。"); } return fd;
}
static NSString *newName(NSDictionary *d,NSDictionary *p) { return [NSString stringWithFormat:@"LegacyPrint_%@_%@",p[@"queueSlug"], [d[@"id"] substringToIndex:12]]; }
static void configure(NSDictionary *d) {
    requireAdmin(); NSDictionary *p=verifiedProfile(d); module(p,YES); int lock=lockDevice(d[@"id"]);
    @try {
        NSDictionary *q=queue(d,p); if(q && pending(q[@"name"])) fail(@"打印机仍有未完成任务，请先在软件中清除旧任务；如仍走纸，请关闭再开启打印机。");
        NSString *name=q ? q[@"name"]:newName(d,p);
        if(!safeToken(name)) fail(@"队列名称无效。");
        if(!q) for(NSDictionary *other in queues()) if([other[@"name"] isEqual:name]) fail(@"队列名称已被其他设备使用，未修改设置。");
        NSDictionary *current=capture(d,p,q,name),*original=nil;
        if([fm fileExistsAtPath:snapshotPath(d[@"id"])]) {
            trusted(snapshotPath(d[@"id"])); original=readSnapshot(d[@"id"]);
            if(![original[@"queue"] isEqual:name] || ![original[@"uri"] isEqual:current[@"uri"]]) fail(@"目标队列在备份后发生变化，请先恢复或检查原设置。");
        } else { original=current; writeData([NSJSONSerialization dataWithJSONObject:original options:NSJSONWritingPrettyPrinted error:NULL],snapshotPath(d[@"id"])); }
        writeData([@"backup available\n" dataUsingEncoding:NSUTF8StringEncoding],markerPath(d[@"id"]));
        [fm setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:markerPath(d[@"id"]) error:NULL];
        NSString *ppd=[NSString stringWithContentsOfFile:asset(p[@"ppd"]) encoding:NSUTF8StringEncoding error:NULL];
        NSData *old=[[NSData alloc] initWithBase64EncodedString:current[@"ppd"] options:0]; NSString *oldPPD=old ? [[NSString alloc] initWithData:old encoding:NSUTF8StringEncoding]:nil;
        BOOL compatible=[p[@"preservePPDMarkers"] count]>0;
        for(NSString *marker in p[@"preservePPDMarkers"]) if(![oldPPD containsString:marker]) compatible=NO;
        if(compatible) {
            NSMutableArray *lines=[NSMutableArray new];
            for(NSString *line in [oldPPD componentsSeparatedByString:@"\n"]) if(![line hasPrefix:@"*cupsFilter:"] && ![line hasPrefix:@"*cupsFilter2:"]) [lines addObject:line];
            [lines addObject:[NSString stringWithFormat:@"*cupsFilter: \"application/vnd.cups-raster 0 %@\"",driver(p)]]; ppd=[lines componentsJoinedByString:@"\n"];
        }
        NSString *prepared=[directory(d[@"id"]) stringByAppendingPathComponent:@"configured.ppd"]; writeData([ppd dataUsingEncoding:NSUTF8StringEncoding],prepared);
        run(@"/usr/bin/cupstestppd",@[@"-q",prepared],NO);
        @try {
            if(q) run(@"/usr/sbin/cupsdisable",@[@"-r",@"LegacyPrint setup",name],NO);
            NSString *label=current[@"bridge"];
            if(label.length) {
                run(@"/bin/launchctl",@[@"disable",[@"system/" stringByAppendingString:label]],NO);
                NSString *loaded=run(@"/bin/launchctl",@[@"print",[@"system/" stringByAppendingString:label]],YES);
                if([loaded hasPrefix:[NSString stringWithFormat:@"system/%@ =",label]]) run(@"/bin/launchctl",@[@"bootout",[@"system/" stringByAppendingString:label]],NO);
                run([base stringByAppendingPathComponent:@"legacyprint-usb"],@[@"--classic",d[@"serial"]],NO);
            }
            NSMutableArray *args=[@[@"-p",name,@"-v",current[@"uri"],@"-P",prepared] mutableCopy];
            if(!q) [args addObjectsFromArray:@[@"-D",[NSString stringWithFormat:@"聪明的野猪 · %@",p[@"model"]],@"-L",@"USB",@"-o",@"printer-is-shared=false",@"-o",@"printer-error-policy=stop-printer"]];
            run(@"/usr/sbin/lpadmin",args,NO); run(@"/usr/sbin/cupsenable",@[name],NO);
            if(!q) run(@"/usr/sbin/cupsaccept",@[name],NO);
            puts([NSString stringWithFormat:@"%@ 已完成自动设置。请打印一页测试并确认实际出纸。",p[@"model"]].UTF8String);
        } @catch(NSException *e) {
            @try { restore(current); } @catch(NSException *ignored) { fputs("自动恢复未全部完成。原设置备份仍保留，请在软件中恢复原设置。\n",stderr); }
            @throw e;
        }
    } @finally { close(lock); }
}
static NSDictionary *inventoryRow(NSDictionary *d) {
    NSDictionary *m=match(d),*p=m[@"profile"]; NSMutableDictionary *row=[d mutableCopy];
    row[@"model"]=p ? p[@"model"]:([d[@"product"] length] ? d[@"product"]:@"未命名 USB 打印机");
    row[@"support"]=m[@"status"]; row[@"profile"]=p ? p[@"id"]:@""; row[@"family"]=p ? p[@"family"]:@"待识别";
    row[@"message"]=p ? p[@"notes"]:m[@"message"]; row[@"canConfigure"]=@NO; row[@"configured"]=@NO; row[@"enabled"]=@NO; row[@"queue"]=@""; row[@"canRestore"]=@([fm fileExistsAtPath:markerPath(d[@"id"])]);
    if([m[@"status"] isEqual:@"verified"] && safeToken(d[@"serial"])) {
        @try {
            verifiedProfile(d); module(p,NO); NSDictionary *q=queue(d,p);
            NSString *ppd=q ? [NSString stringWithContentsOfFile:ppdPath(q[@"name"]) encoding:NSUTF8StringEncoding error:NULL]:nil;
            row[@"queue"]=q ? q[@"name"]:@""; row[@"configured"]=@([ppd containsString:driver(p)]); row[@"enabled"]=@(q ? enabled(q[@"name"]):NO); row[@"canConfigure"]=@YES;
        } @catch(NSException *e) { row[@"message"]=e.reason; }
    } else if([m[@"status"] isEqual:@"verified"]) row[@"message"]=@"型号已匹配，但序列号不完整，暂不自动设置。";
    return row;
}
static void plan(NSDictionary *d) {
    NSDictionary *p=verifiedProfile(d); module(p,NO); NSDictionary *q=queue(d,p);
    printJSON(@{@"model":p[@"model"],@"id":d[@"id"],@"profile":p[@"id"],@"module":p[@"module"],@"queue":q ? q[@"name"]:newName(d,p),@"existingQueue":@(q!=nil),@"pendingJobs":@(q ? pending(q[@"name"]):NO),@"bridge":bridge(d,p),@"driver":driver(p),@"backup":snapshotPath(d[@"id"]),@"sendsPrintData":@NO});
}
int main(int argc,const char **argv) { @autoreleasepool {
    fm=NSFileManager.defaultManager;
    @try {
        if(argc<2 || argc>3) fail(@"需要指定有效操作。"); loadCatalog();
        NSString *command=@(argv[1]),*identity=argc>2 && strcmp(argv[2],"--auto") ? @(argv[2]):nil;
        if([command isEqual:@"catalog"]) printJSON(catalog);
        else if([command isEqual:@"inventory"]) {
            NSMutableArray *rows=[NSMutableArray new]; for(NSDictionary *d in devices()) [rows addObject:inventoryRow(d)];
            printJSON(@{@"devices":rows,@"version":@"0.2.0",@"catalogVersion":catalog[@"version"]});
        } else if([command isEqual:@"report"]) {
            NSMutableArray *rows=[NSMutableArray new]; for(NSDictionary *d in devices()) { NSDictionary *m=match(d),*p=m[@"profile"]; [rows addObject:@{@"model":p ? p[@"model"]:d[@"product"],@"manufacturer":d[@"manufacturer"],@"vid":d[@"vid"],@"pid":d[@"pid"],@"support":m[@"status"],@"profile":p ? p[@"id"]:@""}]; }
            printJSON(@{@"version":@"0.2.0",@"catalogVersion":catalog[@"version"],@"macOS":NSProcessInfo.processInfo.operatingSystemVersionString,@"architecture":@"arm64",@"devices":rows,@"privacy":@"不包含序列号、设备标识、队列地址、用户名或文件路径。"});
        } else if([command isEqual:@"plan"]) plan(selectDevice(identity));
        else if([command isEqual:@"configure"]) { requireAdmin(); configure(selectDevice(identity)); }
        else if([command isEqual:@"rollback"]) {
            requireAdmin(); if(!identity) fail(@"请选择要恢复的设备。"); int lock=lockDevice(identity);
            @try {
                trusted(snapshotPath(identity)); NSDictionary *snap=readSnapshot(identity);
                for(NSDictionary *q in queues()) if([q[@"name"] isEqual:snap[@"queue"]] && pending(q[@"name"])) fail(@"请先清除所选打印机的未完成任务再恢复。");
                restore(snap); NSError *e=nil;
                if(![fm removeItemAtPath:snapshotPath(identity) error:&e]) fail(e.localizedDescription);
                [fm removeItemAtPath:markerPath(identity) error:NULL]; puts("已恢复原设置。若恢复了原桥接服务，请重新插拔 USB。");
            } @finally { close(lock); }
        } else if([command isEqual:@"test"] || [command isEqual:@"clear-jobs"]) {
            if([command isEqual:@"clear-jobs"]) requireAdmin();
            NSDictionary *d=selectDevice(identity),*p=verifiedProfile(d); module(p,NO); NSDictionary *q=queue(d,p);
            if(!q) fail(@"所选打印机还没有队列，请先自动设置。");
            if([command isEqual:@"clear-jobs"]) {
                run(@"/usr/sbin/cupsdisable",@[@"-r",@"LegacyPrint clearing old jobs",q[@"name"]],NO); run(@"/usr/bin/cancel",@[@"-a",q[@"name"]],NO);
                puts("所选打印机已暂停，旧任务已取消。如仍走纸，请关闭再开启打印机，然后重新设置。");
            } else {
                NSString *ppd=[NSString stringWithContentsOfFile:ppdPath(q[@"name"]) encoding:NSUTF8StringEncoding error:NULL];
                if(![ppd containsString:driver(p)]) fail(@"请先自动设置这台打印机。");
                if(!enabled(q[@"name"]) || pending(q[@"name"])) fail(@"队列暂停或仍有旧任务，请先检查状态。");
                puts(run(@"/usr/bin/lp",@[@"-d",q[@"name"],@"-n",@"1",@"-t",@"LegacyPrint single page test",@"-o",@"media=A4",@"-o",@"sides=one-sided",@"-o",@"job-sheets=none",asset(@"test-page.txt")],NO).UTF8String);
            }
        } else fail(@"未知操作。");
    } @catch(NSException *e) { fputs([e.reason stringByAppendingString:@"\n"].UTF8String,stderr); return 1; }
    return 0;
} }
