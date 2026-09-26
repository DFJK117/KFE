# KFE · KadeFuck Engine

[![KFE Build (Windows)](https://github.com/DFJK117/KFE/actions/workflows/kfe-build.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-build.yml)
[![KFE Build (Linux)](https://github.com/DFJK117/KFE/actions/workflows/kfe-linux.yml/badge.svg)](https://github.com/DFJK117/KFE/actions/workflows/kfe-linux.yml)

> **一套引擎，跑多代模组的 modchart。**
>
> 以 Kade Engine 1.8 为底座，加了一层「方言兼容层」——
> 让 KE 原生、LE (Andromeda) 风格的对象式脚本，以及更老一代模组的资源，
> 都能在同一套引擎里加载运行，不用为了一个模组换一个引擎版本。

---

## 为什么会有这个东西

FNF 的 modchart 生态**没有统一标准**。不同引擎分支各自演化出一套脚本写法：

- 同一个对象，在不同分支里叫不同的名字
- 同一个事件，hook 函数名不一样（`start` vs `create`）
- modchart 文件放在不同路径下
- 甚至同一个开关的存档语义是**反的**

结果就是：一个模组只能在它当初针对的那个引擎版本上跑，换个版本就直接报错或者静默失效。

KFE 的做法是**不去改模组，而是让引擎同时认得下所有写法**——
同名对象挂多个别名、事件扇出到所有方言的 hook 名、路径按候选表探测。
改的是引擎侧，模组那一侧不用动。

---

## 目录

- [特性一览](#特性一览)
- [补丁全表](#补丁全表)
- [平台与编译](#平台与编译)
- [画质选项](#画质选项)
- [底座校验](#底座校验)
- [未落地 / 不可兼容](#未落地--不可兼容)
- [排错记录](#排错记录)
- [关于](#关于)

---

## 特性一览

### 一、modchart 多方言加载

| 特性 | 说明 |
|---|---|
| 路径候选探测 | 加载路径从单一硬编码改为**多方言候选**（KE 原生 / LE 风格 / 老式 `<song>/modchart` / SM 目录…） |
| 找不到就安静退回 | 原版找不到 modchart 会弹错误窗口并踢回自由模式；KFE 改成只记日志、按原版行为继续跑 |
| 判定与加载同源 | 存在性判定和实际加载走同一张候选表，不会出现「判定说有、加载说没有」 |

### 二、事件名多方言扇出

一次 `executeState` 会扇出到所有方言的事件名。例如：

| KE 1.8 写法 | LE 风格写法 | 含义 |
|---|---|---|
| `start` | `create` | 谱面开始 |
| `playerTwoSing` | `dadNoteHit` | 对手唱歌 |
| `playerOneMiss` | `doMiss` | 玩家漏接 |
| … | … | 共 12 组映射 |

- **零成本**：调用不存在的全局会得到 `attempt to call a nil value` 并被静默吞掉，所以多调几个名字没有副作用
- **修了栈泄漏**：调用会在 Lua 栈上留值不弹，一整首歌累积下来会撞栈上限，KFE 补上了弹栈

### 三、对象双方言命名

同一个对象同时注册两个名字，脚本用哪个都能取到：

| 对象 | KE 名 | LE 名 |
|---|---|---|
| 判定线 | `receptor_0..7` | `leftDadNote` / `leftPlrNote` … |
| 相机 | `camGame` / `camHUD` / `camSustains` / `camNotes` | `gameCam` / `HUDCam` / `holdCam` / `receptorCam` |
| 角色 | `boyfriend` / `gf` / `dad` | `bf` / `gf` / `dad` |

顺带**修正了原版的一处笔误**：KE 1.8 把 `camNotes` 也绑到了 `camSustains` 上，
KFE 改回绑定真正的 `camNotes` 对象。

### 四、补注入脚本全局

原版 KE 1.8 没给脚本这两个变量，导致 modchart 无法按舞台或模式分支：

- `curStage`（当前舞台）
- `storyMode`（是否故事模式）

### 五、`setVar` 类型感知

原版 `setVar` 固定把值转成数字推给 Lua，带来两个坑：

- 布尔被推成数字 —— 而 **Lua 里 `0` 是真值**，判断语义直接反了
- 字符串类型不符

KFE 改成按实际类型分发。

### 六、新增脚本回调

新增 7 个脚本可用回调：

`playSound` / `stopSound` / `playMusic` / `cameraFade` / `pushWarnNote` / `getOption` / `makeSpriteEx`

其中 `makeSpriteEx` 走常规资源路径加载，解决原版 `makeSprite` 只在歌曲目录里找图的问题。

### 七、存档开关语义

`getOption()` 返回**原始存档值**（布尔就返回布尔），不做任何取反。

> 这里有个坑值得记：部分模组的存档开关是**反语义**存的
> （存的值和界面显示相反）。所以脚本里写 `!save.data.X` 时，
> 直译成 `not getOption("X")` 就对了，**不要自作聪明去"纠正"**。

### 八、警告音符系统

- `Note` 新增 `kfeWarning` / `kfeFake` 字段与对应的图形切换
- 可向未生成音符队列注入警告音符，**注入后会重排序**
  （原流程已经排过一次序，不重排的话按队首推进会漏掉后面的音符）
- 命中回调可替换原版硬编码的扣血逻辑
- 音符队列放开为公开，供兼容层注入

### 九、画质选项

见 [画质选项](#画质选项)。

### 十、兼容层 API（`KFECompat.hx`）

| API | 作用 |
|---|---|
| `modchartCandidates()` | modchart 路径候选表 |
| `findModchartPath()` | 按候选表探测实际存在的路径 |
| `hasModchart()` | 存在性判定（与加载表同源） |
| `hookAliases(name)` | 事件名的多方言映射 |
| `receptorAliases(i)` / `cameraAliases(ke, le)` / `characterAliases(name)` | 双方言名字表 |
| `registerAliased(obj, lua, names)` | 把同一个对象按多个名字注册进脚本 |
| `getSaveOption(name)` | 读存档开关（返回原始值） |

---

## 补丁全表

共 **16 个补丁**，改动 4 个原版文件 + 新增 3 个文件，附带 36 条自动化断言。

| 补丁 | 文件 | 内容 |
|---|---|---|
| `MS-1` | `ModchartState.hx` | 加载路径改多方言候选，找不到时安静退回原版 |
| `MS-2` | `ModchartState.hx` | 注入 `curStage` / `storyMode` |
| `MS-3` | `ModchartState.hx` | 新增 6 个回调 |
| `MS-4` | `ModchartState.hx` | 判定线双方言命名 |
| `MS-5` / `MS-5b` | `ModchartState.hx` | `executeState` 改事件名扇出 + 修栈泄漏 |
| `MS-6` | `ModchartState.hx` | 音效句柄表 + 警告音符注入（含重排序）+ `makeSpriteEx` |
| `MS-7` | `ModchartState.hx` | `setVar` 改类型感知 |
| `PS-1` | `PlayState.hx` | `executeModchart` 改多候选判定 |
| `PS-2` | `PlayState.hx` | 相机 / 角色双方言命名，并修正 `camNotes` 绑定 |
| `PS-3` | `PlayState.hx` | 警告音符命中回调 |
| `PS-4` | `PlayState.hx` | 音符队列放开为公开 |
| `PS-5` | `PlayState.hx` | 向画质层登记主相机，让动态模糊生效 |
| `NT-1` | `Note.hx` | 警告 / 假音符字段与图形切换 |
| `OM-1` | `OptionsMenu.hx` | Appearance 分组新增「动态模糊」与「渲染后端」两项 |
| — | `Project.xml` | 加 `--no-opt`（降低编译期内存峰值）；Lua modchart 支持放宽到桌面端 |

### 新增文件（3 个）

| 文件 | 作用 |
|---|---|
| `source/KFECompat.hx` | 方言兼容层（上表全部 API） |
| `source/KFEGraphics.hx` | 画质状态机与两个选项控件 |
| `source/KFEBlurShader.hx` | 动态模糊着色器 |

> 刻意**不碰 `Lua_helper`**：它的模块路径无法从工程内确定，
> 所有新增能力都走已经确定可用的回调注册入口。

---

## 平台与编译

不用在本地装 Haxe 那一整套（haxe / haxelib / lime / hxcpp / MSVC）。
`.github/workflows/` 下的流水线会在 push 后自动跑：

| Workflow | 平台 | 产出 |
|---|---|---|
| `kfe-build.yml` | Windows | artifact `KFE-windows` |
| `kfe-linux.yml` | Linux | artifact `KFE-linux` |
| `kfe-baseline.yml` | Windows | 对照用：编**不打补丁**的原版引擎 |

锁定的依赖版本（每个都在 lib.haxe.org 上核实过存在）：

```
hxcpp 4.2.1   lime 7.9.0   openfl 9.1.0   flixel 4.9.0
flixel-addons 2.10.0   flixel-ui 2.3.3   hscript 2.0.7   actuate 1.8.7
polymod 1.4.3
git: discord_rpc / extension-webm / linc_luajit / hxvm-luajit
```

装完依赖后会**回读校验**实际生效版本，对不上就立刻停——
因为 haxelib 的当前版本很容易被后面某条命令悄悄顶掉。

底层（Lime 7.9 / OpenFL 9.1）支持 Windows / Linux / macOS / HTML5 / 移动端 / Switch，
但**目前只有 Windows 与 Linux 这两条流水线是真的在跑的**，其余平台未验证。

---

## 画质选项

Appearance 分组里新增两项：

| 选项 | 档位 | 生效方式 |
|---|---|---|
| `Motion Blur` | off / low / medium / high | 即时（纯 shader） |
| `Renderer` | Auto / OpenGL / Direct3D 11 (via ANGLE) / Software | 需重启，按一下即重启 |

**关于「DX11」要说清楚：**

> Lime 7.9.0 的渲染上下文枚举里**没有 `d3d11`**，
> 全部取值只有 `cairo / canvas / dom / flash / opengl / opengles / webgl / custom`。
> 传 `d3d11` 会被直接丢掉——那种「DX11 开关」是假的。
>
> Windows 上真正走 D3D 的路径是 **ANGLE**：GLES 调用经 EGL → ANGLE → 转译成 D3D11。
> 所以本引擎里的「DX11」档实际传的是 `opengles`，
> 界面上也老老实实标成 `Direct3D 11 (via ANGLE)`，不装成原生 DX11。

**动态模糊是单帧径向多 tap 的近似**，不是物理正确的运动模糊
（真运动模糊需要帧历史或速度缓冲，这条管线拿不到）。所以叫「近似」，不叫「运动模糊」。

| 档位 | 强度 | 采样数 |
|---|---|---|
| off | 0.000 | 2 |
| low | 0.020 | 6 |
| medium | 0.045 | 12 |
| high | 0.080 | 20 |

画质层还会回收已销毁的相机，并用替换语义保证重复设置不出问题。

完整取证见 `docs/06_画质选项.md`。

---

## 底座校验

重新生成分发时会**逐字节断言**锚点文件的校验和，不一致就拒绝继续——
防止底座版本串味。

> 踩过一次坑：某个号称「1.8 Template」的仓库其实被改过
> （精灵注册被注释掉、Lua modchart 的条件守卫被拆了）。
> 所以这一步是硬性的，不是可选项。

---

## 未落地 / 不可兼容

**未落地**（后续阶段）：

- **LE 对象成员补齐**：LE 的脚本精灵对象有 32 个成员，KE 1.8 只有 9 个
  （缺 `visible` / `scaleX` / `scaleY` / `scrollFactorX` / `makeGraphic` 等）
- **KE 1.5.x ~ 1.6.2 平铺式 API 桥**：那几代是近百个平铺全局函数，范式完全不同
- `countdown` 触发点

**不可兼容**：

- `doEvent` —— KE 1.8 没有谱面事件系统，没有对应的宿主机制

---

## 排错记录

编译过程中踩过的坑记在 `docs/07_云端编译排错.md`，包括：

- 某个依赖的上游仓库已 404（原版自己的 CI 地址失效了）
- 一条 `haxelib` 命令把整个依赖版本矩阵掀了，而当时的脚本把它掩盖了
- 补丁的两个真实语法错误（多一个花括号把构造函数提前关掉）
- 一个反直觉的教训：**花括号计数相等查不出这类错**（总数照样凑平）
- Windows 上编译器进程 OOM，天花板是「提交上限」= 物理内存 + 页面文件

有新的失败会继续往那份文档里补。

---

## 关于

| | |
|---|---|
| **作者** | **京葉Viii** |
| **辅助生成** | 本项目由 **Hy4** 辅助生成 |
| **底座** | [`kadedev/Kade-Engine` @ tag `1.8`](https://github.com/kadedev/Kade-Engine) |
| **许可** | 沿用底座原 `LICENSE` |

补丁设计、取证工作与 CI 排错由 Hy4 辅助完成；项目的归属与最终决策属于京葉Viii。

本项目是 Kade Engine 的分支，不含任何其他模组的源码。
