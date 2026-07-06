"""
Per-conversation log file support.

When enabled, each chat request can write logs to a dedicated file
logs/chat_logs/{conv_uid}.log for the duration of that request.
"""

import logging
import os
from typing import Optional

try:
    from dbgpt.configs.model_config import LOGDIR
except ImportError:
    LOGDIR = os.getenv("DBGPT_LOG_DIR", os.path.join(os.getcwd(), "logs"))

# 子目录，每个对话的 log 写在此目录下
CHAT_LOGS_SUBDIR = "chat_logs"
CONV_LOG_DIR_ENV = "DBGPT_CONV_LOG_DIR"


def get_conv_log_dir() -> str:
    """Return the directory for per-conversation log files."""
    base_dir = os.getenv(CONV_LOG_DIR_ENV) or LOGDIR
    log_dir = os.path.join(base_dir, CHAT_LOGS_SUBDIR)
    return log_dir


def add_conv_log_handler(conv_uid: Optional[str]) -> Optional[logging.FileHandler]:
    """
    Add a FileHandler that writes to logs/chat_logs/{conv_uid}.log
    to the root logger for the duration of this request.
    Caller must call remove_conv_log_handler with the returned handler when done.

    Args:
        conv_uid: Conversation id (e.g. from dialogue.conv_uid). If None, no handler is added.

    Returns:
        The handler if added, else None.
    """
    if not conv_uid or not conv_uid.strip():
        return None
    log_dir = get_conv_log_dir()
    os.makedirs(log_dir, exist_ok=True)
    # 使用 conv_uid 作为文件名，去掉不合法字符
    safe_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in conv_uid)
    log_file = os.path.join(log_dir, f"{safe_name}.log")
    try:
        handler = logging.FileHandler(log_file, mode="a", encoding="utf-8")
    except OSError:
        return None
    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    handler.setFormatter(formatter)
    handler.setLevel(logging.DEBUG)
    root = logging.getLogger()
    root.addHandler(handler)
    return handler


def remove_conv_log_handler(handler: Optional[logging.Handler]) -> None:
    """
    Remove and close the per-conversation log handler.
    Must be called in finally so it runs even on exception.
    """
    if handler is None:
        return
    try:
        root = logging.getLogger()
        root.removeHandler(handler)
        handler.close()
    except Exception:
        pass
