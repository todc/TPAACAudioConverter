//
//  AACConverterViewController.m
//  AACConverter
//
//  Created by Michael Tyson on 02/04/2011.
//  Copyright 2011 A Tasty Pixel. All rights reserved.
//

#import "AACConverterViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define checkResult(result,operation) (_checkResult((result),(operation),__FILE__,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&result);
        return NO;
    }
    return YES;
}


@interface AACConverterViewController ()
{
    BOOL isAudioSessionInitialized;
}
@end


@implementation AACConverterViewController
@synthesize convertButton;
@synthesize playConvertedButton;
@synthesize emailConvertedButton;
@synthesize progressView;
@synthesize spinner;

// Callback to be notified of audio session interruptions (which have an impact on the conversion process)
- (void)audioSessionDidChangeInterruptionType:(NSNotification *)notification
{
    AVAudioSessionInterruptionType interruptionType = [[[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (AVAudioSessionInterruptionTypeBegan == interruptionType)
    {
        // make sure we are again the active session
		checkResult(AudioSessionSetActive(true), "resume audio session");
        if ( self->audioConverter ) [self->audioConverter resume];
    }
    else if (AVAudioSessionInterruptionTypeEnded == interruptionType)
    {
        if ( self->audioConverter ) [self->audioConverter interrupt];
    }
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    isAudioSessionInitialized = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionDidChangeInterruptionType:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
}

- (void)viewDidUnload
{
    [self setConvertButton:nil];
    [self setPlayConvertedButton:nil];
    [self setEmailConvertedButton:nil];
    progressView = nil;
    spinner = nil;
    [self setProgressView:nil];
    [self setSpinner:nil];
    [super viewDidUnload];
}

#pragma mark - Responders

- (IBAction)playOriginal:(id)sender {
    if ( audioPlayer ) {
        [audioPlayer stop];
        audioPlayer = nil;
        [(UIButton*)sender setTitle:@"Play original" forState:UIControlStateNormal];
    } else {
        audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"audio" withExtension:@"aiff"] error:NULL];
        [audioPlayer play];
        
        [(UIButton*)sender setTitle:@"Stop" forState:UIControlStateNormal];
    }
}

- (IBAction)convert:(id)sender {
    if ( ![TPAACAudioConverter AACConverterAvailable] ) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Converting audio", @"")
                                    message:NSLocalizedString(@"Couldn't convert audio: Not supported on this device", @"")
                                   delegate:nil
                          cancelButtonTitle:nil
                          otherButtonTitles:NSLocalizedString(@"OK", @""), nil] show];
        return;
    }
    
    NSError *initError;
    BOOL activated = [[AVAudioSession sharedInstance] setActive:YES error:&initError];
    if (initError != nil || !activated) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Converting audio", @"")
                                    message:NSLocalizedString(@"Couldn't initialise audio session!", @"")
                                   delegate:nil
                          cancelButtonTitle:nil
                          otherButtonTitles:NSLocalizedString(@"OK", @""), nil] show];
        return;
    }
    
    NSError *nsError;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&nsError];
    if (nsError != nil) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Converting audio", @"")
                                    message:NSLocalizedString(@"Couldn't setup audio category!", @"")
                                   delegate:nil
                          cancelButtonTitle:nil
                          otherButtonTitles:NSLocalizedString(@"OK", @""), nil] show];
        return;
    }
    
    NSArray *documentsFolders = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    audioConverter = [[TPAACAudioConverter alloc] initWithDelegate:self
                                                            source:[[NSBundle mainBundle] pathForResource:@"audio" ofType:@"aiff"]
                                                       destination:[[documentsFolders objectAtIndex:0] stringByAppendingPathComponent:@"audio.m4a"]];
    ((UIButton*)sender).enabled = NO;
    [self.spinner startAnimating];
    self.progressView.progress = 0.0;
    self.progressView.hidden = NO;
    
    [audioConverter start];
}

- (IBAction)playConverted:(id)sender {
    if ( audioPlayer ) {
        [audioPlayer stop];
        audioPlayer = nil;
        [(UIButton*)sender setTitle:@"Play converted" forState:UIControlStateNormal];
    } else {
        NSArray *documentsFolders = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *path = [[documentsFolders objectAtIndex:0] stringByAppendingPathComponent:@"audio.m4a"];
        audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:NULL];
        [audioPlayer play];
        
        [(UIButton*)sender setTitle:@"Stop" forState:UIControlStateNormal];
    }
}

- (IBAction)emailConverted:(id)sender {
    NSArray *documentsFolders = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [[documentsFolders objectAtIndex:0] stringByAppendingPathComponent:@"audio.m4a"];
    
    MFMailComposeViewController *mailController = [[MFMailComposeViewController alloc] init];
    mailController.mailComposeDelegate = self;
    [mailController setSubject:NSLocalizedString(@"Recording", @"")];
    [mailController addAttachmentData:[NSData dataWithContentsOfMappedFile:path]
                             mimeType:@"audio/mp4a-latm"
                             fileName:[path lastPathComponent]];
    
    [self presentModalViewController:mailController animated:YES];
}

#pragma mark - Audio converter delegate

-(void)AACAudioConverter:(TPAACAudioConverter *)converter didMakeProgress:(CGFloat)progress {
    self.progressView.progress = progress;
}

-(void)AACAudioConverterDidFinishConversion:(TPAACAudioConverter *)converter {
    self.progressView.hidden = YES;
    [self.spinner stopAnimating];
    self.convertButton.enabled = YES;
    self.playConvertedButton.enabled = YES;
    self.emailConvertedButton.enabled = YES;
    audioConverter = nil;
}

-(void)AACAudioConverter:(TPAACAudioConverter *)converter didFailWithError:(NSError *)error {
    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Converting audio", @"")
                                message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't convert audio: %@", @""), [error localizedDescription]]
                               delegate:nil
                      cancelButtonTitle:nil
                      otherButtonTitles:NSLocalizedString(@"OK", @""), nil] show];
    self.convertButton.enabled = YES;
    audioConverter = nil;
}

#pragma mark - Mail composer delegate

-(void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [self dismissModalViewControllerAnimated:YES];
}

@end
