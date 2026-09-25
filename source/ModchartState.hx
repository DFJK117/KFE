// this file is for modchart things, this is to declutter playstate.hx
// Lua
#if FEATURE_LUAMODCHART
import LuaClass.LuaGame;
import LuaClass.LuaWindow;
import LuaClass.LuaSprite;
import LuaClass.LuaCamera;
import LuaClass.LuaReceptor;
import openfl.display3D.textures.VideoTexture;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.tweens.FlxEase;
import openfl.filters.ShaderFilter;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import openfl.geom.Matrix;
import openfl.display.BitmapData;
import lime.app.Application;
import flixel.FlxSprite;
import llua.Convert;
import llua.Lua;
import llua.State;
import llua.LuaL;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;

class ModchartState
{
	// public static var shaders:Array<LuaShader> = null;
	public static var lua:State = null;

	// ===== KFE: 音效句柄表（stopSound 需要它）=====
	public static var kfeSounds:Map<String, FlxSound> = [];

	// ===== KFE: 往 unspawnNotes 注入警告音符 =====
	// 等价实现原 Bob's Onslaught 的 PlayState.hx:1801-1850。
	// 原版用 new Note(t, data, null, false, _warning, _mustHitNotes)；
	// KE 1.8 的 Note 没这两个参数，所以 KFE 在 Note.hx 上加了 kfeWarning/kfeFake 字段。
	public function kfePushWarnNote(strumTime:Float, noteData:Int, isWarning:Bool):Void
	{
		if (PlayState.instance == null)
			return;

		var n:Note = new Note(strumTime, noteData, null, false);
		n.kfeWarning = isWarning;
		n.kfeFake = !isWarning;
		n.scrollFactor.set(0, 0);
		n.mustPress = true;
		n.x += FlxG.width / 2;
		n.setKfeWarningGraphic();

		PlayState.instance.unspawnNotes.push(n);
		// generateSong 里已经排过一次序，追加之后必须重排，
		// 否则 PlayState 按 unspawnNotes[0] 推进时会漏掉后面的音符。
		PlayState.instance.unspawnNotes.sort(function(a:Note, b:Note):Int
		{
			if (a.strumTime < b.strumTime) return -1;
			if (a.strumTime > b.strumTime) return 1;
			return 0;
		});
	}

	// ===== KFE: 走 Paths.image() 的精灵加载（原版 makeSprite 只认 song 目录）=====
	// 原版: BitmapData.fromFile(cwd + "assets/data/songs/" + songId + "/" + path + ".png")
	//   → 模组图集在 assets/shared/images/ 下，原版根本找不到。
	public function kfeMakeSpriteEx(spritePath:String, toBeCalled:String, drawBehind:Bool = false):Void
	{
		if (PlayState.instance == null)
			return;

		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(Paths.image(spritePath));
		sprite.updateHitbox();
		luaSprites.set(toBeCalled, sprite);

		@:privateAccess
		{
			if (drawBehind)
			{
				PlayState.instance.removeObject(PlayState.gf);
				PlayState.instance.removeObject(PlayState.boyfriend);
				PlayState.instance.removeObject(PlayState.dad);
			}
			PlayState.instance.addObject(sprite);
			if (drawBehind)
			{
				PlayState.instance.addObject(PlayState.gf);
				PlayState.instance.addObject(PlayState.boyfriend);
				PlayState.instance.addObject(PlayState.dad);
			}
		}

		new LuaSprite(sprite, toBeCalled).Register(lua);
	}

	function callLua(func_name:String, args:Array<Dynamic>, ?type:String):Dynamic
	{
		var result:Any = null;

		Lua.getglobal(lua, func_name);

		for (arg in args)
		{
			Convert.toLua(lua, arg);
		}

		result = Lua.pcall(lua, args.length, 1, 0);
		var p = Lua.tostring(lua, result);
		var e = getLuaErrorMessage(lua);

		Lua.tostring(lua, -1);

		if (e != null)
		{
			if (e != "attempt to call a nil value")
			{
				trace(StringTools.replace(e, "c++", "haxe function"));
			}
		}
		if (result == null)
		{
			return null;
		}
		else
		{
			return convert(result, type);
		}
	}

	static function toLua(l:State, val:Any):Bool
	{
		switch (Type.typeof(val))
		{
			case Type.ValueType.TNull:
				Lua.pushnil(l);
			case Type.ValueType.TBool:
				Lua.pushboolean(l, val);
			case Type.ValueType.TInt:
				Lua.pushinteger(l, cast(val, Int));
			case Type.ValueType.TFloat:
				Lua.pushnumber(l, val);
			case Type.ValueType.TClass(String):
				Lua.pushstring(l, cast(val, String));
			case Type.ValueType.TClass(Array):
				Convert.arrayToLua(l, val);
			case Type.ValueType.TObject:
				objectToLua(l, val);
			default:
				trace("haxe value not supported - " + val + " which is a type of " + Type.typeof(val));
				return false;
		}

		return true;
	}

	static function objectToLua(l:State, res:Any)
	{
		var FUCK = 0;
		for (n in Reflect.fields(res))
		{
			trace(Type.typeof(n).getName());
			FUCK++;
		}

		Lua.createtable(l, FUCK, 0); // TODONE: I did it

		for (n in Reflect.fields(res))
		{
			if (!Reflect.isObject(n))
				continue;
			Lua.pushstring(l, n);
			toLua(l, Reflect.field(res, n));
			Lua.settable(l, -3);
		}
	}

	function getType(l, type):Any
	{
		return switch Lua.type(l, type)
		{
			case t if (t == Lua.LUA_TNIL): null;
			case t if (t == Lua.LUA_TNUMBER): Lua.tonumber(l, type);
			case t if (t == Lua.LUA_TSTRING): (Lua.tostring(l, type) : String);
			case t if (t == Lua.LUA_TBOOLEAN): Lua.toboolean(l, type);
			case t: throw 'you don goofed up. lua type error ($t)';
		}
	}

	function getReturnValues(l)
	{
		var lua_v:Int;
		var v:Any = null;
		while ((lua_v = Lua.gettop(l)) != 0)
		{
			var type:String = getType(l, lua_v);
			v = convert(lua_v, type);
			Lua.pop(l, 1);
		}
		return v;
	}

	private function convert(v:Any, type:String):Dynamic
	{ // I didn't write this lol
		if (Std.is(v, String) && type != null)
		{
			var v:String = v;
			if (type.substr(0, 4) == 'array')
			{
				if (type.substr(4) == 'float')
				{
					var array:Array<String> = v.split(',');
					var array2:Array<Float> = new Array();

					for (vars in array)
					{
						array2.push(Std.parseFloat(vars));
					}

					return array2;
				}
				else if (type.substr(4) == 'int')
				{
					var array:Array<String> = v.split(',');
					var array2:Array<Int> = new Array();

					for (vars in array)
					{
						array2.push(Std.parseInt(vars));
					}

					return array2;
				}
				else
				{
					var array:Array<String> = v.split(',');
					return array;
				}
			}
			else if (type == 'float')
			{
				return Std.parseFloat(v);
			}
			else if (type == 'int')
			{
				return Std.parseInt(v);
			}
			else if (type == 'bool')
			{
				if (v == 'true')
				{
					return true;
				}
				else
				{
					return false;
				}
			}
			else
			{
				return v;
			}
		}
		else
		{
			return v;
		}
	}

	function getLuaErrorMessage(l)
	{
		var v:String = Lua.tostring(l, -1);
		Lua.pop(l, 1);
		return v;
	}

	public function setVar(var_name:String, object:Dynamic)
	{
		// trace('setting variable ' + var_name + ' to ' + object);

		// ===== KFE: 类型感知推送 =====
		// 原版这里固定 Lua.pushnumber，导致 Bool 变数字（0 在 Lua 里是真值）、
		// 字符串直接类型不符。改用本文件已有的 toLua()。
		toLua(lua, object);
		Lua.setglobal(lua, var_name);
	}

	public function getVar(var_name:String, type:String):Dynamic
	{
		var result:Any = null;

		// trace('getting variable ' + var_name + ' with a type of ' + type);

		Lua.getglobal(lua, var_name);
		result = Convert.fromLua(lua, -1);
		Lua.pop(lua, 1);

		if (result == null)
		{
			return null;
		}
		else
		{
			var result = convert(result, type);
			// trace(var_name + ' result: ' + result);
			return result;
		}
	}

	function getActorByName(id:String):Dynamic
	{
		// pre defined names
		switch (id)
		{
			case 'boyfriend':
				@:privateAccess
				return PlayState.boyfriend;
			case 'girlfriend':
				@:privateAccess
				return PlayState.gf;
			case 'dad':
				@:privateAccess
				return PlayState.dad;
		}
		// lua objects or what ever
		if (luaSprites.get(id) == null)
		{
			if (Std.parseInt(id) == null)
				return Reflect.getProperty(PlayState.instance, id);
			return PlayState.PlayState.strumLineNotes.members[Std.parseInt(id)];
		}
		return luaSprites.get(id);
	}

	function getPropertyByName(id:String)
	{
		return Reflect.field(PlayState.instance, id);
	}

	public static var luaSprites:Map<String, FlxSprite> = [];

	function changeDadCharacter(id:String)
	{
		var olddadx = PlayState.dad.x;
		var olddady = PlayState.dad.y;
		PlayState.instance.removeObject(PlayState.dad);
		PlayState.dad = new Character(olddadx, olddady, id);
		PlayState.instance.addObject(PlayState.dad);
		PlayState.instance.iconP2.changeIcon(id);
	}

	function changeBoyfriendCharacter(id:String)
	{
		var oldboyfriendx = PlayState.boyfriend.x;
		var oldboyfriendy = PlayState.boyfriend.y;
		PlayState.instance.removeObject(PlayState.boyfriend);
		PlayState.boyfriend = new Boyfriend(oldboyfriendx, oldboyfriendy, id);
		PlayState.instance.addObject(PlayState.boyfriend);
		PlayState.instance.iconP1.changeIcon(id);
	}

	function makeAnimatedLuaSprite(spritePath:String, names:Array<String>, prefixes:Array<String>, startAnim:String, id:String)
	{
		#if FEATURE_FILESYSTEM
		// TODO: Make this use OpenFlAssets.
		var data:BitmapData = BitmapData.fromFile(Sys.getCwd() + "assets/data/songs/" + PlayState.SONG.songId + '/' + spritePath + ".png");

		var sprite:FlxSprite = new FlxSprite(0, 0);

		sprite.frames = FlxAtlasFrames.fromSparrow(FlxGraphic.fromBitmapData(data),
			Sys.getCwd() + "assets/data/songs/" + PlayState.SONG.songId + "/" + spritePath + ".xml");

		trace(sprite.frames.frames.length);

		for (p in 0...names.length)
		{
			var i = names[p];
			var ii = prefixes[p];
			sprite.animation.addByPrefix(i, ii, 24, false);
		}

		luaSprites.set(id, sprite);

		PlayState.instance.addObject(sprite);

		sprite.animation.play(startAnim);
		return id;
		#end
	}

	function makeLuaSprite(spritePath:String, toBeCalled:String, drawBehind:Bool)
	{
		#if FEATURE_FILESYSTEM
		// pre lowercasing the song name (makeLuaSprite)
		var songLowercase = StringTools.replace(PlayState.SONG.songId, " ", "-").toLowerCase();
		switch (songLowercase)
		{
			case 'dad-battle':
				songLowercase = 'dadbattle';
			case 'philly-nice':
				songLowercase = 'philly';
			case 'm.i.l.f':
				songLowercase = 'milf';
		}

		var path = Sys.getCwd() + "assets/data/songs/" + PlayState.SONG.songId + '/';

		if (PlayState.isSM)
			path = PlayState.pathToSm + "/";

		var data:BitmapData = BitmapData.fromFile(path + spritePath + ".png");

		var sprite:FlxSprite = new FlxSprite(0, 0);
		var imgWidth:Float = FlxG.width / data.width;
		var imgHeight:Float = FlxG.height / data.height;
		var scale:Float = imgWidth <= imgHeight ? imgWidth : imgHeight;

		// Cap the scale at x1
		if (scale > 1)
			scale = 1;

		sprite.makeGraphic(Std.int(data.width * scale), Std.int(data.width * scale), FlxColor.TRANSPARENT);

		var data2:BitmapData = sprite.pixels.clone();
		var matrix:Matrix = new Matrix();
		matrix.identity();
		matrix.scale(scale, scale);
		data2.fillRect(data2.rect, FlxColor.TRANSPARENT);
		data2.draw(data, matrix, null, null, null, true);
		sprite.pixels = data2;

		luaSprites.set(toBeCalled, sprite);
		// and I quote:
		// shitty layering but it works!
		@:privateAccess
		{
			if (drawBehind)
			{
				PlayState.instance.removeObject(PlayState.gf);
				PlayState.instance.removeObject(PlayState.boyfriend);
				PlayState.instance.removeObject(PlayState.dad);
			}
			PlayState.instance.addObject(sprite);
			if (drawBehind)
			{
				PlayState.instance.addObject(PlayState.gf);
				PlayState.instance.addObject(PlayState.boyfriend);
				PlayState.instance.addObject(PlayState.dad);
			}
		}
		#end

		new LuaSprite(sprite, toBeCalled).Register(lua);

		return toBeCalled;
	}

	public function die()
	{
		Lua.close(lua);
		lua = null;
	}

	public var luaWiggles:Map<String, WiggleEffect> = new Map<String, WiggleEffect>();

	// LUA SHIT

	function new(?isStoryMode = true)
	{
		trace('opening a lua state (because we are cool :))');
		lua = LuaL.newstate();
		LuaL.openlibs(lua);
		trace("Lua version: " + Lua.version());
		trace("LuaJIT version: " + Lua.versionJIT());
		Lua.init_callbacks(lua);

		// shaders = new Array<LuaShader>();

		// pre lowercasing the song name (new)
		var songLowercase = StringTools.replace(PlayState.SONG.songId, " ", "-").toLowerCase();
		switch (songLowercase)
		{
			case 'dad-battle':
				songLowercase = 'dadbattle';
			case 'philly-nice':
				songLowercase = 'philly';
			case 'm.i.l.f':
				songLowercase = 'milf';
		}

		// ===== KFE: 多方言 modchart 路径候选 =====
		// KE1.8 原生 / LE(chartName.toLowerCase()) / 老式 <song>/modchart / SM 目录
		// 依据: docs/01_版本矩阵.md；实现: KFECompat.modchartCandidates()
		var path:String = KFECompat.findModchartPath();
		if (path == null)
		{
			trace('[KFE] 未找到 modchart，按原版 KE 运行');
			lua = null;
			return;
		}
		trace('[KFE] 加载 modchart: ' + path);

		var result = LuaL.dofile(lua, path);

		if (result != 0)
		{
			var kfeErr:String = Lua.tostring(lua, result);
			trace('[KFE] Lua 错误: ' + kfeErr);
			Application.current.window.alert("LUA COMPILE ERROR:\n" + kfeErr, "Kade Engine Modcharts");
			FlxG.switchState(new FreeplayState());
			return;
		}
			return;
		}

		// get some fukin globals up in here bois

		setVar("difficulty", PlayState.storyDifficulty);
		setVar("bpm", Conductor.bpm);
		setVar("scrollspeed", FlxG.save.data.scrollSpeed != 1 ? FlxG.save.data.scrollSpeed : PlayState.SONG.speed);
		setVar("fpsCap", FlxG.save.data.fpsCap);
		setVar("downscroll", FlxG.save.data.downscroll);
		setVar("flashing", FlxG.save.data.flashing);
		setVar("distractions", FlxG.save.data.distractions);
		setVar("colour", FlxG.save.data.colour);

		setVar("curStep", 0);
		setVar("curBeat", 0);
		setVar("crochet", Conductor.stepCrochet);
		setVar("safeZoneOffset", Conductor.safeZoneOffset);

		setVar("hudZoom", PlayState.instance.camHUD.zoom);
		setVar("cameraZoom", FlxG.camera.zoom);

		setVar("cameraAngle", FlxG.camera.angle);
		setVar("camHudAngle", PlayState.instance.camHUD.angle);

		setVar("followXOffset", 0);
		setVar("followYOffset", 0);

		setVar("showOnlyStrums", false);
		setVar("strumLine1Visible", true);
		setVar("strumLine2Visible", true);

		setVar("screenWidth", FlxG.width);
		setVar("screenHeight", FlxG.height);
		setVar("windowWidth", FlxG.width);
		setVar("windowHeight", FlxG.height);
		setVar("hudWidth", PlayState.instance.camHUD.width);
		setVar("hudHeight", PlayState.instance.camHUD.height);

		setVar("mustHit", false);

		setVar("strumLineY", PlayState.instance.strumLine.y);

		// ===== KFE: 补注入两个脚本必需的全局 =====
		// 原版 KE 1.8 没给 Lua，导致 modchart 无法按舞台/模式分支
		setVar("curStage", Stage.curStage);
		setVar("storyMode", isStoryMode);

		// callbacks

		// ===== KFE 新增回调 =====
		// 原版 KE 1.8 的 Lua 完全无法播声音、无法相机淡入淡出、
		// 也无法把自定义音符塞进 unspawnNotes —— 这三件事 bobcompat 都要用。

		Lua_helper.add_callback(lua, "playSound", function(name:String, ?volume:Float = 1)
		{
			var s:FlxSound = FlxG.sound.play(Paths.sound(name), volume);
			kfeSounds.set(name, s);
		});

		Lua_helper.add_callback(lua, "stopSound", function(name:String)
		{
			if (kfeSounds.exists(name))
			{
				kfeSounds.get(name).stop();
				kfeSounds.remove(name);
			}
		});

		Lua_helper.add_callback(lua, "playMusic", function(name:String, ?volume:Float = 1, ?loop:Bool = false)
		{
			FlxG.sound.playMusic(Paths.music(name), volume, loop);
		});

		Lua_helper.add_callback(lua, "cameraFade", function(color:String, duration:Float, fadeIn:Bool)
		{
			var hex:String = StringTools.replace(color, "#", "");
			var col:Int = 0xFF000000;
			var parsed:Null<Int> = Std.parseInt("0x" + hex);
			if (parsed != null) col = 0xFF000000 | parsed;
			FlxG.camera.fade(col, duration, fadeIn, null, true);
		});

		Lua_helper.add_callback(lua, "pushWarnNote", function(strumTime:Float, noteData:Int, isWarning:Bool)
		{
			kfePushWarnNote(strumTime, noteData, isWarning);
		});

		// 原版 makeSprite 只从 assets/data/songs/<songId>/ 找图（ModchartState.hx:339），
		// 但模组的图在 assets/shared/images/ 下，所以必须另给一个走 Paths.image() 的版本。
		Lua_helper.add_callback(lua, "makeSpriteEx", function(spritePath:String, toBeCalled:String, ?drawBehind:Bool = false)
		{
			kfeMakeSpriteEx(spritePath, toBeCalled, drawBehind);
		});

		Lua_helper.add_callback(lua, "getOption", function(name:String)
		{
			return KFECompat.getSaveOption(name);
		});

		Lua_helper.add_callback(lua, "makeSprite", makeLuaSprite);

		// sprites

		Lua_helper.add_callback(lua, "setNoteWiggle", function(wiggleId)
		{
			PlayState.instance.camNotes.setFilters([new ShaderFilter(luaWiggles.get(wiggleId).shader)]);
		});

		Lua_helper.add_callback(lua, "setSustainWiggle", function(wiggleId)
		{
			PlayState.instance.camSustains.setFilters([new ShaderFilter(luaWiggles.get(wiggleId).shader)]);
		});

		Lua_helper.add_callback(lua, "createWiggle", function(freq:Float, amplitude:Float, speed:Float)
		{
			var wiggle = new WiggleEffect();
			wiggle.waveAmplitude = amplitude;
			wiggle.waveSpeed = speed;
			wiggle.waveFrequency = freq;

			var id = Lambda.count(luaWiggles) + 1 + "";

			luaWiggles.set(id, wiggle);
			return id;
		});

		Lua_helper.add_callback(lua, "setWiggleTime", function(wiggleId:String, time:Float)
		{
			var wiggle = luaWiggles.get(wiggleId);

			wiggle.shader.uTime.value = [time];
		});

		Lua_helper.add_callback(lua, "setWiggleAmplitude", function(wiggleId:String, amp:Float)
		{
			var wiggle = luaWiggles.get(wiggleId);

			wiggle.waveAmplitude = amp;
		});

		Lua_helper.add_callback(lua, "setStrumlineY", function(y:Float)
		{
			PlayState.instance.strumLine.y = y;
		});

		Lua_helper.add_callback(lua, "getNumberOfNotes", function(y:Float)
		{
			return PlayState.instance.notes.members.length;
		});

		for (i in 0...PlayState.strumLineNotes.length)
		{
			var member = PlayState.strumLineNotes.members[i];
		// ===== KFE: 判定线双方言命名 =====
		// KE 叫什么都能对上: receptor_0..7  ←→  leftDadNote/leftPlrNote...
		// 依据: LE/PlayState.hx:464/468 的注册点
		for (i in 0...PlayState.strumLineNotes.length)
		{
			var member = PlayState.strumLineNotes.members[i];
			KFECompat.registerAliased(new LuaReceptor(member, "receptor_" + i), lua,
				KFECompat.receptorAliases(i));
		}

		new LuaGame().Register(lua);

		new LuaWindow().Register(lua);
	}

	// ===== KFE: 一次引擎事件扇出到所有方言的 hook 名 =====
	// 安全前提: callLua 对缺失的全局会拿到 "attempt to call a nil value"
	// 并被静默吞掉，所以多调几个不存在的名字零成本。
	// 但 callLua 每次会在栈上留 1 个值不弹，这里必须补上，
	// 否则一整首歌累积下来会撞 Lua 栈上限。
	// 例: start↔create、playerTwoSing↔dadNoteHit、playerOneMiss↔doMiss
	public function executeState(name, args:Array<Dynamic>)
	{
		if (lua == null)
			return null;

		var kfeTop:Int = Lua.gettop(lua);
		var kfeRet:Dynamic = null;
		for (h in KFECompat.hookAliases(name))
		{
			kfeRet = Lua.tostring(lua, callLua(h, args));
			var kfeNow:Int = Lua.gettop(lua);
			if (kfeNow > kfeTop)
				Lua.pop(lua, kfeNow - kfeTop);
		}
		return kfeRet;
	}

	public static function createModchartState(?isStoryMode = true):ModchartState
	{
		return new ModchartState(isStoryMode);
	}
}
#end
