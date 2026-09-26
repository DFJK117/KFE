#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KFE 模组包打包工具
==================

把任意文件夹打成一个 KFE 能打开的包：

  .kfemod  模组（Mod）
  .kfepack 材质包 / 皮肤包（Pack）
  .kfeds   双合一（Dual = 模组 + 材质包）

包本质是一个 ZIP，根目录必须有一份 kfe.json 清单：

  {
    "type":    "mod" | "pack" | "dual",
    "id":      "唯一标识，也是解压后的文件夹名",
    "title":   "显示名",
    "version": "1.0.0",
    "description": "说明"
  }

用法示例
--------
  # 打一个模组
  python kfe_pack.py --source ./my-mod --type mod --id my-mod

  # 打一个材质包
  python kfe_pack.py --source ./my-skin --type pack --id neon-skin --title "Neon Skin"

  # 双合一
  python kfe_pack.py --source ./combo --type dual --id combo-pack

输出文件默认就叫 <id>.<后缀>，可用 --output 指定。
"""

import argparse
import json
import os
import sys
import zipfile

EXT_BY_TYPE = {
    "mod": ".kfemod",
    "pack": ".kfepack",
    "dual": ".kfeds",
}

MANIFEST_NAME = "kfe.json"


def build_manifest(args):
    manifest = {
        "type": args.type,
        "id": args.id,
    }
    if args.title:
        manifest["title"] = args.title
    if args.version:
        manifest["version"] = args.version
    if args.description:
        manifest["description"] = args.description
    return manifest


def pack(source, manifest, output):
    source = os.path.abspath(source)
    if not os.path.isdir(source):
        sys.exit(f"[kfe_pack] 源文件夹不存在：{source}")

    if os.path.exists(output):
        sys.exit(f"[kfe_pack] 输出文件已存在，先删掉再跑：{output}")

    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
        # 先写清单，保证它在压缩包根目录
        zf.writestr(MANIFEST_NAME, json.dumps(manifest, ensure_ascii=False, indent=2))

        for root, _dirs, files in os.walk(source):
            for name in files:
                full = os.path.join(root, name)
                # 不把已有的同名清单再打进去（用我们生成的为准）
                if os.path.basename(full) == MANIFEST_NAME:
                    continue
                arcname = os.path.relpath(full, source)
                zf.write(full, arcname)

    size = os.path.getsize(output)
    print(f"[kfe_pack] 已生成：{output}  ({size} 字节)")
    print(f"[kfe_pack] 清单：{json.dumps(manifest, ensure_ascii=False)}")


def main():
    parser = argparse.ArgumentParser(
        description="把文件夹打成 KFE 模组包 (.kfemod/.kfepack/.kfeds)")
    parser.add_argument("--source", required=True, help="要打包的源文件夹")
    parser.add_argument("--type", required=True, choices=["mod", "pack", "dual"],
                        help="包类型：mod / pack / dual")
    parser.add_argument("--id", required=True,
                        help="唯一标识（也是解压后的文件夹名，建议只用字母数字下划线）")
    parser.add_argument("--title", default="", help="显示名（可选）")
    parser.add_argument("--version", default="1.0.0", help="版本号（可选，默认 1.0.0）")
    parser.add_argument("--description", default="", help="说明（可选）")
    parser.add_argument("--output", default=None, help="输出文件名（默认 <id>.<后缀>）")
    args = parser.parse_args()

    manifest = build_manifest(args)
    output = args.output or (args.id + EXT_BY_TYPE[args.type])
    pack(args.source, manifest, output)


if __name__ == "__main__":
    main()
