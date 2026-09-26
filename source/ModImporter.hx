package;

#if FEATURE_MODCORE
import haxe.zip.Reader;
import haxe.zip.Entry;
import haxe.io.BytesInput;
import haxe.io.Bytes;
import sys.io.File;
import sys.FileSystem;
import lime.system.System;

/**
 * KFE 模组包导入器。
 *
 * 负责识别并"打开"三种 KFE 专属文件：
 *   - .kfemod  模组（Mod）
 *   - .kfepack 材质包 / 皮肤包（Pack）
 *   - .kfeds   双合一（Dual = 同时是模组 + 材质包）
 *
 * 文件格式（由 KFE 定义）：一个标准的 ZIP 压缩包，根目录放一个 `kfe.json` 清单：
 *   {
 *     "type": "mod" | "pack" | "dual",
 *     "id":   "唯一标识，用作解压后的文件夹名",
 *     "title": "显示名（可选）",
 *     "version": "1.0.0（可选）",
 *     "description": "说明（可选）"
 *   }
 *
 * 解压落盘规则：
 *   - type = "mod"  或 "dual"  -> 解压到 <base>/mods/<id>/
 *   - type = "pack" 或 "dual"  -> 解压到 <base>/packs/<id>/
 * Polymod 会把 mods/* 与 packs/* 都当成资源覆盖层加载。
 *
 * 使用方式：
 *   1) 把 .kfemod/.kfepack/.kfeds 丢进"收件箱"目录，KFE 启动时自动导入；
 *      - 桌面端：可执行文件同级的 ./inbox
 *      - Android：应用私有存储（applicationStorageDirectory）/inbox
 *   2) 调试控制台执行 importkfe <文件路径> 手动导入单个文件。
 */
class ModImporter
{
	/** 清单文件名，必须位于压缩包根目录。 */
	public static final MANIFEST_NAME = "kfe.json";

	public static final EXT_MOD = ".kfemod";
	public static final EXT_PACK = ".kfepack";
	public static final EXT_DUAL = ".kfeds";

	/**
	 * 返回同时包含 mods/ 与 packs/ 的父目录。
	 * 桌面端用当前工作目录（即可执行文件同级）；
	 * Android 用应用私有存储，保证可读写且不被 APK 覆盖。
	 */
	public static function baseDir():String
	{
		#if android
		return System.applicationStorageDirectory;
		#else
		return ".";
		#end
	}

	public static function modsDir():String
	{
		return baseDir() + "/mods";
	}

	public static function packsDir():String
	{
		return baseDir() + "/packs";
	}

	public static function inboxDir():String
	{
		return baseDir() + "/inbox";
	}

	/**
	 * 扫描收件箱目录，把三种 KFE 文件全部导入一次。
	 * 在 ModCore.initialize() 里于加载模组之前调用。
	 */
	public static function scanAndImport():Void
	{
		var inbox = inboxDir();
		if (!FileSystem.exists(inbox) || !FileSystem.isDirectory(inbox))
		{
			Debug.logInfo('[ModImporter] 收件箱不存在：$inbox，跳过自动导入。');
			return;
		}

		var files:Array<String> = FileSystem.readDirectory(inbox);
		var imported = 0;
		for (f in files)
		{
			var full = inbox + "/" + f;
			if (FileSystem.isDirectory(full))
				continue;

			if (StringTools.endsWith(f, EXT_MOD)
				|| StringTools.endsWith(f, EXT_PACK)
				|| StringTools.endsWith(f, EXT_DUAL))
			{
				var r = importFile(full);
				if (r.ok)
					imported++;
			}
		}
		Debug.logInfo('[ModImporter] 收件箱自动导入完成，本次成功 $imported 个。');
	}

	/**
	 * 导入单个 KFE 包文件。成功返回 ok=true，失败在 error 里说明原因。
	 */
	public static function importFile(path:String):ImportResult
	{
		var result = new ImportResult(path);
		Debug.logInfo('[ModImporter] 正在导入：$path');

		if (!FileSystem.exists(path))
		{
			result.error = '文件不存在：$path';
			Debug.logError(result.error);
			return result;
		}

		var bytes:Bytes;
		try
		{
			bytes = File.getBytes(path);
		}
		catch (e:Dynamic)
		{
			result.error = '无法读取文件：$e';
			Debug.logError(result.error);
			return result;
		}

		var entries:List<haxe.zip.Entry> = tryReadZip(bytes, result);
		if (entries == null)
			return result;

		// 找到清单文件（兼容 "./kfe.json" 这种带点的写法）
		var manifestEntry:Entry = null;
		for (e in entries)
		{
			if (e.fileName == MANIFEST_NAME || StringTools.endsWith(e.fileName, "/" + MANIFEST_NAME))
			{
				manifestEntry = e;
				break;
			}
		}
		if (manifestEntry == null)
		{
			result.error = '压缩包里缺少 $MANIFEST_NAME 清单，不是合法的 KFE 包。';
			Debug.logError(result.error);
			return result;
		}

		var type:String;
		var id:String;
		try
		{
			var json:Dynamic = haxe.Json.parse(Reader.unzip(manifestEntry).toString());
			type = json.type;
			id = json.id;
		}
		catch (e:Dynamic)
		{
			result.error = '清单解析失败：$e';
			Debug.logError(result.error);
			return result;
		}

		if (type != "mod" && type != "pack" && type != "dual")
		{
			result.error = '未知的包类型 "$type"（应为 mod / pack / dual）。';
			Debug.logError(result.error);
			return result;
		}
		if (id == null || id == "")
		{
			// 没有 id 就用文件名兜底，并把空格换成下划线
			id = StringTools.replace(haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path)), " ", "_");
		}

		// 决定解压目的地
		var dests:Array<String> = [];
		if (type == "mod" || type == "dual")
			dests.push(modsDir() + "/" + id);
		if (type == "pack" || type == "dual")
			dests.push(packsDir() + "/" + id);

		for (dest in dests)
		{
			ensureDir(dest);
			extractEntries(entries, dest);
		}

		result.ok = true;
		result.type = type;
		result.id = id;
		result.dests = dests;
		Debug.logInfo('[ModImporter] 导入成功："$id"（$type）-> ${dests.join(", ")}');

		// 把已导入的包移出收件箱，避免下次重复导入（保留副本备查）
		try
		{
			var done = inboxDir() + "/.imported_" + haxe.io.Path.withoutDirectory(path);
			if (FileSystem.exists(done))
				FileSystem.deleteFile(done);
			FileSystem.rename(path, done);
		}
		catch (e:Dynamic)
		{
			Debug.logWarn('[ModImporter] 无法把已导入的包移出收件箱：$e');
		}

		return result;
	}

	static function tryReadZip(bytes:Bytes, result:ImportResult):List<haxe.zip.Entry>
	{
		try
		{
			var reader = new Reader(new BytesInput(bytes));
			return reader.read();
		}
		catch (e:Dynamic)
		{
			result.error = '不是合法的 ZIP / KFE 包（解压失败）：$e';
			Debug.logError(result.error);
			return null;
		}
	}

	static function ensureDir(dir:String):Void
	{
		if (!FileSystem.exists(dir))
			FileSystem.createDirectory(dir);
	}

	static function extractEntries(entries:List<haxe.zip.Entry>, dest:String):Void
	{
		for (e in entries)
		{
			if (e.fileName == MANIFEST_NAME || StringTools.endsWith(e.fileName, "/" + MANIFEST_NAME))
				continue;

			var rel = sanitizePath(e.fileName);
			if (rel == null)
			{
				Debug.logWarn('[ModImporter] 跳过可疑路径：${e.fileName}');
				continue;
			}

			var outPath = dest + "/" + rel;
			if (StringTools.endsWith(rel, "/"))
			{
				ensureDir(outPath);
				continue;
			}

			ensureDir(haxe.io.Path.directory(outPath));
			try
			{
				File.saveBytes(outPath, Reader.unzip(e));
			}
			catch (ex:Dynamic)
			{
				Debug.logWarn('[ModImporter] 解压失败 ${e.fileName}：$ex');
			}
		}
	}

	/**
	 * 清洗压缩包内路径，去掉前导 ./，拦截 ../ 穿越，防止写到目标目录之外。
	 */
	static function sanitizePath(p:String):String
	{
		p = StringTools.replace(p, "\\", "/");
		while (StringTools.startsWith(p, "./"))
			p = p.substr(2);
		if (StringTools.startsWith(p, "/"))
			p = p.substr(1);
		if (p == "" || p == "." || StringTools.startsWith(p, "..") || p.indexOf("../") >= 0)
			return null;
		return p;
	}
}

/**
 * 单次导入的结果，便于调试控制台回显。
 */
class ImportResult
{
	public var path:String;
	public var ok:Bool = false;
	public var error:String = "";
	public var type:String = "";
	public var id:String = "";
	public var dests:Array<String> = [];

	public function new(p:String)
	{
		path = p;
	}
}
#end
