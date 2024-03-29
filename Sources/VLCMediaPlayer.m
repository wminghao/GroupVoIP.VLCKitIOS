/*****************************************************************************
 * VLCMediaPlayer.m: VLCKit.framework VLCMediaPlayer implementation
 *****************************************************************************
 * Copyright (C) 2007-2009 Pierre d'Herbemont
 * Copyright (C) 2007-2014 VLC authors and VideoLAN
 * Partial Copyright (C) 2009-2014 Felix Paul Kühne
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Faustion Osuna <enrique.osuna # gmail.com>
 *          Felix Paul Kühne <fkuehne # videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCLibrary.h"
#import "VLCMediaPlayer.h"
#import "VLCEventManager.h"
#import "VLCLibVLCBridging.h"
#if !TARGET_OS_IPHONE
# import "VLCVideoView.h"
#endif
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#if !TARGET_OS_IPHONE
/* prevent system sleep */
# import <CoreServices/CoreServices.h>
/* FIXME: Ugly hack! */
# ifdef __x86_64__
#  import <CoreServices/../Frameworks/OSServices.framework/Headers/Power.h>
# endif
#endif

#include <vlc/vlc.h>

/* Notification Messages */
NSString *const VLCMediaPlayerTimeChanged    = @"VLCMediaPlayerTimeChanged";
NSString *const VLCMediaPlayerStateChanged   = @"VLCMediaPlayerStateChanged";

NSString * VLCMediaPlayerStateToString(VLCMediaPlayerState state)
{
    static NSString * stateToStrings[] = {
        [VLCMediaPlayerStateStopped]      = @"VLCMediaPlayerStateStopped",
        [VLCMediaPlayerStateOpening]      = @"VLCMediaPlayerStateOpening",
        [VLCMediaPlayerStateBuffering]    = @"VLCMediaPlayerStateBuffering",
        [VLCMediaPlayerStateEnded]        = @"VLCMediaPlayerStateEnded",
        [VLCMediaPlayerStateError]        = @"VLCMediaPlayerStateError",
        [VLCMediaPlayerStatePlaying]      = @"VLCMediaPlayerStatePlaying",
        [VLCMediaPlayerStatePaused]       = @"VLCMediaPlayerStatePaused"
    };
    return stateToStrings[state];
}

static void HandleMediaTimeChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(mediaPlayerTimeChanged:)
                                       withArgumentAsObject:@(event->u.media_player_time_changed.new_time)];

    [[VLCEventManager sharedManager] callOnMainThreadDelegateOfObject:self
                                                   withDelegateMethod:@selector(mediaPlayerTimeChanged:)
                                                 withNotificationName:VLCMediaPlayerTimeChanged];
    [pool release];
}

static void HandleMediaPositionChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(mediaPlayerPositionChanged:)
                                       withArgumentAsObject:@(event->u.media_player_position_changed.new_position)];
    [pool release];
}

static void HandleMediaInstanceStateChanged(const libvlc_event_t * event, void * self)
{
    VLCMediaPlayerState newState;

    if (event->type == libvlc_MediaPlayerPlaying)
        newState = VLCMediaPlayerStatePlaying;
    else if (event->type == libvlc_MediaPlayerPaused)
        newState = VLCMediaPlayerStatePaused;
    else if (event->type == libvlc_MediaPlayerEndReached || event->type == libvlc_MediaPlayerStopped)
        newState = VLCMediaPlayerStateStopped;
    else if (event->type == libvlc_MediaPlayerEncounteredError)
        newState = VLCMediaPlayerStateError;
    else if (event->type == libvlc_MediaPlayerBuffering)
        newState = VLCMediaPlayerStateBuffering;
    else if (event->type == libvlc_MediaPlayerOpening)
        newState = VLCMediaPlayerStateOpening;
    else {
        VKLog(@"%s: Unknown event", __FUNCTION__);
        return;
    }

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(mediaPlayerStateChanged:)
                                       withArgumentAsObject:@(newState)];

    [[VLCEventManager sharedManager] callOnMainThreadDelegateOfObject:self
                                                   withDelegateMethod:@selector(mediaPlayerStateChanged:)
                                                 withNotificationName:VLCMediaPlayerStateChanged];

    [pool release];
}

static void HandleMediaPlayerMediaChanged(const libvlc_event_t * event, void * self)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    [[VLCEventManager sharedManager] callOnMainThreadObject:self
                                                 withMethod:@selector(mediaPlayerMediaChanged:)
                                       withArgumentAsObject:[VLCMedia mediaWithLibVLCMediaDescriptor:event->u.media_player_media_changed.new_media]];

    [pool release];
}


// TODO: Documentation
@interface VLCMediaPlayer (Private)

- (id)initWithDrawable:(id)aDrawable options:(NSArray *)options;

- (void)registerObservers;
- (void)unregisterObservers;
- (void)mediaPlayerTimeChanged:(NSNumber *)newTime;
- (void)mediaPlayerPositionChanged:(NSNumber *)newTime;
- (void)mediaPlayerStateChanged:(NSNumber *)newState;
- (void)mediaPlayerMediaChanged:(VLCMedia *)media;
@end

@interface VLCMediaPlayer ()
{
    VLCLibrary *_privateLibrary;
    id _delegate;                        //< Object delegate
    void * _playerInstance;              //  Internal
    VLCMedia * _media;                   //< Current media being played
    VLCTime * _cachedTime;               //< Cached time of the media being played
    VLCTime * _cachedRemainingTime;      //< Cached remaining time of the media being played
    VLCMediaPlayerState _cachedState;    //< Cached state of the media being played
    float _position;                     //< The position of the media being played
    id _drawable;                        //< The drawable associated to this media player
    VLCAudio *_audio;
    libvlc_equalizer_t *_equalizerInstance;
    BOOL _equalizerEnabled;
}
@end

@implementation VLCMediaPlayer
@synthesize libraryInstance = _privateLibrary;

/* Bindings */
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    static NSDictionary * dict = nil;
    NSSet * superKeyPaths;
    if (!dict) {
        dict = [@{@"playing": [NSSet setWithObject:@"state"],
                @"seekable": [NSSet setWithObjects:@"state", @"media", nil],
                @"canPause": [NSSet setWithObjects:@"state", @"media", nil],
                @"description": [NSSet setWithObjects:@"state", @"media", nil]} retain];
    }
    if ((superKeyPaths = [super keyPathsForValuesAffectingValueForKey: key])) {
        NSMutableSet * ret = [NSMutableSet setWithSet:dict[key]];
        [ret unionSet:superKeyPaths];
        return ret;
    }
    return dict[key];
}

/* Constructor */
- (id)init
{
    return [self initWithDrawable:nil options:nil];
}

#if !TARGET_OS_IPHONE
- (id)initWithVideoView:(VLCVideoView *)aVideoView
{
    return [self initWithDrawable: aVideoView options:nil];
}

- (id)initWithVideoLayer:(VLCVideoLayer *)aVideoLayer
{
    return [self initWithDrawable: aVideoLayer options:nil];
}

- (id)initWithVideoView:(VLCVideoView *)aVideoView options:(NSArray *)options
{
    return [self initWithDrawable: aVideoView options:options];
}

- (id)initWithVideoLayer:(VLCVideoLayer *)aVideoLayer options:(NSArray *)options
{
    return [self initWithDrawable: aVideoLayer options:options];
}
#endif

- (id)initWithOptions:(NSArray *)options
{
    return [self initWithDrawable:nil options:options];
}

- (void)dealloc
{
    NSAssert(libvlc_media_player_get_state(_playerInstance) == libvlc_Stopped || libvlc_media_player_get_state(_playerInstance) == libvlc_NothingSpecial, @"You released the media player before ensuring that it is stopped");

    [self unregisterObservers];
    [[VLCEventManager sharedManager] cancelCallToObject:self];

    // Always get rid of the delegate first so we can stop sending messages to it
    // TODO: Should we tell the delegate that we're shutting down?
    _delegate = nil;

    // Clear our drawable as we are going to release it, we don't
    // want the core to use it from this point. This won't happen as
    // the media player must be stopped.
    libvlc_media_player_set_nsobject(_playerInstance, nil);

    if (_equalizerInstance) {
        libvlc_media_player_set_equalizer(_playerInstance, NULL);
        libvlc_audio_equalizer_release(_equalizerInstance);
    }

    libvlc_media_player_release(_playerInstance);
    if (_privateLibrary != [VLCLibrary sharedLibrary])
        libvlc_release(_privateLibrary.instance);

    // Get rid of everything else
    [_media release];
    [_cachedTime release];
    [_cachedRemainingTime release];
    [_drawable release];
    [_audio release];
    if (_privateLibrary != [VLCLibrary sharedLibrary])
        [_privateLibrary release];

    [super dealloc];
}

- (void)setDelegate:(id)value
{
    _delegate = value;
}

- (id)delegate
{
    return _delegate;
}

#if !TARGET_OS_IPHONE
- (void)setVideoView:(VLCVideoView *)aVideoView
{
    [self setDrawable: aVideoView];
}

- (void)setVideoLayer:(VLCVideoLayer *)aVideoLayer
{
    [self setDrawable: aVideoLayer];
}
#endif

- (void)setDrawable:(id)aDrawable
{
    // Make sure that this instance has been associated with the drawing canvas.
    libvlc_media_player_set_nsobject(_playerInstance, aDrawable);
}

- (id)drawable
{
    return libvlc_media_player_get_nsobject(_playerInstance);
}

- (VLCAudio *)audio
{
    if (!_audio)
        _audio = [[VLCAudio alloc] initWithMediaPlayer:self];
    return _audio;
}

#pragma mark -
#pragma mark Video Tracks
- (void)setCurrentVideoTrackIndex:(NSUInteger)value
{
    libvlc_video_set_track(_playerInstance, (int)value);
}

- (NSUInteger)currentVideoTrackIndex
{
    NSInteger count = libvlc_video_get_track_count(_playerInstance);
    if (count <= 0)
        return NSNotFound;

    NSUInteger result = libvlc_video_get_track(_playerInstance);
    return result;
}

- (NSArray *)videoTrackNames
{
    NSInteger count = libvlc_video_get_track_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *currentTrack = libvlc_video_get_track_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->psz_name)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (NSArray *)videoTrackIndexes
{
    NSInteger count = libvlc_video_get_track_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *currentTrack = libvlc_video_get_track_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->i_id)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (NSArray *)videoTracks
{
    NSInteger count = libvlc_video_get_track_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *tracks = libvlc_video_get_track_description(_playerInstance);
    NSMutableArray *tempArray = [NSMutableArray array];
    for (NSUInteger i = 0; i < count ; i++) {
        [tempArray addObject:@(tracks->psz_name)];
        tracks = tracks->p_next;
    }
    libvlc_track_description_list_release(tracks);

    return [NSArray arrayWithArray: tempArray];
}

#pragma mark -
#pragma mark Subtitles

- (void)setCurrentVideoSubTitleIndex:(NSUInteger)index
{
    libvlc_video_set_spu(_playerInstance, (int)index);
}

- (NSUInteger)currentVideoSubTitleIndex
{
    NSInteger count = libvlc_video_get_spu_count(_playerInstance);

    if (count <= 0)
        return NSNotFound;

    return libvlc_video_get_spu(_playerInstance);
}

- (NSArray *)videoSubTitlesNames
{
    NSInteger count = libvlc_video_get_spu_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *currentTrack = libvlc_video_get_spu_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->psz_name)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (NSArray *)videoSubTitlesIndexes
{
    NSInteger count = libvlc_video_get_spu_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *currentTrack = libvlc_video_get_spu_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->i_id)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (BOOL)openVideoSubTitlesFromFile:(NSString *)path
{
    return libvlc_video_set_subtitle_file(_playerInstance, [path UTF8String]);
}

- (NSArray *)videoSubTitles
{
    libvlc_track_description_t *currentTrack = libvlc_video_get_spu_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->psz_name)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (void)setCurrentVideoSubTitleDelay:(NSInteger)index
{
    libvlc_video_set_spu_delay(_playerInstance, index);
}

- (NSInteger)currentVideoSubTitleDelay
{
    return libvlc_video_get_spu_delay(_playerInstance);
}

#if TARGET_OS_IPHONE
- (void)setTextRendererFontSize:(NSNumber *)fontSize
{
    libvlc_video_set_textrenderer_int(_playerInstance, libvlc_textrender_fontsize, [fontSize intValue]);
}
#endif

#if TARGET_OS_IPHONE
- (void)setTextRendererFont:(NSString *)fontname
{
    libvlc_video_set_textrenderer_string(_playerInstance, libvlc_textrender_font, [fontname UTF8String]);
}
#endif

#if TARGET_OS_IPHONE
- (void)setTextRendererFontColor:(NSNumber *)fontColor
{
    libvlc_video_set_textrenderer_int(_playerInstance, libvlc_textrender_fontcolor, [fontColor intValue]);
}
#endif

#pragma mark -
#pragma mark Video Crop geometry

- (void)setVideoCropGeometry:(char *)value
{
    libvlc_video_set_crop_geometry(_playerInstance, value);
}

- (char *)videoCropGeometry
{
    char * result = libvlc_video_get_crop_geometry(_playerInstance);
    return result;
}

- (void)setVideoAspectRatio:(char *)value
{
    libvlc_video_set_aspect_ratio(_playerInstance, value);
}

- (char *)videoAspectRatio
{
    char * result = libvlc_video_get_aspect_ratio(_playerInstance);
    return result;
}

- (void)setScaleFactor:(float)value
{
    libvlc_video_set_scale(_playerInstance, value);
}

- (float)scaleFactor
{
    return libvlc_video_get_scale(_playerInstance);
}

- (void)saveVideoSnapshotAt:(NSString *)path withWidth:(int)width andHeight:(int)height
{
    int failure = libvlc_video_take_snapshot(_playerInstance, 0, [path UTF8String], width, height);
    if (failure)
        [[NSException exceptionWithName:@"Can't take a video snapshot" reason:@"No video output" userInfo:nil] raise];
}

- (void)setDeinterlaceFilter:(NSString *)name
{
    if (!name || name.length < 1)
        libvlc_video_set_deinterlace(_playerInstance, NULL);
    else
        libvlc_video_set_deinterlace(_playerInstance, [name UTF8String]);
}

- (BOOL)adjustFilterEnabled
{
    return libvlc_video_get_adjust_int(_playerInstance, libvlc_adjust_Enable);
}
- (void)setAdjustFilterEnabled:(BOOL)b_value
{
    libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, b_value);
}
- (float)contrast
{
    libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
    return libvlc_video_get_adjust_float(_playerInstance, libvlc_adjust_Contrast);
}
- (void)setContrast:(float)f_value
{
    if (f_value <= 2. && f_value >= 0.) {
        libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
        libvlc_video_set_adjust_float(_playerInstance,libvlc_adjust_Contrast, f_value);
    }
}
- (float)brightness
{
    libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
    return libvlc_video_get_adjust_float(_playerInstance, libvlc_adjust_Brightness);
}
- (void)setBrightness:(float)f_value
{
    if (f_value <= 2. && f_value >= 0.) {
        libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
        libvlc_video_set_adjust_float(_playerInstance, libvlc_adjust_Brightness, f_value);
    }
}
- (int)hue
{
    libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
    return libvlc_video_get_adjust_int(_playerInstance, libvlc_adjust_Hue);
}
- (void)setHue:(int)i_value
{
    if (i_value <= 360 && i_value >= 0) {
        libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
        libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Hue, i_value);
    }
}
- (float)saturation
{
    libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
    return libvlc_video_get_adjust_float(_playerInstance, libvlc_adjust_Saturation);
}
- (void)setSaturation:(float)f_value
{
    if (f_value <= 3. && f_value >= 0.) {
        libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
        libvlc_video_set_adjust_float(_playerInstance, libvlc_adjust_Saturation, f_value);
    }
}
- (float)gamma
{
    libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
    return libvlc_video_get_adjust_float(_playerInstance, libvlc_adjust_Gamma);
}
- (void)setGamma:(float)f_value
{
    if (f_value <= 10. && f_value >= 0.) {
        libvlc_video_set_adjust_int(_playerInstance, libvlc_adjust_Enable, 1);
        libvlc_video_set_adjust_float(_playerInstance, libvlc_adjust_Gamma, f_value);
    }
}

- (void)setRate:(float)value
{
    libvlc_media_player_set_rate(_playerInstance, value);
}

- (float)rate
{
    return libvlc_media_player_get_rate(_playerInstance);
}

- (CGSize)videoSize
{
    unsigned height = 0, width = 0;
    int failure = libvlc_video_get_size(_playerInstance, 0, &width, &height);
    if (failure)
        [[NSException exceptionWithName:@"Can't get video size" reason:@"No video output" userInfo:nil] raise];
    return CGSizeMake(width, height);
}

- (BOOL)hasVideoOut
{
    return libvlc_media_player_has_vout(_playerInstance);
}

- (float)framesPerSecond
{
    return libvlc_media_player_get_fps(_playerInstance);
}

- (void)setTime:(VLCTime *)value
{
    // Time is managed in seconds, while duration is managed in microseconds
    // TODO: Redo VLCTime to provide value numberAsMilliseconds, numberAsMicroseconds, numberAsSeconds, numberAsMinutes, numberAsHours
    libvlc_media_player_set_time(_playerInstance, value ? [[value numberValue] longLongValue] : 0);
}

- (VLCTime *)time
{
    return _cachedTime;
}

- (VLCTime *)remainingTime
{
    return _cachedRemainingTime;
}

- (NSUInteger)fps
{
    return libvlc_media_player_get_fps(_playerInstance);
}

#pragma mark -
#pragma mark Chapters
- (void)setCurrentChapterIndex:(int)value;
{
    libvlc_media_player_set_chapter(_playerInstance, value);
}

- (int)currentChapterIndex
{
    int count = libvlc_media_player_get_chapter_count(_playerInstance);
    if (count <= 0)
        return NSNotFound;
    int result = libvlc_media_player_get_chapter(_playerInstance);
    return result;
}

- (void)nextChapter
{
    libvlc_media_player_next_chapter(_playerInstance);
}

- (void)previousChapter
{
    libvlc_media_player_previous_chapter(_playerInstance);
}

- (NSArray *)chaptersForTitleIndex:(int)title
{
    NSInteger count = libvlc_media_player_get_chapter_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *tracks = libvlc_video_get_chapter_description(_playerInstance, title);
    NSMutableArray *tempArray = [NSMutableArray array];
    for (NSInteger i = 0; i < count ; i++) {
        [tempArray addObject:@(tracks->psz_name)];
        tracks = tracks->p_next;
    }
    libvlc_track_description_list_release(tracks);
    return [NSArray arrayWithArray:tempArray];
}

#pragma mark -
#pragma mark Titles

- (void)setCurrentTitleIndex:(NSUInteger)value
{
    libvlc_media_player_set_title(_playerInstance, value);
}

- (NSUInteger)currentTitleIndex
{
    NSInteger count = libvlc_media_player_get_title_count(_playerInstance);
    if (count <= 0)
        return NSNotFound;

    return libvlc_media_player_get_title(_playerInstance);
}

- (NSUInteger)countOfTitles
{
    NSUInteger result = libvlc_media_player_get_title_count(_playerInstance);
    return result;
}

- (NSArray *)titles
{
    libvlc_track_description_t *tracks = libvlc_video_get_title_description(_playerInstance);
    NSMutableArray *tempArray = [NSMutableArray array];
    for (NSInteger i = 0; i < [self countOfTitles] ; i++) {
        [tempArray addObject:@(tracks->psz_name)];
        tracks = tracks->p_next;
    }
    libvlc_track_description_list_release(tracks);
    return [NSArray arrayWithArray: tempArray];
}

#pragma mark -
#pragma mark Audio tracks
- (void)setCurrentAudioTrackIndex:(NSUInteger)value
{
    libvlc_audio_set_track(_playerInstance, (int)value);
}

- (NSUInteger)currentAudioTrackIndex
{
    NSInteger count = libvlc_audio_get_track_count(_playerInstance);
    if (count <= 0)
        return NSNotFound;

    NSUInteger result = libvlc_audio_get_track(_playerInstance);
    return result;
}

- (NSArray *)audioTrackNames
{
    NSInteger count = libvlc_audio_get_track_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *currentTrack = libvlc_audio_get_track_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->psz_name)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (NSArray *)audioTrackIndexes
{
    NSInteger count = libvlc_audio_get_track_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *currentTrack = libvlc_audio_get_track_description(_playerInstance);

    NSMutableArray *tempArray = [NSMutableArray array];
    while (currentTrack) {
        [tempArray addObject:@(currentTrack->i_id)];
        currentTrack = currentTrack->p_next;
    }
    libvlc_track_description_list_release(currentTrack);
    return [NSArray arrayWithArray: tempArray];
}

- (NSArray *)audioTracks
{
    NSInteger count = libvlc_audio_get_track_count(_playerInstance);
    if (count <= 0)
        return @[];

    libvlc_track_description_t *tracks = libvlc_audio_get_track_description(_playerInstance);
    NSMutableArray *tempArray = [NSMutableArray array];
    for (NSUInteger i = 0; i < count ; i++) {
        [tempArray addObject:@(tracks->psz_name)];
        tracks = tracks->p_next;
    }
    libvlc_track_description_list_release(tracks);

    return [NSArray arrayWithArray: tempArray];
}

- (void)setAudioChannel:(int)value
{
    libvlc_audio_set_channel(_playerInstance, value);
}

- (int)audioChannel
{
    return libvlc_audio_get_channel(_playerInstance);
}

- (void)setCurrentAudioPlaybackDelay:(NSInteger)index
{
    libvlc_audio_set_delay(_playerInstance, index);
}

- (NSInteger)currentAudioPlaybackDelay
{
    return libvlc_audio_get_delay(_playerInstance);
}

#pragma mark -
#pragma mark equalizer

- (void)setEqualizerEnabled:(BOOL)equalizerEnabled
{
    _equalizerEnabled = equalizerEnabled;
    if (!_equalizerEnabled) {
        libvlc_media_player_set_equalizer(_playerInstance, NULL);

        if (_equalizerInstance)
            libvlc_audio_equalizer_release(_equalizerInstance);
        return;
    }

    if (!_equalizerInstance)
        _equalizerInstance = libvlc_audio_equalizer_new();
    libvlc_media_player_set_equalizer(_playerInstance, _equalizerInstance);
}

- (BOOL)equalizerEnabled
{
    return _equalizerEnabled;
}

- (NSArray *)equalizerProfiles
{
    unsigned count = libvlc_audio_equalizer_get_preset_count();
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count];
    for (unsigned x = 0; x < count; x++)
        [array addObject:[NSString stringWithUTF8String:libvlc_audio_equalizer_get_preset_name(x)]];

    return [NSArray arrayWithArray:array];
}

- (void)resetEqualizerFromProfile:(unsigned)profile
{
    BOOL wasactive = NO;
    if (_equalizerInstance) {
        libvlc_media_player_set_equalizer(_playerInstance, NULL);
        libvlc_audio_equalizer_release(_equalizerInstance);
        wasactive = YES;
    }

    _equalizerInstance = libvlc_audio_equalizer_new_from_preset(profile);
    if (wasactive)
        libvlc_media_player_set_equalizer(_playerInstance, _equalizerInstance);
}

- (CGFloat)preAmplification
{
    if (!_equalizerInstance)
        return 0.;

    return libvlc_audio_equalizer_get_preamp(_equalizerInstance);
}

- (void)setPreAmplification:(CGFloat)preAmplification
{
    if (!_equalizerInstance)
        _equalizerInstance = libvlc_audio_equalizer_new();

    libvlc_audio_equalizer_set_preamp(_equalizerInstance, preAmplification);
    libvlc_media_player_set_equalizer(_playerInstance, _equalizerInstance);
}

- (unsigned)numberOfBands
{
    return libvlc_audio_equalizer_get_band_count();
}

- (CGFloat)frequencyOfBandAtIndex:(unsigned int)index
{
    return libvlc_audio_equalizer_get_band_frequency(index);
}

- (void)setAmplification:(CGFloat)amplification forBand:(unsigned int)index
{
    if (!_equalizerInstance)
        _equalizerInstance = libvlc_audio_equalizer_new();

    libvlc_audio_equalizer_set_amp_at_index(_equalizerInstance, amplification, index);
}

- (CGFloat)amplificationOfBand:(unsigned int)index
{
    if (!_equalizerInstance)
        return 0.;

    return libvlc_audio_equalizer_get_amp_at_index(_equalizerInstance, index);
}

#pragma mark -
#pragma mark set/get media

- (void)setMedia:(VLCMedia *)value
{
    if (_media != value) {
        if (_media && [_media compare:value] == NSOrderedSame)
            return;

        [_media release];
        _media = [value retain];

        libvlc_media_player_set_media(_playerInstance, [_media libVLCMediaDescriptor]);
    }
}

- (VLCMedia *)media
{
    return _media;
}

#pragma mark -
#pragma mark playback

- (BOOL)play
{
    libvlc_media_player_play(_playerInstance);
    return YES;
}

- (void)pause
{
    if ([NSThread isMainThread]) {
        /* Hack because we create a dead lock here, when the vout is stopped
         * and tries to recontact us on the main thread */
        /* FIXME: to do this properly we need to do some locking. We may want
         * to move that to libvlc */
        [self performSelectorInBackground:@selector(pause) withObject:nil];
        return;
    }

    // Pause the stream
    libvlc_media_player_pause(_playerInstance);
}

- (void)stop
{
    if ([NSThread isMainThread]) {
        /* Hack because we create a dead lock here, when the vout is stopped
         * and tries to recontact us on the main thread */
        /* FIXME: to do this properly we need to do some locking. We may want
         * to move that to libvlc */
        [self performSelectorInBackground:@selector(stop) withObject:nil];
        return;
    }

    libvlc_media_player_stop(_playerInstance);
}

- (void)gotoNextFrame
{
    libvlc_media_player_next_frame(_playerInstance);

}

- (void)fastForward
{
    [self fastForwardAtRate: 2.0];
}

- (void)fastForwardAtRate:(float)rate
{
    [self setRate:rate];
}

- (void)rewind
{
    [self rewindAtRate: 2.0];
}

- (void)rewindAtRate:(float)rate
{
    [self setRate: -rate];
}

- (void)jumpBackward:(int)interval
{
    if ([self isSeekable]) {
        interval = interval * 1000;
        [self setTime: [VLCTime timeWithInt: ([[self time] intValue] - interval)]];
    }
}

- (void)jumpForward:(int)interval
{
    if ([self isSeekable]) {
        interval = interval * 1000;
        [self setTime: [VLCTime timeWithInt: ([[self time] intValue] + interval)]];
    }
}

- (void)extraShortJumpBackward
{
    [self jumpBackward:3];
}

- (void)extraShortJumpForward
{
    [self jumpForward:3];
}

- (void)shortJumpBackward
{
    [self jumpBackward:10];
}

- (void)shortJumpForward
{
    [self jumpForward:10];
}

- (void)mediumJumpBackward
{
    [self jumpBackward:60];
}

- (void)mediumJumpForward
{
    [self jumpForward:60];
}

- (void)longJumpBackward
{
    [self jumpBackward:300];
}

- (void)longJumpForward
{
    [self jumpForward:300];
}

+ (NSSet *)keyPathsForValuesAffectingIsPlaying
{
    return [NSSet setWithObjects:@"state", nil];
}

- (BOOL)isPlaying
{
    return libvlc_media_player_is_playing(_playerInstance);
}

- (BOOL)willPlay
{
    return libvlc_media_player_will_play(_playerInstance);
}

static const VLCMediaPlayerState libvlc_to_local_state[] =
{
    [libvlc_Stopped]    = VLCMediaPlayerStateStopped,
    [libvlc_Opening]    = VLCMediaPlayerStateOpening,
    [libvlc_Buffering]  = VLCMediaPlayerStateBuffering,
    [libvlc_Playing]    = VLCMediaPlayerStatePlaying,
    [libvlc_Paused]     = VLCMediaPlayerStatePaused,
    [libvlc_Ended]      = VLCMediaPlayerStateEnded,
    [libvlc_Error]      = VLCMediaPlayerStateError
};

- (VLCMediaPlayerState)state
{
    return _cachedState;
}

- (float)position
{
    return _position;
}

- (void)setPosition:(float)newPosition
{
    libvlc_media_player_set_position(_playerInstance, newPosition);
}

- (BOOL)isSeekable
{
    return libvlc_media_player_is_seekable(_playerInstance);
}

- (BOOL)canPause
{
    return libvlc_media_player_can_pause(_playerInstance);
}

- (void *)libVLCMediaPlayer
{
    return _playerInstance;
}
@end

@implementation VLCMediaPlayer (Private)
- (id)initWithDrawable:(id)aDrawable options:(NSArray *)options
{
    if (self = [super init]) {
        _delegate = nil;
        _media = nil;
        _cachedTime = [[VLCTime nullTime] retain];
        _cachedRemainingTime = [[VLCTime nullTime] retain];
        _position = 0.0f;
        _cachedState = VLCMediaPlayerStateStopped;

        // Create a media instance, it doesn't matter what library we start off with
        // it will change depending on the media descriptor provided to the media
        // instance
        if (options && options.count > 0) {
            VKLog(@"creating player instance with private library as options were given");
            _privateLibrary = [[VLCLibrary alloc] initWithOptions:options];
        } else {
            VKLog(@"creating player instance using shared library");
            _privateLibrary = [[VLCLibrary sharedLibrary] retain];
        }
        libvlc_retain([_privateLibrary instance]);
        _playerInstance = libvlc_media_player_new([_privateLibrary instance]);
        libvlc_media_player_retain(_playerInstance);

        [self registerObservers];

        [self setDrawable:aDrawable];
    }
    return self;
}

- (void)registerObservers
{
    // Attach event observers into the media instance
    libvlc_event_manager_t * p_em = libvlc_media_player_event_manager(_playerInstance);
    libvlc_event_attach(p_em, libvlc_MediaPlayerPlaying,          HandleMediaInstanceStateChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerPaused,           HandleMediaInstanceStateChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerEncounteredError, HandleMediaInstanceStateChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerEndReached,       HandleMediaInstanceStateChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerStopped,          HandleMediaInstanceStateChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerOpening,          HandleMediaInstanceStateChanged, self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerBuffering,        HandleMediaInstanceStateChanged, self);

    libvlc_event_attach(p_em, libvlc_MediaPlayerPositionChanged,  HandleMediaPositionChanged,      self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerTimeChanged,      HandleMediaTimeChanged,          self);
    libvlc_event_attach(p_em, libvlc_MediaPlayerMediaChanged,     HandleMediaPlayerMediaChanged,   self);
}

- (void)unregisterObservers
{
    libvlc_event_manager_t * p_em = libvlc_media_player_event_manager(_playerInstance);
    libvlc_event_detach(p_em, libvlc_MediaPlayerPlaying,          HandleMediaInstanceStateChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerPaused,           HandleMediaInstanceStateChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerEncounteredError, HandleMediaInstanceStateChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerEndReached,       HandleMediaInstanceStateChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerStopped,          HandleMediaInstanceStateChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerOpening,          HandleMediaInstanceStateChanged, self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerBuffering,        HandleMediaInstanceStateChanged, self);

    libvlc_event_detach(p_em, libvlc_MediaPlayerPositionChanged,  HandleMediaPositionChanged,      self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerTimeChanged,      HandleMediaTimeChanged,          self);
    libvlc_event_detach(p_em, libvlc_MediaPlayerMediaChanged,     HandleMediaPlayerMediaChanged,   self);
}

- (void)mediaPlayerTimeChanged:(NSNumber *)newTime
{
    [self willChangeValueForKey:@"time"];
    [self willChangeValueForKey:@"remainingTime"];
    [_cachedTime release];
    _cachedTime = [[VLCTime timeWithNumber:newTime] retain];
    [_cachedRemainingTime release];
    double currentTime = [[_cachedTime numberValue] doubleValue];
    if (currentTime > 0) {
        double remaining = currentTime / _position * (1 - _position);
        _cachedRemainingTime = [[VLCTime timeWithNumber:@(-remaining)] retain];
    } else
        _cachedRemainingTime = [[VLCTime nullTime] retain];
    [self didChangeValueForKey:@"remainingTime"];
    [self didChangeValueForKey:@"time"];
}

#if !TARGET_OS_IPHONE
- (void)delaySleep
{
    UpdateSystemActivity(UsrActivity);
}
#endif

- (void)mediaPlayerPositionChanged:(NSNumber *)newPosition
{
#if !TARGET_OS_IPHONE
    // This seems to be the most relevant place to delay sleeping and screen saver.
    [self delaySleep];
#endif

    [self willChangeValueForKey:@"position"];
    _position = [newPosition floatValue];
    [self didChangeValueForKey:@"position"];
}

- (void)mediaPlayerStateChanged:(NSNumber *)newState
{
    [self willChangeValueForKey:@"state"];
    _cachedState = [newState intValue];

#if TARGET_OS_IPHONE
    // Disable idle timer if player is playing media
    // Exclusion can be made for audio only media
    [UIApplication sharedApplication].idleTimerDisabled = [self isPlaying];
#endif
    [self didChangeValueForKey:@"state"];
}

- (void)mediaPlayerMediaChanged:(VLCMedia *)newMedia
{
    [self willChangeValueForKey:@"media"];
    if (_media != newMedia)
    {
        [_media release];
        _media = [newMedia retain];
    }
    [self didChangeValueForKey:@"media"];
}

@end
