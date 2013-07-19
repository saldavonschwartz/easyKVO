
//
//  NSObject+__EASY_KVO__.h
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


//------------------------------------------------------------------------------------------------------------------------------------------

@interface KVOContext : NSObject

@property (nonatomic, assign, readonly)NSObject *broadcaster;
@property (nonatomic, assign, readonly)NSObject *observer;
@property (nonatomic, strong, readonly)NSString *keyPath;
@property (nonatomic, assign, readonly)void *context;
@property (nonatomic, strong, readonly)void(^callback)(void);

@end


//------------------------------------------------------------------------------------------------------------------------------------------

@interface KVOProxy : NSObject

extern NSString *const KVOContextTypeObservers;
extern NSString *const KVOContextTypeObservees;

/*
 The KVO proxy object's contexts can be indexed by:
 KVOContextTypeObservees: a collection of KVOContexts representing objects we are observers of.
 KVOContextTypeObservees: a collection of KVOContexts representing objects that are observers of us.
 
 This is for information purposes only and you should never attempt to mutate the containers or their elements.
 */
@property (nonatomic, strong, readonly)NSDictionary *contexts;

@end


//------------------------------------------------------------------------------------------------------------------------------------------

@interface NSObject (__EASY_KVO__)

@property (nonatomic, readonly)KVOProxy *kvoProxy;

/*
 Use this method if you want to write the handling of a KVO notification 'in-place' thru a callback,
 as opposed to inside -observeValueForKeyPath:ofObject:change:context:
*/
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context callback:(void(^)(void))callback;

@end
