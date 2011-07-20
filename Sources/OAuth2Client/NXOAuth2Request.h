//
//  NXOAuth2Request.h
//  OAuth2Client
//
//  Created by Tobias Kräntzer on 13.07.11.
//  Copyright 2011 nxtbgthng. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^NXOAuth2RequestResponseHandler)(NSData *responseData, NSError *error);
typedef void(^NXOAuth2RequestProgressHandler)(unsigned long long bytesSend, unsigned long long bytesTotal);

@class NXOAuth2Account;
@class NXOAuth2Connection;

@interface NXOAuth2Request : NSObject {
@private    
    NSDictionary *parameters;
    NSURL *resource;
    NSString * requestMethod;
    NXOAuth2Account *account;
    NXOAuth2Connection *connection;
    NXOAuth2RequestResponseHandler responseHandler;
    NXOAuth2RequestProgressHandler progressHandler;
    NXOAuth2Request *me;
}

+ (void)performMethod:(NSString *)method
           onResource:(NSURL *)resource
      usingParameters:(NSDictionary *)parameters
          withAccount:(NXOAuth2Account *)account
  sendProgressHandler:(NXOAuth2RequestProgressHandler)progressHandler
      responseHandler:(NXOAuth2RequestResponseHandler)responseHandler;

#pragma mark Lifecycle

+ (id)requestOnResource:(NSURL *)url withMethod:(NSString *)method usingParameters:(NSDictionary *)parameter;
- (id)initWithResource:(NSURL *)url method:(NSString *)method parameters:(NSDictionary *)parameter;


#pragma mark Accessors

@property(nonatomic, readwrite, retain) NXOAuth2Account *account;
@property(nonatomic, readonly) NSDictionary *parameters;
@property(nonatomic, readonly) NSString *requestMethod;
@property(nonatomic, readonly) NSURL *resource;


#pragma mark Perform Request

- (void)performRequestWithResponseHandler:(NXOAuth2RequestResponseHandler)handler;
- (void)performRequestWithResponseHandler:(NXOAuth2RequestResponseHandler)handler sendProgressHandler:(NXOAuth2RequestProgressHandler)progresHandler;

@end
