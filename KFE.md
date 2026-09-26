# KFE · KadeFuck Engine

[![KFE Build (Windows)](https://github.com/DFJK117/KFE/actions/workflows/kfe-build.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-build.yml)
[![KFE Build (Linux)](https://github.com/DFJK117/KFE/actions/workflows/kfe-linux.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-linux.yml)
[![基线对照](https://github.com/DFJK117/KFE/actions/workflows/kfe-baseline.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-baseline.yml)

> 一个以 **Kade Engine 1.8** 为底座、试图在同一套引擎里兼容多代 FNF 模组脚本与资产的引擎。

---

## 作者与归属

| | |
|---|---|
| **作者** | **京葉Viii** |
| **辅助生成** | 本项目由 **Hy4** 辅助生成 |
| **底座** | [`kadedev/Kade-Engine` @ tag `1.8`](https://github.com/kadedev/Kade-Engine)（逐字节校验） |
| **许可** | 沿用底座原 `LICENSE` |

> 补丁设计、取证工作与 CI 排错由 Hy4 辅助完成，项目的归属与最终决策属于京葉Viii。

---

## 这是什么 / 不是什么

**是**：KE 1.8 的一个分支。在原版基础上加了**多方言兼容层**，
让 LE (Andromeda) 风格的对象式 modchart、以及更老的模组资产能跑起来。

**不是**：

- 不是 Psych Engine 的分支，也没有往 Psych 里塞任何东西
- 不是从零写的引擎
- **没有拿 Bob's Onslaught 的源码当底座** —— 那份源码只用来**取证事件语义**
  （哪个拍触发什么、掉多少血、怎么判舞台），**一行都没进引擎**

---

## 目录

- [特性一览](#特性一览)
- [补丁全表](#补丁全表)
- [平台与编译](#平台与编译)
- [画质选项](#画质选项)
- [底座校验](#底座校验)
- [未落地 / 不可兼容](#未落地--不可兼容)
- [排错记录](#排错记录)

---

## 特性一览

### 一、modchart 多方言加载

| 特性 | 说明 |
|---|---|
| 路径候选探测 | 加载路径从单一硬编码改为 **多方言候选**（KE 原生 / LE 风格 / 老式 `<song>/modchart` / SM 目录…），由 `KFECompat.modchartCandidates()` 统一供给 |
| 找不到就安静退回 | 原版找不到 modchart 会弹 `LUA COMPILE ERROR` 并踢回自由模式；KFE 改成只打日志、按原版行为继续 |
| 存在性判定同源 | `PlayState` 的 `executeModchart` 判定与加载表同一来源，不会「判定说有、加载说没有」 |

### 二、hook 名多方言扇出

`executeState` 一次调用会扇出到所有方言的 hook 名，并且**修掉了 Lua 栈泄漏**：

| 原版（KE 1.8） | LE 风格 | 含义 |
|---|---|---|
| `start` | `create` | 谱面开始 |
| `playerTwoSing` | `dadNoteHit` | 对手唱歌 |
| `playerOneMiss` | `doMiss` | 玩家漏接 |
| … | … | 共 12 组映射 |

- 扇出的安全前提：`callLua` 对缺失的全局会拿到 `attempt to call a nil value` 并被静默吞掉，所以多调几个不存在的名字**零成本**
- 但 `callLua` 每次会在栈上留 1 个值不弹，一整首歌累积下来会撞 Lua 栈上限 —— KFE 补上了弹栈

### 三、双方言命名（同一个对象挂多个名字）

| 对象 | KE 名 | LE 名 |
|---|---|---|
| 判定线 | `receptor_0..7` | `leftDadNote` / `leftPlrNote` … |
| 相机 | `camGame` / `camHUD` / `camSustains` / `camNotes` | `gameCam` / `HUDCam` / `holdCam` / `receptorCam` |
| 角色 | `boyfriend` / `gf` / `dad` | `bf` / `gf` / `dad` |

顺带**修正了原版的一个笔误**：KE 1.8 把 `camNotes` 也绑到了 `camSustains`
（`PlayState.hx:813`），KFE 改成绑定真正的 `camNotes` 对象。

### 四、补注入 Lua 全局

原版 KE 1.8 没给 Lua 这两个，导致 modchart 无法按舞台 / 模式分支：

- `curStage`（取自 `Stage.curStage`）
- `storyMode`

### 五、`setVar` 类型感知

原版 `setVar` 固定走 `pushnumber`，导致：

- `Bool` 被推成数字 —— 而 **Lua 里 `0` 是真值**，语义直接反了
- `String` 类型不符

KFE 改为走 `toLua()` 做类型分发。

### 六、新增回调（6 个 + 1 个）

`playSound` / `stopSound` / `playMusic` / `cameraFade` / `pushWarnNote` / `getOption`，
外加 `kfeMakeSpriteEx`。

其中 `kfeMakeSpriteEx` 走 `Paths.image()`，解决原版 `makeSprite` 只认 song 目录的问题。
配套在 `ModchartState` 里加了 `kfeSounds` 表（`stopSound` 需要它）。

### 七、存档开关语义

`KFECompat.getSaveOption()` 返回**原始存档值**（Bool 就返回 Bool），不做任何取反。

> 这里有个坑记下来了：Bob's Onslaught 的 `Options.hx:147/154` 是**反语义**的
> （存 `jumpscare = !jumpscare`，显示又取反一次），
> 所以脚本里的 `!save.data.X` 直译成 `not getOption("X")` 即可，**不要自作聪明去"纠正"**。

### 八、警告音符系统

- `Note.hx` 新增 `kfeWarning` / `kfeFake` 字段 + `setKfeWarningGraphic()`（走模组 `bob/CustomNotes` 图集）
- `ModchartState.kfePushWarnNote()` 往 `PlayState.instance.unspawnNotes` 注入音符，**注入后重排序**
  （`generateSong` 里已经排过一次，不重排的话 `PlayState` 按 `unspawnNotes[0]` 推进会漏掉后面的音符）
- `PlayState` 加 `kfeWarnHit` 命中回调，替代原版硬编码的 `HealthDrain` 调用
- `unspawnNotes` 由 `private` 放开为 `public`，供兼容层注入

### 九、画质选项

见 [画质选项](#画质选项)。

### 十、Lua 兼容层（`KFECompat.hx`）

| API | 作用 |
|---|---|
| `modchartCandidates()` | modchart 路径候选表 |
| `findModchartPath()` | 按候选表探测实际存在的路径 |
| `hasModchart()` | 存在性判定（与加载表同源） |
| `hookAliases(name)` | hook 名多方言映射 |
| `receptorAliases(i)` / `cameraAliases(ke, le)` / `characterAliases(name)` | 双方言名字表 |
| `registerAliased(obj, lua, names)` | 把同一个对象按多个名字注册进 Lua |
| `getSaveOption(name)` | 读存档开关（返回原始值） |

---

## 补丁全表

共 **16 个补丁**，改动 4 个原版文件 + 新增 3 个文件，附加 36 条自动化断言。

| 补丁 | 文件 | 内容 |
|---|---|---|
| `MS-1` | `ModchartState.hx` | 加载路径改多方言候选，找不到时安静退回原版 |
| `MS-2` | `ModchartState.hx` | 注入 `curStage` / `storyMode` |
| `MS-3` | `ModchartState.hx` | 新增 6 个回调 |
| `MS-4` | `ModchartState.hx` | 判定线双方言命名 |
| `MS-5` / `MS-5b` | `ModchartState.hx` | `executeState` 改 hook 别名扇出 + 修栈泄漏 |
| `MS-6` | `ModchartState.hx` | `kfeSounds` 表 + `kfePushWarnNote()`（含重排序）+ `kfeMakeSpriteEx()` |
| `MS-7` | `ModchartState.hx` | `setVar` 改类型感知 `toLua()` |
| `PS-1` | `PlayState.hx` | `executeModchart` 改多候选判定 |
| `PS-2` | `PlayState.hx` | 相机 / 角色双方言命名，并修正 `camNotes` 绑定 |
| `PS-3` | `PlayState.hx` | 警告音符命中回调 `kfeWarnHit` |
| `PS-4` | `PlayState.hx` | `unspawnNotes` 由 private 改 public |
| `PS-5` | `PlayState.hx` | 向 `KFEGraphics` 登记 `camGame`，让动态模糊生效 |
| `NT-1` | `Note.hx` | `kfeWarning` / `kfeFake` 字段 + `setKfeWarningGraphic()` |
| `OM-1` | `OptionsMenu.hx` | Appearance 分组新增「动态模糊」与「渲染后端」两项 |
| — | `Project.xml` | 加 `--no-opt`（降低 haxe 编译期内存峰值）；`FEATURE_LUAMODCHART` 放宽到 `desktop` |

### 新增文件（3 个）

| 文件 | 作用 |
|---|---|
| `source/KFECompat.hx` | 方言兼容层（上表全部 API） |
| `source/KFEGraphics.hx` | 画质状态机 + 两个 `Option` 子类 |
| `source/KFEBlurShader.hx` | 动态模糊着色器 |

> 刻意**不碰 `Lua_helper`**：它的 Haxe 模块路径无法从工程内确定，
> 所有新增能力都走已经确定可用的 `Lua_helper.add_callback(lua, ...)` 入口。

---

## 平台与编译

不用在本地装 Haxe 那一整套（haxe / haxelib / lime / hxcpp / MSVC）。
`.github/workflows/` 下有三条流水线，push 后自动跑：

| Workflow | 平台 | 产出 |
|---|---|---|
| `kfe-build.yml` | Windows | artifact `KFE-windows` |
| `kfe-linux.yml` | Linux | artifact `KFE-linux` |
| `kfe-baseline.yml` | Windows | 对照用：编**不打补丁**的原版 KE 1.8 |

锁定的依赖版本（每个都在 lib.haxe.org 上核实过存在）：

```
hxcpp 4.2.1   lime 7.9.0   openfl 9.1.0   flixel 4.9.0
flixel-addons 2.10.0   flixel-ui 2.3.3   hscript 2.0.7   actuate 1.8.7
polymod 1.4.3
git: discord_rpc / extension-webm / linc_luajit / hxvm-luajit
```

装完依赖后会**回读校验** `haxelib list` 的 current 版本，对不上就立刻停 ——
因为 haxelib 的 current 版本很容易被后面某条命令悄悄顶掉。

底层（Lime 7.9 / OpenFL 9.1）支持 Windows / Linux / macOS / HTML5 / mobile / Switch，
但**目前只有 Windows 与 Linux 这两条 CI 是真的在跑的**，别的平台没有验证过。

---

## 画质选项

Appearance 分组里新增两项（实现见 `source/KFEGraphics.hx`）：

| 选项 | 档位 | 生效方式 |
|---|---|---|
| `Motion Blur` | off / low / medium / high | 即时（纯 shader） |
| `Renderer` | Auto / OpenGL / Direct3D 11 (via ANGLE) / Software | 需重启，按一下即重启 |

**关于「DX11」必须说清楚：**

> Lime 7.9.0 的 `RenderContextType` 枚举里**没有 `d3d11`**。
> 全部取值只有 `cairo / canvas / dom / flash / opengl / opengles / webgl / custom`。
> 往里传 `d3d11` 会被丢掉，什么都不会发生 —— 那种「DX11 开关」是假的。
>
> Windows 上真正走 D3D 的路径是 **ANGLE**：Lime 仓库自带的
> `dependencies/angle/` 里放着 `d3dcompiler_47.dll`（3.4 MB）和
> `libegl.dll` / `libglesv2.dll`。GLES 调用经 EGL → ANGLE → 转译成 D3D11。
>
> 所以本引擎里的「DX11」档，实际传的是 `--window-render-type=opengles`，
> UI 上老老实实标成 `Direct3D 11 (via ANGLE)`。

**动态模糊也不是物理正确的运动模糊**，是单帧径向多 tap 的**近似**
（真运动模糊要帧历史 / 速度缓冲，这条管线拿不到）。所以文档里写「近似」，不写「运动模糊」。

档位表（`BLUR_TABLE`）：

| 档位 | 强度 | 采样数 |
|---|---|---|
| off | 0.000 | 2 |
| low | 0.020 | 6 |
| medium | 0.045 | 12 |
| high | 0.080 | 20 |

`KFEGraphics` 还会顺带回收 `!cam.exists` 的死相机，
并用**替换**语义（`cam.setFilters(...)`）保证幂等 —— flixel 4.9 的 `FlxCamera`
没有公开的 filters 读接口，所以自己记账。

完整取证链见 `docs/06_画质选项.md`。

---

## 底座校验

重新生成分发时会**逐字节断言**锚点文件的 SHA256，不一致就拒绝继续 ——
防止底座版本串味。

> 本项目已经踩过一次这个坑：某个叫 "1.8 Template" 的仓库其实被作者改过
> （把 `makeSprite` 的精灵注册注释掉了、拆了 `FEATURE_LUAMODCHART` 守卫）。
> 所以校验是硬性的，不是可选项。

---

## 未落地 / 不可兼容

**未落地**（Phase 2）：

- **LE 对象成员补齐**：LE 的 `LuaSprite` 有 32 个成员，KE 1.8 只有 9 个
  （缺 `visible` / `scaleX` / `scaleY` / `scrollFactorX` / `makeGraphic` …）
- **KE 1.5.x ~ 1.6.2 平铺 API 桥**：那几代是 93~112 个平铺全局函数，范式不同
- `countdown` 触发点

**不可兼容**：

- `doEvent` —— KE 1.8 没有谱面事件系统，没有宿主

---

## 排错记录

编译过程中踩过的坑全部记在 `docs/07_云端编译排错.md`，包括：

- polymod 仓库 404（原版 KE 自己的 CI 地址已失效）
- `haxelib run lime setup` 把整个版本矩阵掀了，而我给它加了 `|| true` 掩盖了这件事
- 补丁的两个真实语法错误（多一个 `}` 把 `new()` 提前关掉）
- 一个反直觉的教训：**花括号计数相等查不出这类错**（总数照样凑平）
- Windows 上 haxe 编译 OOM，天花板是「提交上限」= 物理内存 + 页面文件

有新的失败会继续往那份文档里补。
