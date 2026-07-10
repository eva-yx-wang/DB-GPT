#!/usr/bin/env python3
"""Extract basic KPI statistics from a CSV file for enterprise-kpi-summary skill."""

import argparse
import json
import sys
from pathlib import Path

try:
    import pandas as pd
except ImportError:
    print(json.dumps({"error": "pandas not installed"}))
    sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract KPI summary from CSV")
    parser.add_argument("--input_file", required=True, help="Path to CSV file")
    args = parser.parse_args()

    path = Path(args.input_file)
    if not path.exists():
        print(json.dumps({"error": f"file not found: {path}"}))
        sys.exit(1)

    df = pd.read_csv(path)
    numeric_cols = df.select_dtypes(include="number").columns.tolist()

    summary = {
        "rows": len(df),
        "columns": list(df.columns),
        "numeric_columns": numeric_cols,
    }

    if numeric_cols:
        stats = df[numeric_cols].agg(["sum", "mean", "min", "max"]).round(2)
        summary["statistics"] = stats.to_dict()

    print("###KPI_SUMMARY_START###")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print("###KPI_SUMMARY_END###")

    print("\n[Statistical Summary]")
    print(f"Rows: {summary['rows']}, Columns: {len(summary['columns'])}")
    if numeric_cols:
        for col in numeric_cols:
            print(f"  {col}: sum={df[col].sum():.2f}, mean={df[col].mean():.2f}")


if __name__ == "__main__":
    main()
