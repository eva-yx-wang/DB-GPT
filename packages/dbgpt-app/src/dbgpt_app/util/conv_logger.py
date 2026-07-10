"""
Per-conversation log file support.

When enabled, each chat request can write logs to a dedicated file under
logs/chat_logs/ for the duration of that request.

Log file name format:
    yyyy-MM-dd-<timestamp>-<app_name>-<unique_random_str>.log

Where yyyy-MM-dd-<timestamp> is the conversation creation date/time,
app_name is the app/scene name, and unique_random_str identifies the conversation.
"""

import logging
import os
import uuid
from datetime import datetime
from typing import Dict, Optional

try:
    from dbgpt.configs.model_config import LOGDIR
except ImportError:
    LOGDIR = os.getenv("DBGPT_LOG_DIR", os.path.join(os.getcwd(), "logs"))

# 子目录，每个对话的 log 写在此目录下
CHAT_LOGS_SUBDIR = "chat_logs"
CONV_LOG_DIR_ENV = "DBGPT_CONV_LOG_DIR"

# conv_uid -> resolved log file name (without directory)
_conv_log_filename_cache: Dict[str, str] = {}


def get_conv_log_dir() -> str:
    """Return the directory for per-conversation log files."""
    base_dir = os.getenv(CONV_LOG_DIR_ENV) or LOGDIR
    log_dir = os.path.join(base_dir, CHAT_LOGS_SUBDIR)
    return log_dir


def _sanitize_filename_part(value: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in value.strip())


def resolve_app_name(
    app_name: Optional[str] = None,
    app_code: Optional[str] = None,
    chat_mode: Optional[str] = None,
    chat_param: Optional[str] = None,
) -> str:
    """Resolve a filesystem-safe app/scene name for the log file."""
    for candidate in (app_code, app_name, chat_mode, chat_param):
        if candidate and str(candidate).strip():
            return _sanitize_filename_part(str(candidate))
    return "unknown"


def _uuid1_to_datetime(conv_uid: str) -> Optional[datetime]:
    try:
        parsed = uuid.UUID(conv_uid)
        if parsed.version != 1:
            return None
        timestamp = (parsed.time - 0x01B21DD213814000) / 1e7
        return datetime.fromtimestamp(timestamp)
    except (ValueError, AttributeError, OverflowError, OSError):
        return None


def _lookup_conv_created_at(conv_uid: str) -> Optional[datetime]:
    try:
        from dbgpt.storage.chat_history.chat_history_db import ChatHistoryDao

        entity = ChatHistoryDao().get_by_uid(conv_uid)
        if entity is not None:
            gmt_created = entity.gmt_created
            if isinstance(gmt_created, datetime):
                return gmt_created
    except Exception:
        pass
    return None


def resolve_conv_created_at(
    conv_uid: str, created_at: Optional[datetime] = None
) -> datetime:
    """Resolve conversation creation time for log file naming."""
    if created_at is not None:
        return created_at
    db_created_at = _lookup_conv_created_at(conv_uid)
    if db_created_at is not None:
        return db_created_at
    uuid_created_at = _uuid1_to_datetime(conv_uid)
    if uuid_created_at is not None:
        return uuid_created_at
    return datetime.now()


def build_conv_log_filename(
    conv_uid: str,
    app_name: Optional[str] = None,
    app_code: Optional[str] = None,
    chat_mode: Optional[str] = None,
    chat_param: Optional[str] = None,
    created_at: Optional[datetime] = None,
) -> str:
    """
    Build per-conversation log file name.

    Format: yyyy-MM-dd-<timestamp>-app_name-<unique_random_str>.log
    """
    cached = _conv_log_filename_cache.get(conv_uid)
    if cached:
        return cached

    created = resolve_conv_created_at(conv_uid, created_at)
    date_part = created.strftime("%Y-%m-%d")
    time_part = created.strftime("%H%M%S")
    app = resolve_app_name(
        app_name=app_name,
        app_code=app_code,
        chat_mode=chat_mode,
        chat_param=chat_param,
    )
    unique_str = conv_uid.replace("-", "")[:8]
    filename = f"{date_part}-{time_part}-{app}-{unique_str}.log"
    _conv_log_filename_cache[conv_uid] = filename
    return filename


def add_conv_log_handler(
    conv_uid: Optional[str],
    app_name: Optional[str] = None,
    app_code: Optional[str] = None,
    chat_mode: Optional[str] = None,
    chat_param: Optional[str] = None,
    created_at: Optional[datetime] = None,
) -> Optional[logging.FileHandler]:
    """
    Add a FileHandler for this conversation to the root logger.
    Caller must call remove_conv_log_handler with the returned handler when done.

    Args:
        conv_uid: Conversation id. If None, no handler is added.
        app_name: Optional explicit app name for the log file.
        app_code: Custom app code, preferred over chat_mode when present.
        chat_mode: Chat scene/mode, e.g. chat_excel.
        chat_param: Chat mode parameter, e.g. gpts/flow id.
        created_at: Optional conversation creation time override.

    Returns:
        The handler if added, else None.
    """
    if not conv_uid or not conv_uid.strip():
        return None
    log_dir = get_conv_log_dir()
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(
        log_dir,
        build_conv_log_filename(
            conv_uid=conv_uid,
            app_name=app_name,
            app_code=app_code,
            chat_mode=chat_mode,
            chat_param=chat_param,
            created_at=created_at,
        ),
    )
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
