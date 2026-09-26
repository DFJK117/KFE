package;

import flixel.FlxG;
import flixel.FlxCamera;
import openfl.filters.BitmapFilter;
import openfl.filters.ShaderFilter;

/**
 * KFE 画质设置的运行时状态与副作用。
 *
 * 这里放的是「逻辑」，Option 子类只负责 UI 和按键。分开的理由：
 * 同一份状态既被选项菜单改（主菜单 / 暂停菜单），又要被 PlayState 消费
 * （进曲时挂 filter），还要被重启逻辑读（拼启动参数）——三处都要用，
 * 塞进 Option 类里会变成跨类摸 private 字段。
 *
 * ======================== 关于「DX11」这件事 ========================
 * 先说结论，因为这里最容易造假：
 *
 *   **Lime 7.9.0 里根本没有 `d3d11` 这个渲染后端。**
 *
 * 取证（`reference/lime/`，全部来自 openfl/lime @ 7.9.0）：
 *
 *  1. `src/lime/graphics/RenderContextType.hx` 是 `@:enum abstract
 *     RenderContextType(String)`，全部取值只有 8 个：
 *        cairo / canvas / dom / flash / opengl / opengles / webgl / custom
 *     没有 d3d11、没有 d3d9、没有 directx。写 `--window-render-type=d3d11`
 *     只会拿到一个 Lime 不认识的字符串，然后被丢掉、回落到默认值。
 *     ——也就是说，做一个自称“DX11”的选项去传 `d3d11`，是**假的**。
 *
 *  2. 但 Windows 上确实走 D3D —— 走的是 **ANGLE** 这条转译路：
 *     `src/lime/system/System.hx:495` 把 `--window-render-type` 的值直接
 *     赋给 `attributes.context.type`；而 Lime 仓库自带
 *     `dependencies/angle/`，里面躺着
 *        `d3dcompiler_47.dll` (3.4 MB)  ← Direct3D 的 HLSL 编译器
 *        `libegl.dll` / `libglesv2.dll` ← ANGLE 的两个核心库
 *     GLES 调用经 EGL → ANGLE → 转译成 D3D11。
 *
 *  3. 所以本引擎里「DX11」这个档，真实含义是
 *        `--window-render-type=opengles`（在 Windows 上 = ANGLE = D3D11）
 *     UI 上老老实实标成 `Direct3D 11 (via ANGLE)`，不写成裸的 “DX11”。
 *
 *  4. `--window-hardware=false` 是另一个维度：不看 GPU，走软件光栅。
 *     它由 `System.hx:485` 的 `attributes.context.hardware` 接住。
 *
 * 参数解析时机（`System.hx:425 __parseArguments`）在窗口创建之前，
 * 读的是**命令行**（`Sys.args()`）。而且 KE 1.8 的 Project.xml 里没有定义
 * `lime_disable_window_override`（第 464 行的开关），所以这些参数**会生效**，
 * 并且会**覆盖** Project.xml 里 `<window ...>` 的同名属性。
 *
 * ⇒ 结论：后端是**启动期**决定的，切换必须带参重启进程。没有运行时热切换
 *    这种好事，谁跟你说能热切换谁就是在骗你。
 * ====================================================================
 */
class KFEGraphics
{
	// ---------------------------------------------------------------- 动态模糊

	public static inline var BLUR_OFF = 0;
	public static inline var BLUR_LOW = 1;
	public static inline var BLUR_MED = 2;
	public static inline var BLUR_HIGH = 3;

	static inline var BLUR_MAX = 3;

	/** 档位 → [强度, tap 数]。索引即档位常量。 */
	static final BLUR_TABLE:Array<Array<Float>> = [
		[0.000, 2.0],   // OFF
		[0.020, 6.0],   // LOW
		[0.045, 12.0],  // MED
		[0.080, 20.0],  // HIGH
	];

	static final BLUR_NAMES:Array<String> = ["off", "low", "medium", "high"];

	/** 复用一个实例。每次切换都 new 一个的话，GLSL 程序会被反复编译/丢弃。 */
	static var blurShader:KFEBlurShader = null;

	// ---------------------------------------------------------------- 渲染后端

	public static inline var BACKEND_AUTO = "auto";
	public static inline var BACKEND_OPENGL = "opengl";
	public static inline var BACKEND_D3D11 = "opengles";
	public static inline var BACKEND_SOFTWARE = "software";

	/** 选项循环顺序。 */
	public static final RENDER_ORDER:Array<String> = [BACKEND_AUTO, BACKEND_OPENGL, BACKEND_D3D11, BACKEND_SOFTWARE];

	// ================================================================= 动态模糊

	public static function getBlurLevel():Int
	{
		var v = FlxG.save.data.kfeMotionBlur;
		if (v == null) return BLUR_OFF;
		var i = Std.int(v);
		if (i < 0 || i > BLUR_MAX) i = BLUR_OFF;
		return i;
	}

	public static function setBlurLevel(level:Int):Void
	{
		if (level < 0 || level > BLUR_MAX) level = BLUR_OFF;
		FlxG.save.data.kfeMotionBlur = level;
	}

	public static function blurLevelName(level:Int):String
	{
		if (level < 0 || level >= BLUR_NAMES.length) return BLUR_NAMES[0];
		return BLUR_NAMES[level];
	}

	/**
	 * 把模糊 filter 挂到给定相机上。
	 *
	 * ⚠️ 这里不能「读出旧 filter 再把我们的追加进去」——那种写法看起来很
	 * 讲究（保留别人的 filter），但它**编译不过**：flixel 4.9 的 `FlxCamera`
	 * 根本没有公开的 `filters` 读接口。
	 *
	 * 取证（`reference/flixel/FlxCamera.hx`，flixel @ 4.9.0）：
	 *   :419  `/** Internal, the filters array to be applied to the camera. *␣/`
	 *   :421  `var _filters:Array<BitmapFilter>;`        ← private，无访问器
	 *   :305  `public var filtersEnabled:Bool = true;`   ← 只有这个是可读的
	 *   :1496 `public function setFilters(filters) { _filters = filters; ... }`
	 * 也就是说 `setFilters()` 是**替换**语义、`_filters` 读不到。
	 *
	 * 所以改成自己记账（`blurAttachedTo`）。`setFilters` 的替换语义顺带
	 * 保证了幂等：反复调用只会重建数组，不会像 `addFilter` 那样堆叠。
	 *
	 * 关于「会不会踹掉别人的 filter」：会的，但 KE 里撞不上 ——
	 * `ModchartState.hx` 只往 `camNotes` / `camSustains` 挂 wiggle，
	 * 我们只挂 `camGame`，两台相机。这一点在文档里写明了，不藏着。
	 */
	public static function applyBlurTo(cam:FlxCamera):Void
	{
		if (cam == null) return;

		var level = getBlurLevel();

		if (level <= BLUR_OFF)
		{
			// 只有确实挂过才去清，否则会把别人挂在这台相机上的 filter 一起抹掉。
			if (hasBlurOn(cam))
			{
				cam.setFilters([]);
				blurAttachedTo.remove(cam);
			}
			return;
		}

		if (blurShader == null) blurShader = new KFEBlurShader();

		var cfg = BLUR_TABLE[level];
		blurShader.uStrength.value = [cfg[0]];
		blurShader.uSamples.value = [cfg[1]];
		blurShader.uCenter.value = [0.5, 0.5];
		blurShader.uAspect.value = [aspect()];

		cam.setFilters([new ShaderFilter(blurShader)]);
		if (!hasBlurOn(cam)) blurAttachedTo.push(cam);
	}

	/** 当前是否已经挂着我们的模糊 filter。 */
	public static function blurIsAttached(cam:FlxCamera):Bool
	{
		return hasBlurOn(cam);
	}

	/**
	 * 登记一台需要受画质选项管理的相机，并立刻套用当前设置。
	 *
	 * 为什么是「登记」而不是直接去摸 `PlayState.instance.camGame`：
	 * `camGame` 在 PlayState 里是 private（`PlayState.hx:204 private var
	 * camGame:FlxCamera;`），跨类访问编译不过；为了这一个调用去改它的
	 * 可见性，动静比收益大。改成由 PlayState 自己在 create() 里登记，
	 * 那边一行就够，而且天然只在「游戏真的在跑」时才登记。
	 */
	public static function registerCamera(cam:FlxCamera):Void
	{
		if (cam == null) return;
		if (registered.indexOf(cam) < 0) registered.push(cam);
		applyBlurTo(cam);
	}

	/**
	 * 让改动立刻在画面上生效。
	 *
	 * 在主菜单里改的时候一台相机都没登记过，这里自然什么都不做 —— 这是
	 * 对的：选项已经写进 save，进曲时 `PlayState.create()` 会读。
	 *
	 * 顺手回收已经死掉的相机：切歌 / 回菜单会把 camGame 从 FlxG.cameras
	 * 里摘掉，`exists` 变 false。不收的话这个数组会一直攥着死相机的引用，
	 * 每切一首歌漏一台。
	 */
	public static function refreshBlur():Void
	{
		var live:Array<FlxCamera> = [];
		for (cam in registered)
		{
			if (cam == null || !cam.exists) continue;
			live.push(cam);
			applyBlurTo(cam);
		}
		registered = live;
	}

	// 挂过模糊的相机。FlxCamera 不提供 filters 读接口，只能自己记账。
	static var blurAttachedTo:Array<FlxCamera> = [];

	// 由 PlayState 登记进来、需要受画质选项管理的相机。
	static var registered:Array<FlxCamera> = [];

	static function hasBlurOn(cam:FlxCamera):Bool
	{
		return blurAttachedTo.indexOf(cam) >= 0;
	}

	static function aspect():Float
	{
		var w = FlxG.width <= 0 ? 1.0 : FlxG.width;
		var h = FlxG.height <= 0 ? 1.0 : FlxG.height;
		return w / h;
	}

	// ================================================================ 渲染后端

	public static function getRenderBackend():String
	{
		var v = FlxG.save.data.kfeRenderBackend;
		if (v == null) return BACKEND_AUTO;
		return Std.string(v);
	}

	public static function setRenderBackend(v:String):Void
	{
		FlxG.save.data.kfeRenderBackend = v;
	}

	public static function backendLabel(v:String):String
	{
		switch (v)
		{
			case BACKEND_OPENGL: return "OpenGL";
			case BACKEND_D3D11: return "Direct3D 11 (via ANGLE)";
			case BACKEND_SOFTWARE: return "Software (no GPU)";
			default: return "Auto";
		}
	}

	/**
	 * 把选项翻译成 lime 认识的启动参数。
	 *
	 * 参数名逐条对照 `src/lime/system/System.hx:466-513` 的 switch。
	 * 注意 System.hx:524 的 `__parseBool` 是 `value == "true"` ——
	 * **严格匹配小写 true**，写 "True" / "1" 都当 false。
	 */
	public static function buildRenderArgs():Array<String>
	{
		var out:Array<String> = [];
		switch (getRenderBackend())
		{
			case BACKEND_OPENGL:
				out.push("--window-render-type=opengl");
			case BACKEND_D3D11:
				out.push("--window-render-type=opengles");
			case BACKEND_SOFTWARE:
				out.push("--window-hardware=false");
			default:
				// AUTO：一个参数都不传，让 Project.xml 的 <window ...> 说了算。
		}
		return out;
	}

	/**
	 * 读**当前进程实际**用着的后端。
	 *
	 * 这是全套里最诚实的一个函数：不猜、不推理，直接问 Lime
	 * （`RenderContext.type:RenderContextType`，见
	 * `src/lime/graphics/RenderContext.hx`）。选项 UI 把它显示出来，
	 * 用户可以自己核对「我选的」和「实际跑的」是不是一回事。
	 */
	public static function getActiveRenderBackend():String
	{
		#if desktop
		try
		{
			var app = lime.app.Application.current;
			if (app != null && app.window != null && app.window.context != null)
			{
				var t = app.window.context.type;
				if (t != null && Std.string(t).length > 0) return Std.string(t);
			}
		}
		catch (e:Dynamic) {}
		#end
		return "unknown";
	}

	/**
	 * 用当前的画质设置重启进程。
	 *
	 * 后端是启动期的，所以只能重启。做法：把自身 exe 重新拉起来，
	 * 参数 = 原有参数（剔除旧的渲染参数）+ 新渲染参数。
	 *
	 * `Sys.programPath()` 在 hxcpp 下是 exe 全路径；工作目录要先
	 * `setCwd` 到 exe 所在目录，否则打包后的程序在新进程里会找不到
	 * `assets/` 而白屏。
	 */
	public static function restartWithGraphicsArgs():Bool
	{
		#if sys
		try
		{
			var exe = Sys.programPath();
			if (exe == null || exe.length == 0) return false;

			var args:Array<String> = [];
			for (a in Sys.args())
			{
				if (a == null) continue;
				if (StringTools.startsWith(a, "--window-render-type=")) continue;
				if (StringTools.startsWith(a, "--window-renderer=")) continue;
				if (StringTools.startsWith(a, "--window-hardware=")) continue;
				args.push(a);
			}
			for (extra in buildRenderArgs()) args.push(extra);

			var dir = haxe.io.Path.directory(exe);
			if (dir != null && dir.length > 0) Sys.setCwd(dir);

			// 先把设置落盘，否则重启后读到的还是旧值。
			FlxG.save.flush();

			new sys.io.Process(exe, args);
			Sys.exit(0);
			return true;
		}
		catch (e:Dynamic) {}
		#end
		return false;
	}
}

/**
 * 动态模糊强度。左右循环 4 档，**即时生效**（纯 shader，不涉及后端）。
 */
class KFEMotionBlurOption extends Option
{
	public function new(desc:String)
	{
		super();
		description = desc;
	}

	function cycle(dir:Int):Void
	{
		var l = (KFEGraphics.getBlurLevel() + dir + 4) % 4;
		KFEGraphics.setBlurLevel(l);
		KFEGraphics.refreshBlur();
		display = updateDisplay();
	}

	public override function left():Bool
	{
		cycle(-1);
		return true;
	}

	public override function right():Bool
	{
		cycle(1);
		return true;
	}

	private override function updateDisplay():String
	{
		return "Motion Blur: < " + KFEGraphics.blurLevelName(KFEGraphics.getBlurLevel()) + " >";
	}
}

/**
 * 渲染后端。需要重启才能生效。
 *
 * UI 会同时显示「你选的」和「当前进程实际在跑的」，两者不一致时一眼可见。
 */
class KFERenderBackendOption extends Option
{
	public function new(desc:String)
	{
		super();
		if (OptionsMenu.isInPause)
			description = "This option cannot be changed in the pause menu.";
		else
			description = desc;
	}

	public override function left():Bool
	{
		cycle(-1);
		return true;
	}

	public override function right():Bool
	{
		cycle(1);
		return true;
	}

	function cycle(dir:Int):Void
	{
		var cur = KFEGraphics.getRenderBackend();
		var i = KFEGraphics.RENDER_ORDER.indexOf(cur);
		if (i < 0) i = 0;
		i = (i + dir + KFEGraphics.RENDER_ORDER.length) % KFEGraphics.RENDER_ORDER.length;
		KFEGraphics.setRenderBackend(KFEGraphics.RENDER_ORDER[i]);
		FlxG.save.flush();
		display = updateDisplay();
	}

	/** 按一下就用新设置重启进程（描述里已写明，不是暗搓搓的行为）。 */
	public override function press():Bool
	{
		if (OptionsMenu.isInPause) return false;
		if (!KFEGraphics.restartWithGraphicsArgs())
		{
			display = "Renderer: restart failed - close and reopen the game manually";
		}
		return true;
	}

	private override function updateDisplay():String
	{
		return "Renderer: < " + KFEGraphics.backendLabel(KFEGraphics.getRenderBackend())
			+ " >  running: " + KFEGraphics.getActiveRenderBackend();
	}
}
