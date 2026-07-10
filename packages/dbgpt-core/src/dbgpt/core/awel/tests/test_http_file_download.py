import pandas as pd

from dbgpt.core.awel.trigger.http_trigger import (
    HttpFileDownloadBody,
    _wrap_http_trigger_result,
)
from dbgpt.core.awel.util.chat_util import parse_single_output
from dbgpt.util.pd_utils import df_to_csv


def test_df_to_csv():
    df = pd.DataFrame({"category": ["A", "B"], "sales": [10, 20]})
    csv_text = df_to_csv(df)
    assert "category,sales" in csv_text
    assert "A,10" in csv_text


def test_wrap_http_trigger_result_builds_attachment_response():
    body = HttpFileDownloadBody(
        content="category,sales\nA,10",
        filename="query_result.csv",
        media_type="text/csv",
    )
    response = _wrap_http_trigger_result(body)
    assert response.status_code == 200
    assert response.media_type == "text/csv"
    assert "attachment" in response.headers["content-disposition"]
    assert "query_result.csv" in response.headers["content-disposition"]
    assert response.body.startswith(b"\xef\xbb\xbfcategory,sales")


def test_parse_single_output_handles_http_file_download_body():
    body = HttpFileDownloadBody(
        content="category,sales\nA,10",
        filename="query_result.csv",
        media_type="text/csv",
    )
    output = parse_single_output(body, is_sse=False)
    assert output.success
    assert "```vis-file-download" in output.text
    assert "query_result.csv" in output.text
    assert "content_base64" in output.text
