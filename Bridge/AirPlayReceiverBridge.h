#ifndef AirPlayReceiverBridge_h
#define AirPlayReceiverBridge_h

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AirPlayBridgeState) {
    AirPlayBridgeStateStopped,
    AirPlayBridgeStateStarting,
    AirPlayBridgeStateRunning,
    AirPlayBridgeStateConnected,
    AirPlayBridgeStateFailed
};

@class AirPlayReceiverBridge;

@protocol AirPlayReceiverBridgeDelegate <NSObject>
@optional
- (void)receiverDidStartOnPort:(uint16_t)port;
- (void)receiverDidStop;
- (void)receiverDidRequestPIN:(NSString *)pin;
- (void)receiverDidConnectSession:(uint64_t)sessionID
                       deviceName:(NSString *)name
                            model:(NSString *)model
    NS_SWIFT_NAME(receiverDidConnect(sessionID:name:model:));
- (void)receiverDidReceiveVideoData:(NSData *)data
                         forSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidReceiveVideoData(_:sessionID:));
- (void)receiverDidSetAudioFormat:(uint8_t)compressionType
                       sampleRate:(uint32_t)sampleRate
                  framesPerPacket:(uint16_t)framesPerPacket
                       forSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidSetAudioFormat(compressionType:sampleRate:framesPerPacket:sessionID:));
- (void)receiverDidReceiveAudioData:(NSData *)data
                         forSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidReceiveAudioData(_:sessionID:));
- (void)receiverDidSetAudioVolume:(float)decibels
                       forSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidSetAudioVolume(_:sessionID:));
- (void)receiverDidFlushAudioForSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidFlushAudio(sessionID:));
- (void)receiverDidStopAudioForSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidStopAudio(sessionID:));
- (void)receiverDidDisconnectSession:(uint64_t)sessionID
    NS_SWIFT_NAME(receiverDidDisconnect(sessionID:));
@end

@interface AirPlayReceiverBridge : NSObject

@property (nonatomic, weak) id<AirPlayReceiverBridgeDelegate> delegate;
@property (nonatomic, readonly) AirPlayBridgeState state;
@property (nonatomic, copy) NSString *receiverName;
@property (nonatomic, assign) uint16_t pin;
@property (nonatomic, assign, getter=isPinFixed) BOOL pinFixed;

// Exposed for C callback access
@property (nonatomic, strong, readonly) NSString *pairingRegisterPath;

- (instancetype)initWithReceiverName:(NSString *)name pin:(uint16_t)pin;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (void)disconnectSession:(uint64_t)sessionID
    NS_SWIFT_NAME(disconnect(sessionID:));
- (BOOL)isRunning;

@end

NS_ASSUME_NONNULL_END

#endif /* AirPlayReceiverBridge_h */
