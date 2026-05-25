#include <amxmodx>
#include <fakemeta>

#define PLUGIN_NAME "[KZ] Co-op Basic (SiMen Compatible)"
#define VERSION "1.3"
#define AUTHOR "AI Assistant"

#define PREFIX "[Co-op KZ]"

new g_Partner[33];
new g_InvitedBy[33];
new Float:g_CheckPoint[33][3];

public plugin_init() {
    register_plugin(PLUGIN_NAME, VERSION, AUTHOR);

    register_clcmd("say /coop", "Cmd_CoopMenu");
    register_clcmd("say /leave", "Cmd_Leave");
    register_clcmd("say /cp", "Cmd_Checkpoint");
    register_clcmd("say /tp", "Cmd_Teleport");

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
   组队菜单系统
========================================= */
public Cmd_CoopMenu(id) {
    if (g_Partner[id]) {
        client_print(id, print_chat, "%s 你已经有搭档了！输入 /leave 退出当前队伍。", PREFIX);
        return PLUGIN_HANDLED;
    }

    new menu = menu_create("\y选择一名玩家成为搭档:", "CoopMenu_Handler");
    new players[32], pnum, player;
    new name[32], info[3];

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
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

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
    if (item == MENU_EXIT) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

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
   羁绊传送系统：一人传送，拉取队友
========================================= */
public Cmd_Checkpoint(id) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;
    
    pev(id, pev_origin, g_CheckPoint[id]); 
    client_print(id, print_chat, "%s 检查点已保存。输入 /tp 返回。", PREFIX);
    client_cmd(id, "spk buttons/button9.wav");
    
    return PLUGIN_HANDLED;
}

public Cmd_Teleport(id) {
    if (!is_user_alive(id)) return PLUGIN_HANDLED;
    
    if (g_CheckPoint[id][0] == 0.0 && g_CheckPoint[id][1] == 0.0) {
         client_print(id, print_chat, "%s 你还没有保存过检查点！请先输入 /cp", PREFIX);
         return PLUGIN_HANDLED;
    }

    engfunc(EngFunc_SetOrigin, id, g_CheckPoint[id]);
    client_cmd(id, "spk buttons/blip1.wav");

    new partner = g_Partner[id];
    if (partner && is_user_alive(partner)) {
        new Float:partnerOrigin[3];
        partnerOrigin[0] = g_CheckPoint[id][0];
        partnerOrigin[1] = g_CheckPoint[id][1];
        partnerOrigin[2] = g_CheckPoint[id][2] + 100.0; 
        
        engfunc(EngFunc_SetOrigin, partner, partnerOrigin);
        client_print(partner, print_chat, "%s 你的搭档传送了，你被强制拉回！", PREFIX);
        client_cmd(partner, "spk buttons/blip1.wav");
    }

    return PLUGIN_HANDLED;
}