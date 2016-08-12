package com.zego.instanttalk.ui.acivities;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.text.TextUtils;

import com.zego.biz.BizStream;
import com.zego.biz.BizUser;
import com.zego.instanttalk.R;
import com.zego.instanttalk.constants.IntentExtra;
import com.zego.instanttalk.interfaces.VideoTalkView;
import com.zego.instanttalk.presenters.BizLivePresenter;
import com.zego.instanttalk.utils.BizLiveUitl;
import com.zego.instanttalk.utils.CommonUtil;
import com.zego.instanttalk.utils.PreferenceUtil;
import com.zego.zegoavkit2.entity.ZegoUser;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

/**
 * Copyright © 2016 Zego. All rights reserved.
 * des:
 */
public class PublishActivity extends BaseLiveActivity {

    protected ArrayList<BizUser> mListToUser = new ArrayList<>();

    protected ArrayList<BizStream> mListStream = new ArrayList<>();

    protected HashMap<String, String> mMapStreamToUser = new HashMap<>();

    protected boolean mHaveLeftPublicRoom = false;

    protected long mRoomKey;

    private  int mPlayCount = 0;

    /**
     * 启动入口.
     *
     * @param activity 源activity
     */
    public static void actionStart(Activity activity, ArrayList<BizUser> listToUser, long roomKey) {
        Intent intent = new Intent(activity, PublishActivity.class);
        intent.putParcelableArrayListExtra(IntentExtra.TO_USERS, listToUser);
        intent.putExtra(IntentExtra.ROOM_KEY, roomKey);
        activity.startActivity(intent);
    }

    @Override
    protected void initExtraData(Bundle savedInstanceState) {
        super.initExtraData(savedInstanceState);
        if (savedInstanceState == null) {
            mListToUser = getIntent().getParcelableArrayListExtra(IntentExtra.TO_USERS);
            mRoomKey = getIntent().getLongExtra(IntentExtra.ROOM_KEY, 0);
            if(CommonUtil.isListEmpty(mListToUser) || mRoomKey == 0){
                finish();
            }
        }
    }

    @Override
    protected void doBusiness(Bundle savedInstanceState) {

        BizLivePresenter.getInstance().setVideoTalkView(new VideoTalkView() {
            @Override
            public void onLoginSuccessfully(long roomKey, long serverKey) {
                mChannel = BizLiveUitl.getChannel(roomKey, serverKey);

                showMainMsg(getString(R.string.login_private_room_success));
                printLog(getString(R.string.myself, getString(R.string.login_private_room_success_log, "0x" + Long.toHexString(roomKey), "0x" + Long.toHexString(serverKey))));

                ZegoUser zegoUser = new ZegoUser(PreferenceUtil.getInstance().getUserID(), PreferenceUtil.getInstance().getUserName());
                mZegoAVKit.loginChannel(zegoUser, mChannel);
                printLog(getString(R.string.myself, getString(R.string.start_to_login_channel, mChannel)));
            }

            @Override
            public void onLoginFailed(int errCode, long roomKey, long serverKey) {
                showMainMsg(getString(R.string.login_private_room_failed));
                printLog(getString(R.string.myself, getString(R.string.login_private_room_failed_log, "0x" + Long.toHexString(roomKey), "0x" + Long.toHexString(serverKey))));
            }

            @Override
            public void onLeaveRoom(int errCode) {
                mHaveLeftPublicRoom = true;

                printLog(getString(R.string.myself, getString(R.string.logout_public_room_success)));

                BizLivePresenter.getInstance().loginRoom(mRoomKey);
                showMainMsg(getString(R.string.start_to_login_private_room));
                printLog(getString(R.string.myself, getString(R.string.start_to_login_private_room_log, mRoomKey + "")));
            }

            @Override
            public void onCancelChat() {

            }

            @Override
            public void onDisconnected(int errCode, long roomKey, long serverKey) {
                showMainMsg(getString(R.string.you_have_disconnected));
                printLog(getString(R.string.myself, getString(R.string.you_have_disconnected)));
            }

            @Override
            public void onStreamCreate(String streamID, String url) {
                if (!TextUtils.isEmpty(streamID)) {
                    mPublishStreamID = streamID;

                    printLog(getString(R.string.myself, getString(R.string.create_stream_success, streamID)));
                    startPublish();
                } else {
                    printLog(getString(R.string.myself, getString(R.string.create_stream_fail, streamID)));
                }
            }

            @Override
            public void onStreamAdd(BizStream[] bizStreams) {
                if (bizStreams != null && bizStreams.length > 0) {
                    for (BizStream bizStream : bizStreams) {
                        printLog(getString(R.string.someone_created_stream, bizStream.userName, bizStream.streamID));
                        // 存储流信息
                        mMapStreamToUser.put(bizStream.streamID, bizStream.userName);

                        if (mHaveLoginedChannel) {
                            startPlay(bizStream.streamID, getFreeZegoRemoteViewIndex());
                        }else {
                            // 未登录的情况下, 先存储流信息, 等待登陆成功后再播放
                            mListStream.add(bizStream);
                        }
                    }
                }
            }

            @Override
            public void onStreamDelete(BizStream[] bizStreams) {
                if (bizStreams != null && bizStreams.length > 0) {
                    for (BizStream bizStream : bizStreams) {
                        printLog(getString(R.string.someone_deleted_stream, bizStream.userName, bizStream.streamID));
                        stopPlay(bizStream.streamID);
                    }
                }
            }

            @Override
            public void onShowRequestMsg(List<BizUser> listToUser, String magic, long roomKey, String fromUserName) {

            }

            @Override
            public void onShowRespondMsg(boolean isRespondToMyRequest, long roomKey, boolean isAgreed, String fromUserName) {
            }
        }, mHandler);


        if (savedInstanceState == null) {

            // 设置聊天状态, 此时不接受其它聊天请求
            BizLivePresenter.getInstance().setVideoChatState(true);

            // 退出大厅房间
            BizLivePresenter.getInstance().leaveRoom();
            showMainMsg(getString(R.string.start_to_logout_public_room));
            printLog(getString(R.string.myself, getString(R.string.start_to_logout_public_room)));

        }else {
            // 恢复发布 播放
            replayAndRepublish();
        }
    }


    @Override
    protected void doLiveBusinessAfterLoginChannel() {
        if (mHostHasBeenCalled) {
            mHostHasBeenCalled = false;
            // 挂断电话重新恢复
            replayAndRepublishAfterRingOff();
        } else {

            mPublishTitle = PreferenceUtil.getInstance().getUserName() + " is coming";
            mBizLiveRoom.createSreamInRoom(mPublishTitle, mPublishStreamID);
            printLog(getString(R.string.myself, getString(R.string.start_to_create_stream)));

            for (BizStream bizStream : mListStream) {
                startPlay(bizStream.streamID, getFreeZegoRemoteViewIndex());
            }
        }
    }


    @Override
    protected void hidePlayBackground() {

    }

    @Override
    protected void afterPlayingSuccess(String streamID) {
        mPlayCount++;

        showSubMsg(getString(R.string.someone_has_entered_the_room, mMapStreamToUser.get(streamID)));
        showMainMsg(getString(R.string.chatting));
    }

    @Override
    protected void afterPlayingStop(String streamID) {
        mPlayCount--;

        showSubMsg(getString(R.string.someone_has_left_the_room, mMapStreamToUser.get(streamID)));
        if(mPlayCount == 0){
            showMainMsg(getString(R.string.chat_finished));
            if(mListToUser.size() > 1){
                showSubMsg(getString(R.string.all_friends_have_left_the_room));
            }
        }
    }


    @Override
    protected void onDestroy() {
        super.onDestroy();

        // 离开房间
        BizLivePresenter.getInstance().setVideoChatState(false);

        if(mHaveLeftPublicRoom) {
            BizLivePresenter.getInstance().leaveRoom();
        }
    }
}
