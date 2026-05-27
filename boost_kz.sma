#include <amxmodx>
#include <fakemeta>

#define PLUGIN_NAME "[KZ] Co-op Basic (Ultimate)"
#define VERSION "1.7"
#define AUTHOR "AI Assistant"

#define PREFIX "[Co-op KZ]"
#define TASK_SYNC 1000

new g_Partner[33];
new g_InvitedBy[33];
new g_SwapRequestedBy[33]; 
new g_TpRequestedBy[33];   // 新增：记录谁发起了读点请求
new Float:g_CheckPoint[33][3];

new g_SyncStep[33];

public plugin_init() {
    register_plugin(PLUGIN_NAME, VERSION, AUTHOR);

    register_clcmd("say /coop", "Cmd_CoopMenu");
    register_clcmd("say /leave", "Cmd_Leave");
    register_clcmd("say /cp", "Cmd_Checkpoint");
    register_clcmd("say /tp", "Cmd_Teleport");
    register_clcmd("say /sync", "Cmd_SyncTimer");
    register_clcmd("say /swap", "Cmd_Swap"); 

    register_clcmd("say /bkzmenu", "Cmd_BkzMenu");

    register_forward(FM_ShouldCollide, "OnShouldCollide");
}

public client_disconnect(id) {
    new partner = g_Partner[id];
    if (partner) {
        g_Partner[partner] = 0;
        client_print(partner, print_chat, "%s 你的搭档离开了游戏，队伍已解散。", PREFIX);
    }
    g_Partner[id] = 0;
    g_InvitedBy[id] = 0;
    g_SwapRequestedBy[id] = 0;
    g_TpRequestedBy[id] = 0;
    
    if (task_exists(id + TASK_SYNC)) {
        remove_task(id + TASK_SYNC);
    }
}

/* =========================================
   综合菜单系统 (常驻 + 0键关闭)
========================================= */
public Cmd_BkzMenu(id) {
    if (!is_user_alive(id)) {
        client_print(id, print_chat, "%s 必须活着才能使用菜单。", PREFIX);
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("\y双人KZ 综合菜单", "BkzMenu_Handler");

    menu_additem(menu, "存点 \r(CheckPoint)", "1");
    menu_additem(menu, "读点 \r(Teleport)", "2");
    menu_additem(menu, "同步倒计时 \y(Sync)", "3");

    if (g_Partner[id]) {
        menu_additem(menu, "交换位置 \y(Swap)", "4");
        menu_additem(menu, "\d邀请搭档 (已组队)", "5");
        menu_additem(menu, "离开队伍 \r(Leave)", "6");
    } else {
        menu_additem(menu, "\d交换位置 (未组队)", "4");
        menu_additem(menu, "邀请搭档 \y(Co-op)", "5");
        menu_additem(menu, "\d离开队伍 (未组队)", "6");
    }

    // 设置第0号按键为关闭菜单
    menu_setprop(menu, MPROP_EXITNAME, "关闭菜单 \y(Close)");

    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public BkzMenu_Handler(id, menu, item) {
    // 玩家按下了 0 (MENU_EXIT)
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED; // 直接结束，菜单消失
    }

    new data[3], dummy;
    menu_item_getinfo(menu, item, dummy, data, 2, _, _, dummy);
    new choice = str_to_num(data);

    switch (choice) {
        case 1: Cmd_Checkpoint(id);
        case 2: Cmd_Teleport(id);
        case 3: Cmd_SyncTimer(id);
        case 4: Cmd_Swap(id);
        case 5: Cmd_CoopMenu(id);
        case 6: Cmd_Leave(id);
    }

    menu_destroy(menu);

    // 核心：只要没有按 0，操作完成后无条件重新打开主菜单 (常驻效果)
    Cmd_BkzMenu(id);
    
    return PLUGIN_HANDLED;
}

/* =========================================
   读点系统 (请求确认 + 速度归零防摔)
========================================= */
public Cmd_Checkpoint(id) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;

    pev(id, pev_origin, g_CheckPoint[id]);
    client_print(id, print_chat, "%s 检查点已保存。", PREFIX);
    client_cmd(id, "spk buttons/button9.wav");

    return PLUGIN_HANDLED;
}

public Cmd_Teleport(id) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;

    if (g_CheckPoint[id][0] == 0.0 && g_CheckPoint[id][1] == 0.0) {
         client_print(id, print_chat, "%s 你还没有保存过检查点！", PREFIX);
         return PLUGIN_HANDLED;
    }

    new partner = g_Partner[id];
    
    // 如果有队友，必须先征求同意
    if (partner && is_user_alive(partner)) {
        g_TpRequestedBy[partner] = id;
        ShowTpMenu(partner, id);
        client_print(id, print_chat, "%s 已向队友发送读点请求，等待同意...", PREFIX);
    } else {
        // 单人游玩，直接读点
        PerformTeleport(id);
    }

    return PLUGIN_HANDLED;
}

// 队友的同意菜单
public ShowTpMenu(target, inviter) {
    new name[32], title[64];
    get_user_name(inviter, name, 31);
    formatex(title, 63, "\y队友 \r%s \y请求读取检查点^n接受吗?", name);

    new menu = menu_create(title, "TpMenu_Handler");
    menu_additem(menu, "接受", "1");
    menu_additem(menu, "拒绝", "2");

    menu_display(target, menu, 0);
}

public TpMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[3], dummy;
    menu_item_getinfo(menu, item, dummy, data, 2, _, _, dummy);
    new choice = str_to_num(data);
    new inviter = g_TpRequestedBy[id]; 

    if (!is_user_connected(inviter) || !is_user_alive(inviter) || !is_user_alive(id)) {
        client_print(id, print_chat, "%s 读点失败：队伍状态已改变或有人死亡。", PREFIX);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    if (choice == 1) {
        // 队友同意，执行读点！
        PerformTeleport(inviter);
    } else {
        client_print(inviter, print_chat, "%s 队友拒绝了你的读点请求。", PREFIX);
    }

    g_TpRequestedBy[id] = 0;
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// 真正的核心：执行读点（包含防卡和速度归零）
public PerformTeleport(id) {
    new partner = g_Partner[id];
    new Float:safeOrigin[3];
    new bool:foundSafeSpot = false;

    // 清空速度的矢量 (0,0,0)
    new Float:zeroVec[3] = {0.0, 0.0, 0.0};

    // 空间防卡检测
    if (partner && is_user_alive(partner)) {
        safeOrigin[0] = g_CheckPoint[id][0];
        safeOrigin[1] = g_CheckPoint[id][1];
        safeOrigin[2] = g_CheckPoint[id][2];

        new Float:offsets[5][3] = {
            {0.0, 0.0, 100.0}, {40.0, 0.0, 0.0}, {-40.0, 0.0, 0.0}, {0.0, 40.0, 0.0}, {0.0, -40.0, 0.0}
        };

        new tr;
        for (new i = 0; i < 5; i++) {
            new Float:testOrigin[3];
            testOrigin[0] = safeOrigin[0] + offsets[i][0];
            testOrigin[1] = safeOrigin[1] + offsets[i][1];
            testOrigin[2] = safeOrigin[2] + offsets[i][2];

            engfunc(EngFunc_TraceHull, testOrigin, testOrigin, DONT_IGNORE_MONSTERS, HULL_HUMAN, partner, tr);

            if (!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid)) {
                safeOrigin = testOrigin; 
                foundSafeSpot = true;
                break;
            }
        }

        if (!foundSafeSpot) {
            client_print(id, print_chat, "%s 警告！当前存点处空间太小无法容纳双人，请重新找开阔地 /cp", PREFIX);
            client_cmd(id, "spk buttons/button2.wav"); 
            return; // 空间不够，中断传送
        }
    }

    // 1. 传送发起者，并清空惯性防摔
    engfunc(EngFunc_SetOrigin, id, g_CheckPoint[id]);
    set_pev(id, pev_velocity, zeroVec); 
    client_cmd(id, "spk buttons/blip1.wav");

    // 2. 传送队友，并清空惯性防摔
    if (partner && is_user_alive(partner) && foundSafeSpot) {
        engfunc(EngFunc_SetOrigin, partner, safeOrigin);
        set_pev(partner, pev_velocity, zeroVec); 
        client_print(partner, print_chat, "%s 你的搭档读点了，你已被拉回！", PREFIX);
        client_cmd(partner, "spk buttons/blip1.wav");
    }
}

/* =========================================
   交换位置系统
========================================= */
public Cmd_Swap(id) {
    new partner = g_Partner[id];
    if (!partner) {
        client_print(id, print_chat, "%s 只有在组队状态下才能交换位置！", PREFIX);
        return PLUGIN_HANDLED;
    }
    if (!is_user_alive(id) || !is_user_alive(partner)) return PLUGIN_HANDLED;

    g_SwapRequestedBy[partner] = id;
    ShowSwapMenu(partner, id);
    client_print(id, print_chat, "%s 已向队友发送互换请求，等待同意...", PREFIX);
    return PLUGIN_HANDLED;
}

public ShowSwapMenu(target, inviter) {
    new name[32], title[64];
    get_user_name(inviter, name, 31);
    formatex(title, 63, "\y队友 \r%s \y请求互换位置^n接受吗?", name);
    new menu = menu_create(title, "SwapMenu_Handler");
    menu_additem(menu, "接受", "1");
    menu_additem(menu, "拒绝", "2");
    menu_display(target, menu, 0);
}

public SwapMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    new data[3], dummy;
    menu_item_getinfo(menu, item, dummy, data, 2, _, _, dummy);
    new choice = str_to_num(data);
    new inviter = g_SwapRequestedBy[id]; 

    if (!is_user_connected(inviter) || !is_user_alive(inviter) || !is_user_alive(id)) {
        menu_destroy(menu); return PLUGIN_HANDLED;
    }

    if (choice == 1) {
        new Float:originA[3], Float:originB[3];
        pev(id, pev_origin, originA); 
        pev(inviter, pev_origin, originB); 
        engfunc(EngFunc_SetOrigin, id, originB);
        engfunc(EngFunc_SetOrigin, inviter, originA);

        new Float:zeroVec[3] = {0.0, 0.0, 0.0};
        set_pev(id, pev_velocity, zeroVec);
        set_pev(inviter, pev_velocity, zeroVec);

        client_print(id, print_chat, "%s 位置交换成功！", PREFIX);
        client_print(inviter, print_chat, "%s 对方已同意，位置交换成功！", PREFIX);
        client_cmd(id, "spk buttons/blip2.wav");
        client_cmd(inviter, "spk buttons/blip2.wav");
    } else {
        client_print(inviter, print_chat, "%s 队友拒绝了你的交换请求。", PREFIX);
    }
    g_SwapRequestedBy[id] = 0;
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

/* =========================================
   同步倒计时系统
========================================= */
public Cmd_SyncTimer(id) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;
    if (task_exists(id + TASK_SYNC)) {
        client_print(id, print_chat, "%s 倒计时正在进行中！", PREFIX);
        return PLUGIN_HANDLED;
    }
    g_SyncStep[id] = 3;
    ExecuteSyncTick(id); 
    set_task(0.5, "Task_SyncTick", id + TASK_SYNC, _, _, "a", 3);
    return PLUGIN_HANDLED;
}

public Task_SyncTick(taskid) {
    new id = taskid - TASK_SYNC;
    g_SyncStep[id]--;
    ExecuteSyncTick(id);
}

public ExecuteSyncTick(id) {
    new partner = g_Partner[id];
    new step = g_SyncStep[id];
    new text[16], r, g, b, sound[64];

    if (step > 0) {
        formatex(text, charsmax(text), "%d", step);
        r = 255; g = 150; b = 0; 
        copy(sound, charsmax(sound), "buttons/blip1.wav"); 
    } else {
        formatex(text, charsmax(text), "GO!");
        r = 0; g = 255; b = 0; 
        copy(sound, charsmax(sound), "buttons/bell1.wav"); 
    }
    ShowSyncHudAndSound(id, text, r, g, b, sound);
    if (partner && is_user_connected(partner)) ShowSyncHudAndSound(partner, text, r, g, b, sound);
}

stock ShowSyncHudAndSound(id, text[], r, g, b, sound[]) {
    set_hudmessage(r, g, b, -1.0, 0.35, 0, 0.0, 0.5, 0.01, 0.01, 4);
    show_hudmessage(id, text);
    client_cmd(id, "spk %s", sound);
}

/* =========================================
   组队系统基础模块 & 碰撞模块 (精简合并显示)
========================================= */
public OnShouldCollide(ent1, ent2) {
    if (ent1 >= 1 && ent1 <= 32 && ent2 >= 1 && ent2 <= 32) {
        if (is_user_alive(ent1) && is_user_alive(ent2)) {
            if (g_Partner[ent1] == ent2) return FMRES_IGNORED;
            forward_return(FMV_CELL, 0);
            return FMRES_SUPERCEDE;
        }
    }
    return FMRES_IGNORED;
}

public Cmd_CoopMenu(id) {
    if (g_Partner[id]) { client_print(id, print_chat, "%s 你已经有搭档了！", PREFIX); return PLUGIN_HANDLED; }
    new menu = menu_create("\y选择一名玩家成为搭档:", "CoopMenu_Handler");
    new players[32], pnum, player, name[32], info[3];
    get_players(players, pnum, "a");
    for (new i = 0; i < pnum; i++) {
        player = players[i];
        if (player == id || g_Partner[player]) continue;
        get_user_name(player, name, 31);
        num_to_str(player, info, 2);
        menu_additem(menu, name, info);
    }
    if (menu_items(menu) == 0) { client_print(id, print_chat, "%s 当前没有可邀请的玩家。", PREFIX); menu_destroy(menu); return PLUGIN_HANDLED; }
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public CoopMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[3], dummy;
    menu_item_getinfo(menu, item, dummy, data, 2, _, _, dummy);
    new target = str_to_num(data);
    if (is_user_connected(target) && !g_Partner[target]) {
        g_InvitedBy[target] = id;
        ShowInviteMenu(target, id);
        new targetName[32]; get_user_name(target, targetName, 31);
        client_print(id, print_chat, "%s 已向 %s 发送组队邀请。", PREFIX, targetName);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public ShowInviteMenu(target, inviter) {
    new name[32], title[64]; get_user_name(inviter, name, 31);
    formatex(title, 63, "\y玩家 \r%s \y邀请你双人KZ^n接受吗?", name);
    new menu = menu_create(title, "InviteMenu_Handler");
    menu_additem(menu, "接受", "1");
    menu_additem(menu, "拒绝", "2");
    menu_display(target, menu, 0);
}

public InviteMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) { menu_destroy(menu); return PLUGIN_HANDLED; }
    new data[3], dummy;
    menu_item_getinfo(menu, item, dummy, data, 2, _, _, dummy);
    new choice = str_to_num(data);
    new inviter = g_InvitedBy[id];
    if (!is_user_connected(inviter)) return PLUGIN_HANDLED;
    if (choice == 1) {
        g_Partner[id] = inviter; g_Partner[inviter] = id;
        new name1[32], name2[32]; get_user_name(id, name1, 31); get_user_name(inviter, name2, 31);
        client_print(0, print_chat, "%s %s 和 %s 组成了双人KZ队伍！", PREFIX, name1, name2);
    } else {
        client_print(inviter, print_chat, "%s 对方拒绝了你的邀请。", PREFIX);
    }
    g_InvitedBy[id] = 0;
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public Cmd_Leave(id) {
    new partner = g_Partner[id];
    if (partner) {
        g_Partner[partner] = 0; g_Partner[id] = 0;
        client_print(id, print_chat, "%s 你离开了队伍。", PREFIX);
        client_print(partner, print_chat, "%s 你的搭档解散了队伍。", PREFIX);
    } else {
        client_print(id, print_chat, "%s 你当前不在任何队伍中。", PREFIX);
    }
    return PLUGIN_HANDLED;
}