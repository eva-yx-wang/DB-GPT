---
name: enterprise-kpi-summary
description: 企业 KPI 指标摘要技能。当用户需要快速汇总业务关键指标、生成管理层可读的数据摘要时使用。触发词包括「KPI摘要」「指标汇总」「业务概览」「enterprise summary」「kpi report」。
---

# 企业 KPI 指标摘要

本技能是 DB-GPT 二次开发 POC，演示如何通过 Skill 机制封装可复用的领域分析流程。

## 适用场景

- 用户已连接数据库或上传 CSV/Excel
- 需要输出管理层可读的业务 KPI 摘要（收入、订单量、转化率等）
- 需要结构化 Markdown 报告而非原始 SQL 结果

## 工作流程

### 步骤 1：获取数据

若用户附加了数据源，使用 `sql_interpreter` 查询关键指标；若上传了表格文件，使用 `execute_skill_script_file` 运行 `scripts/kpi_extract.py`。

**SQL 示例（按实际 schema 调整）：**
```sql
SELECT COUNT(*) AS total_orders,
       SUM(amount) AS total_revenue,
       AVG(amount) AS avg_order_value
FROM orders
WHERE order_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY);
```

**脚本调用示例：**
```json
{
  "skill_name": "enterprise-kpi-summary",
  "script_file_name": "kpi_extract.py",
  "args": {"input_file": "/path/to/sales.csv"}
}
```

### 步骤 2：生成摘要报告

基于查询结果，输出包含以下章节的 Markdown 报告：

1. **执行摘要** — 3-5 条核心发现
2. **关键指标表** — 指标名、数值、环比/同比（如有）
3. **异常与风险** — 需关注的指标波动
4. **建议行动** — 2-3 条可执行建议

## 输出格式要求

- 使用与用户提问相同的语言
- 数值保留合理精度，大数使用千分位
- 不得编造未查询到的指标
