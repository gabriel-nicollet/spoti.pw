// The line being sung in place of the artist in the system's now playing: lock screen, Dynamic Island,
// Control Center, CarPlay. There is a Live Activity for it too (Shared/LiveActivity). The
// lines and the clock come from Karaoke.
//
// And, as a switch of its own, the lyrics on the cover: the artwork the lock screen shows is a card of the line being
// sung with the one before and the one after, over the album's cover blurred and dimmed, drawn again on each line
// (LockScreenLyricsCover.m). It is the artwork the system is handed, so animated artwork steps aside while it is on.
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>

#define SGKeyLockScreenLyrics @"spotifyglass.lockScreenLyrics"
#define SGKeyLockScreenLyricsCover @"spotifyglass.lockScreenLyrics.cover"   // off until switched on

// The artwork of the lyrics card, a class of its own so a hook that remembers Spotify's cover can tell it is not it.
@interface SGLyricsCoverArtwork : MPMediaItemArtwork
@end

// The card for `current` between `previous` and `next` (either may be nil), over `cover` (nil: black), `size` points square
// at scale 1. Safe on any thread.
UIImage *SGLyricsCoverImage(UIImage *cover, NSString *previous, NSString *current, NSString *next, CGSize size);
