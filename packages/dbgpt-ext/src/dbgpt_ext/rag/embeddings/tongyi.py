"""Tongyi embeddings for RAG."""

import os
from dataclasses import dataclass, field
from typing import List, Optional, Type

from dbgpt._private.pydantic import BaseModel, ConfigDict, Field
from dbgpt.core import EmbeddingModelMetadata, Embeddings
from dbgpt.core.interface.parameter import EmbeddingDeployModelParameters
from dbgpt.model.adapter.base import register_embedding_adapter
from dbgpt.util.i18n_utils import _

_FALLBACK_OPENAPI_EMBEDDING_URL = (
    "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings"
)
_OPENAPI_EMBEDDING_MODELS = frozenset({"text-embedding-v3", "text-embedding-v4"})


def _default_openapi_embedding_url() -> str:
    url = os.getenv("TONGYI_EMBEDDING_MODEL_API_URL")
    if url:
        return url
    return _FALLBACK_OPENAPI_EMBEDDING_URL


@dataclass
class TongyiEmbeddingDeployModelParameters(EmbeddingDeployModelParameters):
    """Tongyi Embeddings deploy model parameters."""

    provider: str = "proxy/tongyi"

    api_key: Optional[str] = field(
        default=None, metadata={"help": _("The API key for the embeddings API.")}
    )
    api_url: Optional[str] = field(
        default=None,
        metadata={
            "help": _(
                "OpenAI-compatible embeddings API URL. Required for text-embedding-v3/v4."
            ),
        },
    )
    backend: Optional[str] = field(
        default="text-embedding-v1",
        metadata={
            "help": _(
                "The real model name to pass to the provider, default is None. If "
                "backend is None, use name as the real model name."
            ),
        },
    )
    timeout: int = field(
        default=60,
        metadata={"help": _("The timeout for the request in seconds.")},
    )

    @property
    def real_provider_model_name(self) -> str:
        """Get the real provider model name."""
        return self.name or self.backend


class TongYiEmbeddings(BaseModel, Embeddings):
    """The tongyi embeddings.

    Legacy models (e.g. text-embedding-v1) use the dashscope SDK.
    text-embedding-v3/v4 use DashScope's OpenAI-compatible embeddings API.
    """

    model_config = ConfigDict(arbitrary_types_allowed=True, protected_namespaces=())
    api_key: Optional[str] = Field(
        default=None, description="The API key for the embeddings API."
    )
    model_name: str = Field(
        default="text-embedding-v1", description="The name of the model to use."
    )
    api_url: Optional[str] = Field(
        default=None,
        description="OpenAI-compatible embeddings API URL.",
    )
    timeout: int = Field(
        default=60, description="The timeout for the request in seconds."
    )

    def __init__(self, **kwargs):
        """Initialize TongYiEmbeddings."""
        api_key = kwargs.get("api_key")
        api_url = kwargs.get("api_url")
        timeout = kwargs.get("timeout", 60)
        super().__init__(**kwargs)
        self._api_key = api_key
        self._api_url = api_url
        self._timeout = timeout
        if not self._effective_api_url():
            try:
                import dashscope  # type: ignore
            except ImportError as exc:
                raise ValueError(
                    "Could not import python package: dashscope "
                    "Please install dashscope by command `pip install dashscope"
                ) from exc
            dashscope.TextEmbedding.api_key = api_key

    @classmethod
    def param_class(cls) -> Type[TongyiEmbeddingDeployModelParameters]:
        """Get the parameter class."""
        return TongyiEmbeddingDeployModelParameters

    @classmethod
    def from_parameters(
        cls, parameters: TongyiEmbeddingDeployModelParameters
    ) -> "Embeddings":
        """Create an embedding model from parameters."""
        return cls(
            api_key=parameters.api_key,
            model_name=parameters.real_provider_model_name,
            api_url=parameters.api_url,
            timeout=parameters.timeout,
        )

    def _effective_api_url(self) -> Optional[str]:
        if self._api_url:
            return self._api_url
        if str(self.model_name) in _OPENAPI_EMBEDDING_MODELS:
            return _default_openapi_embedding_url()
        return None

    def _max_batch_size(self) -> int:
        if str(self.model_name) in _OPENAPI_EMBEDDING_MODELS:
            return 6
        return 25

    def _embed_via_openapi(self, texts: List[str]) -> List[List[float]]:
        import requests
        from dbgpt.rag.embedding.embeddings import _handle_request_result

        api_url = self._effective_api_url()
        if not api_url:
            raise RuntimeError("OpenAI-compatible embedding API URL is not configured.")

        session = requests.Session()
        if self._api_key:
            session.headers.update({"Authorization": f"Bearer {self._api_key}"})
        res = session.post(
            api_url,
            json={"input": texts, "model": self.model_name},
            timeout=self._timeout,
        )
        return _handle_request_result(res)

    def _embed_via_dashscope_sdk(self, texts: List[str]) -> List[List[float]]:
        from dashscope import TextEmbedding

        embeddings: List[List[float]] = []
        max_batch_chunks_size = self._max_batch_size()
        for i in range(0, len(texts), max_batch_chunks_size):
            batch_texts = texts[i : i + max_batch_chunks_size]
            resp = TextEmbedding.call(
                model=self.model_name, input=batch_texts, api_key=self._api_key
            )
            if not isinstance(resp, dict):
                raise RuntimeError(f"Unexpected Tongyi embedding response: {resp!r}")

            output = resp.get("output")
            if output is None:
                message = resp.get("message") or resp.get("code") or str(resp)
                raise RuntimeError(
                    f"Tongyi embedding failed for model {self.model_name}: {message}"
                )

            batch_embeddings = output.get("embeddings")
            if not batch_embeddings:
                raise RuntimeError(
                    f"Tongyi embedding returned empty embeddings for model "
                    f"{self.model_name}: {resp}"
                )
            sorted_embeddings = sorted(
                batch_embeddings, key=lambda e: e["text_index"]
            )
            embeddings.extend([result["embedding"] for result in sorted_embeddings])
        return embeddings

    def embed_documents(
        self, texts: List[str], max_batch_chunks_size=25
    ) -> List[List[float]]:
        """Get the embeddings for a list of texts.

        refer:https://help.aliyun.com/zh/model-studio/getting-started/models?
        spm=a2c4g.11186623.0.0.62524a77NlILDI#c05fe72732770

        Args:
            texts (Documents): A list of texts to get embeddings for.
            max_batch_chunks_size: The max batch size for embedding.

        Returns:
            Embedded texts as List[List[float]], where each inner List[float]
                corresponds to a single input text.
        """
        if self._effective_api_url():
            embeddings: List[List[float]] = []
            batch_size = min(max_batch_chunks_size, self._max_batch_size())
            for i in range(0, len(texts), batch_size):
                batch_texts = texts[i : i + batch_size]
                embeddings.extend(self._embed_via_openapi(batch_texts))
            return embeddings
        return self._embed_via_dashscope_sdk(texts)

    def embed_query(self, text: str) -> List[float]:
        """Compute query embeddings using a OpenAPI embedding model.

        Args:
            text: The text to embed.

        Returns:
            Embeddings for the text.
        """
        return self.embed_documents([text])[0]


register_embedding_adapter(
    TongYiEmbeddings,
    supported_models=[
        EmbeddingModelMetadata(
            model="text-embedding-v3",
            dimension=1024,
            context_length=8192,
            description=_(
                "The embedding model are trained by TongYi, it support more than 50 "
                "working languages."
            ),
        ),
        EmbeddingModelMetadata(
            model="text-embedding-v4",
            dimension=1024,
            context_length=8192,
            description=_(
                "The embedding model are trained by TongYi (v4), it support more than "
                "50 working languages."
            ),
        ),
    ],
)
