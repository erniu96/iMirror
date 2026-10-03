#import "AirPlayReceiverBridge.h"

#include "raop.h"
#include "pairing.h"
#include "dnssd.h"
#include "logger.h"
#include "stream.h"
#include "global.h"

#include <ifaddrs.h>
#include <net/if_dl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <net/if.h>
#include <sys/sysctl.h>

#define MAX_ACTIVE_SESSIONS 10
#define NTP_TIMEOUT_LIMIT 5

static void get_mac(uint8_t mac[6]) {
    struct ifaddrs *ifaddrs;
    if (getifaddrs(&ifaddrs) != 0) return;
    struct ifaddrs *ifa = ifaddrs;
    do {
        if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_INET && ifa->ifa_name && strncmp("lo", ifa->ifa_name, 2)) {
            size_t len;
            int mib[] = {CTL_NET, AF_ROUTE, 0, AF_LINK, NET_RT_IFLIST, (int)if_nametoindex(ifa->ifa_name)};
            if (mib[5] == 0) continue;
            if (sysctl(mib, sizeof(mib)/sizeof(mib[0]), NULL, &len, NULL, 0) < 0) continue;
            char *macbuf = (char *)malloc(len);
            if (!macbuf) continue;
            if (sysctl(mib, 6, macbuf, &len, NULL, 0) < 0) { free(macbuf); continue; }
            struct if_msghdr *ifm = (struct if_msghdr *)macbuf;
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)(ifm + 1);
            memcpy(mac, (unsigned char *)LLADDR(sdl), 6);
            free(macbuf);
            break;
        }
    } while ((ifa = ifa->ifa_next));
    freeifaddrs(ifaddrs);
}

@interface AirPlayReceiverBridge () {
    raop_t *_raop;
    dnssd_t *_dnssd;
    AirPlayBridgeState _state;
}
@property (nonatomic, readwrite) AirPlayBridgeState state;
@property (nonatomic, strong, readwrite) NSString *pairingRegisterPath;
@property (nonatomic, strong, readwrite) NSString *keyPath;
@property (nonatomic, strong) NSLock *sessionLock;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *activeSessionIDs;
- (void)_logMessage:(NSString *)message level:(int)level;
- (void)_activateSessionID:(uint64_t)sessionID;
- (BOOL)_deactivateSessionID:(uint64_t)sessionID;
- (BOOL)_isSessionActive:(uint64_t)sessionID;
- (BOOL)_hasActiveSessions;
- (void)_clearSessions;
@end

// Forward callback declarations
static void _conn_init(void *cls, raop_connection_t *conn);
static void _conn_destroy(void *cls, raop_connection_t *conn);
static void _conn_reset(void *cls, int timeouts, bool reset_video, raop_connection_t *conn);
static void _conn_teardown(void *cls, bool *teardown_96, bool *teardown_110, raop_connection_t *conn);
static void _audio_process(void *cls, raop_ntp_t *ntp, aac_decode_struct *data, raop_connection_t *conn);
static void _video_process(void *cls, raop_ntp_t *ntp, h264_decode_struct *data, raop_connection_t *conn);
static void _display_pin(void *cls, const char *pin);
static void _register_client(void *cls, const char *device_id, const char *public_key);
static bool _check_register(void *cls, const char *public_key);
static void _log_callback(void *cls, int level, const char *msg);
static void _notify_disconnected(AirPlayReceiverBridge *bridge, uint64_t sessionID);

@implementation AirPlayReceiverBridge

- (instancetype)initWithReceiverName:(NSString *)name pin:(uint16_t)pin {
    self = [super init];
    if (self) {
        _receiverName = [name copy] ?: @"iMirror";
        _pin = pin;
        _pinFixed = (pin > 0);
        _state = AirPlayBridgeStateStopped;
        _raop = NULL;
        _dnssd = NULL;
        _sessionLock = [[NSLock alloc] init];
        _activeSessionIDs = [[NSMutableSet alloc] init];
        
        // Setup application support directory
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *supportURL = [fm URLForDirectory:NSApplicationSupportDirectory
                                       inDomain:NSUserDomainMask
                              appropriateForURL:nil
                                         create:YES
                                          error:nil];
        NSURL *appSupportURL = [supportURL URLByAppendingPathComponent:@"iMirror" isDirectory:YES];
        [fm createDirectoryAtURL:appSupportURL withIntermediateDirectories:YES attributes:nil error:nil];
        
        self.keyPath = [[appSupportURL URLByAppendingPathComponent:@"airplay-key.pem"] path];
        self.pairingRegisterPath = [[appSupportURL URLByAppendingPathComponent:@"trusted-airplay-clients.txt"] path];
    }
    return self;
}

- (BOOL)start:(NSError **)error {
    if (_state == AirPlayBridgeStateRunning || _state == AirPlayBridgeStateConnected) {
        if (error) *error = [NSError errorWithDomain:@"com.erniu.imirror" code:1 userInfo:@{NSLocalizedDescriptionKey: @"接收器已在运行"}];
        return NO;
    }
    
    self.state = AirPlayBridgeStateStarting;
    [self _clearSessions];
    [self _logMessage:@"Starting AirPlay receiver..." level:LOGGER_INFO];
    
    // Setup callbacks
    raop_callbacks_t cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.cls = (__bridge void *)self;
    cbs.conn_init = _conn_init;
    cbs.conn_destroy = _conn_destroy;
    cbs.conn_reset = _conn_reset;
    cbs.conn_teardown = _conn_teardown;
    cbs.audio_process = _audio_process;
    cbs.video_process = _video_process;
    cbs.display_pin = _display_pin;
    cbs.register_client = _register_client;
    cbs.check_register = _check_register;
    
    // Get hardware MAC address
    uint8_t hw_addr[] = {0x0a, 0x0b, 0x00, 0x00, 0x0b, 0x0a};
    get_mac(hw_addr);
    
    char device_id[18] = {0};
    snprintf(device_id, sizeof(device_id), "%02X:%02X:%02X:%02X:%02X:%02X",
             hw_addr[0], hw_addr[1], hw_addr[2], hw_addr[3], hw_addr[4], hw_addr[5]);
    
    // Initialize RAOP
    _raop = raop_init(MAX_ACTIVE_SESSIONS * 2, &cbs, device_id, _keyPath.UTF8String);
    if (!_raop) {
        [self _logMessage:@"Failed to initialize AirPlay receiver" level:LOGGER_ERR];
        self.state = AirPlayBridgeStateFailed;
        if (error) *error = [NSError errorWithDomain:@"com.erniu.imirror" code:2 userInfo:@{NSLocalizedDescriptionKey: @"无法初始化 AirPlay 接收器"}];
        return NO;
    }
    
    // Ensure key file has correct permissions
    chmod(_keyPath.UTF8String, S_IRUSR | S_IWUSR);
    
    // Set PIN
    raop_set_pin(_raop, _pin, _pinFixed ? 1 : 0);
    [self _logMessage:[NSString stringWithFormat:_pinFixed ? @"PIN mode: fixed %04u" : @"PIN mode: random", _pin]
                level:LOGGER_INFO];
    
    // Configure H.264 only, 1920×1080
    raop_set_plist(_raop, "width", 1920);
    raop_set_plist(_raop, "height", 1080);
    raop_set_plist(_raop, "refreshRate", 60);
    raop_set_plist(_raop, "maxFPS", 60);
    raop_set_plist(_raop, "overscanned", 0);
    raop_set_plist(_raop, "max_ntp_timeouts", NTP_TIMEOUT_LIMIT);
    
    // Auto-assign ports
    unsigned short tcpPorts[2] = {0};
    unsigned short udpPorts[3] = {0};
    raop_set_tcp_ports(_raop, tcpPorts);
    raop_set_udp_ports(_raop, udpPorts);
    
    // Setup logger
    raop_set_log_callback(_raop, _log_callback, (__bridge void *)self);
    raop_set_log_level(_raop, LOGGER_DEBUG);
    
    // Start RAOP
    unsigned short port = 0;
    [self _logMessage:@"Calling raop_start..." level:LOGGER_INFO];
    int result = raop_start(_raop, &port);
    [self _logMessage:[NSString stringWithFormat:@"raop_start returned %d, port=%u", result, port] level:LOGGER_INFO];
    // httpd_start returns 1 on success, 0 if already running, negative on error
    if (result < 0) {
        [self _logMessage:[NSString stringWithFormat:@"Failed to start RAOP listener, error=%d", result] level:LOGGER_ERR];
        raop_destroy(_raop);
        _raop = NULL;
        self.state = AirPlayBridgeStateFailed;
        if (error) *error = [NSError errorWithDomain:@"com.erniu.imirror" code:3 userInfo:@{NSLocalizedDescriptionKey: @"无法启动 AirPlay 网络监听"}];
        return NO;
    }
    
    raop_set_port(_raop, port);
    [self _logMessage:[NSString stringWithFormat:@"RAOP listening on port %u", port] level:LOGGER_INFO];
    
    // Setup DNS-SD
    int dnssd_error = 0;
    char server_name[64] = {0};
    snprintf(server_name, sizeof(server_name), "%s", _receiverName.UTF8String);
    
    _dnssd = dnssd_init(server_name, (int)strlen(server_name), (char *)hw_addr, sizeof(hw_addr), &dnssd_error);
    if (dnssd_error != 0 || !_dnssd) {
        [self _logMessage:[NSString stringWithFormat:@"Failed to initialize DNS-SD, error=%d", dnssd_error] level:LOGGER_ERR];
        raop_destroy(_raop);
        _raop = NULL;
        self.state = AirPlayBridgeStateFailed;
        if (error) *error = [NSError errorWithDomain:@"com.erniu.imirror" code:4 userInfo:@{NSLocalizedDescriptionKey: @"无法初始化 Bonjour/AWDL 广播"}];
        return NO;
    }
    
    // Set public key on DNS-SD
    unsigned char public_key[32];
    raop_get_public_key(_raop, public_key);
    if (dnssd_set_airplay_public_key(_dnssd, public_key, sizeof(public_key)) != 0) {
        [self _logMessage:@"Failed to set public key on DNS-SD" level:LOGGER_ERR];
        dnssd_destroy(_dnssd);
        _dnssd = NULL;
        raop_destroy(_raop);
        _raop = NULL;
        self.state = AirPlayBridgeStateFailed;
        if (error) *error = [NSError errorWithDomain:@"com.erniu.imirror" code:5 userInfo:@{NSLocalizedDescriptionKey: @"无法配置 AirPlay 接收器身份"}];
        return NO;
    }
    
    // Register DNS-SD services
    dnssd_set_pin_required(_dnssd, 1);
    raop_set_dnssd(_raop, _dnssd);
    int raop_reg = dnssd_register_raop(_dnssd, port);
    int airplay_reg = dnssd_register_airplay(_dnssd, port);
    [self _logMessage:[NSString stringWithFormat:@"DNS-SD register raop=%d airplay=%d", raop_reg, airplay_reg]
                level:LOGGER_INFO];
    
    if (raop_reg != 0 || airplay_reg != 0) {
        if (_dnssd) {
            dnssd_unregister_raop(_dnssd);
            dnssd_unregister_airplay(_dnssd);
            dnssd_destroy(_dnssd);
            _dnssd = NULL;
        }
        raop_destroy(_raop);
        _raop = NULL;
        self.state = AirPlayBridgeStateFailed;
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Bonjour/AWDL 服务注册失败（RAOP=%d, AirPlay=%d）", raop_reg, airplay_reg];
            *error = [NSError errorWithDomain:@"com.erniu.imirror" code:6 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    self.state = AirPlayBridgeStateRunning;
    [self _logMessage:@"AirPlay receiver started successfully" level:LOGGER_INFO];
    
    if ([self.delegate respondsToSelector:@selector(receiverDidStartOnPort:)]) {
        [self.delegate receiverDidStartOnPort:port];
    }
    
    return YES;
}

- (void)stop {
    if (_state == AirPlayBridgeStateStopped) return;
    
    [self _logMessage:@"Stopping AirPlay receiver..." level:LOGGER_INFO];
    [self _clearSessions];
    
    if (_dnssd) {
        dnssd_unregister_raop(_dnssd);
        dnssd_unregister_airplay(_dnssd);
        dnssd_destroy(_dnssd);
        _dnssd = NULL;
    }
    
    if (_raop) {
        raop_destroy(_raop);
        _raop = NULL;
    }
    
    self.state = AirPlayBridgeStateStopped;
    
    [self _logMessage:@"AirPlay receiver stopped" level:LOGGER_INFO];
    
    if ([self.delegate respondsToSelector:@selector(receiverDidStop)]) {
        [self.delegate receiverDidStop];
    }
}

- (void)disconnectSession:(uint64_t)sessionID {
    if (!_raop || ![self _isSessionActive:sessionID]) return;

    raop_connection_t *connection = (raop_connection_t *)(uintptr_t)sessionID;
    [self _logMessage:[NSString stringWithFormat:@"Disconnecting session %llu", sessionID]
                  level:LOGGER_INFO];
    raop_stop_conn(connection);
}

- (BOOL)isRunning {
    return _raop != NULL && raop_is_running(_raop);
}

#pragma mark - Internal

- (void)_logMessage:(NSString *)message level:(int)level {
    NSLog(@"[AirPlay] %@", message);
}

- (void)_activateSessionID:(uint64_t)sessionID {
    [self.sessionLock lock];
    [self.activeSessionIDs addObject:@(sessionID)];
    [self.sessionLock unlock];
}

- (BOOL)_deactivateSessionID:(uint64_t)sessionID {
    [self.sessionLock lock];
    NSNumber *identifier = @(sessionID);
    BOOL wasActive = [self.activeSessionIDs containsObject:identifier];
    if (wasActive) {
        [self.activeSessionIDs removeObject:identifier];
    }
    [self.sessionLock unlock];
    return wasActive;
}

- (BOOL)_isSessionActive:(uint64_t)sessionID {
    [self.sessionLock lock];
    BOOL active = [self.activeSessionIDs containsObject:@(sessionID)];
    [self.sessionLock unlock];
    return active;
}

- (BOOL)_hasActiveSessions {
    [self.sessionLock lock];
    BOOL hasActiveSessions = self.activeSessionIDs.count > 0;
    [self.sessionLock unlock];
    return hasActiveSessions;
}

- (void)_clearSessions {
    [self.sessionLock lock];
    [self.activeSessionIDs removeAllObjects];
    [self.sessionLock unlock];
}

@end

// ══════════════════════════════════════════════════════════════════════════
// C Callback implementations
// ══════════════════════════════════════════════════════════════════════════

static AirPlayReceiverBridge *_bridge(void *cls) {
    return (__bridge AirPlayReceiverBridge *)cls;
}

static void _conn_init(void *cls, raop_connection_t *conn) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        [bridge _logMessage:@"Client connected" level:LOGGER_INFO];
        conn->usr_data = cls;
        uint64_t sessionID = (uint64_t)(uintptr_t)conn;
        [bridge _activateSessionID:sessionID];
        
        NSString *name = conn->devInfo.name ? [NSString stringWithUTF8String:conn->devInfo.name] : @"Apple 设备";
        NSString *model = conn->devInfo.model ? [NSString stringWithUTF8String:conn->devInfo.model] : @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            bridge.state = AirPlayBridgeStateConnected;
            if ([bridge.delegate respondsToSelector:@selector(receiverDidConnectSession:deviceName:model:)]) {
                [bridge.delegate receiverDidConnectSession:sessionID deviceName:name model:model];
            }
        });
    }
}

static void _conn_destroy(void *cls, raop_connection_t *conn) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        [bridge _logMessage:@"Client disconnected" level:LOGGER_INFO];
        uint64_t sessionID = (uint64_t)(uintptr_t)conn;
        conn->usr_data = NULL;
        _notify_disconnected(bridge, sessionID);
    }
}

static void _conn_reset(void *cls, int timeouts, bool reset_video, raop_connection_t *conn) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        [bridge _logMessage:[NSString stringWithFormat:@"Connection reset: timeouts=%d, reset_video=%d", timeouts, reset_video]
                      level:LOGGER_INFO];
    }
}

static void _conn_teardown(void *cls, bool *teardown_96, bool *teardown_110, raop_connection_t *conn) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        [bridge _logMessage:@"Connection teardown" level:LOGGER_INFO];
        BOOL endsVideo = *teardown_110 || !*teardown_96;
        if (endsVideo) {
            uint64_t sessionID = (uint64_t)(uintptr_t)conn;
            conn->usr_data = NULL;
            _notify_disconnected(bridge, sessionID);
        }
    }
}

static void _notify_disconnected(AirPlayReceiverBridge *bridge, uint64_t sessionID) {
    if (![bridge _deactivateSessionID:sessionID]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        bridge.state = [bridge _hasActiveSessions] ? AirPlayBridgeStateConnected : AirPlayBridgeStateRunning;
        if ([bridge.delegate respondsToSelector:@selector(receiverDidDisconnectSession:)]) {
            [bridge.delegate receiverDidDisconnectSession:sessionID];
        }
    });
}

static void _audio_process(void *cls, raop_ntp_t *ntp, aac_decode_struct *data, raop_connection_t *conn) {
    // Audio data received - first version silently discards
}

static void _video_process(void *cls, raop_ntp_t *ntp, h264_decode_struct *data, raop_connection_t *conn) {
    @autoreleasepool {
        if (!data || !data->data || data->data_len <= 0) return;
        AirPlayReceiverBridge *bridge = _bridge(cls);
        uint64_t sessionID = (uint64_t)(uintptr_t)conn;
        if (![bridge _isSessionActive:sessionID]) return;
        
        // IMPORTANT: data->data is only valid for the duration of this callback.
        // Copy immediately before handing off to an async queue.
        NSData *copy = [NSData dataWithBytes:data->data length:data->data_len];
        if (!copy) return;
        
        if ([bridge.delegate respondsToSelector:@selector(receiverDidReceiveVideoData:forSession:)]) {
            [bridge.delegate receiverDidReceiveVideoData:copy forSession:sessionID];
        }
    }
}

static void _display_pin(void *cls, const char *pin) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        NSString *pinStr = pin ? [NSString stringWithUTF8String:pin] : @"";
        
        [bridge _logMessage:[NSString stringWithFormat:@"PIN requested: %@", pinStr] level:LOGGER_INFO];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([bridge.delegate respondsToSelector:@selector(receiverDidRequestPIN:)]) {
                [bridge.delegate receiverDidRequestPIN:pinStr];
            }
        });
    }
}

static void _register_client(void *cls, const char *device_id, const char *public_key) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        if (!bridge.pairingRegisterPath || !public_key) return;
        
        NSString *key = [NSString stringWithUTF8String:public_key];
        NSString *device = device_id ? [NSString stringWithUTF8String:device_id] : @"";
        NSString *path = bridge.pairingRegisterPath;
        
        @synchronized ([NSApplication class]) {
            NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            
            for (NSString *line in lines) {
                if ([line isEqualToString:key] || [line hasPrefix:[key stringByAppendingString:@"\t"]]) {
                    return; // Already registered
                }
            }
            
            NSString *entry = [NSString stringWithFormat:@"%@\t%@\n", key, device];
            NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
            NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
            if (file) {
                [file seekToEndOfFile];
                [file writeData:data];
                [file closeFile];
            } else {
                [data writeToFile:path options:NSDataWritingAtomic error:nil];
            }
            chmod(path.UTF8String, S_IRUSR | S_IWUSR);
        }
        
        [bridge _logMessage:[NSString stringWithFormat:@"Registered trusted client: %@", device] level:LOGGER_INFO];
    }
}

static bool _check_register(void *cls, const char *public_key) {
    @autoreleasepool {
        AirPlayReceiverBridge *bridge = _bridge(cls);
        if (!bridge.pairingRegisterPath || !public_key) return false;
        
        NSString *key = [NSString stringWithUTF8String:public_key];
        NSString *path = bridge.pairingRegisterPath;
        
        @synchronized ([NSApplication class]) {
            NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            
            for (NSString *line in lines) {
                if ([line isEqualToString:key] || [line hasPrefix:[key stringByAppendingString:@"\t"]]) {
                    [bridge _logMessage:@"Trusted AirPlay client recognized" level:LOGGER_INFO];
                    return true;
                }
            }
        }
    }
    return false;
}

static void _log_callback(void *cls, int level, const char *msg) {
    @autoreleasepool {
        if (!cls) return;
        // Always print C backend logs to stderr for debugging.
        fprintf(stderr, "[AirPlay-C] %s\n", msg ?: "");
    }
}
