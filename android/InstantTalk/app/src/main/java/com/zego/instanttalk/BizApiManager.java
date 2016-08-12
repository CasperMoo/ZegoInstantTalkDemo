package com.zego.instanttalk;


import android.content.Context;
import android.text.TextUtils;

import com.zego.biz.BizLiveRoom;
import com.zego.instanttalk.utils.BizLiveUitl;
import com.zego.instanttalk.utils.PreferenceUtil;
import com.zego.zegoavkit2.ZegoAVKit;


/**
 * des: zego api管理器.
 */
public class  BizApiManager {

    private static BizApiManager sInstance = null;

    private BizLiveRoom mBizLiveRoom = null;

    private BizApiManager() {
        mBizLiveRoom = new BizLiveRoom();

        String userID = PreferenceUtil.getInstance().getUserID();
        String userName = PreferenceUtil.getInstance().getUserName();

        if (TextUtils.isEmpty(userID) || TextUtils.isEmpty(userName)) {

            userID = BizLiveUitl.generateUserID();
            userName = BizLiveUitl.generateUserName(userID);

            PreferenceUtil.getInstance().setUserID(userID);
            PreferenceUtil.getInstance().setUserName(userName);
        }
    }

    public static BizApiManager getInstance() {
        if (sInstance == null) {
            synchronized (BizApiManager.class) {
                if (sInstance == null) {
                    sInstance = new BizApiManager();
                }
            }
        }
        return sInstance;
    }

    /**
     * 初始化sdk.
     */
    public void init(Context context) {

        // 设置日志level
        mBizLiveRoom.setLogLevel(context, ZegoAVKit.LOG_LEVEL_DEBUG, null);

        // 即构分配的key与id
        byte[] signKey = {
                (byte)0x18,  (byte)0x9d,  (byte)0x83,  (byte)0x5a,  (byte)0x62,  (byte)0xe8,  (byte)0xec, (byte)0xbf,
                (byte)0xc6,  (byte)0x58,  (byte)0x53,  (byte)0xeb,  (byte)0xaf,  (byte)0x26, (byte)0x5a, (byte)0xab,
                (byte)0x34,  (byte)0x48,  (byte)0x58,  (byte)0x6f,  (byte)0x7a,  (byte)0x9d,  (byte)0xd0, (byte)0x10,
                 (byte)0xee,  (byte)0xb3,  (byte)0x81,  (byte)0x78,  (byte)0x6d,  (byte)0x86,  (byte)0x18,  (byte)0x5d
        };
        long appID = 766949305;

        mBizLiveRoom.initSdk(appID, signKey, signKey.length, context);
    }


    /**
     * 释放sdk.
     */
    public void releaseSDK() {
        mBizLiveRoom.unInitSdk();
    }

    public BizLiveRoom getBizLiveRoom() {
        return mBizLiveRoom;
    }
}