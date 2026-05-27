#include <amxmodx>
#include <fakemeta>

#define PLUGIN_NAME "[KZ] Co-op Basic (Advanced Pro)"
#define VERSION "1.1"
#define AUTHOR "AI Assistant"

#define PREFIX "[Co-op KZ]"

// 用于倒计时任务的唯一ID偏移量
#define TASK_SYNC 1000

new g_Partner[33];
new g_InvitedBy[33];
new Float:g_CheckPoint[33][3];

// 记录倒计时的进度
new g_SyncStep[33];

public plugin_init() {
    register_plugin(PLUGIN_NAME, VERSION, AUTHOR);

    // 独立指令保留，方便绑定按键
    register_clcmd("say /coop", "Cmd_CoopMenu");
    register_clcmd("say /leave", "Cmd_Leave");
    register_clcmd("say /cp", "Cmd_Checkpoint");
    register_clcmd("say /tp", "Cmd_Teleport");
    register_clcmd("say /sync", "Cmd_SyncTimer"); // 新增：直接触发倒计时

    // 综合菜单指令
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

    // 如果玩家退出，清理他可能正在运行的倒计时
    if (task_exists(id + TASK_SYNC)) {
        remove_task(id + TASK_SYNC);
    }
}

/* =========================================
   综合菜单系统 (/bkzmenu)
========================================= */
public Cmd_BkzMenu(id) {
    if (!is_user_alive(id)) {
        client_print(id, print_chat, "%s 必须活着才能使用菜单。", PREFIX);
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("\y双人KZ 综合菜单", "BkzMenu_Handler");

    menu_additem(menu, "存点 \r(CheckPoint)", "1");
    menu_additem(menu, "读点 \r(Teleport)", "2");

    if (g_Partner[id]) {
        menu_additem(menu, "\d邀请搭档 (已组队)", "3");
        menu_additem(menu, "离开队伍 \y(Leave)", "4");
        menu_additem(menu, "同步倒计时 \y(Sync)", "5"); // 新增按键 5
    } else {
        menu_additem(menu, "邀请搭档 \y(Co-op)", "3");
        menu_additem(menu, "\d离开队伍 (未组队)", "4");
        menu_additem(menu, "同步倒计时 \y(单人可用)", "5");
    }

    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public BkzMenu_Handler(id, menu, item) {
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new data[3], dummy;
    menu_item_getinfo(menu, item, dummy, data, 2, _, _, dummy);
    new choice = str_to_num(data);

    switch (choice) {
        case 1: Cmd_Checkpoint(id);
        case 2: Cmd_Teleport(id);
        case 3: Cmd_CoopMenu(id);
        case 4: Cmd_Leave(id);
        case 5: Cmd_SyncTimer(id); // 触发倒计时
    }

    menu_destroy(menu);

    // 存点、组队、离队后重新打开菜单。读点和倒计时不需要重开，以免挡视野
    if (choice == 1 || choice == 2 || choice == 3 || choice == 4 || choice == 5) {
        Cmd_BkzMenu(id);
    }

    return PLUGIN_HANDLED;
}

/* =========================================
   同步倒计时系统 (3, 2, 1, GO!)
========================================= */
public Cmd_SyncTimer(id) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;

    // 防止玩家狂按倒计时导致重叠
    if (task_exists(id + TASK_SYNC)) {
        client_print(id, print_chat, "%s 倒计时正在进行中！", PREFIX);
        return PLUGIN_HANDLED;
    }

    g_SyncStep[id] = 3; // 设置初始数字
    ExecuteSyncTick(id); // 立即执行第一下 (播报 3)

    // 创建一个间隔 0.5 秒，重复 3 次的任务 (分别播报 2, 1, GO!)
    set_task(0.5, "Task_SyncTick", id + TASK_SYNC, _, _, "a", 3);

    return PLUGIN_HANDLED;
}

public Task_SyncTick(taskid) {
    new id = taskid - TASK_SYNC;
    g_SyncStep[id]--; // 数字递减
    ExecuteSyncTick(id);
}

public ExecuteSyncTick(id) {
    new partner = g_Partner[id];
    new step = g_SyncStep[id];

    new text[16];
    new r, g, b;
    new sound[64];

    if (step > 0) {
        // 3, 2, 1 的状态
        formatex(text, charsmax(text), "%d", step);
        r = 255; g = 150; b = 0; // 橙色文字
        copy(sound, charsmax(sound), "buttons/blip1.wav"); // 滴滴声
    } else {
        // GO! 的状态
        formatex(text, charsmax(text), "GO!");
        r = 0; g = 255; b = 0; // 绿色文字
        copy(sound, charsmax(sound), "buttons/bell1.wav"); // 嘟嘟声(铃声)
    }

    // 给自己发 HUD 和声音
    ShowSyncHudAndSound(id, text, r, g, b, sound);

    // 如果有队友，也给队友发一份完全一样的 HUD 和声音
    if (partner && is_user_connected(partner)) {
        ShowSyncHudAndSound(partner, text, r, g, b, sound);
    }
}

// 封装一个 HUD 显示和播放声音的函数
stock ShowSyncHudAndSound(id, text[], r, g, b, sound[]) {
    // 设置HUD属性：居中靠上 (Y=0.35)，显示时间0.5秒
    set_hudmessage(r, g, b, -1.0, 0.35, 0, 0.0, 0.5, 0.01, 0.01, 4);
    show_hudmessage(id, text);
    client_cmd(id, "spk %s", sound);
}

/* =========================================
   核心机制：队伍内允许踩头，队伍外互相穿透
========================================= */
public OnShouldCollide(ent1, ent2) {
    if (ent1 >= 1 && ent1 <= 32 && ent2 >= 1 && ent2 <= 32) {
        if (is_user_alive(ent1) && is_user_alive(ent2)) {
            if (g_Partner[ent1] == ent2) {
                return FMRES_IGNORED;
            }
            forward_return(FMV_CELL, 0);
            return FMRES_SUPERCEDE;
        }
    }
    return FMRES_IGNORED;
}

/* =========================================
   组队菜单子系统 (代码保持不变)
========================================= */
public Cmd_CoopMenu(id) {
    if (g_Partner[id]) {
        client_print(id, print_chat, "%s 你已经有搭档了！", PREFIX);
        return PLUGIN_HANDLED;
    }
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
    if (menu_items(menu) == 0) {
        client_print(id, print_chat, "%s 当前没有可邀请的玩家。", PREFIX);
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
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
        new targetName[32];
        get_user_name(target, targetName, 31);
        client_print(id, print_chat, "%s 已向 %s 发送组队邀请。", PREFIX, targetName);
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

public ShowInviteMenu(target, inviter) {
    new name[32], title[64];
    get_user_name(inviter, name, 31);
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
        g_Partner[id] = inviter;
        g_Partner[inviter] = id;
        new name1[32], name2[32];
        get_user_name(id, name1, 31);
        get_user_name(inviter, name2, 31);
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
        g_Partner[partner] = 0;
        g_Partner[id] = 0;
        client_print(id, print_chat, "%s 你离开了队伍。", PREFIX);
        client_print(partner, print_chat, "%s 你的搭档解散了队伍。", PREFIX);
    } else {
        client_print(id, print_chat, "%s 你当前不在任何队伍中。", PREFIX);
    }
    return PLUGIN_HANDLED;
}

/* =========================================
   安全传送系统 (先探测空间，再执行拉取)
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
    new Float:safeOrigin[3];
    new bool:foundSafeSpot = false;

    // 【新增逻辑】如果处于组队状态，在读点前，先探测空间！
    if (partner && is_user_alive(partner)) {
        safeOrigin[0] = g_CheckPoint[id][0];
        safeOrigin[1] = g_CheckPoint[id][1];
        safeOrigin[2] = g_CheckPoint[id][2];

        // 尝试偏移位置：1.头顶(+100) 2.右边(+40) 3.左边(-40) 4.前面(+40) 5.后面(-40)
        new Float:offsets[5][3] = {
            {0.0, 0.0, 100.0},
            {40.0, 0.0, 0.0},
            {-40.0, 0.0, 0.0},
            {0.0, 40.0, 0.0},
            {0.0, -40.0, 0.0}
        };

        new tr;
        for (new i = 0; i < 5; i++) {
            new Float:testOrigin[3];
            testOrigin[0] = safeOrigin[0] + offsets[i][0];
            testOrigin[1] = safeOrigin[1] + offsets[i][1];
            testOrigin[2] = safeOrigin[2] + offsets[i][2];

            // 划重点：检测人物体积大小的空间是否碰壁
            engfunc(EngFunc_TraceHull, testOrigin, testOrigin, DONT_IGNORE_MONSTERS, HULL_HUMAN, partner, tr);

            if (!get_tr2(tr, TR_StartSolid) && !get_tr2(tr, TR_AllSolid)) {
                safeOrigin = testOrigin; // 这个位置安全！
                foundSafeSpot = true;
                break;
            }
        }

        // 致命阻断：如果 5 个位置都卡墙，拒绝传送！
        if (!foundSafeSpot) {
            client_print(id, print_chat, "%s 警告！当前存点处空间太小无法容纳双人，请调整位置重新 /cp", PREFIX);
            client_cmd(id, "spk buttons/button2.wav"); // 播放错误音效
            return PLUGIN_HANDLED;
        }
    }

    // 空间检测通过（或者只是单人玩），执行发起者的传送
    engfunc(EngFunc_SetOrigin, id, g_CheckPoint[id]);
    client_cmd(id, "spk buttons/blip1.wav");

    // 将队友传送到刚才找到的绝对安全坐标
    if (partner && is_user_alive(partner) && foundSafeSpot) {
        engfunc(EngFunc_SetOrigin, partner, safeOrigin);
        client_print(partner, print_chat, "%s 你的搭档读点了，你已被拉回！", PREFIX);
        client_cmd(partner, "spk buttons/blip1.wav");
    }

    return PLUGIN_HANDLED;
}
