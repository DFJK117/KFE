#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 kfe-build.yml（Windows 工作流）升级为带完整诊断体系的版本。
用法：python tools/patch_kfe_build.py  （在 KFE 仓库根目录执行）
"""

P = '.github/workflows/kfe-build.yml'
s = open(P, encoding='utf-8').read()

# 1) job 级 permissions（心跳/失败推送需要 contents:write）
s = s.replace(
    """  build-windows:
    runs-on: windows-latest""",
    """  build-windows:
    runs-on: windows-latest
    permissions:
      contents: write""",
    1)

# 2) 安装依赖 tee 化（pipefail + 每条 tee 进 build.log）
s = s.replace(
    """        run: |
          set -e
          mkdir -p "$HAXELIB_PATH"
          haxelib setup "$HAXELIB_PATH"
""",
    """        run: |
          set -e
          set -o pipefail
          mkdir -p "$HAXELIB_PATH"
          haxelib setup "$HAXELIB_PATH" 2>&1 | tee -a build.log
""", 1)

for lib in ["hxcpp 4.2.1", "lime 7.9.0", "openfl 9.1.0", "flixel 4.9.0",
            "flixel-addons 2.10.0", "flixel-ui 2.3.3", "hscript 2.0.7",
            "actuate 1.9.0", "polymod 1.4.3"]:
    s = s.replace("haxelib install " + lib + "\n",
                  "haxelib install " + lib + " 2>&1 | tee -a build.log\n")

s = s.replace("haxelib git faxe https://github.com/uhrobots/faxe --quiet || true\n",
              "haxelib git faxe https://github.com/uhrobots/faxe --quiet 2>&1 | tee -a build.log || true\n")
s = s.replace("haxelib git discord_rpc https://github.com/Aidan63/linc_discord-rpc --quiet\n",
              "haxelib git discord_rpc https://github.com/Aidan63/linc_discord-rpc --quiet 2>&1 | tee -a build.log\n")
s = s.replace("haxelib git extension-webm https://github.com/Kade-github/extension-webm --quiet\n",
              "haxelib git extension-webm https://github.com/Kade-github/extension-webm --quiet 2>&1 | tee -a build.log\n")
s = s.replace("haxelib git linc_luajit https://github.com/nebulazorua/linc_luajit.git --quiet\n",
              "haxelib git linc_luajit https://github.com/nebulazorua/linc_luajit.git --quiet 2>&1 | tee -a build.log\n")
s = s.replace("haxelib git hxvm-luajit https://github.com/nebulazorua/hxvm-luajit --quiet\n",
              "haxelib git hxvm-luajit https://github.com/nebulazorua/hxvm-luajit --quiet 2>&1 | tee -a build.log\n")

# 3) 编译步骤头：注入 git 身份与心跳说明
old_head = """      - name: 编译 windows -release
        shell: bash
        run: |
          set -e
"""
new_head = """      - name: 编译 windows -release
        shell: bash
        env:
          GITHUB_TOKEN: ${{ github.token }}
        run: |
          set -e
          git config user.email "ci@users.noreply.github.com"
          git config user.name "KFE CI Bot"
          # 【KFE 诊断】心跳：每 60s 把 build.log 尾部 + 内存/页面文件快照推到
          # ci-diag 分支；无论编译进程怎么死，死前 1 分钟的现场必在远端。
"""
assert old_head in s, "编译步骤头没匹配上"
s = s.replace(old_head, new_head, 1)

# 4) memlog 循环增强：haxe 进程内存 + 心跳推送
old_mem = (
    """              powershell -NoProfile -Command "
                \\$os = Get-CimInstance Win32_OperatingSystem
                '{0} avail={1}MB commitLimit={2}MB' -f (Get-Date -Format HH:mm:ss),
                  [math]::Round(\\$os.FreePhysicalMemory/1KB),
                  [math]::Round([double]\\$os.TotalVirtualMemorySize/1KB)
              " >> memlog.txt 2>&1 || true
              sleep 60
            done
          ) &
          MEMPID=$!
""")
new_mem = (
    """              powershell -NoProfile -Command "
                \\$os = Get-CimInstance Win32_OperatingSystem
                '{0} avail={1}MB commitLimit={2}MB' -f (Get-Date -Format HH:mm:ss),
                  [math]::Round(\\$os.FreePhysicalMemory/1KB),
                  [math]::Round([double]\\$os.TotalVirtualMemorySize/1KB)
                Get-Process haxe -ErrorAction SilentlyContinue | ForEach-Object {{
                  'haxe WS(GB): ' + [math]::Round(\\$_.WorkingSet64/1GB,2) + '  PM(GB): ' + [math]::Round(\\$_.PagedMemorySize64/1GB,2)
                }}
              " >> memlog.txt 2>&1 || true
              if [ -f build.log ]; then
                tail -n 300 build.log > build.diag.log 2>/dev/null || true
                cat memlog.txt >> build.diag.log 2>/dev/null || true
                git add -f build.diag.log 2>/dev/null || true
                git commit -m "ci-diag-win heartbeat $(date +%H:%M:%S)" >/dev/null 2>&1 || true
                git push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${{ github.repository }}.git" HEAD:ci-diag >/dev/null 2>&1 || true
              fi
              sleep 60
            done
          ) &
          MEMPID=$!
""")
assert old_mem in s, "memlog 块没匹配上"
s = s.replace(old_mem, new_mem, 1)

# 5) 编译命令：重定向 build.log + verbose + 退出码规范化 + 失败推送
old_cmd = (
    """          set +e
          haxelib run lime build windows -release
          RC=$?
          kill $MEMPID 2>/dev/null || true

          echo "--- 内存曲线（全程）---"
          cat memlog.txt || true
          echo "--- 产出目录 ---"
          ls -la export/release/windows/bin || true
          exit $RC
""")
new_cmd = (
    """          set +e
          haxelib run lime build windows -release -verbose > build.log 2>&1
          RC=$?
          kill $MEMPID 2>/dev/null || true

          echo "--- 内存曲线（全程）---"
          cat memlog.txt || true
          echo "--- 产出目录 ---"
          ls -la export/release/windows/bin || true

          if [ "$RC" -ne 0 ]; then
            echo "!! 编译失败，原始退出码 $RC（规范化为 1）"
            echo "--- build.log 末尾 80 行 ---"
            tail -n 80 build.log || true
            # 失败现场推到 ci-diag，本机 git 拉取即可读
            tail -n 3000 build.log > build.diag.log 2>/dev/null || true
            git add -f build.diag.log 2>/dev/null || true
            git add -f memlog.txt 2>/dev/null || true
            git commit -m "ci-diag-win: windows build.log run ${{ github.run_id }}" >/dev/null 2>&1 || true
            git push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${{ github.repository }}.git" HEAD:ci-diag >/dev/null 2>&1 || true
            exit 1
          fi
          exit 0
""")
assert old_cmd in s, "编译命令块没匹配上"
s = s.replace(old_cmd, new_cmd, 1)

open(P, 'w', encoding='utf-8').write(s)
print("kfe-build.yml 改造完成：permissions / tee / 心跳 / 失败推送 全部就位")
