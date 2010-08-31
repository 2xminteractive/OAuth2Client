//
//  NXOAuth2Client.m
//  OAuth2Client
//
//  Created by Ullrich Schäfer on 26.08.10.
//  Copyright 2010 nxtbgthng. All rights reserved.
//

#import "NXOAuth2Connection.h"
#import "NXOAuth2AccessToken.h"

#import "NSURL+NXOAuth2.h"
#import "NSMutableURLRequest+NXOAuth2.h"

#import "NXOAuth2Client.h"


@interface NXOAuth2Client ()
- (void)requestTokenWithAuthGrand:(NSString *)authGrand andRedirectURL:(NSURL *)redirectURL;
@end


@implementation NXOAuth2Client


#pragma mark Lifecycle

- (id)initWithClientID:(NSString *)aClientId
		  clientSecret:(NSString *)aClientSecret
		  authorizeURL:(NSURL *)anAuthorizeURL
			  tokenURL:(NSURL *)aTokenURL
		  authDelegate:(NSObject<NXOAuth2ClientAuthDelegate> *)anAuthDelegate;
{
	NSAssert(aTokenURL != nil && anAuthorizeURL != nil, @"No token or no authorize URL");
	if (self = [super init]) {
		clientId = [aClientId copy];
		clientSecret = [aClientSecret copy];
		authorizeURL = [anAuthorizeURL copy];
		tokenURL = [aTokenURL copy];
		
		self.authDelegate = anAuthDelegate;
	}
	return self;
}

- (void)dealloc;
{
	[retryConnectionsAfterTokenExchange release];
	[authConnection cancel];
	[authConnection release];
	[clientId release];
	[clientSecret release];
	[super dealloc];
}


#pragma mark Accessors

@synthesize clientId, clientSecret, authDelegate;

@dynamic accessToken;

- (NXOAuth2AccessToken *)accessToken;
{
	if (accessToken) return accessToken;
	accessToken = [[NXOAuth2AccessToken tokenFromDefaultKeychainWithServiceProviderName:[tokenURL host]] retain];
	return accessToken;
}

- (void)setAccessToken:(NXOAuth2AccessToken *)value;
{
	if (!value) {
		[self.accessToken removeFromDefaultKeychainWithServiceProviderName:[tokenURL host]];
	}
	
	[self willChangeValueForKey:@"accessToken"];
	[value retain];	[accessToken release]; accessToken = value;
	[self didChangeValueForKey:@"accessToken"];
	
	[accessToken storeInDefaultKeychainWithServiceProviderName:[tokenURL host]];
}


#pragma mark Flow

- (void)requestAccess;
{
	if (!self.accessToken) {
		[authDelegate oauthClientRequestedAuthorization:self];
	} else {
		[authDelegate oauthClientDidGetAccessToken:self];
	}
}

- (NSURL *)authorizeWithRedirectURL:(NSURL *)redirectURL;
{
	return [authorizeURL URLByAddingParameters:[NSDictionary dictionaryWithObjectsAndKeys:
												@"code", @"response_type",
												clientId, @"client_id",
												[redirectURL absoluteString], @"redirect_uri",
												nil]];
}


// Web Server Flow only
- (BOOL)openRedirectURL:(NSURL *)URL;
{
	NSString *accessGrand = [URL valueForQueryParameterKey:@"code"];
	if (accessGrand) {
		[self requestTokenWithAuthGrand:accessGrand andRedirectURL:[URL URLWithoutQueryString]];
		return YES;
	}
	return NO;
}

#pragma mark accessGrand -> accessToken

// Web Server Flow only
- (void)requestTokenWithAuthGrand:(NSString *)authGrand andRedirectURL:(NSURL *)redirectURL;
{
	NSAssert(!authConnection, @"invalid state");
	
	NSMutableURLRequest *tokenRequest = [NSMutableURLRequest requestWithURL:tokenURL];
	[tokenRequest setHTTPMethod:@"POST"];
	[tokenRequest setParameters:[NSDictionary dictionaryWithObjectsAndKeys:
								 @"authorization_code", @"grant_type",
								 clientId, @"client_id",
								 clientSecret, @"client_secret",
								 [redirectURL absoluteString], @"redirect_uri",
								 authGrand, @"code",
								 nil]];
	[authConnection release]; // just to be sure
	authConnection = [[NXOAuth2Connection alloc] initWithRequest:tokenRequest
													 oauthClient:self
														delegate:self];
}


// User Password Flow Only
- (void)authorizeWithUsername:(NSString *)username password:(NSString *)password;
{
	NSAssert(!authConnection, @"invalid state");
	NSMutableURLRequest *tokenRequest = [NSMutableURLRequest requestWithURL:tokenURL];
	[tokenRequest setHTTPMethod:@"POST"];
	[tokenRequest setParameters:[NSDictionary dictionaryWithObjectsAndKeys:
								 @"password", @"grant_type",
								 clientId, @"client_id",
								 clientSecret, @"client_secret",
								 username, @"username",
								 password, @"password",
								 nil]];
	 [authConnection release]; // just to be sure
	 authConnection = [[NXOAuth2Connection alloc] initWithRequest:tokenRequest
													  oauthClient:self
														 delegate:self];
}


#pragma mark Public

- (void)refreshAccessToken;
{
	[self refreshAccessTokenAndRetryConnection:nil];
}

- (void)refreshAccessTokenAndRetryConnection:(NXOAuth2Connection *)retryConnection;
{
	if (retryConnection) {
		if (!retryConnectionsAfterTokenExchange) retryConnectionsAfterTokenExchange = [[NSMutableArray alloc] init];
		[retryConnectionsAfterTokenExchange addObject:retryConnection];
	}
	if (!authConnection) {
		NSAssert((accessToken.refreshToken != nil), @"invalid state");
		NSMutableURLRequest *tokenRequest = [NSMutableURLRequest requestWithURL:tokenURL];
		[tokenRequest setHTTPMethod:@"POST"];
		[tokenRequest setParameters:[NSDictionary dictionaryWithObjectsAndKeys:
									 @"refresh_token", @"grant_type",
									 clientId, @"client_id",
									 clientSecret, @"client_secret",
									 accessToken.refreshToken, @"refresh_token",
									 nil]];
		[authConnection release]; // not needed, but looks more clean to me :)
		authConnection = [[NXOAuth2Connection alloc] initWithRequest:tokenRequest
														 oauthClient:nil
															delegate:self];	
	}
}

- (void)abortRetryOfConnection:(NXOAuth2Connection *)retryConnection;
{
	if (retryConnection) {
		[retryConnectionsAfterTokenExchange removeObject:retryConnection];
	}
}


#pragma mark NXOAuth2ConnectionDelegate

- (void)oauthConnection:(NXOAuth2Connection *)connection didFinishWithData:(NSData *)data;
{
	if (connection == authConnection) {
		NSString *result = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NXOAuth2AccessToken *newToken = [NXOAuth2AccessToken tokenWithResponseBody:result];
		NSAssert(newToken != nil, @"invalid response?");
		self.accessToken = newToken;
		[authDelegate oauthClientDidGetAccessToken:self];
		
		for (NXOAuth2Connection *retryConnection in retryConnectionsAfterTokenExchange) {
			[retryConnection retry];
		}
		[retryConnectionsAfterTokenExchange removeAllObjects];
	}
}

- (void)oauthConnection:(NXOAuth2Connection *)connection didFailWithError:(NSError *)error;
{
	if (connection == authConnection) {
		[authDelegate oauthClient:self didFailToGetAccessTokenWithError:error]; // TODO: create own error domain?
	}
}


@end
