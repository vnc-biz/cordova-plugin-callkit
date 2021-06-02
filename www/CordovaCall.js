var exec = require('cordova/exec');

exports.setAppName = function(appName, success, error) {
    exec(success, error, "CordovaCall", "setAppName", [appName]);
};

exports.setIcon = function(iconName, success, error) {
    exec(success, error, "CordovaCall", "setIcon", [iconName]);
};

exports.setRingtone = function(ringtoneName, success, error) {
    exec(success, error, "CordovaCall", "setRingtone", [ringtoneName]);
};

exports.setIncludeInRecents = function(value, success, error) {
    if(typeof value == "boolean") {
      exec(success, error, "CordovaCall", "setIncludeInRecents", [value]);
    } else {
      error("Value Must Be True Or False");
    }
};

exports.setDTMFState = function(value, success, error) {
    if(typeof value == "boolean") {
      exec(success, error, "CordovaCall", "setDTMFState", [value]);
    } else {
      error("Value Must Be True Or False");
    }
};

exports.setVideo = function(value, success, error) {
    if(typeof value == "boolean") {
      exec(success, error, "CordovaCall", "setVideo", [value]);
    } else {
      error("Value Must Be True Or False");
    }
};

/**
 * 
 * @param {string} callerName - The name of the person you want to get a call from
 * @param {string} callerId - The user id that allows you to identify the person's name
 * @param {string} callId - The unique identifier for the call, should be a UUID string
 * @param {int} callType - The type of call, 1 - for video, 0 - for audio
 * @param {function} success - A callback that gets executed if the incoming call is successful
 * @param {function} error - A callback that gets executed if the incoming call fails
 */
exports.receiveCall = function(callerName, callerId, callId, callType, success, error) {
  if(!callerName || !callerId || !callId){
    error("Parameters: callerName, callerId, callId, isVideo - can nor be null or empty");
  } else {
    exec(success, error, "CordovaCall", "receiveCall", [callerName, callerId, callId, callType]);
  }
};

/**
 * 
 * @param {string} receiverName - The name of the person you want to call
 * @param {string} receiverId - The user id that allows you to identify the person's name
 * @param {int} callType - The type of call, 1 - for video, 0 - for audio
 * @param {function} success - A callback that gets executed if the outgoing call is successful
 * @param {function} error - A callback that gets executed if the outgoing call fails
 */
exports.sendCall = function(receiverName, receiverId, callType, success, error) {
    if(!receiverName || !receiverId){
      error("Parameters: receiverName, receiverId - can nor be null or empty");
    } else {
      exec(success, error, "CordovaCall", "sendCall", [receiverName, receiverId, callType]);
    }
};

exports.connectCall = function(success, error) {
    exec(success, error, "CordovaCall", "connectCall", []);
};

exports.endCall = function(success, error) {
    exec(success, error, "CordovaCall", "endCall", []);
};

exports.mute = function(success, error) {
    exec(success, error, "CordovaCall", "mute", []);
};

exports.unmute = function(success, error) {
    exec(success, error, "CordovaCall", "unmute", []);
};

exports.speakerOn = function(success, error) {
    exec(success, error, "CordovaCall", "speakerOn", []);
};

exports.speakerOff = function(success, error) {
    exec(success, error, "CordovaCall", "speakerOff", []);
};

exports.callNumber = function(to, success, error) {
    exec(success, error, "CordovaCall", "callNumber", [to]);
};

exports.on = function(e, f) {
    var success = function(message) {
      f(message);
    };
    var error = function() {
    };
    exec(success, error, "CordovaCall", "registerEvent", [e]);
};
