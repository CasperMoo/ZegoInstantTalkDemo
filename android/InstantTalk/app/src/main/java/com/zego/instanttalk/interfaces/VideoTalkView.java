package com.zego.instanttalk.interfaces;

import com.zego.biz.BizStream;
import com.zego.biz.BizUser;

import java.util.List;

/**
 * Copyright © 2016 Zego. All rights reserved.
 * des:
 */

public interface VideoTalkView {
    void onLoginSuccessfully(long roomKey, long serverKey);
    void onLoginFailed(int errCode, long roomKey, long serverKey);
    void onLeaveRoom(int errCode);
    void onCancelChat();
    void onDisconnected(int errCode, long roomKey, long serverKey);
    void onStreamCreate(String streamID, String url);
    void onStreamAdd(BizStream[] bizStreams);
    void onStreamDelete(BizStream[] bizStreams);
    void onShowRequestMsg(List<BizUser> listToUser, String magic, long roomKey, String fromUserName);
    void onShowRespondMsg(boolean isRespondToMyRequest, long roomKey, boolean isAgreed, String fromUserName);
}
