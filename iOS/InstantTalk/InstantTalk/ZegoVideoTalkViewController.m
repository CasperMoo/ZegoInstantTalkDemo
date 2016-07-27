//
//  ZegoVideoTalkViewController.m
//  InstantTalk
//
//  Created by Strong on 16/7/11.
//  Copyright © 2016年 ZEGO. All rights reserved.
//

#import "ZegoVideoTalkViewController.h"
#import "ZegoAVKitManager.h"
#import "ZegoDataCenter.h"
#import "ZegoStreamInfo.h"
#import "ZegoLogTableViewController.h"

@interface ZegoVideoTalkViewController () <ZegoLiveApiDelegate, BizRoomStreamDelegate>

@property (nonatomic, weak) IBOutlet UIView *playContainerView;
@property (nonatomic, weak) IBOutlet UILabel *tipsLabel;

@property (nonatomic, strong) NSMutableArray *playStreamList;
@property (nonatomic, strong) NSMutableDictionary *viewContainersDict;
@property (nonatomic, strong) NSMutableDictionary *viewIndexDict;

@property (nonatomic, copy) NSString *liveChannel;
@property (nonatomic, copy) NSString *liveStreamID;
@property (nonatomic, copy) NSString *liveTitle;

@property (nonatomic, strong) UIView *publishView;

@property (nonatomic, assign) BOOL firstPlayStream;
@property (nonatomic, assign) BOOL loginChannelSuccess;
@property (nonatomic, assign) BOOL loginPrivateRoomSuccess;

@property (nonatomic, strong) NSTimer *checkTimer;
@property (nonatomic, assign) NSUInteger refuseUserNumber;

@property (nonatomic, assign) BOOL isPublishing;
@property (nonatomic, assign) BOOL shouldInterrutped;

@property (nonatomic, strong) NSMutableArray *retryStreamList;

@end

@implementation ZegoVideoTalkViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    if (self.isRequester)
    {
        [[ZegoDataCenter sharedInstance] requestVideoTalk:self.userList];
    }
    
    _viewContainersDict = [[NSMutableDictionary alloc] initWithCapacity:MAX_STREAM_COUNT];
    _viewIndexDict = [[NSMutableDictionary alloc] initWithCapacity:MAX_STREAM_COUNT];
    _playStreamList = [[NSMutableArray alloc] init];
    _retryStreamList = [[NSMutableArray alloc] init];
    
    //先创建一个小view进行preview
    UIView *publishView = [self createPublishView];
    if (publishView)
    {
        [self setAnchorConfig:publishView];
        [getZegoAV_ShareInstance() startPreview];
        self.publishView = publishView;
    }

    
    if (self.isRequester)
    {
        //监听消息
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onRespondVideoTalk:) name:kUserRespondVideoTalkNotification object:nil];
        self.tipsLabel.text = @"等待对方同意...";
    }
    else
    {
        //退出大厅，进入私有房间
        [[ZegoDataCenter sharedInstance] leaveRoom];
        self.tipsLabel.text = @"退出大厅...";
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onLeaveRoomFinished:) name:kUserLeaveRoomNotification object:nil];
    self.checkTimer = [NSTimer scheduledTimerWithTimeInterval:120 target:self selector:@selector(onCheckUser) userInfo:nil repeats:NO];
}

- (void)audioSessionWasInterrupted:(NSNotification *)notification
{
    if (AVAudioSessionInterruptionTypeBegan == [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue])
    {
        if (!self.isPublishing)
        {
            self.shouldInterrutped = NO;
            return;
        }
        else
        {
            self.shouldInterrutped = YES;
        }
        
        [self closeAllStream];
        
        [getZegoAV_ShareInstance() logoutChannel];
    }
    else if (AVAudioSessionInterruptionTypeEnded == [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue])
    {
        if (!self.shouldInterrutped)
            return;
        
        [getBizRoomInstance() cteateStreamInRoom:self.liveTitle preferredStreamID:self.liveStreamID];
        
        NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"创建断开之前相同的流", nil)];
        [self addLogString:logString];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (self.isMovingFromParentViewController)
    {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
}

- (void)setupLiveKit
{
    getZegoAV_ShareInstance().delegate = self;
    getBizRoomInstance().streamDelegate = self;
}

- (void)onCheckUser
{
    if (self.liveStreamID == nil || self.playStreamList.count == 0)
    {
        if (self.isPublishing)
            self.tipsLabel.text = @"所有人都退出了聊天";
        else
            self.tipsLabel.text = @"对方可能无法响应";
    }
}

- (void)loginPrivateRoom
{
    if (self.privateRoomID == 0)
    {
        NSLog(@"token is 0, not a private room");
        return;
    }
    
    ZegoUser *user = [[ZegoSettings sharedInstance] getZegoUser];
    [getBizRoomInstance() loginLiveRoom:user.userID userName:user.userName bizToken:0 bizID:self.privateRoomID];
    
    [self addLogString:[NSString stringWithFormat:@"开始登录私有房间,房间ID: 0x%x", self.privateRoomID]];
}

- (void)onRespondVideoTalk:(NSNotification *)notification
{
    BOOL agreed = [notification.userInfo[@"result"] boolValue];
    if (agreed)
    {
        //退出大厅，进入私有房间
        [[ZegoDataCenter sharedInstance] leaveRoom];
        self.privateRoomID = [notification.userInfo[@"roomID"] unsignedIntValue];
    }
    else
    {
        //有用户拒绝
        self.refuseUserNumber += 1;
        if (self.refuseUserNumber == self.userList.count - 1)
        {
            //所有用户都拒绝了
            if (self.userList.count == 2)
                self.tipsLabel.text = @"对方拒绝了您的请求";
            else
                self.tipsLabel.text = @"所有人都拒绝了您的请求";
        }
    }
}

- (void)onLeaveRoomFinished:(NSNotification *)notification
{
    //退出了大厅，进入私有房间
    [self setupLiveKit];
    [self loginPrivateRoom];
    self.tipsLabel.text = @"开始登录私有房间...";
    
    [self.logArray addObject:[NSString stringWithFormat:@"退出大厅,开始登录私有房间"]];
}

- (void)dismissViewController
{
    self.loginPrivateRoomSuccess = NO;
    
    //发广播,让dataCenter开始重新登录公共房间
    [[NSNotificationCenter defaultCenter] postNotificationName:kUserLeavePrivateRoomNotification object:nil userInfo:nil];
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)closeAllStream
{
    [getZegoAV_ShareInstance() stopPreview];
    [getZegoAV_ShareInstance() setLocalView:nil];
    [getZegoAV_ShareInstance() stopPublishing];
    
    [self reportStreamAction:NO streamID:self.liveStreamID];
    [self removeStreamViewContainer:self.liveStreamID];
    self.publishView = nil;
    self.firstPlayStream = NO;
    
    for (ZegoStreamInfo *info in self.playStreamList)
    {
        NSLog(@"stop Play Stream: %@", info.streamID);
        [getZegoAV_ShareInstance() stopPlayStream:info.streamID];
        [self removeStreamViewContainer:info.streamID];
    }
    
    [self.viewContainersDict removeAllObjects];
    [self.viewIndexDict removeAllObjects];
    [self.retryStreamList removeAllObjects];
}

- (IBAction)closeView:(id)sender
{
    self.tipsLabel.text = @"退出视频聊天...";
    
    [getZegoAV_ShareInstance() stopPreview];
    [getZegoAV_ShareInstance() setLocalView:nil];
    
    if (self.loginChannelSuccess)
    {
        [self closeAllStream];
    
        [getZegoAV_ShareInstance() logoutChannel];
    }
    
    if (self.loginPrivateRoomSuccess)
    {
        [getBizRoomInstance() leaveLiveRoom];
        self.loginPrivateRoomSuccess = NO;
    }
    else
    {
        [self dismissViewController];
        if (self.isRequester)
        {
            //请求方在还没有应答时就退出了页面
            [[ZegoDataCenter sharedInstance] cancelVideoTalk:self.userList];
        }
    }
    
    [[ZegoDataCenter sharedInstance] stopVideoTalk];
}

- (IBAction)onShowPublishOption:(id)sender
{
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    ZegoAnchorOptionViewController *optionController = (ZegoAnchorOptionViewController *)[storyboard instantiateViewControllerWithIdentifier:@"anchorOptionID"];
    
    optionController.useFrontCamera = self.useFrontCamera;
    optionController.enableMicrophone = self.enableMicrophone;
    optionController.enableTorch = self.enableTorch;
    optionController.beautifyRow = self.beautifyFeature;
    optionController.filterRow = self.filter;
    optionController.enableCamera = self.enableCamera;
    
    optionController.delegate = self;
    
    self.definesPresentationContext = YES;
    if (![self isDeviceiOS7])
        optionController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    else
        optionController.modalPresentationStyle = UIModalPresentationCurrentContext;
    
    optionController.view.backgroundColor = [UIColor clearColor];
    [self presentViewController:optionController animated:YES completion:nil];
    
}
- (UIView *)createPublishView
{
    UIView *publishView = [[UIView alloc] init];
    publishView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playContainerView addSubview:publishView];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapView:)];
    [publishView addGestureRecognizer:tapGesture];
    
    BOOL bResult = [self setContainerConstraints:publishView containerView:self.playContainerView viewCount:0];
    if (bResult == NO)
    {
        [publishView removeFromSuperview];
        return nil;
    }
    
    [self.playContainerView bringSubviewToFront:publishView];
    
    return publishView;
}

- (void)onTapView:(UIGestureRecognizer *)recognizer
{
    if (self.playContainerView.subviews.count < 2)
        return;
    
    UIView *view = recognizer.view;
    if (view == nil)
        return;
    
    [self updateContainerConstraintsForTap:view containerView:self.playContainerView];
}

- (void)createStream
{
    self.liveTitle = [NSString stringWithFormat:@"Hello-%@", [ZegoSettings sharedInstance].userName];
    [getBizRoomInstance() cteateStreamInRoom:self.liveTitle preferredStreamID:nil];
    
    NSString *logString = [NSString stringWithFormat:@"创建流"];
    [self addLogString:logString];
}

- (void)getStreamList
{
    [getBizRoomInstance() getStreamList];
    
    NSString *logString = [NSString stringWithFormat:@"开始获取直播流列表"];
    [self addLogString:logString];
}

- (UIView *)createPlayView:(NSString *)streamID
{
    UIView *playView = [[UIView alloc] init];
    playView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playContainerView addSubview:playView];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapView:)];
    [playView addGestureRecognizer:tapGesture];
    
    NSUInteger count = self.viewContainersDict.count;
    if (self.viewContainersDict.count == 0)
        count = 1;
    
    BOOL bResult = [self setContainerConstraints:playView containerView:self.playContainerView viewCount:count];
    if (bResult == NO)
    {
        [playView removeFromSuperview];
        return nil;
    }
    
    self.viewContainersDict[streamID] = playView;
    [self.playContainerView bringSubviewToFront:playView];
    
    return playView;
    
}

- (int)getRemoteViewIndex
{
    int index = 0;
    for (; index < MAX_STREAM_COUNT; index++)
    {
        if ([self.viewIndexDict allKeysForObject:@(index)].count == 0)
            return index;
    }
    
    if (index == MAX_STREAM_COUNT)
        NSLog(@"cannot find indx to add view");
    
    return index;
}

- (void)createPlayStream:(NSString *)streamID
{
    UIView *playView = [self createPlayView:streamID];
    
    RemoteViewIndex index = (RemoteViewIndex)[self getRemoteViewIndex];
    self.viewIndexDict[streamID] = @(index);
    
    [getZegoAV_ShareInstance() setRemoteView:index view:playView];
    [getZegoAV_ShareInstance() setRemoteViewMode:index mode:ZegoVideoViewModeScaleAspectFill];
    bool ret = [getZegoAV_ShareInstance() startPlayStream:streamID viewIndex:index];
    assert(ret);
    
    if (self.firstPlayStream == NO)
    {
        self.firstPlayStream = YES;
        [self updateContainerConstraintsForTap:playView containerView:self.playContainerView];
    }
}

- (void)onStreamUpdateForAdd:(NSArray<NSDictionary *> *)streamList
{
    for (NSDictionary *dic in streamList)
    {
        NSString *streamID = dic[kRoomStreamIDKey];
        if ([self isStreamIDExist:streamID])
        {
            continue;
        }
        
        ZegoStreamInfo *streamInfo = [ZegoStreamInfo getStreamInfo:dic];
        [self.playStreamList addObject:streamInfo];
        [self createPlayStream:streamID];
        
        NSString *logString = [NSString stringWithFormat:@"新增一条流, 流ID:%@", streamID];
        [self addLogString:logString];
        
        if (self.isPublishing)
            self.tipsLabel.text = @"视频聊天中...";
        
        if (self.viewContainersDict.count >= MAX_STREAM_COUNT)
            break;
    }
}

- (void)onStreamUpdateForDelete:(NSArray<NSDictionary *> *)streamList
{
    for (NSDictionary *dic in streamList)
    {
        NSString *streamID = dic[kRoomStreamIDKey];
        if (![self isStreamIDExist:streamID])
            continue;
        
        [self removeStreamViewContainer:streamID];
        [self removeStreamInfo:streamID];
        
        NSString *logString = [NSString stringWithFormat:@"删除一条流, 流ID:%@", streamID];
        [self addLogString:logString];
    }
    
    if (self.playStreamList.count == 0)
    {
        self.tipsLabel.text = @"对方退出视频聊天";
        self.firstPlayStream = NO;
    }
}

- (BOOL)isStreamIDExist:(NSString *)streamID
{
    if ([self.liveStreamID isEqualToString:streamID])
        return YES;
    
    for (ZegoStreamInfo *info in self.playStreamList)
    {
        if ([info.streamID isEqualToString:streamID])
            return YES;
    }
    
    return NO;
}

- (void)removeStreamInfo:(NSString *)streamID
{
    NSInteger index = NSNotFound;
    for (ZegoStreamInfo *info in self.playStreamList)
    {
        if ([info.streamID isEqualToString:streamID])
        {
            index = [self.playStreamList indexOfObject:info];
            break;
        }
    }
    
    if (index != NSNotFound)
        [self.playStreamList removeObjectAtIndex:index];
}

#pragma mark BizStreamRoom Delegate
- (void)onLoginRoom:(int)err bizID:(unsigned int)bizID bizToken:(unsigned int)bizToken
{
    NSLog(@"%s, error: %d", __func__, err);
    if (err == 0)
    {
        if (bizID != self.privateRoomID)
        {
            NSString *logString = [NSString stringWithFormat:@"登录私有房间成功,room id不同. token 0x%x, id 0x%x", bizToken, bizID];
            [self addLogString:logString];
            return;
        }
        
        NSString *logString = [NSString stringWithFormat:@"登录私有房间成功. token 0x%x, id 0x%x", bizToken, bizID];
        [self addLogString:logString];
        
        self.liveChannel = [[ZegoSettings sharedInstance] getChannelID:bizToken bizID:bizID];
        [self createStream];
        
        self.loginPrivateRoomSuccess = YES;
        self.tipsLabel.text = @"与对方连接中...";
    }
    else
    {
        NSString *logString = [NSString stringWithFormat:@"登录私有房间失败，token 0x%x, id 0x%x, privateID 0x%x. error: %d", bizToken, bizID, self.privateRoomID, err];
        [self addLogString:logString];
        self.tipsLabel.text = @"登录私有房间失败";
    }
}

- (void)onDisconnected:(int)err bizID:(unsigned int)bizID bizToken:(unsigned int)bizToken
{
    NSLog(@"%s, error: %d", __func__, err);
}

- (void)onLeaveRoom:(int)err
{
    NSLog(@"%s, error: %d", __func__, err);
    NSString *logString = [NSString stringWithFormat:@"退出房间, error: %d", err];
    [self addLogString:logString];
    
    [self dismissViewController];
}

- (void)onStreamCreate:(NSString *)streamID url:(NSString *)url
{
    if (streamID.length != 0)
    {
        NSString *logString = [NSString stringWithFormat:@"创建流成功, streamID:%@", streamID];
        [self addLogString:logString];
        
        self.liveStreamID = streamID;
        [self loginChannel];
    }
    else
    {
        NSString *logString = [NSString stringWithFormat:@"创建流失败"];
        [self addLogString:logString];
    }
}

- (void)onStreamUpdate:(NSArray<NSDictionary *> *)streamList flag:(int)flag
{
    if (!self.loginChannelSuccess)
    {
        NSString *logString = [NSString stringWithFormat:@"流列表有更新, 此时还未登录channel,先缓存"];
        [self addLogString:logString];
        
        if (flag == 1)
            return;
        
        //先把流缓存起来
        for (NSDictionary *dic in streamList)
        {
            NSString *streamID = dic[kRoomStreamIDKey];
            if ([self isStreamIDExist:streamID])
            {
                continue;
            }
            
            ZegoStreamInfo *streamInfo = [ZegoStreamInfo getStreamInfo:dic];
            [self.playStreamList addObject:streamInfo];
        }
        
        return;
    }
    
    if (streamList.count == 0)
    {
        NSString *logString = [NSString stringWithFormat:@"流更新列表为空"];
        [self addLogString:logString];
        return;
    }
    
    if (flag == 0)
        [self onStreamUpdateForAdd:streamList];
    else if (flag == 1)
        [self onStreamUpdateForDelete:streamList];
}

#pragma mark ZegoLiveAPI
- (void)loginChannel
{
    ZegoUser *user = [[ZegoSettings sharedInstance] getZegoUser];
    bool ret = [getZegoAV_ShareInstance() loginChannel:self.liveChannel user:user];
    assert(ret);
    
    NSLog(@"%s, ret: %d", __func__, ret);
    
    NSString *logString = [NSString stringWithFormat:@"登录channel"];
    [self addLogString:logString];
}

- (void)removeStreamViewContainer:(NSString *)streamID
{
    UIView *view = self.viewContainersDict[streamID];
    if (view == nil)
        return;
    
    [self updateContainerConstraintsForRemove:view containerView:self.playContainerView];
    
    [self.viewContainersDict removeObjectForKey:streamID];
    [self.viewIndexDict removeObjectForKey:streamID];
}

#pragma mark ZegoLiveApiDelegate
- (void)onLoginChannel:(NSString *)channel error:(uint32)err
{
    NSLog(@"%s, err: %u", __func__, err);
    if (err != 0)
    {
        //TODO: error warning
        NSString *logString = [NSString stringWithFormat:@"登录channel失败, error:%d", err];
        [self addLogString:logString];
        return;
    }
    
    NSString *logString = [NSString stringWithFormat:@"登录channel成功"];
    [self addLogString:logString];
    
    if (self.publishView == nil)
    {
        self.publishView = [self createPublishView];
        if (self.publishView)
        {
            [self setAnchorConfig:self.publishView];
            [getZegoAV_ShareInstance() startPreview];
        }
    }
    
    self.viewContainersDict[self.liveStreamID] = self.publishView;
    
    //开始直播
    bool b = [getZegoAV_ShareInstance() startPublishingWithTitle:self.liveTitle streamID:self.liveStreamID];
    assert(b);
    NSLog(@"%s, ret: %d", __func__, b);

    [self addLogString:[NSString stringWithFormat:@"开始直播，流ID:%@", self.liveStreamID]];
    
    //同时开始拉流
    if (self.playStreamList.count == 0)
        [self getStreamList];
    else
    {
        for (ZegoStreamInfo *info in self.playStreamList)
        {
            if (self.viewContainersDict[info.streamID] != nil)
                return;
            
            [self createPlayStream:info.streamID];
            
            NSString *logString = [NSString stringWithFormat:@"继续播放之前的流, 流ID:%@", info.streamID];
            [self addLogString:logString];
            
            if (self.isPublishing)
                self.tipsLabel.text = @"视频聊天中...";
        }
    }
    
    self.loginChannelSuccess = YES;
}

- (void)onPublishSucc:(NSString *)streamID channel:(NSString *)channel streamInfo:(NSDictionary *)info
{
    NSLog(@"%s, stream: %@", __func__, streamID);
    
    [self reportStreamAction:YES streamID:self.liveStreamID];
    
    if (self.playStreamList.count != 0)
        self.tipsLabel.text = @"视频聊天中...";
    
    self.isPublishing = YES;
    self.shouldInterrutped = YES;
    
    NSString *logString = [NSString stringWithFormat:@"发布直播成功,流ID:%@", streamID];
    [self addLogString:logString];
}

- (void)onPublishStop:(uint32)err stream:(NSString *)streamID channel:(NSString *)channel
{
    NSLog(@"%s, stream: %@, err: %u", __func__, streamID, err);
//    assert(streamID.length != 0);
    
    if (err == 1)
    {
        NSString *logString = [NSString stringWithFormat:@"直播结束,流ID:%@", streamID];
        [self addLogString:logString];
    }
    else
    {
        NSString *logString = [NSString stringWithFormat:@"直播结束,流ID：%@, error:%d", streamID, err];
        [self addLogString:logString];
    }
    
    [self reportStreamAction:NO streamID:self.liveStreamID];
    [self removeStreamViewContainer:self.liveStreamID];
    
    self.isPublishing = NO;
    self.tipsLabel.text = @"与对方连接中断...";
}

- (void)onPlaySucc:(NSString *)streamID channel:(NSString *)channel
{
    NSLog(@"%s, streamID:%@", __func__, streamID);
    
    NSString *logString = [NSString stringWithFormat:@"播放流成功, 流ID: %@", streamID];
    [self addLogString:logString];
}

- (void)onPlayStop:(uint32)err streamID:(NSString *)streamID channel:(NSString *)channel
{
    NSLog(@"%s, streamID:%@", __func__, streamID);
//    assert(streamID.length != 0);
    
    NSString *logString = [NSString stringWithFormat:@"播放流失败, 流ID:%@, error: %d", streamID, err];
    [self addLogString:logString];
    
    if (err == 2 && streamID.length != 0)
    {
        if (![self isRetryStreamStop:streamID] && [self.viewIndexDict objectForKey:streamID] != nil)
        {
            
            NSString *logString = [NSString stringWithFormat:NSLocalizedString(@"重新播放, 流ID:%@", nil), streamID];
            [self addLogString:logString];
            
            [self.retryStreamList addObject:streamID];
            //尝试重新play
            RemoteViewIndex index = [self.viewIndexDict[streamID] unsignedIntValue];
            [getZegoAV_ShareInstance() startPlayStream:streamID viewIndex:index];
        }
    }
}

- (BOOL)isRetryStreamStop:(NSString *)streamID
{
    for (NSString *stream in self.retryStreamList)
    {
        if ([streamID isEqualToString:stream])
            return YES;
    }
    
    return NO;
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    if ([segue.identifier isEqualToString:@"logSegueIdentifier"])
    {
        UINavigationController *navigationController = [segue destinationViewController];
        ZegoLogTableViewController *logViewController = (ZegoLogTableViewController *)[navigationController.viewControllers firstObject];
        logViewController.logArray = self.logArray;
    }
}


@end
