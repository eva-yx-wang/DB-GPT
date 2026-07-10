import logging
import re
from typing import Dict, List, Type

from dbgpt import SystemApp
from dbgpt.agent.util.api_call import ApiCall
from dbgpt.util.executor_utils import blocking_func_to_async
from dbgpt.util.tracer import root_tracer, trace
from dbgpt_app.scene import BaseChat, ChatScene
from dbgpt_app.scene.base_chat import ChatParam
from dbgpt_app.scene.chat_db.auto_execute.config import ChatWithDBExecuteConfig
from dbgpt_serve.core.config import GPTsAppCommonConfig
from dbgpt_serve.datasource.manages import ConnectorManager

logger = logging.getLogger(__name__)

_TABLE_NAME_PATTERN = r"[A-Za-z_][A-Za-z0-9_]*"

_SCHEMA_DETAIL_PATTERN = re.compile(
    r"主键|primary\s*key|unique\s*key|唯一键|唯一索引|索引|index|表结构|建表|约束|constraint",
    re.IGNORECASE,
)

class ChatWithDbAutoExecute(BaseChat):
    chat_scene: str = ChatScene.ChatWithDbExecute.value()

    """Number of results to return from the query"""

    @classmethod
    def param_class(cls) -> Type[GPTsAppCommonConfig]:
        return ChatWithDBExecuteConfig

    def __init__(self, chat_param: ChatParam, system_app: SystemApp):
        """Chat Data Module Initialization
        Args:
           - chat_param: Dict
            - chat_session_id: (str) chat session_id
            - current_user_input: (str) current user input
            - model_name:(str) llm model name
            - select_param:(str) dbname
        """
        self.db_name = chat_param.select_param
        self.curr_config = chat_param.real_app_config(ChatWithDBExecuteConfig)
        super().__init__(chat_param=chat_param, system_app=system_app)
        if not self.db_name:
            raise ValueError(
                f"{ChatScene.ChatWithDbExecute.value} mode should chose db!"
            )
        with root_tracer.start_span(
            "ChatWithDbAutoExecute.get_connect", metadata={"db_name": self.db_name}
        ):
            local_db_manager = ConnectorManager.get_instance(self.system_app)
            self.database = local_db_manager.get_connector(self.db_name)
        self.api_call = ApiCall()

    def _extract_referenced_tables(self, user_input: str) -> List[str]:
        """Extract table names explicitly referenced in the user query."""
        if not user_input or self.database is None:
            return []
        try:
            all_tables = set(self.database.get_table_names())
        except Exception as e:
            logger.warning("Failed to list tables for %s: %s", self.db_name, e)
            return []

        found: List[str] = []
        for match in re.finditer(
            rf"{re.escape(self.db_name)}\.({_TABLE_NAME_PATTERN})",
            user_input,
            re.IGNORECASE,
        ):
            table = match.group(1)
            if table in all_tables and table not in found:
                found.append(table)

        for match in re.finditer(
            rf"(?<![A-Za-z0-9_])({_TABLE_NAME_PATTERN})(?![A-Za-z0-9_])",
            user_input,
        ):
            table = match.group(1)
            if table in all_tables and table not in found:
                found.append(table)
        return found

    def _needs_detailed_schema(self, user_input: str) -> bool:
        return bool(_SCHEMA_DETAIL_PATTERN.search(user_input or ""))

    def _get_detailed_table_schemas(self, table_names: List[str]) -> List[str]:
        """Fetch full DDL (including UNIQUE KEY / indexes) for specific tables."""
        schemas: List[str] = []
        for table_name in table_names:
            try:
                if hasattr(self.database, "get_show_create_table"):
                    ddl = self.database.get_show_create_table(table_name)
                    if ddl and "CREATE TABLE" in ddl.upper():
                        schemas.append(ddl)
                        continue
                info = self.database.get_table_info([table_name])
                if info:
                    schemas.append(info)
            except Exception as e:
                logger.warning(
                    "Failed to get detailed schema for %s.%s: %s",
                    self.db_name,
                    table_name,
                    e,
                )
        return schemas

    def _merge_table_infos(
        self, detailed: List[str], retrieved: List[str]
    ) -> List[str]:
        if not detailed:
            return retrieved or []
        merged = list(detailed)
        detailed_tables = set()
        for item in detailed:
            match = re.search(r"CREATE TABLE [`']?(\w+)", item, re.IGNORECASE)
            if match:
                detailed_tables.add(match.group(1).lower())

        for item in retrieved or []:
            item_lower = item.lower()
            if any(
                item_lower.startswith(f"{table}(") or f"`{table}`" in item_lower
                for table in detailed_tables
            ):
                continue
            merged.append(item)
        return merged

    @trace()
    async def generate_input_values(self) -> Dict:
        """
        generate input values
        """
        try:
            from dbgpt_serve.datasource.service.db_summary_client import DBSummaryClient
        except ImportError:
            raise ValueError("Could not import DBSummaryClient. ")
        user_input = self.current_user_input.last_text
        referenced_tables = self._extract_referenced_tables(user_input)
        needs_detail = self._needs_detailed_schema(user_input)
        detailed_schemas: List[str] = []

        if referenced_tables and (needs_detail or len(referenced_tables) <= 3):
            detailed_schemas = await blocking_func_to_async(
                self._executor,
                self._get_detailed_table_schemas,
                referenced_tables,
            )
            logger.info(
                "Loaded detailed schema for referenced tables %s in %s",
                referenced_tables,
                self.db_name,
            )

        client = DBSummaryClient(system_app=self.system_app)
        try:
            with root_tracer.start_span("ChatWithDbAutoExecute.get_db_summary"):
                table_infos = await blocking_func_to_async(
                    self._executor,
                    client.get_db_summary,
                    self.db_name,
                    user_input,
                    self.curr_config.schema_retrieve_top_k,
                )
        except Exception as e:
            logger.error(f"Retrieved table info error: {str(e)}")
            table_infos = await blocking_func_to_async(
                self._executor, self.database.table_simple_info
            )
            if len(table_infos) > self.curr_config.schema_max_tokens:
                # Load all tables schema, must be less then schema_max_tokens
                # Here we just truncate the table_infos
                # TODO: Count the number of tokens by LLMClient
                table_infos = table_infos[: self.curr_config.schema_max_tokens]

        table_infos = self._merge_table_infos(detailed_schemas, table_infos or [])

        input_values = {
            "db_name": self.db_name,
            "user_input": user_input,
            "top_k": self.curr_config.max_num_results,
            "dialect": self.database.dialect,
            "table_info": table_infos,
            "display_type": self._generate_numbered_list(),
        }
        return input_values

    def do_action(self, prompt_response):
        timeout = self.curr_config.sql_query_timeout

        def run_sql_to_df(command: str, fetch: str = "all"):
            return self.database.run_to_df(command, fetch=fetch, timeout=timeout)

        return run_sql_to_df
