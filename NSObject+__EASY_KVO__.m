
//
//  NSObject+__EASY_KVO__.m
//
/*
    Copyright (c) 2013 Federico Saldarini

    Permission is hereby granted, free of charge, to any person obtaining a copy of
    this software and associated documentation files (the "Software"), to deal in
    the Software without restriction, including without limitation the rights to
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
    the Software, and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import "NSObject+__EASY_KVO__.h"
#import <objc/runtime.h>

static const char *KVOProxyKey = "KVOProxyKey";

//------------------------------------------------------------------------------------------------------------------------------------------


@interface KVOContext : NSObject

@property (nonatomic, assign)NSObject *broadcaster;
@property (nonatomic, strong)NSString *keyPath;
@property (nonatomic, assign)void *context;
@property (nonatomic, strong)void(^callback)(void);

- (id)initWithBroadcaster:(NSObject*)broadcaster keyPath:(NSString*)keyPath context:(void*)context callback:(void(^)(void))callback;
- (BOOL)isEqual:(id)object;

@end


@implementation KVOContext

- (id)initWithBroadcaster:(NSObject*)broadcaster keyPath:(NSString*)keyPath context:(void*)context callback:(void(^)(void))callback
{
    self = [super init];
    if (self) {
        self.broadcaster = broadcaster;
        self.keyPath = keyPath;
        self.context = self.context;
        self.callback = [callback copy];
    }
    
    return self;
}

- (BOOL)isEqual:(id)object
{
    BOOL equality = NO;
    if (object && [object isKindOfClass:KVOContext.class]) {
        KVOContext *rho = (KVOContext*)object;
        equality = (self.broadcaster == rho.broadcaster && self.context == rho.context && [self.keyPath isEqualToString:rho.keyPath]);
    }
    
    return equality;
}

@end

//------------------------------------------------------------------------------------------------------------------------------------------


@interface KVOProxy : NSObject

@property (nonatomic, assign)NSObject *observer;
@property (nonatomic, strong, readonly)NSMutableArray *kvoContexts;

- (void)addKVOContext:(KVOContext *)context options:(NSKeyValueObservingOptions)options;

@end


@interface KVOProxy ()

@property (nonatomic, strong, readwrite)NSMutableArray *kvoContexts;
@property (nonatomic, strong)NSMutableIndexSet *i;
@end


@implementation KVOProxy

- (id)initWithObserver:(NSObject*)observer
{
    self = [super init];
    if (self) {
        _observer = observer;
        _kvoContexts = [[NSMutableArray alloc] init];
        _i = [[NSMutableIndexSet alloc] init];
    }
    
    return self;
}

- (void)removeKVOContext:(KVOContext *)context
{
    for (KVOContext *kvoContext in self.kvoContexts) {
        if ([kvoContext isEqual:context]) {
            [context.broadcaster removeObserver:self forKeyPath:context.keyPath context:context.context];
        }
    }
    
    [self.kvoContexts removeObject:context];
}

- (void)addKVOContext:(KVOContext *)context options:(NSKeyValueObservingOptions)options
{
    [self.kvoContexts addObject:context];
    [context.broadcaster addObserver:self forKeyPath:context.keyPath options:options context:context.context];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{    
    KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:object keyPath:keyPath context:context callback:nil];
    
    if (!self.i.count) {
        self.i = [self.kvoContexts indexesOfObjectsPassingTest:^BOOL(KVOContext *anotherContext, NSUInteger idx, BOOL *stop) {
            return [kvoContext isEqual:anotherContext];
        }].mutableCopy;
#if !__has_feature(objc_arc)
        [_i release];
#endif
    }
    
    if (self.i.count) {
#if !__has_feature(objc_arc)
        [kvoContext release];
#endif
        kvoContext = self.kvoContexts[self.i.firstIndex];
        [self.i removeIndex:self.i.firstIndex];

        if (kvoContext.callback) {
            kvoContext.callback();
            return;
        }
        
        [self.observer observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)dealloc
{
    for (KVOContext *kvoContext in self.kvoContexts) {
        [kvoContext.broadcaster removeObserver:self forKeyPath:kvoContext.keyPath context:kvoContext.context];
    }

#if !__has_feature(objc_arc)
    [_kvoContexts release];
    [_i release];
    [super dealloc];
#endif

}

@end

//------------------------------------------------------------------------------------------------------------------------------------------


@implementation NSObject (__EASY_KVO__)

static IMP _originalAddObserver;
static IMP _originalRemoveObserver;
static IMP _originalRemoveObserverWithContext;
#if !__has_feature(objc_arc)
static IMP _originalDealloc;
#endif

IMP popAndReplaceImplementation(Class class, SEL original, SEL replacement)
{
    const char *methodTypeEncoding = method_getTypeEncoding(class_getInstanceMethod(class, original));
    IMP poppedIMP = class_getMethodImplementation(class, original);
    class_replaceMethod(class, original, class_getMethodImplementation(class, replacement), methodTypeEncoding);
    return poppedIMP;
}

+ (void)load
{
    _originalAddObserver = popAndReplaceImplementation(self, @selector(addObserver:forKeyPath:options:context:), @selector(__EASY_KVO__addObserver:forKeyPath:options:context:));
    _originalRemoveObserver = popAndReplaceImplementation(self, @selector(removeObserver:forKeyPath:), @selector(__EASY_KVO__removeObserver:forKeyPath:));
    _originalRemoveObserverWithContext = popAndReplaceImplementation(self, @selector(removeObserver:forKeyPath:context:), @selector(__EASY_KVO__removeObserver:forKeyPath:context:));
#if !__has_feature(objc_arc)
    _originalDealloc = popAndReplaceImplementation(self, @selector(dealloc), @selector(__EASY_KVO__dealloc));
#endif
}

- (void)__EASY_KVO__removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    KVOProxy *kvoProxy = objc_getAssociatedObject(observer, KVOProxyKey);
    if (kvoProxy) {
        KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:self keyPath:keyPath context:nil callback:nil];
        [kvoProxy removeKVOContext:kvoContext];
#if !__has_feature(objc_arc)
        [kvoContext release];
#endif
    }
    else {
        _originalRemoveObserver(self, @selector(removeObserver:forKeyPath:context:), observer, keyPath);
    }
    
}

- (void)__EASY_KVO__removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context
{
    KVOProxy *kvoProxy = objc_getAssociatedObject(observer, KVOProxyKey);
    if (kvoProxy) {
        KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:self keyPath:keyPath context:context callback:nil];
        [kvoProxy removeKVOContext:kvoContext];
#if !__has_feature(objc_arc)
        [kvoContext release];
#endif
    }
    else {
        _originalRemoveObserver(self, @selector(removeObserver:forKeyPath:context:), observer, keyPath, context);
    }
}

- (void)__EASY_KVO__addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context
{
    [self addObserver:observer forKeyPath:keyPath options:options context:context callback:nil];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context callback:(void(^)(void))callback
{
    if ([observer isKindOfClass:KVOProxy.class]) {
        _originalAddObserver(self, @selector(addObserver:forKeyPath:options:context:), observer, keyPath, options, context);
    }
    else {
        KVOProxy *kvoProxy = objc_getAssociatedObject(observer, KVOProxyKey);
        if (!kvoProxy) {
            kvoProxy = [[KVOProxy alloc] initWithObserver:observer];
            objc_setAssociatedObject(observer, KVOProxyKey, kvoProxy, OBJC_ASSOCIATION_RETAIN);
        }
        
        KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:self keyPath:keyPath context:context callback:callback];
        [kvoProxy addKVOContext:kvoContext options:options];
#if !__has_feature(objc_arc)
        [kvoContext release];
#endif

    }
}

#if !__has_feature(objc_arc)
- (void)__EASY_KVO__dealloc
{
    KVOProxy *kvoProxy = objc_getAssociatedObject(self, KVOProxyKey);
    if (kvoProxy) {
        [kvoProxy release];
    }
    
    _originalDealloc(self, @selector(dealloc));
}
#endif

@end
