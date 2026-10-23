#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
static id c;
static void state(const char *label) {
    NSError *e = nil;
    unsigned char lim = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(c, NSSelectorFromString(@"getMCLLimitWithError:"), &e);
    unsigned long long cur = ((unsigned long long (*)(id, SEL, NSError **))objc_msgSend)(c, NSSelectorFromString(@"currentChargeLimit:"), &e);
    printf("%-14s MCL=%u currentChargeLimit=%llu\n", label, lim, cur);
}
int main(void) { @autoreleasepool {
    setvbuf(stdout, NULL, _IONBF, 0);
    dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
    c = ((id (*)(id, SEL, id))objc_msgSend)([NSClassFromString(@"PowerUISmartChargeClient") alloc], @selector(initWithClientName:), @"com.aaravmuthu.stracotto");
    state("before");
    NSError *e = nil;
    BOOL ok = ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(c, NSSelectorFromString(@"temporarilyOverrideMCLTargetSoC:error:"), 100, &e);
    printf("override(100) ok=%d err=%s\n", ok, e ? [[e description] UTF8String] : "none"); sleep(1);
    state("during top up");
    ok = ((BOOL (*)(id, SEL, unsigned char, NSError **))objc_msgSend)(c, NSSelectorFromString(@"setMCLLimit:error:"), 80, &e);
    sleep(1); state("after reset");
}}
