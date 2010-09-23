//
//  SHKSoundCloud.h
//  ShareKit
//
//  Created by Frederik Seiffert on 09/20/10.

//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//


#import "SHKSoundCloud.h"

#if SHKSoundCloudUseSandbox
	#warning Using SoundCloud sandbox
	#define kSoundCloudAPIURL						@"http://api.sandbox-soundcloud.com"
	#define kSoundCloudAPIRequestTokenURL			@"http://api.sandbox-soundcloud.com/oauth/request_token"
	#define kSoundCloudAPIAccesTokenURL				@"http://api.sandbox-soundcloud.com/oauth/access_token"
	#define kSoundCloudAuthURL						@"http://sandbox-soundcloud.com/oauth/authorize"
#else
	#define kSoundCloudAPIURL						@"http://api.soundcloud.com"
	#define kSoundCloudAPIRequestTokenURL			@"http://api.soundcloud.com/oauth/request_token"
	#define kSoundCloudAPIAccesTokenURL				@"http://api.soundcloud.com/oauth/access_token"
	#define kSoundCloudAuthURL						@"http://soundcloud.com/oauth/authorize"
#endif


@implementation SHKSoundCloud
@synthesize permalink;

- (void)dealloc
{
	[permalink release];
	
	[super dealloc];
}


#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return @"SoundCloud";
}

+ (BOOL)canShareFile
{
	return YES;
}


#pragma mark -
#pragma mark Authentication

- (id)init
{
	if (self = [super init])
	{		
		self.consumerKey = SHKSoundCloudConsumerKey;		
		self.secretKey = SHKSoundCloudSecretKey;
 		self.authorizeCallbackURL = [NSURL URLWithString:@"oob"];	// out-of-band (for some reason real callback URLs don't work)
		
		
		// -- //
		
		
		// You do not need to edit these, they are the same for everyone
	    self.requestURL = [NSURL URLWithString:kSoundCloudAPIRequestTokenURL];
	    self.accessURL = [NSURL URLWithString:kSoundCloudAPIAccesTokenURL];
	    self.authorizeURL = [NSURL URLWithString:kSoundCloudAuthURL];
		
		self.signatureProvider = [[[OAHMAC_SHA1SignatureProvider alloc] init] autorelease];
	}	
	return self;
}

- (void)tokenRequestModifyRequest:(OAMutableURLRequest *)oRequest
{
	[oRequest setOAuthParameterName:@"oauth_callback" withValue:self.authorizeCallbackURL.absoluteString];
}

- (void)tokenAccessModifyRequest:(OAMutableURLRequest *)oRequest
{
	[oRequest setOAuthParameterName:@"oauth_verifier" withValue:[self.authorizeResponseQueryVars objectForKey:@"oauth_verifier"]];
}

- (void)tokenAuthorizeView:(SHKOAuthView *)authView didFinishLoadingWebView:(UIWebView *)webView
{
	// try to extract authorization code from web view
	NSString *webViewAccessToken = [webView stringByEvaluatingJavaScriptFromString:@"document.getElementsByTagName('input')[0].getAttribute('value')"];
	if ([webViewAccessToken intValue] > 0)
	{
		[[SHK currentHelper] hideCurrentViewControllerAnimated:YES];
		
		self.authorizeResponseQueryVars = [NSDictionary dictionaryWithObject:webViewAccessToken forKey:@"oauth_verifier"];
		[self tokenAccess];
	}
}


#pragma mark -
#pragma mark Share Form

- (NSArray *)shareFormFieldsForType:(SHKShareType)type
{
	if (type == SHKShareTypeFile)
	{
		return [NSArray arrayWithObjects:
				[SHKFormFieldSettings label:SHKLocalizedString(@"Title") key:@"title" type:SHKFormFieldTypeText start:self.item.title],
				[SHKFormFieldSettings label:SHKLocalizedString(@"Description") key:@"text" type:SHKFormFieldTypeText start:self.item.text],
				[SHKFormFieldSettings label:SHKLocalizedString(@"Genre") key:@"genre" type:SHKFormFieldTypeText start:@""],
				[SHKFormFieldSettings label:SHKLocalizedString(@"Public") key:@"public" type:SHKFormFieldTypeSwitch start:SHKFormFieldSwitchOff],
				nil];
	}
	
	return nil;
}

+ (BOOL)canAutoShare
{
	return NO;
}


#pragma mark -
#pragma mark Implementation

- (NSURL *)URLForResource:(NSString *)resource
{
	return [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", kSoundCloudAPIURL, resource]];
}

- (BOOL)send
{	
	if (![self validateItem])
		return NO;
	
	OAMutableURLRequest *oRequest = [[[OAMutableURLRequest alloc] initWithURL:[self URLForResource:@"tracks"]
																	 consumer:self.consumer // this is a consumer object already made available to us
																		token:self.accessToken // this is our accessToken already made available to us
																		realm:nil
															signatureProvider:self.signatureProvider] autorelease];
	[oRequest setHTTPMethod:@"POST"];
	
	NSString *description = self.item.text;
	if (SHKSoundCloudSignature)
	{
		if ([description length] > 0)
			description = [description stringByAppendingString:@"\n\n"];
		description = [description stringByAppendingString:SHKSoundCloudSignature];
	}
	
	[oRequest setParameters:[NSArray arrayWithObjects:
							 [[[OARequestParameter alloc] initWithName:@"track[title]" value:self.item.title] autorelease],
							 [[[OARequestParameter alloc] initWithName:@"track[description]" value:description] autorelease],
							 [[[OARequestParameter alloc] initWithName:@"track[genre]" value:[self.item customValueForKey:@"genre"]] autorelease],
							 [[[OARequestParameter alloc] initWithName:@"track[sharing]" value:([self.item customBoolForSwitchKey:@"public"] ? @"public" : @"private")] autorelease],
							 nil]];
	[oRequest attachFileWithName:@"track[asset_data]" filename:self.item.filename contentType:self.item.mimeType data:self.item.data];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																						  delegate:self
																				 didFinishSelector:@selector(sendTicket:didFinishWithData:)
																				   didFailSelector:@selector(sendTicket:didFailWithError:)
																			   didProgressSelector:@selector(sendTicket:didProgress:)];
	[fetcher start];
	
	[self sendDidStart];
	
	return YES;
}

- (void)sendTicket:(OAServiceTicket *)ticket didProgress:(NSNumber *)progressNum
{
	float progress = [progressNum floatValue];
	if (progress >= 1.0)
		[[SHKActivityIndicator currentIndicator] showSpinner];
	else
		[[SHKActivityIndicator currentIndicator] setProgress:progress];
}

- (void)sendTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{	
	if (ticket.didSucceed)
	{
		// try to extract permalink from XML
		// TODO: improve parsing so it always returns /track/permalink-url independent of XML node order
		NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSScanner *scanner = [NSScanner scannerWithString:dataString];
		if ([scanner scanUpToString:@"<permalink-url>" intoString:nil]) {
			[scanner scanString:@"<permalink-url>" intoString:nil];
			NSString *permalinkString = nil;
			if ([scanner scanUpToString:@"</permalink-url>" intoString:&permalinkString]) {
				[permalink release];
				permalink = [[NSURL URLWithString:permalinkString] retain];
			}
		}
		
		[self sendDidFinish];
	}
	else if (ticket.response.statusCode == 401)
	{
		// e.g. access was revoked
		self.pendingAction = SHKPendingRefreshToken;
		[self sendDidFailShouldRelogin];
	}
	else 
	{
		NSString *errorString = SHKLocalizedString(@"Unknown error");
		
		// try to extract first error from XML
		NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSScanner *scanner = [NSScanner scannerWithString:dataString];
		if ([scanner scanUpToString:@"<error>" intoString:nil]) {
			[scanner scanString:@"<error>" intoString:nil];
			[scanner scanUpToString:@"</error>" intoString:&errorString];
		}
		
		[self sendDidFailWithError:[SHK error:errorString] shouldRelogin:NO];
	}
}

@end
