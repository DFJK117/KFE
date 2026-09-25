// KFE — KadeFuck Engine · 多方言兼容层
// 目标引擎：Kade Engine 1.8（source/ 目录，默认包，与其它 KE 类同级）
//
// 本文件**只放纯逻辑**，不调用 Lua_helper。
// 原因：ModchartState.hx 里 Lua_helper 能用，但它的 Haxe 模块路径（llua? 根包?）
// 无法从工程内确定 ——KE 1.8 的 source/import.hx 只 `import Paths;`，
// ModchartState.hx 也没有 import 它。为了不引入编译期风险，
// Lua_helper.add_callback(...) 的调用一律由 apply_kfe_patch.py 注入到
// ModchartState.hx 的 new() 里（那里已被证明可用）。
//
// 覆盖方言：
//   KE 1.5 / 1.5.1 / 1.5.2 / 1.5.3 / 1.5.4 / 1.6 / 1.6.1 / 1.6.2   平铺 API
//   KE 1.7 / 1.8                                                    对象式（原生）
//   Andromeda Engine Legacy (LE)                                    对象式（异名）

package;

#if FEATURE_LUAMODCHART
import llua.Lua;
import llua.State;
#end

import sys.FileSystem;
import flixel.FlxG;

class KFECompat
{
#if FEATURE_LUAMODCHART

	//=========================================================================
	// 1. modchart 路径候选
	//=========================================================================
	//
	// 各引擎的加载路径（实测，见 docs/01_版本矩阵.md）:
	//   KE 1.5 ~ 1.6.2 : assets/data/<song>.lua            Paths.lua(song)
	//   KE 1.7 / 1.8   : assets/data/songs/<songId>/modchart.lua
	//   LE             : assets/data/songs/<chartName.toLowerCase()>/modchart.lua
	//   SM 模式         : <pathToSm>/modchart.lua
	//
	// Paths.lua(key) 内部是 getPath('data/$key.lua')，会自己补 .lua。
	// 所以传 'songs/X/modchart' 是正确用法；裸路径要自己带 .lua。

	public static function modchartCandidates():Array<String>
	{
		var out:Array<String> = [];
		var raw:String = PlayState.SONG.songId;
		var lower:String = StringTools.replace(raw, " ", "-").toLowerCase();

		// KE 上游的历史别名（ModchartState.hx:413-422 原样保留）
		var special:String = lower;
		switch (special)
		{
			case 'dad-battle': special = 'dadbattle';
			case 'philly-nice': special = 'philly';
			case 'm.i.l.f': special = 'milf';
		}

		var seen:Map<String, Bool> = [];

		function push(p:String)
		{
			if (p == null || p == "" || seen.exists(p))
				return;
			seen.set(p, true);
			out.push(p);
		}

		// ① KE 1.7/1.8 原生（songId 原样）—— 优先级最高，保证原 1.8 模组行为不变
		push(Paths.lua('songs/$raw/modchart'));

		// ② LE：chartName 小写。KE 的 SongData 不一定有 chartName 字段，用 Reflect 兜底
		if (PlayState.SONG != null && Reflect.hasField(PlayState.SONG, 'chartName'))
		{
			var cn:String = Std.string(Reflect.field(PlayState.SONG, 'chartName'));
			if (cn != null && cn != "")
				push(Paths.lua('songs/${cn.toLowerCase()}/modchart'));
		}

		// ③ 空格转横杠 + 小写
		push(Paths.lua('songs/$lower/modchart'));

		// ④ 上游历史别名
		push(Paths.lua('songs/$special/modchart'));

		// ⑤ 老式：assets/data/<songId>/modchart.lua（某些 KE 分支）
		push(Paths.lua('$raw/modchart'));
		push(Paths.lua('$lower/modchart'));

		// ⑥ SM 模式
		if (PlayState.isSM && PlayState.pathToSm != null)
			push(PlayState.pathToSm + "/modchart.lua");

		return out;
	}

	/** 返回第一个真实存在的 modchart 路径；都不存在返回 null。 */
	public static function findModchartPath():String
	{
		for (p in modchartCandidates())
		{
			if (p != null && FileSystem.exists(p))
				return p;
		}
		return null;
	}

	/** 有没有任何一个候选路径存在（PlayState 判 executeModchart 用）。 */
	public static function hasModchart():Bool
	{
		return findModchartPath() != null;
	}

	//=========================================================================
	// 2. hook 名扇出表
	//=========================================================================
	//
	// 一次引擎事件 → 扇出到所有方言的对应 hook 名。
	// 安全前提：ModchartState.callLua() 里对缺失的全局走
	//   Lua.pcall → 报 "attempt to call a nil value" → 被静默吞掉
	//   （见 reference/ke18/ModchartState.hx:52）
	// 所以"多调几个不存在的名字"是零成本的。
	//
	// 调用方必须在扇出前后自己平衡 Lua 栈：callLua 每次会留 1 个值不弹。
	// 见 patchedExecuteState()。

	public static var HOOK_ALIASES:Map<String, Array<String>> = [
		// KE 1.8 原生名              → 别名（LE / Psych / 1.5.x）
		"start"         => ["start", "create", "onCreate"],
		"songStart"     => ["songStart", "onSongStart"],
		"update"        => ["update", "onUpdate"],
		"stepHit"       => ["stepHit", "onStepHit"],
		"beatHit"       => ["beatHit", "onBeatHit"],
		"keyPressed"    => ["keyPressed", "onKeyPress"],
		"keyReleased"   => ["keyReleased", "onKeyRelease"],
		"playerOneSing" => ["playerOneSing", "goodNoteHit", "bfNoteHit"],
		"playerTwoSing" => ["playerTwoSing", "dadNoteHit"],
		"playerOneMiss" => ["playerOneMiss", "doMiss", "bfNoteMiss"],
		"playerTwoMiss" => ["playerTwoMiss", "dadNoteMiss"],
		"playerOneTurn" => ["playerOneTurn"],
		"playerTwoTurn" => ["playerTwoTurn"],
		// KE 1.8 没有、但 LE 有的 —— 需要 PlayState 侧新增触发点
		"countdown"     => ["countdown", "startCountdown", "onCountdownTick"],
		"doEvent"       => ["doEvent", "onEvent"],
		"hitMine"       => ["hitMine"],
		// KFE 内部：警告音符被打中
		"kfeWarnHit"    => ["kfeWarnHit", "healthDrain"]
	];

	public static function hookAliases(name:String):Array<String>
	{
		if (HOOK_ALIASES.exists(name))
			return HOOK_ALIASES.get(name);
		return [name];
	}

	//=========================================================================
	// 3. 一个对象注册成多个全局名
	//=========================================================================
	//
	// LuaClass.Register(l) 会把对象表挂在 className 这个全局名下，
	// 并给它挂上以 className + "Metatable" 命名的元表（属性读写都走它）。
	// 只要把**同一张表**再挂到别的全局名下，别名就自然共享全部属性和方法。
	//
	// obj 用 Dynamic：避免为了一个类型名去 import LuaClass.LuaClass
	// （module 名与 type 名同名，容易踩 Haxe 的模块解析坑）。

	public static function registerAliased(obj:Dynamic, l:State, names:Array<String>):Void
	{
		if (obj == null || l == null || names == null || names.length == 0)
			return;

		var primary:String = names[0];
		var saved:String = obj.className;
		obj.className = primary;
		obj.Register(l);
		obj.className = saved;

		// 把主名对应的表复制到其余别名的全局槽
		Lua.getglobal(l, primary);
		var i:Int = 1;
		while (i < names.length)
		{
			Lua.pushvalue(l, -1);
			Lua.setglobal(l, names[i]);
			i++;
		}
		Lua.pop(l, 1);
	}

	//=========================================================================
	// 4. 判定线 / 相机的双方言名字
	//=========================================================================
	//
	// PlayState.strumLineNotes 顺序是 [对手 0..3][玩家 4..7]（vanilla FNF 惯例）。
	// LE 的注册点是 PlayState.hx:464/468，dirs = [left, down, up, right]：
	//   对手 → '${dir}DadNote'，玩家 → '${dir}PlrNote'
	// 与 KE 的 receptor_0..7 指向的是同一批对象，于是别名成对注册。

	public static var DIRS:Array<String> = ["left", "down", "up", "right"];

	public static function receptorAliases(i:Int):Array<String>
	{
		var out:Array<String> = ["receptor_$i"];
		var dir:String = DIRS[i % 4];
		// 前 4 条是对手线，后 4 条是玩家线
		out.push(i < 4 ? '${dir}DadNote' : '${dir}PlrNote');
		return out;
	}

	public static function characterAliases(luaName:String):Array<String>
	{
		switch (luaName)
		{
			case "boyfriend": return ["boyfriend", "bf"]; // LE 叫 bf
			default:          return [luaName];
		}
	}

	public static function cameraAliases(camName:String, actual:String):Array<String>
	{
		switch (camName)
		{
			case "camGame":     return ["camGame", "gameCam"];
			case "camHUD":      return ["camHUD", "HUDCam"];
			case "camSustains": return ["camSustains", "holdCam"];
			case "camNotes":    return ["camNotes", "notesCam"];
			// KE 1.8 没有独立的 receptorCam 对象，用 camHUD 顶替（LE 里它也是 HUD 相机）
			case "camReceptor": return ["receptorCam"];
			default:            return [camName];
		}
	}

	//=========================================================================
	// 5. 存档开关读取（对应原版 FlxG.save.data.xxx）
	//=========================================================================

	/**
	 * 读存档里的选项，给 Lua 的 getOption(name) 用。
	 *
	 * **注意 Bob's Onslaught 的反语义**（reference/bobsrc/Options.hx:147/154, 185/192）：
	 *     存: FlxG.save.data.jumpscare = !FlxG.save.data.jumpscare;
	 *     显示: return "jumpscare " + (!FlxG.save.data.jumpscare ? "on" : "off");
	 * 所以存下来的布尔含义是「关」：false = 选项 on（默认开启）。
	 * 脚本里的 `!save.data.X` 直译成 `not getOption("X")` 即可，不要自作聪明去"纠正"。
	 *
	 * 返回的是**原始存档值**（Bool 就返回 Bool），不做任何取反。
	 * 未知名字走 default 分支按存档字段名直读；不存在则返回 null，
	 * 脚本侧约定 null 视为默认（= 允许）。
	 */
	public static function getSaveOption(name:String):Dynamic
	{
		if (FlxG.save == null || FlxG.save.data == null)
			return null;
		var data:Dynamic = FlxG.save.data;
		switch (name)
		{
			case "shakingscreen": return Reflect.hasField(data, 'shakingscreen') ? Reflect.field(data, 'shakingscreen') : false;
			case "jumpscare":     return Reflect.hasField(data, 'jumpscare') ? Reflect.field(data, 'jumpscare') : false;
			case "happybob":      return Reflect.hasField(data, 'happybob') ? Reflect.field(data, 'happybob') : false;
			case "downscroll":    return data.downscroll;
			case "flashing":      return data.flashing;
			case "distractions":  return data.distractions;
			default:
				return Reflect.hasField(data, name) ? Reflect.field(data, name) : null;
		}
	}

#end
}
