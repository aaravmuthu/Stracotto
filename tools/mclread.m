#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
int main(void) { @autoreleasepool {
    setvbuf(stdout, NULL, _IONBF, 0);
    dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
    id c = ((id (*)(id, SEL, id))objc_msgSend)([NSClassFromString(@"PowerUISmartChargeClient") alloc], @selector(initWithClientName:), @"com.aaravmuthu.stracotto");
    NSError *e = nil;
    unsigned char lim = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(c, NSSelectorFromString(@"getMCLLimitWithError:"), &e);
    printf("getMCLLimit: %u  err=%s\n", lim, e ? [[e description] UTF8String] : "none"); e = nil;
    unsigned long long en = ((unsigned long long (*)(id, SEL, NSError **))objc_msgSend)(c, NSSelectorFromString(@"isMCLCurrentlyEnabled:"), &e);
    printf("isMCLCurrentlyEnabled: %llu  err=%s\n", en, e ? [[e description] UTF8String] : "none"); e = nil;
    unsigned long long cur = ((unsigned long long (*)(id, SEL, NSError **))objc_msgSend)(c, NSSelectorFromString(@"currentChargeLimit:"), &e);
    printf("currentChargeLimit: %llu  err=%s\n", cur, e ? [[e description] UTF8String] : "none"); e = nil;
    id avail = ((id (*)(id, SEL, NSError **))objc_msgSend)(c, NSSelectorFromString(@"availableChargeLimitsWithError:"), &e);
    printf("availableChargeLimits: %s  err=%s\n", [[avail description] UTF8String], e ? [[e description] UTF8String] : "none");
}}
