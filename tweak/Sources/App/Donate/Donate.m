#import "Core/SGCore.h"
#import "Donate.h"

// Donation prompts and external support redirects are disabled in Spotifyre.
void SGShowDonateSheet(void) {}
SGModRow *SGDonateRow(void) { return nil; }
void SGWatchForDonate(void) {}
void SGDonateAfterTour(BOOL restarting) { (void)restarting; }
BOOL SGDonateAfterTourPending(void) { return NO; }
void SGOfferDonate(void) {}
BOOL SGDonateShown(void) { return NO; }
void SGDonateHoldOff(void) {}
