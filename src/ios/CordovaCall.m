#import "CordovaCall.h"
#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>

@implementation CordovaCall

@synthesize VoIPPushCallbackId, VoIPPushClassName, VoIPPushMethodName;

BOOL hasVideo = NO;
NSString* appName;
NSString* ringtone;
NSString* icon;
BOOL includeInRecents = NO;
NSMutableDictionary *callbackIds;
NSDictionary* pendingCallFromRecents;
BOOL monitorAudioRouteChange = NO;
BOOL enableDTMF = NO;
NSMutableDictionary *currentCallData;
NSMutableDictionary *voipTokenData = NULL;

- (void)pluginInitialize
{
    CXProviderConfiguration *providerConfiguration;
    appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    providerConfiguration = [[CXProviderConfiguration alloc] initWithLocalizedName:appName];
    providerConfiguration.maximumCallGroups = 1;
    providerConfiguration.maximumCallsPerCallGroup = 1;
    NSMutableSet *handleTypes = [[NSMutableSet alloc] init];
    [handleTypes addObject:@(CXHandleTypeGeneric)];
    providerConfiguration.supportedHandleTypes = handleTypes;
    providerConfiguration.supportsVideo = YES;
    if (@available(iOS 11.0, *)) {
        providerConfiguration.includesCallsInRecents = NO;
    }
    self.provider = [[CXProvider alloc] initWithConfiguration:providerConfiguration];
    [self.provider setDelegate:self queue:nil];
    self.callController = [[CXCallController alloc] init];
    //initialize callback dictionary
    callbackIds = [[NSMutableDictionary alloc]initWithCapacity:5];
    [callbackIds setObject:[NSMutableArray array] forKey:@"answer"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"reject"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"hangup"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"sendCall"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"receiveCall"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"mute"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"unmute"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"speakerOn"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"speakerOff"];
    [callbackIds setObject:[NSMutableArray array] forKey:@"DTMF"];
    //allows user to make call from recents
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveCallFromRecents:) name:@"RecentsCallNotification" object:nil];
    //detect Audio Route Changes to make speakerOn and speakerOff event handlers
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAudioRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];

    //http://stackoverflow.com/questions/27245808/implement-pushkit-and-test-in-development-behavior/28562124#28562124
    PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

// CallKit - Interface
- (void)updateProviderConfig
{
    CXProviderConfiguration *providerConfiguration;
    providerConfiguration = [[CXProviderConfiguration alloc] initWithLocalizedName:appName];
    providerConfiguration.maximumCallGroups = 1;
    providerConfiguration.maximumCallsPerCallGroup = 1;
    if(ringtone != nil) {
        providerConfiguration.ringtoneSound = ringtone;
    }
    if(icon != nil) {
        UIImage *iconImage = [UIImage imageNamed:icon];
        NSData *iconData = UIImagePNGRepresentation(iconImage);
        providerConfiguration.iconTemplateImageData = iconData;
    }
    NSMutableSet *handleTypes = [[NSMutableSet alloc] init];
    [handleTypes addObject:@(CXHandleTypeGeneric)];
    providerConfiguration.supportedHandleTypes = handleTypes;
    providerConfiguration.supportsVideo = hasVideo;
    if (@available(iOS 11.0, *)) {
        providerConfiguration.includesCallsInRecents = includeInRecents;
    }

    self.provider.configuration = providerConfiguration;
}

- (void)setupAudioSession
{
    @try {
      AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
      [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
      [sessionInstance setMode:AVAudioSessionModeVoiceChat error:nil];
      NSTimeInterval bufferDuration = .005;
      [sessionInstance setPreferredIOBufferDuration:bufferDuration error:nil];
      [sessionInstance setPreferredSampleRate:44100 error:nil];
      NSLog(@"Configuring Audio");
    }
    @catch (NSException *exception) {
       NSLog(@"Unknown error returned from setupAudioSession");
    }
    return;
}

- (void)setAppName:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* proposedAppName = [command.arguments objectAtIndex:0];

    if (proposedAppName != nil && [proposedAppName length] > 0) {
        appName = proposedAppName;
        [self updateProviderConfig];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"App Name Changed Successfully"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"App Name Can't Be Empty"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setIcon:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* proposedIconName = [command.arguments objectAtIndex:0];

    if (proposedIconName == nil || [proposedIconName length] == 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Icon Name Can't Be Empty"];
    } else if([UIImage imageNamed:proposedIconName] == nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"This icon does not exist. Make sure to add it to your project the right way."];
    } else {
        icon = proposedIconName;
        [self updateProviderConfig];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Icon Changed Successfully"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setRingtone:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* proposedRingtoneName = [command.arguments objectAtIndex:0];
    
    NSLog(@"[objC] setRingtone: %@", proposedRingtoneName);

    if (proposedRingtoneName == nil || [proposedRingtoneName length] == 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Ringtone Name Can't Be Empty"];
    } else {
        ringtone = [NSString stringWithFormat: @"%@.caf", proposedRingtoneName];
        [self updateProviderConfig];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Ringtone Changed Successfully"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setIncludeInRecents:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    includeInRecents = [[command.arguments objectAtIndex:0] boolValue];
    [self updateProviderConfig];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"includeInRecents Changed Successfully"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setDTMFState:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    enableDTMF = [[command.arguments objectAtIndex:0] boolValue];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"enableDTMF Changed Successfully"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setVideo:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    hasVideo = [[command.arguments objectAtIndex:0] boolValue];
    [self updateProviderConfig];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"hasVideo Changed Successfully"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)receiveCall:(CDVInvokedUrlCommand*)command
{
    
//    [args addObject:[caller valueForKey:@"Username"]];
//    [args addObject:[caller valueForKey:@"ConnectionId"]];
//    [args addObject:fromJid];
//    [args addObject:[NSNumber numberWithBool:[callType isEqualToString:@"video"]]];
//    [args addObject:callSignal];
//    [args addObject:callType];
//    [args addObject:chatType];
//    [args addObject:initiatorName];
//    [args addObject:jitsiRoom];
//    [args addObject:jitsiURL];
//    [args addObject:conferenceId];
    
    NSLog(@"[objC] [receiveCall] args: %@", command.arguments);
    BOOL hasId = ![[command.arguments objectAtIndex:1] isEqual:[NSNull null]];
    CDVPluginResult *pluginResult = nil;
    NSString *callerName = [command.arguments objectAtIndex:0];
    NSString *callId = [command.arguments objectAtIndex:1];
    NSUUID *callUUID = [[NSUUID alloc] initWithUUIDString:callId];
    NSString *callerId = [command.arguments objectAtIndex:2];
    BOOL isVideoCall = [[command.arguments objectAtIndex:3] boolValue];
    NSNumber *callSignal = [command.arguments objectAtIndex:4];
    NSString *callType = [command.arguments objectAtIndex:5];
    NSString *chatType = [command.arguments objectAtIndex:6];
    NSString *initiatorName = [command.arguments objectAtIndex:7];
    NSString *jitsiRoom = [command.arguments objectAtIndex:8];
    NSString *jitsiURL = [command.arguments objectAtIndex:9];
    NSString *sound = [command.arguments objectAtIndex:10];
    NSString *conferenceId = [command.arguments objectAtIndex:11];
    
    if ([self hasActiveCall]){
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Skip VoIP for exist call"] callbackId:command.callbackId];
        return;
    }
    
    currentCallData = [NSMutableDictionary dictionaryWithCapacity:9];
    [currentCallData setObject:callSignal forKey:@"callSignal"];
    [currentCallData setObject:callType forKey:@"call_type"];
    [currentCallData setObject:chatType forKey:@"chat_type"];
    [currentCallData setObject:initiatorName forKey:@"initiator_name"];
    [currentCallData setObject:jitsiRoom forKey:@"jitsiRoom"];
    [currentCallData setObject:jitsiURL forKey:@"jitsiURL"];
    [currentCallData setObject:callId forKey:@"call_id"];
    [currentCallData setObject:callerId forKey:@"from_jid"];
    [currentCallData setObject:sound forKey:@"sound"];
    [currentCallData setObject:conferenceId forKey:@"conferenceId"];

    if (hasId) {
        [[NSUserDefaults standardUserDefaults] setObject:callerName forKey:[command.arguments objectAtIndex:1]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    if (callerName != nil && [callerName length] > 0) {
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:callerId];
        CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
        callUpdate.remoteHandle = handle;
        callUpdate.hasVideo = isVideoCall;
        callUpdate.localizedCallerName = callerName;
        callUpdate.supportsGrouping = NO;
        callUpdate.supportsUngrouping = NO;
        callUpdate.supportsHolding = NO;
        callUpdate.supportsDTMF = NO;

        [self.provider reportNewIncomingCallWithUUID:callUUID update:callUpdate completion:^(NSError * _Nullable error) {
            if(error == nil) {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Incoming call successful"] callbackId:command.callbackId];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:command.callbackId];
            }
        }];
        for (id callbackId in callbackIds[@"receiveCall"]) {
            CDVPluginResult* pluginResult = nil;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:currentCallData];
            [pluginResult setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
        }
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Caller id can't be empty"] callbackId:command.callbackId];
    }
}

- (void)sendCall:(CDVInvokedUrlCommand*)command
{
    BOOL hasId = ![[command.arguments objectAtIndex:2] isEqual:[NSNull null]];
    NSString *receiverName = [command.arguments objectAtIndex:0];
    NSString *receiverId = [command.arguments objectAtIndex:1];
    NSString *callId = [command.arguments objectAtIndex:2];
    NSUUID *callUUID = hasId?[[NSUUID alloc] initWithUUIDString:callId] : [[NSUUID alloc] init];
    BOOL isVideoCall = [[command.arguments objectAtIndex:3] boolValue];
    

    if (hasId) {
        [[NSUserDefaults standardUserDefaults] setObject:receiverName forKey:[command.arguments objectAtIndex:1]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    if (receiverId != nil && [receiverId length] > 0) {
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:receiverId];
        CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:callUUID handle:handle];
        startCallAction.contactIdentifier = receiverId;
        startCallAction.video = isVideoCall;
        CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (error == nil) {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Outgoing call successful"] callbackId:command.callbackId];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:command.callbackId];
            }
        }];
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"The caller id can't be empty"] callbackId:command.callbackId];
    }
}

- (void)connectCall:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSArray<CXCall *> *calls = self.callController.callObserver.calls;

    if([calls count] == 1) {
        [self.provider reportOutgoingCallWithUUID:calls[0].UUID connectedAtDate:nil];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call connected successfully"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No call exists for you to connect"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)endCall:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSArray<CXCall *> *calls = self.callController.callObserver.calls;

    if([calls count] == 1) {
        //[self.provider reportCallWithUUID:calls[0].UUID endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
        CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:calls[0].UUID];
        CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (error == nil) {
            } else {
                NSLog(@"%@",[error localizedDescription]);
            }
        }];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call ended successfully"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No call exists for you to connect"];
    }
    
    [currentCallData removeAllObjects];

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)registerEvent:(CDVInvokedUrlCommand*)command
{
    NSString* eventName = [command.arguments objectAtIndex:0];
    if(callbackIds[eventName] != nil) {
        [callbackIds[eventName] addObject:command.callbackId];
    }
    if(pendingCallFromRecents && [eventName isEqual:@"sendCall"]) {
        NSDictionary *callData = pendingCallFromRecents;
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:callData];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)mute:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
//    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
//    if(sessionInstance.isInputGainSettable) {
//      BOOL success = [sessionInstance setInputGain:0.0 error:nil];
//      if(success) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Muted Successfully"];
//      } else {
//        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
//      }
//    } else {
//      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not muted because this device does not allow changing inputGain"];
//    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unmute:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
//    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
//    if(sessionInstance.isInputGainSettable) {
//      BOOL success = [sessionInstance setInputGain:1.0 error:nil];
//      if(success) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Muted Successfully"];
//      } else {
//        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
//      }
//    } else {
//      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not unmuted because this device does not allow changing inputGain"];
//    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)speakerOn:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
//    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
//    BOOL success = [sessionInstance overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
//    if(success) {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Speakerphone is on"];
//    } else {
//      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
//    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)speakerOff:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
//    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
//    BOOL success = [sessionInstance overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
//    if(success) {
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Speakerphone is off"];
//    } else {
//      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
//    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)callNumber:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* phoneNumber = [command.arguments objectAtIndex:0];
    NSString* telNumber = [@"tel://" stringByAppendingString:phoneNumber];
    if (@available(iOS 10.0, *)) {
      [[UIApplication sharedApplication] openURL:[NSURL URLWithString:telNumber]
                                         options:nil
                                         completionHandler:^(BOOL success) {
                                           if(success) {
                                             CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call Successful"];
                                             [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                                           } else {
                                             CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Call Failed"];
                                             [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                                           }
                                         }];
    } else {
      BOOL success = [[UIApplication sharedApplication] openURL:[NSURL URLWithString:telNumber]];
      if(success) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call Successful"];
      } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Call Failed"];
      }
      [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }

}

- (void)receiveCallFromRecents:(NSNotification *) notification
{
    NSString* callID = notification.object[@"callId"];
    NSString* callName = notification.object[@"callName"];
    NSUUID *callUUID = [[NSUUID alloc] init];
    CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:callID];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:callUUID handle:handle];
    startCallAction.video = [notification.object[@"isVideo"] boolValue]?YES:NO;
    startCallAction.contactIdentifier = callName;
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];
    [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
        if (error == nil) {
        } else {
            NSLog(@"%@",[error localizedDescription]);
        }
    }];
}

- (void)handleAudioRouteChange:(NSNotification *) notification
{
    NSLog(@"[objC] [handleAudioRouteChange]");
    if(monitorAudioRouteChange) {
        NSNumber* reasonValue = notification.userInfo[@"AVAudioSessionRouteChangeReasonKey"];
        AVAudioSessionRouteDescription* previousRouteKey = notification.userInfo[@"AVAudioSessionRouteChangePreviousRouteKey"];
        NSArray* outputs = [previousRouteKey outputs];
        NSLog(@"[objC] [handleAudioRouteChange] outputs: %@", outputs);
        if([outputs count] > 0) {
            AVAudioSessionPortDescription *output = outputs[0];
            NSLog(@"[objC] [handleAudioRouteChange] output[0] %@", output);
            if(![output.portType isEqual: @"Speaker"] && [reasonValue isEqual:@4]) {
                for (id callbackId in callbackIds[@"speakerOn"]) {
                    NSLog(@"[objC] [handleAudioRouteChange] notify app 'speakerOn'");
                    CDVPluginResult* pluginResult = nil;
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"speakerOn event called successfully"];
                    [pluginResult setKeepCallbackAsBool:YES];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                }
            } else if([output.portType isEqual: @"Speaker"] && [reasonValue isEqual:@3]) {
                for (id callbackId in callbackIds[@"speakerOff"]) {
                    NSLog(@"[objC] [handleAudioRouteChange] notify app 'speakerOff'");
                    CDVPluginResult* pluginResult = nil;
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"speakerOff event called successfully"];
                    [pluginResult setKeepCallbackAsBool:YES];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
                }
            }
        }
    }
}

// CallKit - Provider
- (void)providerDidReset:(CXProvider *)provider
{
    NSLog(@"%s","providerdidreset");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action
{
    [self setupAudioSession];
    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = action.handle;
    callUpdate.hasVideo = action.video;
    callUpdate.localizedCallerName = action.contactIdentifier;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.supportsHolding = NO;
    callUpdate.supportsDTMF = NO;
    
    [self.provider reportCallWithUUID:action.callUUID updated:callUpdate];
    [action fulfill];
    NSDictionary *callData = @{@"callName":action.contactIdentifier,
                               @"callId": action.handle.value,
                               @"isVideo": action.video?@YES:@NO,
                               @"message": @"sendCall event called successfully"};
    for (id callbackId in callbackIds[@"sendCall"]) {
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:callData];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
    if([callbackIds[@"sendCall"] count] == 0) {
        pendingCallFromRecents = callData;
    }
    //[action fail];
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession
{
    NSLog(@"activated audio");
    monitorAudioRouteChange = YES;
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession
{
    NSLog(@"deactivated audio");
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    [self setupAudioSession];
    [action fulfill];
    for (id callbackId in callbackIds[@"answer"]) {
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:currentCallData];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
    //[action fail];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
    NSArray<CXCall *> *calls = self.callController.callObserver.calls;
    if([calls count] == 1) {
        if(calls[0].hasConnected) {
            for (id callbackId in callbackIds[@"hangup"]) {
                CDVPluginResult* pluginResult = nil;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:currentCallData];
                [pluginResult setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            }
        } else {
            for (id callbackId in callbackIds[@"reject"]) {
                CDVPluginResult* pluginResult = nil;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:currentCallData];
                [pluginResult setKeepCallbackAsBool:YES];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
            }
        }
    }
    
    [currentCallData removeAllObjects];
    monitorAudioRouteChange = NO;
    [action fulfill];
    //[action fail];
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action
{
    [action fulfill];
    BOOL isMuted = action.muted;
    for (id callbackId in callbackIds[isMuted?@"mute":@"unmute"]) {
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:isMuted?@"mute event called successfully":@"unmute event called successfully"];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
    //[action fail];
}

- (void)provider:(CXProvider *)provider performPlayDTMFCallAction:(CXPlayDTMFCallAction *)action
{
    NSLog(@"DTMF Event");
    NSString *digits = action.digits;
    [action fulfill];
    for (id callbackId in callbackIds[@"DTMF"]) {
        CDVPluginResult* pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:digits];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    }
}

// PushKit
- (void)init:(CDVInvokedUrlCommand*)command
{
    self.VoIPPushCallbackId = command.callbackId;
    NSLog(@"[objC][init] callbackId: %@", self.VoIPPushCallbackId);
    
    if (voipTokenData != NULL) {
        NSLog(@"[objC][init] voipTokenData: %@", voipTokenData);
        
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:voipTokenData];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]]; //[pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.VoIPPushCallbackId];
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type{
    if([credentials.token length] == 0) {
        NSLog(@"[objC][pushRegistry] No device token!");
        return;
    }

    //http://stackoverflow.com/a/9372848/534755
    NSLog(@"[objC][pushRegistry] Device token: %@", credentials.token);
    const unsigned *tokenBytes = [credentials.token bytes];
    NSString *sToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                         ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                         ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                         ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];

    NSMutableDictionary* results = [NSMutableDictionary dictionaryWithCapacity:2];
    [results setObject:sToken forKey:@"deviceToken"];
    [results setObject:@"true" forKey:@"registration"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]]; //[pluginResult setKeepCallbackAsBool:YES];
    
    NSLog(@"[objC][pushRegistry] callbackId: %@", self.VoIPPushCallbackId);
    
    if (self.VoIPPushCallbackId != NULL) {
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.VoIPPushCallbackId];
    } else {
        voipTokenData = results;
    }
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    
    // {
    //     aps =     {
    //         alert =         {
    //             body = "Incoming audio call";
    //             title = "Talal Waseem";
    //         };
    //         category = AUDIO;
    //         "content-available" = 1;
    //         sound = "incoming-call-loop.caf";
    //         "thread-id" = "";
    //     };
    //     callSignal = 1;
    //     "call_type" = audio;
    //     "chat_type" = invite;
    //     data = "{\"Caller\":{\"Username\":\"Talal Waseem\",\"ConnectionId\":\"b5b23ef3-857e-4fb2-9cea-169f32092879\"}}";
    //     "from_jid" = "talal.waseem@dev.vnc.de";
    //     "initiator_name" = "Talal Waseem";
    //     jitsiRoom = 72sjomnfjw;
    //     jitsiURL = "https://prod-a.bridge.vnclagoon.com/72sjomnfjw";
    //     conferenceId = "ihor.khomenko#vnc.biz,kapil.nadiyapara#dev.vnc.de";
    // }
    
    NSDictionary *payloadDict = payload.dictionaryPayload[@"aps"];
    NSLog(@"[objC] didReceiveIncomingPushWithPayload: %@", payload.dictionaryPayload);
    
    NSString *sound = payloadDict[@"sound"];

    NSString *message = payloadDict[@"alert"];
    NSLog(@"[objC] received VoIP message: %@", message);
    
    NSNumber *callSignal = payload.dictionaryPayload[@"callSignal"];
    NSString *callType = payload.dictionaryPayload[@"call_type"];
    NSString *chatType = payload.dictionaryPayload[@"chat_type"];
    NSString *fromJid = payload.dictionaryPayload[@"from_jid"];
    NSString *initiatorName = payload.dictionaryPayload[@"initiator_name"];
    NSString *jitsiRoom = payload.dictionaryPayload[@"jitsiRoom"];
    NSString *jitsiURL = payload.dictionaryPayload[@"jitsiURL"];
    NSString *conferenceId = payload.dictionaryPayload[@"conferenceId"];
    
    NSString *data = payload.dictionaryPayload[@"data"];
    NSLog(@"[objC] received data: %@", data);
    
    NSMutableDictionary* results = [NSMutableDictionary dictionaryWithCapacity:2];
    [results setObject:message forKey:@"function"];
    [results setObject:data forKey:@"extra"];
    
    ringtone = sound;
    NSLog(@"[objC] ringtone: %@", ringtone);
    
    hasVideo = [callType isEqualToString:@"video"];
    NSLog(@"[objC] callType: %@", callType);
    
    [self updateProviderConfig];
    
    @try {
        NSError* error;
        NSDictionary* json = [NSJSONSerialization JSONObjectWithData:[data dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
        
        NSObject *caller = [json objectForKey:@"Caller"];
        NSMutableArray *args = [NSMutableArray array];
        [args addObject:[caller valueForKey:@"Username"]];
        [args addObject:[caller valueForKey:@"ConnectionId"]];
        [args addObject:fromJid];
        [args addObject:[NSNumber numberWithBool:[callType isEqualToString:@"video"]]];
        [args addObject:callSignal];
        [args addObject:callType];
        [args addObject:chatType];
        [args addObject:initiatorName];
        [args addObject:jitsiRoom];
        [args addObject:jitsiURL];
        [args addObject:sound];
        [args addObject:conferenceId];
        
        CDVInvokedUrlCommand* newCommand = [[CDVInvokedUrlCommand alloc] initWithArguments:args callbackId:@"" className:self.VoIPPushClassName methodName:self.VoIPPushMethodName];
        
        NSLog(@"[objC] [pushRegistry] receiveCall: %@", args);
        
        [self receiveCall:newCommand];
    }
    @catch (NSException *exception) {
       NSLog(@"[objC] error: %@", exception.reason);
    }
    @finally {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.VoIPPushCallbackId];
    }
}

-(BOOL) hasActiveCall
{
    return currentCallData != nil
    && [currentCallData valueForKey:@"call_id"] != nil
    && [[currentCallData valueForKey:@"call_id"] length] > 0;
}

@end
