#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdatomic.h>
#import "SGSingDSP.h"

// Reads AirPods head motion only while Spatial Voice is enabled. This feeds a small custom
// binaural renderer; it does not rely on Apple's restricted automatic head-pose renderer.
@interface SGSpatialVoiceMotion : NSObject <CMHeadphoneMotionManagerDelegate>
+ (instancetype)shared;
- (void)setEnabled:(BOOL)enabled;
@end

@implementation SGSpatialVoiceMotion {
    CMHeadphoneMotionManager *_manager;
    NSOperationQueue *_queue;
    atomic_bool _enabled;
    BOOL _hasReference;
    double _referenceYaw;
    double _turnedAwaySince;
}

+ (instancetype)shared {
    static SGSpatialVoiceMotion *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [SGSpatialVoiceMotion new]; });
    return instance;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = [NSOperationQueue new];
    _queue.name = @"spotifyglass.spatialvoice.motion";
    _queue.maxConcurrentOperationCount = 1;
    _queue.qualityOfService = NSQualityOfServiceUserInitiated;
    atomic_init(&_enabled, false);
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setEnabled:enabled]; });
        return;
    }
    if (atomic_load_explicit(&_enabled, memory_order_relaxed) == enabled) return;
    atomic_store_explicit(&_enabled, enabled, memory_order_relaxed);
    [_queue addOperationWithBlock:^{ self->_hasReference = NO; self->_turnedAwaySince = 0; }];
    if (!enabled) {
        [_manager stopDeviceMotionUpdates];
        SGSingDSPSetSpatialAzimuthDegrees(0);
        return;
    }

    if (CMHeadphoneMotionManager.authorizationStatus == CMAuthorizationStatusDenied ||
        CMHeadphoneMotionManager.authorizationStatus == CMAuthorizationStatusRestricted) {
        // The effect still works as a fixed front/center voice if motion access is unavailable.
        SGSingDSPSetSpatialAzimuthDegrees(0);
        return;
    }
    if (!_manager) {
        _manager = [CMHeadphoneMotionManager new];
        _manager.delegate = self;
    }
    [self startMotionUpdates];
}

- (void)startMotionUpdates {
    if (!atomic_load_explicit(&_enabled, memory_order_relaxed) || !_manager.isDeviceMotionAvailable) {
        SGSingDSPSetSpatialAzimuthDegrees(0);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [_manager startDeviceMotionUpdatesToQueue:_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        [weakSelf consumeMotion:motion error:error];
    }];
}

- (double)wrappedAngle:(double)angle {
    while (angle > M_PI) angle -= 2.0 * M_PI;
    while (angle < -M_PI) angle += 2.0 * M_PI;
    return angle;
}

// Called serially on _queue. The first sample establishes the user's forward direction.
- (void)consumeMotion:(CMDeviceMotion *)motion error:(NSError *)error {
    if (!atomic_load_explicit(&_enabled, memory_order_relaxed) || error || !motion) return;
    double yaw = motion.attitude.yaw;
    if (!isfinite(yaw)) return;
    if (!_hasReference) {
        _referenceYaw = yaw;
        _hasReference = YES;
        _turnedAwaySince = 0;
        SGSingDSPSetSpatialAzimuthDegrees(0);
        return;
    }

    double relative = [self wrappedAngle:yaw - _referenceYaw];
    double now = motion.timestamp;
    // If the listener keeps looking far away, gradually establish that direction as forward.
    // This avoids leaving the singer stranded behind the listener for an entire song.
    if (fabs(relative) > (55.0 * M_PI / 180.0)) {
        if (_turnedAwaySince == 0) _turnedAwaySince = now;
        if (now - _turnedAwaySince >= 5.0) {
            _referenceYaw = yaw;
            relative = 0;
            _turnedAwaySince = 0;
        }
    } else {
        _turnedAwaySince = 0;
    }

    // The singer stays in world space: turning right moves the voice to the listener's left.
    SGSingDSPSetSpatialAzimuthDegrees((float)(-relative * 180.0 / M_PI));
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    SGSingDSPSetSpatialAzimuthDegrees(0);
    [_queue addOperationWithBlock:^{ self->_hasReference = NO; self->_turnedAwaySince = 0; }];
}

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    // The motion update handler will establish a fresh forward reference on its next sample.
    [_queue addOperationWithBlock:^{ self->_hasReference = NO; }];
    dispatch_async(dispatch_get_main_queue(), ^{ [self startMotionUpdates]; });
}
@end

void SGSpatialVoiceMotionSetEnabled(BOOL enabled) {
    [[SGSpatialVoiceMotion shared] setEnabled:enabled];
}
