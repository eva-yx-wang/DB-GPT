#!/opt/module/anaconda3/envs/aiops/bin/python
"""
Shell 脚本调试包装器
用于在 VS Code 中调试 shell 脚本
支持两种模式：
1. 调试模式（-x）：显示每行命令的执行
2. 正常模式：正常执行脚本
"""
import subprocess
import sys
import os
from datetime import datetime

def main():
    if len(sys.argv) < 2:
        print("Usage: debug_shell.py <shell_script> [args...]")
        print("       Set DEBUG_MODE=1 environment variable to enable trace mode")
        sys.exit(1)

    script_path = sys.argv[1]
    script_args = sys.argv[2:] if len(sys.argv) > 2 else []

    # 检查脚本是否存在
    if not os.path.exists(script_path):
        print(f"Error: Script not found: {script_path}")
        sys.exit(1)

    # 确保脚本有执行权限
    os.chmod(script_path, 0o755)

    # 检查是否启用调试模式
    debug_mode = os.environ.get("DEBUG_MODE", "1") == "1"

    # 构建命令
    # 使用 bash -l -x 来执行脚本（-l 表示 login shell，会 source ~/.bashrc，确保 conda 可用）
    if debug_mode:
        # 使用 bash -l -x 来执行脚本（启用调试跟踪，login shell 确保环境变量正确）
        cmd = ["bash", "-l", "-x", script_path] + script_args
        mode_info = "DEBUG MODE: Tracing script execution (login shell)"
    else:
        # 正常执行，使用 login shell 确保 conda 环境正确
        cmd = ["bash", "-l", script_path] + script_args
        mode_info = "NORMAL MODE: Executing script (login shell)"

    # 准备环境变量，确保能找到 uv 等工具
    # 将 dbgpt 环境的 bin 目录添加到 PATH（如果存在）
    env = os.environ.copy()
    dbgpt_bin = "/opt/module/anaconda3/envs/dbgpt/bin"
    path_info = ""
    if os.path.exists(dbgpt_bin):
        current_path = env.get("PATH", "")
        if dbgpt_bin not in current_path:
            env["PATH"] = f"{dbgpt_bin}:{current_path}"
            path_info = f"Added {dbgpt_bin} to PATH"

    # 设置日志文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_file = os.path.join(script_dir, "run_log.log")

    # 执行脚本，同时输出到终端和日志文件
    try:
        # 打开日志文件（覆盖模式）
        with open(log_file, 'w', encoding='utf-8') as log:
            # 写入开始信息
            start_info = [
                "=" * 80,
                mode_info,
                "=" * 80,
                f"Script execution started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
                f"Script: {script_path}",
                f"Command: {' '.join(cmd)}",
            ]
            if path_info:
                start_info.append(path_info)
            start_info.append("-" * 80)

            for line in start_info:
                log.write(line + "\n")
                print(line)
            log.flush()

            # 创建进程，同时输出到终端和文件
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                universal_newlines=True,
                bufsize=1
            )

            # 实时读取输出并同时写入终端和文件
            for line in process.stdout:
                # 写入日志文件
                log.write(line)
                log.flush()
                # 同时输出到终端
                sys.stdout.write(line)
                sys.stdout.flush()

            # 等待进程完成
            return_code = process.wait()

            # 写入结束信息
            log.write("-" * 80 + "\n")
            log.write(f"Exit code: {return_code}\n")
            log.write(f"Script execution ended at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            log.write("=" * 80 + "\n")
            log.flush()

        print("-" * 80)
        print(f"Exit code: {return_code}")
        print(f"Log saved to: {log_file}")
        sys.exit(return_code)
    except KeyboardInterrupt:
        print("\nScript interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"Error executing script: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

