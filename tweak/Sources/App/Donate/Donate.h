// Legacy donation API retained as inert stubs for source compatibility; Spotifyre shows no donation prompts.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

void SGShowDonateSheet(void);
SGModRow *SGDonateRow(void);
void SGWatchForDonate(void);
// A tour is done: the sheet follows it, or follows Home after the restart.
void SGDonateAfterTour(BOOL restarting);
BOOL SGDonateAfterTourPending(void);
void SGOfferDonate(void);
BOOL SGDonateShown(void);     // this run
void SGDonateHoldOff(void);   // another sheet asked instead; the next ask waits a full round
