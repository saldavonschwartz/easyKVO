//
//  NSObject+__EASY_KVO__.h
//  CoreData
//
//  Created by Federico Saldarini on 7/17/13.
//  Copyright (c) 2013 Federico Saldarini. All rights reserved.
//


@interface NSObject (__EASY_KVO__)

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context callback:(void(^)(void))callback;

@end
