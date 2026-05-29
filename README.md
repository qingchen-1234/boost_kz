这是一份为你量身定制的 `README.md` 文件。它不仅详细记录了插件的功能和安装方法，还回顾了我们这几天一步步排坑、优化的开发历程，非常适合作为你这个项目的“毕业证书”和代码存档说明！

你可以直接复制下面的内容，保存为 `README.md` 放在你的项目文件夹中。

---

# 🌟 CS 1.6 Co-op KZ (双人跳跃插件) 🌟

![Version](https://img.shields.io/badge/Version-1.9_Final-brightgreen)
![Compatibility](https://img.shields.io/badge/Engine-AMXX_1.8%2B%20%7C%20SiMen-blue)
![Module](https://img.shields.io/badge/Module-Fakemeta-orange)

这是一个为 **Counter-Strike 1.6** 开发的专用于 KZ (Kreedz) 模式的双人合作插件。
它将原本孤独的单人极速跳跃，变成了需要两人紧密配合、互相“搭人梯 (Boost)”的战术合作游戏。本插件深度兼容经典的 **SiMen (死门) KZ 服务端** 以及霸道的 **KZ_Rush** 管理系统。

---

## 📖 开发历程 (Development Journey)
本插件经历了多次迭代，从最初的一个简单构想，逐步打磨成一个贴合玩家实战体验的成熟作品：
1. **基础成型**：实现了基础的菜单邀请组队与坐标传送机制。
2. **环境适配**：从依赖现代 `ReAPI` 降级重构为原生 `Fakemeta`，完美兼容古老的 AMXX 1.8.x 编译器与 SiMen 整合包。
3. **防卡与防摔 (痛点解决)**：引入 `TraceHull` 空间检测，防止读点卡墙；引入 `pev_velocity` 速度清零，彻底解决高空读点瞬间摔死的惨剧。
4. **实战功能进化**：加入了“交换位置 (Swap)”拯救搭人梯失误，以及“同步倒计时 (Sync)”解决起跳默契问题。
5. **最终冲突解决**：重写底层碰撞逻辑强制接管引擎，更改指令前缀为 `/b`，完美解决了与 `kz_rush` 插件系统在物理穿透和指令上的冲突。

---

## ✨ 核心功能 (Core Features)

*   👥 **独立队伍羁绊系统**
    *   只有结成搭档的两名玩家之间拥有物理碰撞（可以踩在队友头上）。
    *   碰到服务器里的其他陌生玩家会自动穿透，互不干扰。
*   💾 **双人羁绊存读点 (Safe Teleport)**
    *   **读取确认**：读点或交换位置需要队友按 `1` 同意，防止误拉队友。
    *   **防卡死探测**：读点前系统会自动扫描目标地点的 上、前、后、左、右 空间，如果极其狭窄则拒绝传送。
    *   **惯性清零**：读点落地瞬间速度归零，半空读点不再摔死。
*   🔄 **无缝交换位置 (Position Swap)**
    *   搭人梯失败？不需要跳下来重搭！申请交换位置后，两人瞬间互换坐标，无缝衔接继续跳跃。
*   ⏱️ **HUD 同步倒计时 (Sync Timer)**
    *   按下指令后，双方屏幕中央会同步闪烁 `3 -> 2 -> 1 -> GO!` 并伴随音效，完美解决“321一起跳”的默契问题。
*   🖥️ **极简常驻菜单 (Smart Menu)**
    *   输入 `/bkzmenu` 打开主菜单，操作功能后菜单自动弹回，保持常驻。按下 `0` 键随时关闭，防止跳跃时误触。

---

## ⚙️ 安装与配置 (Installation)

### 1. 编译与安装
1. 将 `boost_kz.sma` 放入 `cstrike/addons/amxmodx/scripting/`。
2. 运行 `compile.exe`，在 `compiled` 文件夹获取 `boost_kz.amxx`。
3. 将 `boost_kz.amxx` 放入 `cstrike/addons/amxmodx/plugins/` 文件夹。

### 2. 插件注册 (⚠️ 极其重要)
为了防止其他插件干扰双人碰撞，**必须给予此插件最高优先级**！
打开 `cstrike/addons/amxmodx/configs/plugins.ini`，将插件名写在**第一行**：
```ini
; 在文件最顶端添加：
boost_kz.amxx
```

### 3. KZ_Rush 兼容性设置 (必须操作)
如果你服务器安装了 `kz_rush`，它会强制关闭所有人的物理碰撞。你需要关掉它自带的穿透功能，交由本插件接管：
1. 打开 `cstrike/addons/amxmodx/configs/kz/kz_rush.cfg`。
2. 找到 `kz_semiclip`，将其值修改为 `0`。
```cfg
kz_semiclip 0
```
3. 保存并重启服务器服务端。

---

## 🎮 玩家指令与按键绑定 (Commands & Binds)

为了防止与服务器自带的 KZ 插件冲突，本插件所有指令均以 **`b`** (Boost) 开头。

### 聊天框指令 (在游戏按 Y 输入)
*   `/bkzmenu` —— 打开双人 KZ 综合主菜单
*   `/bcoop` —— 邀请玩家组队
*   `/bleave` —— 退出当前队伍
*   `/bcp` —— 存点 (CheckPoint)
*   `/btp` —— 读点 (Teleport)
*   `/bswap` —— 请求与队友互换位置
*   `/bsync` —— 发起同步起跳倒计时

### 💡 推荐一键绑定代码
打开游戏控制台 (`~`键)，输入以下代码绑定到你顺手的按键上（以下为推荐键位，可自行修改）：

```console
bind "p" "say /bkzmenu"
bind "c" "say /bcp"
bind "v" "say /btp"
bind "b" "say /bswap"
bind "alt" "say /bsync"
```

---

## 📝 结语
感谢在这段开发旅程中的不断测试与反馈。祝你和你的搭档在这个双人 KZ 世界里一次过关，默契无间！Have Fun & Happy Jumping! 🏃‍♂️🏃‍♂️
