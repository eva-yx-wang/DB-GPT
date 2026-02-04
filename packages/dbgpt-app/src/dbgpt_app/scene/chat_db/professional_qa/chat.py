import re
from typing import Dict, Type

from dbgpt.component import SystemApp, logger
from dbgpt.core import ModelRequest
from dbgpt.core.interface.message import ModelMessage, ModelMessageRoleType
from dbgpt.util.executor_utils import blocking_func_to_async
from dbgpt.util.tracer import trace
from dbgpt_app.scene import BaseChat, ChatScene
from dbgpt_app.scene.base_chat import ChatParam
from dbgpt_app.scene.chat_db.professional_qa.config import ChatWithDBQAConfig
from dbgpt_serve.datasource.manages import ConnectorManager


class ChatWithDbQA(BaseChat):
    """As a DBA, Chat DB Module, chat with combine DB meta schema"""

    chat_scene: str = ChatScene.ChatWithDbQA.value()

    @classmethod
    def param_class(cls) -> Type[ChatWithDBQAConfig]:
        return ChatWithDBQAConfig

    def __init__(self, chat_param: ChatParam, system_app: SystemApp):
        """Chat DB Module Initialization
        Args:
           - chat_param: Dict
            - chat_session_id: (str) chat session_id
            - current_user_input: (str) current user input
            - model_name:(str) llm model name
            - select_param:(str) dbname
        """
        self.db_name = chat_param.select_param
        self.database = None
        self.curr_config = chat_param.real_app_config(ChatWithDBQAConfig)
        super().__init__(chat_param=chat_param, system_app=system_app)

        if self.db_name is None:
            raise Exception(f"Database: {self.db_name} not found")
        if self.db_name:
            local_db_manager = ConnectorManager.get_instance(self.system_app)
            self.database = local_db_manager.get_connector(self.db_name)
            self.tables = self.database.get_table_names()
        if self.database is not None and self.database.is_graph_type():
            # When the current graph database retrieves source data from ChatDB, the
            # topk uses the sum of node table and edge table.
            self.top_k = len(list(self.tables))
        else:
            logger.info(
                "Dialect: "
                f"{self.database.db_type if self.database is not None else None}"
            )
            self.top_k = self.curr_config.schema_retrieve_top_k

    async def _detect_get_db_raw_intent(self, user_input: str) -> bool:
        """Use LLM to detect if user asks for full/raw table structure (get_db_raw=True)."""
        if not user_input or not user_input.strip():
            return False
        system_prompt = (
            "你是一个意图分类器。根据用户问题判断：用户是否在明确要求提供「完整的表结构」或「原始建表信息」。"
            "例如：给我完整的表结构、show create table、全表结构、表结构详情、建表语句、表定义 等。"
            "只回答 true 或 false，不要其他内容。"
        )
        try:
            request = ModelRequest(
                model=self._chat_param.model_name,
                messages=[
                    ModelMessage(
                        role=ModelMessageRoleType.SYSTEM,
                        content=system_prompt,
                    ),
                    ModelMessage(
                        role=ModelMessageRoleType.HUMAN,
                        content=user_input,
                    ),
                ],
            )
            output = await self.call_llm_operator(request)
            text = (output.text or "").strip().lower()
            # 取首词或首行中的 true/false
            if not text:
                return False
            match = re.search(r"\b(true|false|是|否)\b", text)
            if match:
                return match.group(1) in ("true", "是")
            return "true" in text[:20] or "是" in text[:20]
        except Exception as e:
            logger.warning("get_db_raw intent detection failed, default False: %s", e)
            return False

    @trace()
    async def generate_input_values(self) -> Dict:
        try:
            from dbgpt_serve.datasource.service.db_summary_client import DBSummaryClient
        except ImportError:
            raise ValueError("Could not import DBSummaryClient. ")
        user_input = self.current_user_input.last_text
        table_infos = None
        if self.db_name:
            get_db_raw = await self._detect_get_db_raw_intent(user_input)
            if get_db_raw:
                # 用户明确要求完整表结构时，从数据库拉取 table_simple_info
                table_infos = await blocking_func_to_async(
                    self._executor, self.database.table_simple_info
                )
                if len(table_infos) > self.curr_config.schema_max_tokens:
                    table_infos = table_infos[: self.curr_config.schema_max_tokens]
            else:
                client = DBSummaryClient(system_app=self.system_app)
                try:
                    table_infos = await blocking_func_to_async(
                        self._executor,
                        client.get_db_summary,
                        self.db_name,
                        user_input,
                        self.top_k,
                    )
                except Exception as e:
                    logger.error(f"Retrieved table info error: {str(e)}")
                    table_infos = await blocking_func_to_async(
                        self._executor, self.database.table_simple_info
                    )
                    if len(table_infos) > self.curr_config.schema_max_tokens:
                        table_infos = table_infos[: self.curr_config.schema_max_tokens]

        input_values = {
            "input": user_input,
            "table_info": table_infos,
        }
        return input_values
