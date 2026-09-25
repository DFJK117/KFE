# KFE · KadeFuck Engine

> 一个以 **Kade Engine 1.8** 为底座、试图在同一套引擎里兼容多代 FNF 模组脚本/资产的引擎。

底座来源：**`kadedev/Kade-Engine` @ tag `1.8`**（逐字节校验，见下方「底座校验」）。

---

## 这是什么 / 不是什么

**是**：KE 1.8 的一个分支。在原版基础上加了**多方言兼容层**，
让 LE (Andromeda) 风格的对象式 modchart、以及更老的模组资产能跑起来。

**不是**：
- 不是 Psych Engine 的分支，也没有往 Psych 里塞任何东西
- 不是从零写的引擎
- **没有拿 Bob's Onslaught 的源码当底座** —— 那份源码只用来**取证事件语义**
  （哪个拍触发什么、掉多少血、怎么判舞台），一行都没进引擎

---

## 相对原版 KE 1.8 的改动

### 改动的文件（4 个）

| 文件 | 改了什么 |
|---|---|
| `source/ModchartState.hx` | 加载路径改 6 条候选探测；`executeState` 改命运扇出 + 补弹栈；注入 `curStage`/`storyMode`；新增 7 个回调（`playSound`/`stopSound`/`playMusic`/`cameraFade`/`pushWarnNote`/`getOption`/`makeSpriteEx`）；判定线改双方言命名；**`setVar` 改类型感知** |
| `source/PlayState.hx` | `executeModchart` 多候选判定；角色/相机别名注册；修正 `camNotes` 绑定；警告音符命中回调；`unspawnNotes` 放开可见性；**向画质层登记 `camGame`** |
| `source/Note.hx` | 新增 `kfeWarning` / `kfeFake` 字段 + `setKfeWarningGraphic()`（模组 `bob/CustomNotes` 图集） |
| `source/OptionsMenu.hx` | Appearance 分组尾部追加「动态模糊」与「渲染后端」两个选项（不动任何既有选项） |

### 新增的文件（3 个）

| 文件 | 作用 |
|---|---|
| `source/KFECompat.hx` | 方言兼容层：路径候选表 / hook 别名表 / 多名字注册 / 存档开关 |
| `source/KFEGraphics.hx` | 画质选项：动态模糊强度 + 渲染后端切换（含两个 `Option` 子类） |
| `source/KFEBlurShader.hx` | 动态模糊着色器（单帧径向多 tap 近似，非物理准确） |

> 刻意**不碰 `Lua_helper`**：它的 Haxe 模块路径无法从工程内确定，
> 所有新增能力都走已经确定可用的 `Lua_helper.add_callback(lua, ...)` 入口。

---

## 底座校验

`dist/build_report.md` 里记录了 4 个锚点文件的 SHA256（前 16 位）。
重新生成分发时会**逐字节断言**，不一致就拒绝继续——防止底座版本串味。

> 本项目已经踩过一次这个坑：某个叫 "1.8 Template" 的仓库其实被作者改过
> （把 `makeSprite` 的精灵注册注释掉了、拆了 `FEATURE_LUAMODCHART` 守卫）。
> 所以校验是硬性的，不是可选项。

---

## 云端编译

不用在本地装 Haxe 那一整套（haxe / haxelib / lime / hxcpp / MSVC）。

`.github/workflows/kfe-build.yml` 会在 `windows-latest` 上自动：

1. 装 Haxe 4.1.5
2. 装**锁定版本**的 `hxcpp 4.2.1` / `lime 7.9.0` / `openfl 9.1.0` / `flixel 4.9.0` /
   `flixel-addons 2.10.0` / `flixel-ui 2.3.3` / `hscript 2.0.7` / `actuate 1.8.7`，
   以及 git 版的 `polymod` / `discord_rpc` / `extension-webm` /
   **`linc_luajit`** / **`hxvm-luajit`**
3. `lime rebuild extension-webm windows`（原生库，必须重编）
4. `lime build windows -release`
5. 上传 artifact **`KFE-windows`**

触发方式：push（`main`/`master`/`dev` 分支）、PR、或 Actions 页面手动 `Run workflow`。

编译失败时会把 `haxe/log.txt` 一起传上来，方便回贴排查。

> 原版仓库自带的 `windows.yml` / `html5.yml` / `linux.yml` 已改名为 `.disabled`：
> 它们用的是已被 GitHub 停用的 `actions/upload-artifact@v2`，
> 而且用 debug 构建却上传 `export/release/` 路径 —— 必然拿不到东西。

---

## 已落地 / 未落地

**已落地**（有自动化断言）：

- 加载路径 6 条候选探测
- `executeState` 命运扇出（12 组映射）+ Lua 栈补弹
- 判定线双方言命名（`receptor_N` ↔ `leftDadNote`…）
- 角色 / 相机别名（`boyfriend`↔`bf`、`camGame`↔`gameCam`…）
- 注入 `curStage` / `storyMode`
- `setVar` 类型感知（修掉 KE 一直以来的「Bool 被推成数字、Lua 里 0 是真值」问题）
- 7 个新回调
- 警告音符注入 + 图集
- 画质选项：动态模糊（4 档，即时生效）+ 渲染后端切换（含一键重启）

**未落地**（Phase 2）：

- **LE 对象成员补齐**：LE 的 `LuaSprite` 有 32 个成员，KE 1.8 只有 9 个
  （缺 `visible` / `scaleX` / `scaleY` / `scrollFactorX` / `makeGraphic` …）
- **KE 1.5.x ~ 1.6.2 平铺 API 桥**：那几代是 93~112 个平铺全局函数，范式不同
- `countdown` 触发点

**不可兼容**：

- `doEvent` —— KE 1.8 没有谱面事件系统，没有宿主

---

## 一个必须说清的事实

**这套补丁在撰写时从未被编译过**（开发机没有 Haxe 工具链）。
所有静态校验（括号平衡、锚点唯一、改动落地）只能证明"看起来是对的"，
**不能替代真实编译**。

这个 workflow 的存在就是为了补上这一环。

---

## 画质选项

Appearance 分组里新增两项（实现见 `source/KFEGraphics.hx`）：

| 选项 | 档位 | 生效方式 |
|---|---|---|
| `Motion Blur` | off / low / medium / high | 即时（纯 shader） |
| `Renderer` | Auto / OpenGL / **Direct3D 11 (via ANGLE)** / Software | 需重启，按一下即重启 |

关于「DX11」这件事必须说清楚：

> **Lime 7.9.0 的 `RenderContextType` 枚举里没有 `d3d11`。**
> 全部取值只有 `cairo / canvas / dom / flash / opengl / opengles / webgl / custom`。
> 往里传 `d3d11` 会被丢掉，什么都不会发生 —— 那种「DX11 开关」是假的。
>
> Windows 上真正走 D3D 的路径是 **ANGLE**：Lime 仓库自带的
> `dependencies/angle/` 里放着 `d3dcompiler_47.dll`（3.4 MB，D3D 的 HLSL 编译器）
> 和 `libegl.dll` / `libglesv2.dll`。GLES 调用经 EGL → ANGLE → 转译成 D3D11。
>
> 所以本引擎里的「DX11」档，实际传的是 `--window-render-type=opengles`，
> UI 上老老实实标成 `Direct3D 11 (via ANGLE)`。

**动态模糊也不是物理正确的运动模糊**，是单帧径向多 tap 的**近似**
（真运动模糊要帧历史 / 速度缓冲，这条管线拿不到）。
所以文档里写「近似」，不写「运动模糊」。

完整取证链见 `docs/06_画质选项.md`。

---

## 许可

底座为 Kade Engine 1.8，遵循其原 LICENSE（见 `LICENSE`）。
