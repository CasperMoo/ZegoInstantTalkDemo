package com.zego.instanttalk.presenters;

import android.os.Handler;
import android.text.TextUtils;

import com.google.gson.Gson;
import com.google.gson.internal.LinkedTreeMap;
import com.google.gson.reflect.TypeToken;
import com.zego.biz.BizLiveRoom;
import com.zego.biz.BizStream;
import com.zego.biz.BizUser;
import com.zego.biz.callback.BizLiveCallback;
import com.zego.instanttalk.BizApiManager;
import com.zego.instanttalk.interfaces.VideoTalkView;
import com.zego.instanttalk.utils.BizLiveUitl;
import com.zego.instanttalk.utils.PreferenceUtil;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Copyright © 2016 Zego. All rights reserved.
 * des:
 */

public class BizLivePresenter {

    public static long USELESS_ROOM_KEY = -1;

    public static long COMMON_ROOM_KEY = 1;

    private static BizLivePresenter sInstance;

    private BizLiveRoom mBizLiveRoom;

    private VideoTalkView mVideoTalkView;

    private boolean mHasLogined = false;

    private ExecutorService mExecutorService;

    private Handler mUIHandler;

    private long mMyRoomKey = USELESS_ROOM_KEY;

    private String mMyMagic;

    private boolean mIsVideoChatting = false;

    private BizLivePresenter() {
        mBizLiveRoom = BizApiManager.getInstance().getBizLiveRoom();
        mExecutorService = Executors.newFixedThreadPool(4);
        mMyMagic = PreferenceUtil.getInstance().getUserID();
        initCallback();
    }

    public static BizLivePresenter getInstance() {
        if (sInstance == null) {
            synchronized (BizLivePresenter.class) {
                if (sInstance == null) {
                    sInstance = new BizLivePresenter();
                }
            }
        }
        return sInstance;
    }

    private void initCallback() {
        mBizLiveRoom.setBizLiveCallback(new BizLiveCallback() {
            @Override
            public void onLoginRoom(int errCode, long roomKey, long serverKey) {
                if (errCode == 0) {
                    mMyRoomKey = roomKey;
                    mHasLogined = true;
                    if (mVideoTalkView != null) {
                        mVideoTalkView.onLoginSuccessfully(roomKey, serverKey);
                    }
                } else {
                    mMyRoomKey = USELESS_ROOM_KEY;
                    mHasLogined = false;
                    if (mVideoTalkView != null) {
                        mVideoTalkView.onLoginFailed(errCode, roomKey, serverKey);
                    }
                }
            }

            @Override
            public void onLeaveRoom(int errCode) {
                mMyRoomKey = USELESS_ROOM_KEY;
                mHasLogined = false;
                if (mVideoTalkView != null) {
                    mVideoTalkView.onLeaveRoom(errCode);
                }
            }

            @Override
            public void onDisconnected(int errCode, long roomKey, long serverKey) {
                if(mVideoTalkView != null){
                    mVideoTalkView.onDisconnected(errCode, roomKey, serverKey);
                }
            }

            @Override
            public void onKickOut(int i, String s) {

            }

            @Override
            public void onStreamCreate(String streamID, String url) {
                if (mVideoTalkView != null) {
                    mVideoTalkView.onStreamCreate(streamID, url);
                }
            }

            @Override
            public void onStreamAdd(BizStream[] bizStreams) {
                if (mVideoTalkView != null) {
                    mVideoTalkView.onStreamAdd(bizStreams);
                }
            }

            @Override
            public void onStreamDelete(BizStream[] bizStreams) {
                if (mVideoTalkView != null) {
                    mVideoTalkView.onStreamDelete(bizStreams);
                }
            }

            @Override
            public void onReceiveMsg(int msgType, String data) {
                handleMsg(msgType, data);
            }

            @Override
            public void onRoomUserUpdate(final BizUser[] bizUsers, final int flag) {
                mExecutorService.execute(new Runnable() {
                    @Override
                    public void run() {
                        UserListPresenter.getInstance().updateUserList(bizUsers, flag);
                    }
                });
            }

            @Override
            public void onRoomUserCountUpdate(int i) {

            }
        });
    }

    public void loginCommonRoom() {
        if (!mHasLogined) {
            mBizLiveRoom.getInCustomRoom(COMMON_ROOM_KEY, PreferenceUtil.getInstance().getUserID(),
                    PreferenceUtil.getInstance().getUserName());
        }
    }

    public void loginRoom(long roomKey) {
        if (!mHasLogined) {
            mBizLiveRoom.getInCustomRoom(roomKey, PreferenceUtil.getInstance().getUserID(),
                    PreferenceUtil.getInstance().getUserName());
        }
    }

    public void setVideoChatState(boolean isVideoChatting) {
        mIsVideoChatting = isVideoChatting;
    }

    public void leaveRoom() {
        if(mHasLogined){
            mBizLiveRoom.leaveRoom();
        }
    }

    public void setVideoTalkView(VideoTalkView videoTalkView, Handler handler) {
        mUIHandler = handler;
        mVideoTalkView = videoTalkView;
    }

    private void handleMsg(final int msgType, final String data) {
        mExecutorService.execute(new Runnable() {
            @Override
            public void run() {
                if (msgType != 1 || TextUtils.isEmpty(data)) {
                    return;
                }

                final HashMap<String, Object> mapData = (new Gson()).fromJson(data, new TypeToken<HashMap<String, Object>>() {
                }.getType());

                if (mapData == null) {
                    return;
                }

                // 获取目的用户列表
                List<BizUser> listToUser = getToUserList((List<Object>) mapData.get(BizLiveUitl.KEY_TALK_TO_USER));

                // 判断是否是发给自己的消息

                if (!isMyMsg(listToUser)) {
                    return;
                }

                // 获取消息来源用户
                LinkedTreeMap<String, String> mapFromUser = (LinkedTreeMap<String, String>) mapData.get(BizLiveUitl.KEY_TALK_FROM_USER);
                if (mapFromUser == null) {
                    return;
                }
                BizUser fromUser = new BizUser();
                fromUser.userID = mapFromUser.get(BizLiveUitl.KEY_TALK_USER_ID);
                fromUser.userName = mapFromUser.get(BizLiveUitl.KEY_TALK_USER_NAME);

                //移除自己
                String myUserID = PreferenceUtil.getInstance().getUserID();
                for (BizUser toUser : listToUser) {
                    if (myUserID.equals(toUser.userID)) {
                        listToUser.remove(toUser);
                        break;
                    }
                }
                // 将消息来源用户加入目的用户列表,用于稍候发送消息
                listToUser.add(fromUser);

                // 分发消息
                String command = (String) mapData.get(BizLiveUitl.KEY_TALK_COMMAND);

                if (mapFromUser != null) {
                    if (BizLiveUitl.KEY_VIDEO_REQUEST_COMMAND.equals(command)) {

                        receiveVideoRequestMsg(mapData, listToUser, fromUser);

                    } else if (BizLiveUitl.KEY_VIDEO_RESPOND_COMMAND.equals(command)) {

                        receiveVideoRespondMsg(mapData, listToUser, fromUser);

                    } else if (BizLiveUitl.KEY_MESSAGE_COMMAND.equals(command)) {

                        TextMessagePresenter.getInstance().receiveMsg(mapData, listToUser, fromUser);

                    } else if (BizLiveUitl.KEY_VIDEO_CANCEL_COMMAND.equals(command)) {
                        if(mVideoTalkView != null && mUIHandler != null){
                            mUIHandler.post(new Runnable() {
                                @Override
                                public void run() {
                                    mVideoTalkView.onCancelChat();
                                }
                            });
                        }
                    }
                }
            }
        });
    }

    private void receiveVideoRequestMsg(HashMap<String, Object> mapData, final List<BizUser> listToUser, final BizUser fromUser) {

        final String magic = (String) mapData.get(BizLiveUitl.KEY_VIDEO_MAGIC);
        final long roomKey = (long) ((double) mapData.get(BizLiveUitl.KEY_VIDEO_ROOMID));

        // 用户正在视频中，此时拒绝所有其他请求
        if (mIsVideoChatting) {
            respondVideoChat(listToUser, magic, false, roomKey);
            return;
        }

        if (mVideoTalkView != null && mUIHandler != null) {
            mUIHandler.post(new Runnable() {
                @Override
                public void run() {
                    mVideoTalkView.onShowRequestMsg(listToUser, magic, roomKey, fromUser.userName);
                }
            });
        }
    }

    private void receiveVideoRespondMsg(HashMap<String, Object> mapData, final List<BizUser> listToUser, final BizUser fromUser) {

        final String magic = (String) mapData.get(BizLiveUitl.KEY_VIDEO_MAGIC);
        final long roomKey = (long) ((double) mapData.get(BizLiveUitl.KEY_VIDEO_ROOMID));

        final boolean isRespondToMyRequest = mMyMagic.equals(magic);

        boolean isAgree = true;
        String content = (String) mapData.get(BizLiveUitl.KEY_TALK_CONTENT);
        if (!BizLiveUitl.KEY_VIDEO_AGREE.equals(content)) {
            isAgree = false;
        }

        final boolean isAgreeTemp = isAgree;
        if (mVideoTalkView != null && mUIHandler != null) {
            mUIHandler.post(new Runnable() {
                @Override
                public void run() {
                    mVideoTalkView.onShowRespondMsg(isRespondToMyRequest, roomKey, isAgreeTemp, fromUser.userName);
                }
            });
        }
    }

    /**
     * 获取目的用户列表.
     *
     * @param listObject
     * @return
     */
    private List<BizUser> getToUserList(List<Object> listObject) {
        List<BizUser> listToUser = new ArrayList<>();

        if (listObject != null) {
            for (Object object : listObject) {

                LinkedTreeMap<String, String> mapUser = (LinkedTreeMap<String, String>) object;
                if (mapUser != null) {
                    BizUser bizUser = new BizUser();
                    bizUser.userID = mapUser.get(BizLiveUitl.KEY_TALK_USER_ID);
                    bizUser.userName = mapUser.get(BizLiveUitl.KEY_TALK_USER_NAME);

                    listToUser.add(bizUser);
                }
            }
        }

        return listToUser;
    }

    /**
     * 判断本条消息是否发给自己.
     *
     * @param listToUser
     * @return
     */
    private boolean isMyMsg(List<BizUser> listToUser) {

        boolean isMyMsg = false;
        String myUserID = PreferenceUtil.getInstance().getUserID();

        for (BizUser bizUser : listToUser) {
            if (myUserID.equals(bizUser.userID)) {
                isMyMsg = true;
                break;
            }
        }

        return isMyMsg;
    }

    /**
     * 请求视频聊天.
     *
     * @param listToUsers
     * @return
     */
    public void requestVideoChat(List<BizUser> listToUsers) {

        long below = System.currentTimeMillis() & 0xFFFF;
        long high = (Long.valueOf(PreferenceUtil.getInstance().getUserID()) << 16) & 0xFFFF0000L;
        mMyRoomKey = (high | below);
        if (mMyRoomKey <= COMMON_ROOM_KEY) {
            mMyRoomKey = (long) Math.random();
        }

        BizLiveUitl.requestVideoChat(listToUsers, mMyMagic, mMyRoomKey);
    }


    public void respondVideoChat(List<BizUser> listToUsers, String magic, boolean isAgreed, long roomKey){
        BizLiveUitl.respondVideoChat(listToUsers, magic, isAgreed, roomKey);
    }

    public void cancelVideoChat(List<BizUser> listToUsers){
        BizLiveUitl.cancelVideoChat(listToUsers, mMyMagic, false, 0);
    }
}
