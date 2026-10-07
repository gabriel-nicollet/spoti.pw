// Sing's player lifecycle and worker ownership. Main thread except the clock and invalidation APIs.
#import <Foundation/Foundation.h>
#include "SGSingLevel.h"
@class SPTPlayerState;
extern NSString *const SGSingDidChangeNotification;
typedef NS_ENUM(NSUInteger, SGSingState) {
    SGSingUnavailable, SGSingIdle, SGSingPreparing, SGSingActive, SGSingDraining, SGSingFailed,
    SGSingReady,
    SGSingRecovering
};
static inline BOOL SGSingStateIsOn(SGSingState state) {
    return state == SGSingActive || state == SGSingReady || state == SGSingRecovering;
}
BOOL SGSingSupported(void);
void SGSingConfigure(BOOL enabled);
SGSingState SGSingCurrentState(void);
BOOL SGSingAvailable(void);
NSString *SGSingExplanation(void);
BOOL SGSingCanRetry(void);
BOOL SGSingEnabled(void);
float SGSingVocalLevel(void);
float SGSingReducedLevel(void);
void SGSingSetVocalLevel(float level);
// Vocals only: the instrumental is taken out and the vocals play at full, whatever the level. Sing's switch
// still decides whether it runs; this changes what it plays. Safe before Sing is configured.
BOOL SGSingVocalsOnly(void);
void SGSingSetVocalsOnly(BOOL vocalsOnly);
// Spatial Voice focuses the separated vocal stem in the center/front image while leaving
// the existing 0-110% Sing level mapping unchanged.
BOOL SGSingSpatialVoice(void);
void SGSingSetSpatialVoice(BOOL enabled);
void SGSingSetEnabled(BOOL enabled);
void SGSingPlaybackWillChange(void);
void SGSingPlaybackDidChange(void);
void SGSingPlaybackDidSeek(double seconds);
uint64_t SGSingTrackIdentifier(id uri);
BOOL SGSingPosition(SPTPlayerState *state, double *position);
double SGSingSourcePosition(SPTPlayerState *state);
