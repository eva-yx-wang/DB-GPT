"""Vis File Download."""

from typing import Any, Dict, Optional

from ..base import Vis


class VisFileDownload(Vis):
    """Vis tag for triggering browser file download in chat UI."""

    @classmethod
    def vis_tag(cls):
        """Vis File Download tag."""
        return "vis-file-download"

    def sync_generate_param(self, **kwargs) -> Optional[Dict[str, Any]]:
        return {
            "filename": kwargs.get("filename"),
            "media_type": kwargs.get("media_type"),
            "content_base64": kwargs.get("content_base64"),
        }
