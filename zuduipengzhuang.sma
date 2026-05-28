#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <cstrike>


// ============================
// 插件信息
// ============================
#define PLUGIN  "Party Collision System"
#define VERSION "1.0"
#define AUTHOR  "hx"

// ============================
// 常量定义
// ============================
#define MAX_PLAYERS      32
#define PARTY_COLORS_CNT 8

// 发光参数
#define GLOW_AMT    16.0

// 步高（原版 18.0，调高可踩头）
#define CUSTOM_STEP_SIZE 40.0

// 预定义组队颜色 (R, G, B)
new const g_PartyColors[PARTY_COLORS_CNT][3] = {
    {0,   100, 255},  // 蓝
    {255, 50,  50 },  // 红
    {50,  255, 50 },  // 绿
    {255, 255, 50 },  // 黄
    {255, 100, 0  },  // 橙
    {200, 50,  255},  // 紫
    {50,  255, 255},  // 青
    {255, 150, 200}   // 粉
}

// ============================
// 全局变量
// ============================
new g_Party[MAX_PLAYERS + 1]       // 玩家组队 ID (0=无组队)
new g_PartyColor[MAX_PLAYERS + 1]  // 组队颜色索引
new g_PartyCounter = 0             // 组队 ID 计数器
new g_MaxPlayers

// CVar
new Float:g_OriginalStepSize

// ============================
// 插件加载/卸载
// ============================
public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR)

    // --- 命令 ---
    register_clcmd("say",          "fw_Say")
    register_clcmd("say_team",     "fw_Say")

    // --- 碰撞核心 Hook ---
    register_forward(FM_PlayerPreThink, "fw_PreThink")
    register_forward(FM_Touch,          "fw_Touch")

    // --- 生死状态 Hook ---
    RegisterHam(Ham_Spawn,  "player", "fw_Spawn_Post",  1)
    RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)

    // --- 关闭 CS 默认队友碰撞 ---
    set_cvar_num("mp_solid_teammates", 0)

    // --- 修改步高（实现踩头） ---
    g_OriginalStepSize = get_cvar_float("sv_stepsize")
    set_cvar_float("sv_stepsize", CUSTOM_STEP_SIZE)

    g_MaxPlayers = get_maxplayers()

    // --- 管理员命令 ---
    register_concmd("party_reset", "cmdResetAll", ADMIN_RCON,
        "重置所有玩家的组队状态")
}

public plugin_end() {
    // 还原步高
    set_cvar_float("sv_stepsize", g_OriginalStepSize)
}

// ============================
// 玩家进出
// ============================
public client_putinserver(id) {
    g_Party[id]      = 0
    g_PartyColor[id] = 0
}

public client_disconnected(id) {
    new party = g_Party[id]
    if (party > 0) {
        removePlayerFromParty(id)
    }
    g_Party[id]      = 0
    g_PartyColor[id] = 0
}

// ============================
// Ham: 生死状态
// ============================
public fw_Spawn_Post(id) {
    if (!is_user_alive(id)) return HAM_IGNORED

    // 重生后恢复组队发光
    if (g_Party[id] > 0) {
        applyGlow(id)
    }
    return HAM_IGNORED
}

public fw_Killed_Post(victim, attacker, shouldgib) {
    // 死亡后取消固体 + 发光
    set_pev(victim, pev_solid, SOLID_NOT)
    removeGlow(victim)
}

// ============================
// Say 命令处理
// ============================
public fw_Say(id) {
    new msg[192]
    read_args(msg, charsmax(msg))
    remove_quotes(msg)
    trim(msg)

    if (msg[0] != '/' && msg[0] != '!')
        return PLUGIN_CONTINUE

    new cmd[32], arg[64]
    strtok(msg, cmd, charsmax(cmd), arg, charsmax(arg), ' ')
    trim(arg)

    // /party — 创建组队
    if (equali(cmd, "/party") || equali(cmd, "!party")) {
        handleCreateParty(id)
        return PLUGIN_HANDLED
    }

    // /join <玩家名> — 加入组队
    if (equali(cmd, "/join") || equali(cmd, "!join")) {
        handleJoinParty(id, arg)
        return PLUGIN_HANDLED
    }

    // /leave — 离开组队
    if (equali(cmd, "/leave") || equali(cmd, "!leave")) {
        handleLeaveParty(id)
        return PLUGIN_HANDLED
    }

    // /plist — 查看所有组队
    if (equali(cmd, "/plist") || equali(cmd, "!plist")) {
        handlePartyList(id)
        return PLUGIN_HANDLED
    }

    // /help — 帮助
    if (equali(cmd, "/help") || equali(cmd, "!help")) {
        showHelp(id)
        return PLUGIN_HANDLED
    }

    return PLUGIN_CONTINUE
}

// ============================
// 组队命令逻辑
// ============================
handleCreateParty(id) {
    if (g_Party[id] > 0) {
        client_print(id, print_chat,
            "^x04[组队]^x01 你已在组队 #%d 中！输入 /leave 离开", g_Party[id])
        return
    }

    // 分配新组队
    g_PartyCounter++
    g_Party[id] = g_PartyCounter
    g_PartyColor[id] = (g_PartyCounter - 1) % PARTY_COLORS_CNT

    applyGlow(id)

    new name[32]
    get_user_name(id, name, charsmax(name))

    client_print(id, print_chat,
        "^x04[组队]^x01 你创建了^x03组队 #%d^x01！", g_PartyCounter)
    client_print(id, print_chat,
        "^x04[组队]^x01 其他玩家输入^x03 /join %s^x01 加入你的组队", name)
    client_print(0, print_chat,
        "^x04[组队]^x03 %s^x01 创建了新组队，输入^x03 /join %s^x01 加入",
        name, name)
}

handleJoinParty(id, const targetName[]) {
    if (g_Party[id] > 0) {
        client_print(id, print_chat,
            "^x04[组队]^x01 你已在组队中！先输入 /leave 离开")
        return
    }

    if (strlen(targetName) == 0) {
        client_print(id, print_chat,
            "^x04[组队]^x01 用法: /join <玩家名>")
        handlePartyList(id)
        return
    }

    // 查找目标玩家
    new target = findPlayerByName(targetName)
    if (!target) {
        client_print(id, print_chat,
            "^x04[组队]^x01 找不到玩家 '%s'", targetName)
        return
    }

    if (g_Party[target] == 0) {
        new tName[32]
        get_user_name(target, tName, charsmax(tName))
        client_print(id, print_chat,
            "^x04[组队]^x01 %s 不在任何组队中", tName)
        return
    }

    // 加入组队
    new party = g_Party[target]
    g_Party[id] = party
    g_PartyColor[id] = g_PartyColor[target] // 队伍同色

    applyGlow(id)

    new myName[32]
    get_user_name(id, myName, charsmax(myName))

    // 通知自己
    client_print(id, print_chat,
        "^x04[组队]^x01 你加入了^x03组队 #%d^x01！", party)

    // 通知其他队员
    for (new i = 1; i <= g_MaxPlayers; i++) {
        if (i != id && g_Party[i] == party) {
            client_print(i, print_chat,
                "^x04[组队]^x03 %s^x01 加入了组队！", myName)
        }
    }
}

handleLeaveParty(id) {
    if (g_Party[id] == 0) {
        client_print(id, print_chat,
            "^x04[组队]^x01 你不在任何组队中")
        return
    }

    removePlayerFromParty(id)
    client_print(id, print_chat,
        "^x04[组队]^x01 你已离开组队")
}

handlePartyList(id) {
    client_print(id, print_chat,
        "======== ^x04当前组队列表^x01 ========")

    new bool:found = false
    new bool:shown[MAX_PLAYERS + 1]

    for (new i = 1; i <= g_MaxPlayers; i++) {
        if (!is_user_connected(i) || g_Party[i] == 0)
            continue
        if (shown[g_Party[i]])
            continue

        shown[g_Party[i]] = true
        found = true

        new party = g_Party[i]
        new count = getPartyCount(party)
        new leaderName[32], memberList[256]
        get_user_name(i, leaderName, charsmax(leaderName))

        // 收集成员名
        formatex(memberList, charsmax(memberList), "%s", leaderName)
        for (new j = i + 1; j <= g_MaxPlayers; j++) {
            if (g_Party[j] == party) {
                new mName[32]
                get_user_name(j, mName, charsmax(mName))
                format(memberList, charsmax(memberList), "%s, %s", memberList, mName)
            }
        }

        client_print(id, print_chat,
            "^x04组队 #%d^x01 (%d人): %s | /join %s",
            party, count, memberList, leaderName)
    }

    if (!found) {
        client_print(id, print_chat,
            "^x04[组队]^x01 当前没有任何组队，输入 /party 创建")
    }
}

showHelp(id) {
    client_print(id, print_chat,
        "======== ^x04组队碰撞系统^x01 ========")
    client_print(id, print_chat,
        "/party — 创建一个新组队")
    client_print(id, print_chat,
        "/join <名字> — 加入目标玩家的组队")
    client_print(id, print_chat,
        "/leave — 离开当前组队")
    client_print(id, print_chat,
        "/plist — 查看所有组队")
    client_print(id, print_chat,
        "^x04[规则]^x01 组队内可碰撞+踩头，不同队互穿")
}

// ============================
// 组队辅助函数
// ============================
removePlayerFromParty(id) {
    new party = g_Party[id]
    g_Party[id] = 0

    removeGlow(id)

    // 检查组队是否还有人
    if (party > 0 && getPartyCount(party) == 0) {
        // 组队解散（ID不回收，不影响功能）
    }
}

getPartyCount(party) {
    new count = 0
    for (new i = 1; i <= g_MaxPlayers; i++) {
        if (g_Party[i] == party) count++
    }
    return count
}

findPlayerByName(const name[]) {
    // 精确匹配优先
    for (new i = 1; i <= g_MaxPlayers; i++) {
        if (!is_user_connected(i)) continue
        new pName[32]
        get_user_name(i, pName, charsmax(pName))
        if (equali(pName, name)) return i
    }
    // 部分匹配
    for (new i = 1; i <= g_MaxPlayers; i++) {
        if (!is_user_connected(i)) continue
        new pName[32]
        get_user_name(i, pName, charsmax(pName))
        if (containi(pName, name) != -1) return i
    }
    return 0
}

// ============================
// 发光效果
// ============================
applyGlow(id) {
    if (!is_user_alive(id)) return

    new colorIdx = g_PartyColor[id]
    set_pev(id, pev_renderfx, kRenderFxGlowShell)
    set_pev(id, pev_renderamt, GLOW_AMT)
    new Float:color[3]
    color[0] = float(g_PartyColors[colorIdx][0])
    color[1] = float(g_PartyColors[colorIdx][1])
    color[2] = float(g_PartyColors[colorIdx][2])
    set_pev(id, pev_rendercolor, color)
}

removeGlow(id) {
    if (!is_user_connected(id)) return
    set_pev(id, pev_renderfx, kRenderFxNone)
    set_pev(id, pev_renderamt, 0.0)
}

// ============================
// 核心碰撞逻辑 ⭐
// ============================
public fw_PreThink(id) {
    if (!is_user_alive(id))
        return FMRES_IGNORED

    new myParty = g_Party[id]

    // === 第一步：将所有其他玩家设为 SOLID_NOT ===
    for (new i = 1; i <= g_MaxPlayers; i++) {
        if (i != id && is_user_alive(i)) {
            set_pev(i, pev_solid, SOLID_NOT)
        }
    }

    // === 第二步：如果在组队中，将队友设为 SOLID_SLIDEBOX ===
    if (myParty > 0) {
        for (new i = 1; i <= g_MaxPlayers; i++) {
            if (i != id && g_Party[i] == myParty && is_user_alive(i)) {
                set_pev(i, pev_solid, SOLID_SLIDEBOX)
            }
        }
        set_pev(id, pev_solid, SOLID_SLIDEBOX)
    } else {
        // 不在任何组队 → 完全无碰撞
        set_pev(id, pev_solid, SOLID_NOT)
    }

    return FMRES_IGNORED
}

// ============================
// Touch 回调（碰撞事件处理）
// ============================
public fw_Touch(toucher, touched) {
    // 两个玩家碰撞时的额外处理（可选）
    if (!is_user_alive(toucher) || !is_user_alive(touched))
        return FMRES_IGNORED

    // 检测踩头：toucher 站在 touched 头上
    if (g_Party[toucher] > 0 && g_Party[toucher] == g_Party[touched]) {
        new Float:originT[3], Float:originC[3]
        pev(toucher, pev_origin, originT)
        pev(touched, pev_origin, originC)

        // 如果 toucher 的脚底高于 touched 的头顶
        // toucher 脚底: originT.z - 36
        // touched 头顶: originC.z + 36
        if ((originT[2] - 36.0) >= (originC[2] + 30.0)) {
            // 踩头事件！（可加特效/音效/加分等）
            // 这里可以扩展你的趣味逻辑
        }
    }

    return FMRES_IGNORED
}

// ============================
// 管理员命令
// ============================
public cmdResetAll(id, level, cid) {
    if (!cmd_access(id, level, cid, 1))
        return PLUGIN_HANDLED

    for (new i = 1; i <= g_MaxPlayers; i++) {
        g_Party[i] = 0
        removeGlow(i)
    }
    g_PartyCounter = 0

    client_print(id, print_chat,
        "^x04[组队]^x01 已重置所有玩家的组队状态")
    return PLUGIN_HANDLED
}
