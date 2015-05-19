//
//  ViewController.m
//  iOSEchoCancellation
//
//  Created by 李 行 on 15/4/12.
//  Copyright (c) 2015年 lixing123.com. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

typedef struct MyAUGraphStruct{
    AUGraph graph;
    AudioUnit remoteIOUnit;
} MyAUGraphStruct;

#define BUFFER_COUNT 15

MyAUGraphStruct myStruct;

AudioBuffer recordedBuffers[BUFFER_COUNT];//Used to save audio data
int         currentBufferPointer;//Pointer to the current buffer
int         callbackCount;

static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}

OSStatus InputCallback(void *inRefCon,
                       AudioUnitRenderActionFlags *ioActionFlags,
                       const AudioTimeStamp *inTimeStamp,
                       UInt32 inBusNumber,
                       UInt32 inNumberFrames,
                       AudioBufferList *ioData){
    //TODO: implement this function
    MyAUGraphStruct* myStruct = (MyAUGraphStruct*)inRefCon;
    
    //Get samples from input bus(bus 1)
    CheckError(AudioUnitRender(myStruct->remoteIOUnit,
                               ioActionFlags,
                               inTimeStamp,
                               1,
                               inNumberFrames,
                               ioData),
               "AudioUnitRender failed");
    
    //save audio to ring buffer and load from ring buffer
    AudioBuffer buffer = ioData->mBuffers[0];
    recordedBuffers[currentBufferPointer].mNumberChannels = buffer.mNumberChannels;
    recordedBuffers[currentBufferPointer].mDataByteSize = buffer.mDataByteSize;
    free(recordedBuffers[currentBufferPointer].mData);
    recordedBuffers[currentBufferPointer].mData = malloc(sizeof(SInt16)*buffer.mDataByteSize);
    memcpy(recordedBuffers[currentBufferPointer].mData,
           buffer.mData,
           buffer.mDataByteSize);
    currentBufferPointer = (currentBufferPointer+1)%BUFFER_COUNT;
    
    if (callbackCount>=BUFFER_COUNT) {
        memcpy(buffer.mData,
               recordedBuffers[currentBufferPointer].mData,
               buffer.mDataByteSize);
    }
    callbackCount++;
    
    /*
    SInt16 sample = 0;
    int currentFrame = 0;
    UInt32 bytesPerChannel = controller.streamFormat.mBytesPerFrame/controller.streamFormat.mChannelsPerFrame;
    while (currentFrame<inNumberFrames) {
        for (int currentChannel=0; currentChannel<buffer.mNumberChannels; currentChannel++) {
            //Copy sample to buffer, across all channels
            memcpy(&sample,
                   buffer.mData+(currentFrame*controller.streamFormat.mBytesPerFrame) + currentChannel*bytesPerChannel,
                   sizeof(sample));
            
            memcpy(buffer.mData+(currentFrame*controller.streamFormat.mBytesPerFrame) + currentChannel*bytesPerChannel,
                   &sample,
                   sizeof(sample));
        }
        currentFrame++;
    }*/
    
    return noErr;
}

@interface ViewController ()

@end

@implementation ViewController

@synthesize streamFormat;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //Initialize currentBufferPointer
    currentBufferPointer = 0;
    callbackCount = 0;
    
    [self setupSession];
    
    [self createAUGraph:&myStruct];
    
    [self setupRemoteIOUnit:&myStruct];
    
    [self startGraph:myStruct.graph];
    
    [self addControlButton];
}

-(void)addControlButton{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.frame = CGRectMake(60, 60, 200, 50);
    [button setTitle:@"Echo cancellation is open" forState:UIControlStateNormal];
    [button.titleLabel setTextAlignment:NSTextAlignmentCenter];
    [button addTarget:self action:@selector(openOrCloseEchoCancellation:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

-(void)openOrCloseEchoCancellation:(UIButton*)button{
    UInt32 echoCancellation;
    UInt32 size = sizeof(echoCancellation);
    CheckError(AudioUnitGetProperty(myStruct.remoteIOUnit,
                                    kAUVoiceIOProperty_BypassVoiceProcessing,
                                    kAudioUnitScope_Global,
                                    0,
                                    &echoCancellation,
                                    &size),
               "kAUVoiceIOProperty_BypassVoiceProcessing failed");
    if (echoCancellation==0) {
        echoCancellation = 1;
    }else{
        echoCancellation = 0;
    }
    
    CheckError(AudioUnitSetProperty(myStruct.remoteIOUnit,
                                    kAUVoiceIOProperty_BypassVoiceProcessing,
                                    kAudioUnitScope_Global,
                                    0,
                                    &echoCancellation,
                                    sizeof(echoCancellation)),
               "AudioUnitSetProperty kAUVoiceIOProperty_BypassVoiceProcessing failed");
    
    [button setTitle:echoCancellation==0?@"Echo cancellation is open":@"Echo cancellation is closed" forState:UIControlStateNormal];
}

-(void)startGraph:(AUGraph)graph{
    CheckError(AUGraphInitialize(graph),
               "AUGraphInitialize failed");
    
    CheckError(AUGraphStart(graph),
               "AUGraphStart failed");
}

-(void)setupRemoteIOUnit:(MyAUGraphStruct*)myStruct{
    //Open input of the bus 1(input mic)
    UInt32 enableFlag = 1;
    CheckError(AudioUnitSetProperty(myStruct->remoteIOUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    1,
                                    &enableFlag,
                                    sizeof(enableFlag)),
               "Open input of bus 1 failed");
    
    //Open output of bus 0(output speaker)
    CheckError(AudioUnitSetProperty(myStruct->remoteIOUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Output,
                                    0,
                                    &enableFlag,
                                    sizeof(enableFlag)),
               "Open output of bus 0 failed");
    
    //Set up stream format for input and output
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    streamFormat.mSampleRate = 44100;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = 2;
    streamFormat.mBytesPerPacket = 2;
    streamFormat.mBitsPerChannel = 16;
    streamFormat.mChannelsPerFrame = 1;
    
    CheckError(AudioUnitSetProperty(myStruct->remoteIOUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    0,
                                    &streamFormat,
                                    sizeof(streamFormat)),
               "kAudioUnitProperty_StreamFormat of bus 0 failed");
    
    CheckError(AudioUnitSetProperty(myStruct->remoteIOUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    1,
                                    &streamFormat,
                                    sizeof(streamFormat)),
               "kAudioUnitProperty_StreamFormat of bus 1 failed");
    
    //Set up input callback
    AURenderCallbackStruct input;
    input.inputProc = InputCallback;
    input.inputProcRefCon = myStruct;
    CheckError(AudioUnitSetProperty(myStruct->remoteIOUnit,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Global,
                                    0,//input mic
                                    &input,
                                    sizeof(input)),
               "kAudioUnitProperty_SetRenderCallback failed");
}

-(void)createAUGraph:(MyAUGraphStruct*)myStruct{
    //Create graph
    CheckError(NewAUGraph(&myStruct->graph),
               "NewAUGraph failed");
    
    //Create nodes and add to the graph
    //Set up a RemoteIO for synchronously playback
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    //inputcd.componentSubType = kAudioUnitSubType_RemoteIO;
    //we can access the system's echo cancellation by using kAudioUnitSubType_VoiceProcessingIO subtype
    inputcd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AUNode remoteIONode;
    //Add node to the graph
    CheckError(AUGraphAddNode(myStruct->graph,
                              &inputcd,
                              &remoteIONode),
               "AUGraphAddNode failed");
    
    //Open the graph
    CheckError(AUGraphOpen(myStruct->graph),
               "AUGraphOpen failed");
    
    //Get reference to the node
    CheckError(AUGraphNodeInfo(myStruct->graph,
                               remoteIONode,
                               &inputcd,
                               &myStruct->remoteIOUnit),
               "AUGraphNodeInfo failed");
}

-(void)createRemoteIONodeToGraph:(AUGraph*)graph{
    
}

-(void)setupSession{
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    [session setActive:YES error:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
