//
//  FXKeychain.m
//
//  Version 1.5.2
//
//  Created by Nick Lockwood on 29/12/2012.
//  Copyright 2012 Charcoal Design
//
//  Distributed under the permissive zlib License
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/FXKeychain
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//


#import "FXKeychain.h"


#import <Availability.h>
#if !__has_feature(objc_arc)
#error This class requires automatic reference counting
#endif


@implementation NSObject (FXKeychainPropertyListCoding)

- (id)FXKeychain_propertyListRepresentation
{
    return self;
}

@end

#if !FXKEYCHAIN_USE_NSCODING

@implementation NSNull (FXKeychainPropertyListCoding)

- (id)FXKeychain_propertyListRepresentation
{
    return nil;
}

@end


@implementation NSArray (BMPropertyListCoding)

- (id)FXKeychain_propertyListRepresentation
{
    NSMutableArray *copy = [NSMutableArray arrayWithCapacity:[self count]];
    for (id obj in self)
    {
        id value = [obj FXKeychain_propertyListRepresentation];
        if (value) [copy addObject:value];
    }
    return copy;
}

@end


@implementation NSDictionary (BMPropertyListCoding)

- (id)FXKeychain_propertyListRepresentation
{
    NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:[self count]];
    [self enumerateKeysAndObjectsUsingBlock:^(__unsafe_unretained id key, __unsafe_unretained id obj, __unused BOOL *stop) {
        
        id value = [obj FXKeychain_propertyListRepresentation];
        if (value) copy[key] = value;
    }];
    return copy;
}

@end

#endif

#define kDefaultStorageKey @"FXKeychain"


@implementation FXKeychain

+ (instancetype)defaultKeychain
{
    static id sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        NSString *bundleID = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleIdentifierKey];
        sharedInstance = [[FXKeychain alloc] initWithService:bundleID
                                                 accessGroup:nil];
    });
    
    return sharedInstance;
}

- (id)init
{
    return [self initWithService:nil accessGroup:nil];
}

- (void)setAccessibility:(FXKeychainAccess)accessibility
{
    if (accessibility == FXKeychainAccessibleWhenPasscodeSetThisDeviceOnly && NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_1) {
        [NSException raise:@"Invalid Argument" format:@"FXKeychainAccessibleWhenPasscodeSetThisDeviceOnly is availble on iOS8+ only"];
    }
    _accessibility = accessibility;
}

- (id)initWithService:(NSString *)service
          accessGroup:(NSString *)accessGroup
{
    return [self initWithService:service
                     accessGroup:accessGroup
                   accessibility:FXKeychainAccessibleWhenUnlockedThisDeviceOnly];
}

- (id)initWithService:(NSString *)service
          accessGroup:(NSString *)accessGroup
        accessibility:(FXKeychainAccess)accessibility
{
    if ((self = [super init]))
    {
        _service = [service copy];
        _accessGroup = [accessGroup copy];
        _accessibility = accessibility;
    }
    return self;
}

- (BOOL)dataExistsForKey:(id)key
{
    //This can be the case when creating/updating secured key, or updating from secured key to unsecured key
    //generate query
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if ([self.service length]) query[(__bridge NSString *)kSecAttrService] = self.service;
    query[(__bridge NSString *)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    query[(__bridge NSString *)kSecReturnData] = (__bridge id)kCFBooleanFalse;
    query[(__bridge NSString *)kSecAttrAccount] = [key description];
    
    
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_7_1) {
        query[(__bridge NSString *)kSecUseNoAuthenticationUI] = (__bridge id)kCFBooleanTrue;
    }
    if ([_accessGroup length]) query[(__bridge NSString *)kSecAttrAccessGroup] = _accessGroup;
#endif
    
    //check data
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    if (status == errSecSuccess || status == errSecInteractionNotAllowed) {
        return YES;
    }
    else if (status == errSecItemNotFound) {
        return NO;
    }
    else {
        NSLog(@"FXKeychain failed to retrieve data for key '%@', error: %ld", key, (long)status);
        return NO;
    }
}

- (NSData *)dataForKey:(id)key reason:(NSString *)reason
{
    //generate query
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if ([self.service length]) query[(__bridge NSString *)kSecAttrService] = self.service;
    query[(__bridge NSString *)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    query[(__bridge NSString *)kSecReturnData] = (__bridge id)kCFBooleanTrue;
    query[(__bridge NSString *)kSecAttrAccount] = [key description];
    
    
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_7_1 && reason) {
        query[(__bridge NSString *)kSecUseOperationPrompt] = reason;
    }
    
    if ([_accessGroup length]) query[(__bridge NSString *)kSecAttrAccessGroup] = _accessGroup;
    
#endif
    
    //recover data
    CFDataRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&data);
    
    if (status == errSecUserCanceled) {
        NSLog(@"FXKeychain user cancelled operation");
    }
    else if (status == errSecAuthFailed) {
        NSLog(@"FXKeuchain user auth failed");
    }
    else if (status != errSecSuccess && status != errSecItemNotFound)
    {
        NSLog(@"FXKeychain failed to retrieve data for key '%@', error: %ld", key, (long)status);
    }
    return CFBridgingRelease(data);
}

- (BOOL)setObject:(id)object forKey:(id)key
{
    return [self setObject:object forKey:key protectWithTouchID:NO];
}

- (BOOL)setObject:(id)object forKey:(id)key protectWithTouchID:(BOOL)protect
{
    NSParameterAssert(key);
    
    
    if (protect) {
#if !TARGET_OS_IPHONE
        [NSException raise:@"NSInvalidArgumentException" format:@"TouchID protection is available only for iOS"];
        return NO;
#endif
        if (NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_1) {
            [NSException raise:@"NSInvalidArgumentException" format:@"TouchID protection is available only for iOS 8+"];
            return NO;
        }
    }
    
    //generate query
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if ([self.service length]) query[(__bridge NSString *)kSecAttrService] = self.service;
    query[(__bridge NSString *)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge NSString *)kSecAttrAccount] = [key description];
    
    NSError *error = nil;
    
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    if ([_accessGroup length]) query[(__bridge NSString *)kSecAttrAccessGroup] = _accessGroup;
    
#endif
    
    //encode object
    NSData *data = nil;
    if ([(id)object isKindOfClass:[NSString class]])
    {
        //check that string data does not represent a binary plist
        NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
        if (![object hasPrefix:@"bplist"] || ![NSPropertyListSerialization propertyListWithData:[object dataUsingEncoding:NSUTF8StringEncoding]
                                                                                        options:NSPropertyListImmutable
                                                                                         format:&format
                                                                                          error:NULL])
        {
            //safe to encode as a string
            data = [object dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
    
    //if not encoded as a string, encode as plist
    if (object && !data)
    {
        data = [NSPropertyListSerialization dataWithPropertyList:[object FXKeychain_propertyListRepresentation]
                                                          format:NSPropertyListBinaryFormat_v1_0
                                                         options:0
                                                           error:&error];
#if FXKEYCHAIN_USE_NSCODING
        
        //property list encoding failed. try NSCoding
        if (!data)
        {
            data = [NSKeyedArchiver archivedDataWithRootObject:object];
        }
        
#endif
        
    }
    
    //fail if object is invalid
    NSAssert(!object || (object && data), @"FXKeychain failed to encode object for key '%@', error: %@", key, error);
    
    if (data)
    {
        //update values
        NSMutableDictionary *update = [@{(__bridge NSString *)kSecValueData: data} mutableCopy];
        
        //write data
        OSStatus status = errSecSuccess;
        
        //Don't read item protected by TouchID, since it will bring the UI for authentication...
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
        BOOL authWithTouchID = NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_7_1 && protect;
#else
        BOOL authWithTouchID = NO;
#endif
        if (authWithTouchID) {
            CFErrorRef err = NULL;
            SecAccessControlRef sacObject = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                                            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                                            kSecAccessControlUserPresence, &err);
            if (sacObject == NULL || err != NULL) {
                NSLog(@"FXKeychain failed to create access control object, error: %@", err);
                return NO;
            }
            update[(__bridge NSString *)kSecAttrAccessControl] = CFBridgingRelease(sacObject);
        }
        else {
#if TARGET_OS_IPHONE || __MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_9
            if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_7_1) {
                update[(__bridge NSString *)kSecAttrAccessible] = @[(__bridge id)kSecAttrAccessibleWhenUnlocked,
                                                                    (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
                                                                    (__bridge id)kSecAttrAccessibleAlways,
                                                                    (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                    (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                                                    (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly,
                                                                    (__bridge id)kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly][self.accessibility];
            }
            else {
                update[(__bridge NSString *)kSecAttrAccessible] = @[(__bridge id)kSecAttrAccessibleWhenUnlocked,
                                                                    (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
                                                                    (__bridge id)kSecAttrAccessibleAlways,
                                                                    (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                    (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                                                    (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly][self.accessibility];
            }
#endif
        }
        
        if ([self dataExistsForKey:key]) {
            if (authWithTouchID && [[[UIDevice currentDevice] systemName] floatValue] == 8.0) {
                //Workaround for https://developer.apple.com/library/ios/releasenotes/General/RN-iOSSDK-8.0/
                status = SecItemDelete((__bridge CFDictionaryRef)query);
                if (status == errSecSuccess) {
                    status = [self addSecItem:query update:update];
                }
            }
            else {
                status = [self updateSecItem:query update:update];
            }
        }
        else {
            status = [self addSecItem:query update:update];
        }
        
        if (status == errSecUserCanceled) {
            NSLog(@"FXKeychain user cancelled operation");
        }
        else if (status == errSecAuthFailed) {
            NSLog(@"FXKeuchain user auth failed");
        }
        else if (status != errSecSuccess)
        {
            NSLog(@"FXKeychain failed to store data for key '%@', error: %ld", key, (long)status);
            return NO;
        }
    }
    else if (self[key])
    {
        //delete existing data
        
#if TARGET_OS_IPHONE
        
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
#else
        CFTypeRef result = NULL;
        query[(__bridge id)kSecReturnRef] = (__bridge id)kCFBooleanTrue;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status == errSecSuccess)
        {
            status = SecKeychainItemDelete((SecKeychainItemRef) result);
            CFRelease(result);
        }
#endif
        if (status == errSecUserCanceled) {
            NSLog(@"FXKeychain user cancelled operation");
        }
        else if (status == errSecAuthFailed) {
            NSLog(@"FXKeuchain user auth failed");
        }
        else if (status != errSecSuccess)
        {
            NSLog(@"FXKeychain failed to delete data for key '%@', error: %ld", key, (long)status);
            return NO;
        }
    }
    return YES;
}

//no existing data, add a new item
- (OSStatus)addSecItem:(NSDictionary *)query update:(NSDictionary *)update
{
    NSMutableDictionary *copy = [query mutableCopy];
    [copy addEntriesFromDictionary:update];
    return SecItemAdd ((__bridge CFDictionaryRef)copy, NULL);
}

//there's already existing data for this key, update it
- (OSStatus)updateSecItem:(NSDictionary *)query update:(NSDictionary *)update
{
    return SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
}

- (BOOL)setObject:(id)object forKeyedSubscript:(id)key
{
    return [self setObject:object forKey:key];
}

- (BOOL)removeObjectForKey:(id)key
{
    return [self setObject:nil forKey:key];
}

- (id)objectForKey:(id)key
{
    return [self objectForKey:key reason:nil];
}

- (id)objectForKey:(id)key reason:(NSString *)reason
{
    NSData *data = [self dataForKey:key reason:reason];
    if (data)
    {
        id object = nil;
        NSError *error = nil;
        NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
        
        //check if data is a binary plist
        if ([data length] >= 6 && !strncmp("bplist", data.bytes, 6))
        {
            //attempt to decode as a plist
            object = [NSPropertyListSerialization propertyListWithData:data
                                                               options:NSPropertyListImmutable
                                                                format:&format
                                                                 error:&error];
            
            if ([object respondsToSelector:@selector(objectForKey:)] && object[@"$archiver"])
            {
                //data represents an NSCoded archive
                
#if FXKEYCHAIN_USE_NSCODING
                
                //parse as archive
                object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#else
                //don't trust it
                object = nil;
#endif
                
            }
        }
        if (!object || format != NSPropertyListBinaryFormat_v1_0)
        {
            //may be a string
            object = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if (!object)
        {
            NSLog(@"FXKeychain failed to decode data for key '%@', error: %@", key, error);
        }
        return object;
    }
    else
    {
        //no value found
        return nil;
    }
}

- (id)objectForKeyedSubscript:(id)key
{
    return [self objectForKey:key];
}

@end
