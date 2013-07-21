
//
//  NSObject+__EASY_KVO__.m
//  https://github.com/saldavonschwartz/easyKVO
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

#if __has_feature(objc_arc)
#define __BRIDGE_IF_USING_ARC(x) __bridge x
#else
#define __BRIDGE_IF_USING_ARC(x) x
#endif

static const char *KVOProxyKey = "KVOProxyKey";


typedef struct {
    unsigned long reserved;
    unsigned long size;
    void *rest[1];
} BlockDescriptor;

typedef struct {
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    BlockDescriptor *descriptor;
} Block;

NSString *NSStringFromBlockEncoding(id block)
{
    Block *t_block = (__BRIDGE_IF_USING_ARC(void*))block;
    BlockDescriptor *descriptor = t_block->descriptor;
    
    int copyDisposeFlag = 1 << 25;
    int signatureFlag = 1 << 30;
    
    assert(t_block->flags & signatureFlag);
    
    int index = 0;
    if(t_block->flags & copyDisposeFlag)
        index += 2;
    
    return [NSString stringWithUTF8String:descriptor->rest[index]];
}

//------------------------------------------------------------------------------------------------------------------------------------------

@interface KVOContext ()

@property (nonatomic, assign)NSObject *observee;
@property (nonatomic, assign)NSObject *observer;
@property (nonatomic, strong)NSString *keyPath;
@property (nonatomic, assign)void *context;
@property (nonatomic, strong)id callback;
@property (nonatomic, assign)KVOContextCallbackType callbackType;

- (id)initWithObservee:(NSObject*)observee observer:(NSObject*)observer keyPath:(NSString*)keyPath context:(void*)context callback:(id)callback;
- (BOOL)isEqual:(id)object;

@end


@implementation KVOContext

static NSString *CallbackEncodingKVO;
static NSString *CallbackEncodingObserver;

+ (void)initialize
{
    KVOCallback kvoCallback = ^(NSString* keyPath, id object, NSDictionary* change, void* context){};
    OBserverCallback observerCallback = ^(__unsafe_unretained id observeee){};
    CallbackEncodingKVO = NSStringFromBlockEncoding(kvoCallback);
    CallbackEncodingObserver = NSStringFromBlockEncoding(observerCallback);
}

- (id)initWithObservee:(NSObject*)observee observer:(NSObject*)observer keyPath:(NSString*)keyPath context:(void*)context callback:(id)callback
{
    self = [super init];
    if (self) {
        self.observee = observee;
        self.observer = observer;
        self.keyPath = keyPath;
        self.context = self.context;
        
        if (callback) {
            self.callback = [callback copy];
            NSString *callbackEncoding = NSStringFromBlockEncoding(callback);
            if ([callbackEncoding isEqualToString:CallbackEncodingKVO]) {
                self.callbackType = KVOContextCallbackTypeKVO;
            }
            else if ([callbackEncoding isEqualToString:CallbackEncodingObserver]) {
                self.callbackType = KVOContextCallbackTypeObserver;
            }
        }
    }
    
    return self;
}

- (BOOL)isEqual:(id)object
{
    BOOL equality = NO;
    if (object && [object isKindOfClass:KVOContext.class]) {
        KVOContext *rho = (KVOContext*)object;
        equality = (self.observee == rho.observee &&
                    self.observer == rho.observer &&
                    self.context == rho.context &&
                    [self.keyPath isEqualToString:rho.keyPath]);
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

@property (nonatomic, strong)NSMutableIndexSet *i;
@property (nonatomic, strong)NSObject *parent;

@end


@implementation KVOProxy

- (id)initWithParent:(NSObject*)parent
{
    self = [super init];
    if (self) {
        _contexts = [[NSMutableArray alloc] init];
        _i = [[NSMutableIndexSet alloc] init];
        self.parent = parent;
    }
    
    return self;
}

- (KVOProxy *)kvoProxy
{
    return nil;
}

- (void)dealloc
{
    for (KVOContext *aContext in self.contexts.copy) {
        [aContext.observee removeObserver:aContext.observer forKeyPath:aContext.keyPath context:aContext.context];
    }
    
#if !__has_feature(objc_arc)
    [_contexts release];
    [_i release];
    [super dealloc];
#endif
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    KVOContext *aContext = [[KVOContext alloc] initWithObservee:object observer:self.parent keyPath:keyPath context:context callback:nil];
    
    if (!self.i.count) {
        self.i = [self.contexts indexesOfObjectsPassingTest:^BOOL(KVOContext *anotherContext, NSUInteger idx, BOOL *stop) {
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
        
        aContext = _contexts[self.i.firstIndex];
        [self.i removeIndex:self.i.firstIndex];
        
        if (aContext.callback) {
            if (aContext.callbackType == KVOContextCallbackTypeKVO) {
                ((KVOCallback)aContext.callback)(keyPath, object, change, context);
            }
            else {
                ((OBserverCallback)aContext.callback)(object);
            }
            return;
        }
        
        [aContext.observer observeValueForKeyPath:aContext.keyPath ofObject:aContext.observee change:change context:aContext.context];
    }
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
        kvoProxy = [[KVOProxy alloc] initWithParent:self];
        objc_setAssociatedObject(self, KVOProxyKey, kvoProxy, OBJC_ASSOCIATION_RETAIN);
    }
    
    return kvoProxy;
}

- (void)__EASY_KVO__removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    _originalRemoveObserver(self, @selector(removeObserver:forKeyPath:context:), observer.kvoProxy, keyPath);
    KVOContext *aContext = [[KVOContext alloc] initWithObservee:self observer:observer keyPath:keyPath context:nil callback:nil];
    [aContext.observee.kvoProxy.contexts removeObject:aContext];
    [aContext.observer.kvoProxy.contexts removeObject:aContext];
    
}

- (void)__EASY_KVO__removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context
{
    _originalRemoveObserver(self, @selector(removeObserver:forKeyPath:context:), observer.kvoProxy, keyPath, context);
    KVOContext *aContext = [[KVOContext alloc] initWithObservee:self observer:observer keyPath:keyPath context:nil callback:nil];
    [aContext.observee.kvoProxy.contexts removeObject:aContext];
    [aContext.observer.kvoProxy.contexts removeObject:aContext];
}

- (void)__EASY_KVO__addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context
{
    [self addObserver:observer forKeyPath:keyPath options:options context:context genericCallback:nil];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context observerCallback:(OBserverCallback)callback
{
    [self addObserver:observer forKeyPath:keyPath options:options context:context genericCallback:callback];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context KVOCallback:(KVOCallback)callback
{
    [self addObserver:observer forKeyPath:keyPath options:options context:context genericCallback:callback];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context genericCallback:(id)genericCallback
{
    _originalAddObserver(self, @selector(addObserver:forKeyPath:options:context:), observer.kvoProxy, keyPath, options, context);
    KVOContext *newContext = [[KVOContext alloc] initWithObservee:self observer:observer keyPath:keyPath context:context callback:genericCallback];
    [self.kvoProxy.contexts addObject:newContext];
    [observer.kvoProxy.contexts addObject:newContext];
#if !__has_feature(objc_arc)
    [newContext release];
#endif
    
}

- (void)__EASY_KVO__dealloc
{
    KVOProxy *kvoProxy = objc_getAssociatedObject(self, KVOProxyKey);
    if (kvoProxy) {
        objc_setAssociatedObject(self, KVOProxyKey, nil, OBJC_ASSOCIATION_RETAIN);
#if !__has_feature(objc_arc)
        [kvoProxy release];
#endif
    }

    _originalDealloc(self, NSSelectorFromString(@"dealloc"));
}


@end
