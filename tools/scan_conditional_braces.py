#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
扫描 Haxe 源码里的条件编译括号失衡。

背景：FreeplayState.hx 用 #if FEATURE_FILESYSTEM 包住了 if/else { 块的左括号，
但共享代码里的右括号没有条件保护——desktop 分支平衡，Android（不定义该宏）分支
右括号多余，解析器层层错位直到报 "Unexpected public" 这类莫名其妙的位置。

本脚本对三种目标平台（android / windows / linux）的定义集组合，
逐文件模拟条件编译的激活状态，统计 {} 平衡：
  - 深度变负（多余的 }）→ 记录第一处
  - 文件结束深度 != 0 → 记录
只统计花括号 {}；自动剔除字符串与注释里的内容。
"""

import os
import re
import sys

SOURCE_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "source")

# 三种目标平台的条件定义集（对应 Project.xml 的 haxedef + 平台常量）
GLOBAL_DEFS = {
    "PRELOAD_ALL", "FLX_NO_FOCUS_LOST_SCREEN", "FLX_NO_DEBUG",
    "NAPE_RELEASE_BUILD", "HXCPP_GC_BIG_BLOCKS", "LINC_LUA_RELATIVE_DYNAMIC_LIB",
    "SWF_VERSION", "APP_ID", "BUILD_DIR",
}
DEFS = {
    "android": GLOBAL_DEFS | {
        "android", "mobile", "cpp", "sys",
        "FEATURE_MODCORE", "FEATURE_MULTITHREADING",
    },
    "windows": GLOBAL_DEFS | {
        "windows", "desktop", "cpp", "sys",
        "FEATURE_DISCORD", "FEATURE_FILESYSTEM", "FEATURE_LUAMODCHART",
        "FEATURE_WEBM", "FEATURE_STEPMANIA", "FEATURE_MODCORE",
        "FEATURE_MULTITHREADING",
    },
    "linux": GLOBAL_DEFS | {
        "linux", "desktop", "cpp", "sys",
        "FEATURE_DISCORD", "FEATURE_FILESYSTEM", "FEATURE_LUAMODCHART",
        "FEATURE_STEPMANIA", "FEATURE_MODCORE", "FEATURE_MULTITHREADING",
    },
}

DIRECTIVE_RE = re.compile(r"^\s*#\s*(if|elseif|else|end|error)\b(.*)$")
IDENT_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")


def strip_strings_and_comments(text, state):
    """剔除字符串与注释，返回剩余"代码字符"。state 是跨行状态 ['block_comment']。"""
    out = []
    i, n = 0, len(text)
    in_block = state
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 2
            else:
                i += 1
            continue
        if c == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if c == "/" and nxt == "/":
            break  # 行注释，余下全跳
        if c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        if c == "'":
            i += 1
            while i < n and text[i] != "'":
                if text[i] == "\\":
                    i += 1
                i += 1
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out), in_block


def eval_condition(cond, defs):
    """把 #if 条件转成 Python 表达式求值。支持 ! && || ( ) 与标识符。"""
    expr = re.sub(r"(?<!=)!(?!=)", " not ", cond)
    expr = expr.replace("&&", " and ").replace("||", " or ")

    def repl(m):
        name = m.group(0)
        if name in ("and", "or", "not", "True", "False"):
            return name
        return "True" if name in defs else "False"

    expr = IDENT_RE.sub(repl, expr)
    try:
        return bool(eval(expr, {"__builtins__": {}}, {}))
    except Exception:
        # 求值不了的（如比较运算等罕见写法），保守按 True 处理并提示
        print(f"  [warn] 无法求值条件: {cond!r}，按 True 处理", file=sys.stderr)
        return True


def scan_file(path, defs):
    """返回 (问题列表)。每个问题是 (行号, 描述)。"""
    problems = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    stack = []          # 每层: [当前激活, 曾激活过]
    depth = 0
    in_block_comment = False

    for lineno, raw in enumerate(lines, 1):
        code, in_block_comment = strip_strings_and_comments(raw.rstrip("\n"), in_block_comment)
        stripped = code.strip()

        m = DIRECTIVE_RE.match("#" + stripped) if stripped.startswith("#") else None
        if stripped.startswith("#"):
            m = re.match(r"^\s*#\s*(if|elseif|else|end|error)\b(.*)$", raw)
        if m and not in_block_comment:
            kw, rest = m.group(1), m.group(2)
            # 内联形式（同一行里出现 #end）：按普通行处理，不入栈
            inline = kw in ("if",) and re.search(r"#\s*end\b", rest)
            if not inline:
                if kw == "if":
                    active = all(s[0] for s in stack)
                    val = eval_condition(rest.strip(), defs) if active else False
                    stack.append([active and val, active and val])
                    continue
                elif kw == "elseif":
                    if not stack:
                        problems.append((lineno, "#elseif 没有匹配的 #if"))
                        continue
                    parent_active = all(s[0] for s in stack[:-1])
                    ever = stack[-1][1]
                    val = eval_condition(rest.strip(), defs) if (parent_active and not ever) else False
                    stack[-1][0] = parent_active and (not ever) and val
                    stack[-1][1] = stack[-1][1] or stack[-1][0]
                    continue
                elif kw == "else":
                    if not stack:
                        problems.append((lineno, "#else 没有匹配的 #if"))
                        continue
                    parent_active = all(s[0] for s in stack[:-1])
                    ever = stack[-1][1]
                    stack[-1][0] = parent_active and not ever
                    stack[-1][1] = True
                    continue
                elif kw == "end":
                    if not stack:
                        problems.append((lineno, "#end 多余"))
                        continue
                    stack.pop()
                    continue
                elif kw == "error":
                    continue

        if not stack or all(s[0] for s in stack):
            for ch in stripped:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth < 0:
                        problems.append((lineno, "多余的 } （深度变负）"))
                        depth = 0
                        break

    if stack:
        problems.append((len(lines), f"文件结束时还有 {len(stack)} 个未闭合的 #if"))
    if depth != 0:
        problems.append((len(lines), f"文件结束深度为 {depth}（应为 0）"))
    return problems


def main():
    root = os.path.abspath(SOURCE_ROOT)
    total = 0
    for mode, defs in DEFS.items():
        print(f"\n===== 平台模式: {mode} =====")
        count = 0
        for dirpath, _, files in os.walk(root):
            for fn in sorted(files):
                if not fn.endswith(".hx"):
                    continue
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, root)
                probs = scan_file(path, defs)
                if probs:
                    for lineno, desc in probs:
                        print(f"  {rel}:{lineno}  {desc}")
                        count += 1
        print(f"  -> {mode}: {count} 处问题")
        total += count
    print(f"\n总计 {total} 处")
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
