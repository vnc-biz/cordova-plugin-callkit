#import "AppDelegate.h"
#import "Intents/Intents.h"
#import <CallKit/CallKit.h>
#import <objc/runtime.h>

@implementation AppDelegate (CordovaCall)

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray *restorableObjects))restorationHandler
{
    NSLog(@"[AppDelegateCordovaCall][continueUserActivity]");
    INInteraction *interaction = userActivity.interaction;
    INIntent *intent = interaction.intent;
    BOOL isVideo = [intent isKindOfClass:[INStartVideoCallIntent class]];
    INPerson *contact;
    if(isVideo) {
        INStartVideoCallIntent *startCallIntent = (INStartVideoCallIntent *)intent;
        contact = startCallIntent.contacts.firstObject;
    } else {
        INStartAudioCallIntent *startCallIntent = (INStartAudioCallIntent *)intent;
        contact = startCallIntent.contacts.firstObject;
    }
    INPersonHandle *personHandle = contact.personHandle;
    NSString *callId = personHandle.value;
    NSString *callName = [[NSUserDefaults standardUserDefaults] stringForKey:callId];
    if(!callName) {
        callName = callId;
    }
    NSDictionary *intentInfo = @{ @"callName" : callName, @"callId" : callId, @"isVideo" : isVideo?@YES:@NO};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RecentsCallNotification" object:intentInfo];
    return YES;
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    NSLog(@"[AppDelegateCordovaCall][didReceiveRemoteNotification] userInfo: %@", userInfo);
    NSString *callSignalType = [userInfo valueForKey:@"call_signal_type"];
    if(callSignalType != nil){
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CallSignalNotification" object:userInfo];
    }
    
    completionHandler(UIBackgroundFetchResultNewData);
}
@end
