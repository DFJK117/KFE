package;

import flixel.system.FlxAssets.FlxShader;

/**
 * KFE 动态模糊 —— 「单帧径向多 tap 模糊」
 *
 * ============================ 诚实声明 ============================
 * 这**不是**物理正确的运动模糊。
 *
 * 真正的运动模糊（motion blur）需要**帧历史**：保留上一帧的深度 / 速度
 * 缓冲，按像素的屏幕空间速度反向采样若干帧，做时间轴累积。FNF 这套
 * flixel 4.9 + OpenFL 9.1 的管线拿不到速度缓冲，FlxCamera 也不暴露
 * 前一帧的 GPU 纹理给用户 shader。
 *
 * 这里实现的是业界常见的**廉价近似**：把每个像素沿「屏幕中心 → 该像素」
 * 的径向方向拖出一串偏移采样并加权平均。视觉上产生「镜头高速推拉时的
 * 拖影」，观感接近动态模糊，但物理上是假的。本文件不会把它说成真的。
 * =================================================================
 *
 * 写法依据：`source/WiggleEffect.hx`（KE 1.8 自带、活的、带 uniform 的
 * FlxShader 范例）。关键约定全部照抄：
 *   - `@:glFragmentSource('...')` 编译期常量字符串 —— 这是 flixel 的
 *     macro 能解析出 uniform 并生成 `haxe.uXxx.value` 访问器的前提；
 *     运行时才赋值的字符串做不到这一点（KE 自带的 ModchartShader 就是
 *     那种写法，因此它没有 uniform 访问器）。
 *   - `#pragma header` 由 flixel 展开，提供 `bitmap` (sampler2D) 与
 *     `openfl_TextureCoordv` (varying vec2)。
 *   - 采样用 `texture2D(bitmap, uv)`，不是 flixel 的 `flixel_texture2D`。
 *   - 构造里 `super()`。
 *
 * GLSL ES 1.0 约束：`for` 循环必须有**编译期常量上界**，循环内可以
 * 用动态 `break`。所以这里写成 `i < MAX_TAPS` + `if (i >= n) break;`。
 */
class KFEBlurShader extends FlxShader
{
	/** 采样上限，必须与下方 glsl 里的 MAX_TAPS 一致。 */
	public static inline var MAX_TAPS:Int = 24;

	@:glFragmentSource('
		#pragma header

		// 0 = 完全关闭（直接返回原图）。越大拖影越长。
		uniform float uStrength;

		// 实际参与平均的 tap 数（会被 clamp 到 [2, MAX_TAPS]）。
		uniform float uSamples;

		// 径向中心，屏幕 UV 坐标。通常 (0.5, 0.5)。
		uniform vec2 uCenter;

		// 宽高比（width / height）。用于把径向方向校正成各向同性，
		// 否则在非正方形窗口里拖影会被拉扁。
		uniform float uAspect;

		const int MAX_TAPS = 24;

		void main()
		{
			vec2 uv = openfl_TextureCoordv;
			vec4 base = texture2D(bitmap, uv);

			// 关闭态：直接透传，零开销。
			if (uStrength <= 0.0001)
			{
				gl_FragColor = base;
				return;
			}

			// 径向方向（在接近正方形的空间里算，避免被宽高比拉扁）
			vec2 dir = uv - uCenter;
			dir.x *= uAspect;

			int n = int(uSamples);
			if (n < 2) n = 2;
			if (n > MAX_TAPS) n = MAX_TAPS;

			vec4 sum = vec4(0.0);
			float wsum = 0.0;

			for (int i = 0; i < MAX_TAPS; i++)
			{
				if (i >= n) break;

				float t = float(i) / float(n - 1);   // 0.0 → 1.0
				vec2 off = dir * (uStrength * t);
				off.x /= uAspect;                    // 换回 UV 空间

				// 越靠外的采样权重越低，形成拖尾衰减
				float w = 1.0 - t * 0.85;
				sum += texture2D(bitmap, uv + off) * w;
				wsum += w;
			}

			gl_FragColor = sum / wsum;
		}')
	public function new()
	{
		super();
	}
}
