
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

@interface KVOContext ()

@property (nonatomic, assign)NSObject *broadcaster;
@property (nonatomic, assign)NSObject *observer;
@property (nonatomic, strong)NSString *keyPath;
@property (nonatomic, assign)void *context;
@property (nonatomic, strong)void(^callback)(void);

- (id)initWithBroadcaster:(NSObject*)broadcaster observer:(NSObject*)observer keyPath:(NSString*)keyPath context:(void*)context callback:(void(^)(void))callback;
- (BOOL)isEqual:(id)object;

@end


@implementation KVOContext

- (id)initWithBroadcaster:(NSObject*)broadcaster observer:(NSObject*)observer keyPath:(NSString*)keyPath context:(void*)context callback:(void(^)(void))callback
{
    self = [super init];
    if (self) {
        self.broadcaster = broadcaster;
        self.observer = observer;
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
        equality = (self.context == rho.context && [self.keyPath isEqualToString:rho.keyPath]);
    }
    
    return equality;
}

- (KVOProxy *)kvoProxy
{
    return nil;
}

@end


//------------------------------------------------------------------------------------------------------------------------------------------

@interface KVOProxy ()
{
    NSDictionary *_contexts;
}

@property (nonatomic, strong)NSMutableIndexSet *i;

@end


@implementation KVOProxy

NSString *const KVOContextTypeObservers = @"KVOContextTypeObservers";
NSString *const KVOContextTypeObservees = @"KVOContextTypeObservees";

- (id)init
{
    self = [super init];
    if (self) {
        _contexts = [[NSDictionary alloc] initWithObjects:@[[NSMutableArray array], [NSMutableArray array]]
                                                  forKeys:@[KVOContextTypeObservers, KVOContextTypeObservees]];
        _i = [[NSMutableIndexSet alloc] init];
    }
    
    return self;
}

- (KVOProxy *)kvoProxy
{
    return nil;
}

- (NSDictionary *)contexts
{
    NSArray *immutableObservers = [NSArray arrayWithArray:_contexts[KVOContextTypeObservers]];
    NSArray *immutableObservees = [NSArray arrayWithArray:_contexts[KVOContextTypeObservees]];
    return [NSDictionary dictionaryWithObjects:@[immutableObservers, immutableObservees]
                                       forKeys:@[KVOContextTypeObservers, KVOContextTypeObservees]];
}

- (void)removeKVOContext:(KVOContext *)context
{
    NSMutableArray *contexts = context.broadcaster ? _contexts[KVOContextTypeObservees] : _contexts[KVOContextTypeObservers];
    for (KVOContext *aContext in contexts) {
        if ([aContext isEqual:context]) {
            [context.broadcaster ? context.broadcaster : self
                                         removeObserver:context.broadcaster ? self: context.observer
                                             forKeyPath:context.keyPath
                                                context:context.context];
        }
    }
    
    [contexts removeObject:context];    
}

- (void)addKVOContext:(KVOContext *)context options:(NSKeyValueObservingOptions)options
{
    NSMutableArray *contexts = context.broadcaster ? _contexts[KVOContextTypeObservees] : _contexts[KVOContextTypeObservers];
    [contexts addObject:context];
    if (context.broadcaster) {
        [context.broadcaster addObserver:self forKeyPath:context.keyPath options:options context:context.context];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{    
    KVOContext *aContext = [[KVOContext alloc] initWithBroadcaster:object observer:nil keyPath:keyPath context:context callback:nil];
    
    if (!self.i.count) {
        self.i = [_contexts[KVOContextTypeObservees] indexesOfObjectsPassingTest:^BOOL(KVOContext *anotherContext, NSUInteger idx, BOOL *stop) {
            return [aContext isEqual:anotherContext];
        }].mutableCopy;
#if !__has_feature(objc_arc)
        [_i release];
#endif
    }
    
    if (self.i.count) {
#if !__has_feature(objc_arc)
        [aContext release];
#endif
        aContext = _contexts[KVOContextTypeObservees][self.i.firstIndex];
        [self.i removeIndex:self.i.firstIndex];

        if (aContext.callback) {
            aContext.callback();
            return;
        }
        
        [aContext.observer observeValueForKeyPath:aContext.keyPath ofObject:aContext.broadcaster change:change context:aContext.context];
    }
}

- (void)dealloc
{
    for (KVOContext *aContext in _contexts[KVOContextTypeObservees]) {
        [aContext.broadcaster removeObserver:self forKeyPath:aContext.keyPath context:aContext.context];
    }
    
#if !__has_feature(objc_arc)
    [_contexts release];
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
static IMP _originalDealloc;

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
    _originalDealloc = popAndReplaceImplementation(self, NSSelectorFromString(@"dealloc"), @selector(__EASY_KVO__dealloc));
}

- (KVOProxy *)kvoProxy
{
    KVOProxy *kvoProxy = objc_getAssociatedObject(self, KVOProxyKey);
    if (!kvoProxy) {
        kvoProxy = [[KVOProxy alloc] init];
        objc_setAssociatedObject(self, KVOProxyKey, kvoProxy, OBJC_ASSOCIATION_RETAIN);
    }
    
    return kvoProxy;
}

- (void)__EASY_KVO__removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    if (observer.kvoProxy) {
        KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:self observer:observer keyPath:keyPath context:nil callback:nil];
        [observer.kvoProxy removeKVOContext:kvoContext];
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
    if (observer.kvoProxy) {
        KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:self observer:observer keyPath:keyPath context:context callback:nil];
        [observer.kvoProxy removeKVOContext:kvoContext];
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
        KVOContext *kvoContext = [[KVOContext alloc] initWithBroadcaster:self observer:observer keyPath:keyPath context:context callback:callback];
        [observer.kvoProxy addKVOContext:kvoContext options:options];
#if !__has_feature(objc_arc)
        [kvoContext release];
#endif

        kvoContext = [[KVOContext alloc] initWithBroadcaster:nil observer:observer keyPath:keyPath context:context callback:callback];
        [self.kvoProxy addKVOContext:kvoContext options:0];
#if !__has_feature(objc_arc)
        [kvoContext release];
#endif

    }
}

- (void)__EASY_KVO__dealloc
{
    KVOProxy *kvoProxy = objc_getAssociatedObject(self, KVOProxyKey);
    if (kvoProxy) {
        for (KVOContext *aContext in kvoProxy.contexts[KVOContextTypeObservers]) {
            [self removeObserver:aContext.observer forKeyPath:aContext.keyPath context:aContext.context];
        }
    }

#if !__has_feature(objc_arc)
    [kvoProxy release];
#endif

    _originalDealloc(self, NSSelectorFromString(@"dealloc"));
}


@end
