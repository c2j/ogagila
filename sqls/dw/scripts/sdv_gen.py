#!/usr/bin/env python3
"""Phase 3 / T2 — SDV 分布真实性造数

方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §8.1（T2）

三层造数的分工与本脚本的定位：
    T1  确定性 SQL 夹具  -> 功能正确性断言（值可预期，可写精确期望）
    T2  本脚本（SDV）    -> 分布真实性，供回归测试使用
    T3  SQL 规模造数     -> 性能压测

为什么 T2 不能替代 T1：SDV 复现的是训练数据的**统计分布**，产出的具体值不可预知，
因此无法写"期望值等于 X"的断言。反之 T1 无法产出真实分布。两者互补而非替代。

为什么用 GaussianCopulaSynthesizer 而非 HMASynthesizer：
    SDV 官方明示公开版 HMA "is not meant for scale"，且限"约 5 表、1 层深度"
    （Pagila 是 15 表多层）。本脚本因此按**单表**建模，外键由 SQL 侧按构造补齐。

许可证：SDV 为 BUSL-1.1（非 MIT）。Additional Use Grant 允许生产使用，仅禁止
将 SDV 作为"合成数据服务"对外商业提供。内部测试造数在授权范围内。
"""
import argparse
import sys
from pathlib import Path

import pandas as pd


def build_payment(seed_csv: Path, out_csv: Path, n_rows: int) -> dict:
    """对 payment 的金额/时间分布单表建模。

    只保留建模真正需要的列：payment_id 是代理键（无分布意义），
    customer_id/staff_id 是外键（由 SQL 侧按构造补齐，不交给 SDV）。

    amount 必须显式声明为 categorical：Pagila 的金额是**离散价格档位**
    （种子数据仅 19 个不同取值）。若交给 SDV 自动识别为 numerical，
    GaussianCopula 会按连续边缘分布拟合，实测后果是产出 1026 个不同取值、
    仅 8.48% 落在真实档位上、中位数从 3.99 偏到 1.79。声明为 categorical 后
    SDV 改为按观测频率从取值集合采样，档位与频率均得以保留。
    """
    from sdv.metadata import Metadata
    from sdv.single_table import GaussianCopulaSynthesizer

    df = pd.read_csv(seed_csv, parse_dates=["payment_date"])
    model_df = df[["amount", "payment_date"]].copy()

    metadata = Metadata.detect_from_dataframes({"payment": model_df})
    metadata.update_column(
        column_name="amount", sdtype="categorical", table_name="payment"
    )
    synth = GaussianCopulaSynthesizer(metadata, enforce_min_max_values=True)
    synth.fit(model_df)
    sampled = synth.sample(num_rows=n_rows)
    sampled["amount"] = sampled["amount"].astype(float)
    sampled.to_csv(out_csv, index=False)

    seed_grid = set(df["amount"].unique())
    return {
        "seed_rows": len(df),
        "sampled_rows": len(sampled),
        "seed_distinct_amounts": int(df["amount"].nunique()),
        "sampled_distinct_amounts": int(sampled["amount"].nunique()),
        "on_grid_ratio": round(float(sampled["amount"].isin(seed_grid).mean()), 4),
        "seed_amount_mean": round(float(df["amount"].mean()), 4),
        "sampled_amount_mean": round(float(sampled["amount"].mean()), 4),
        "seed_amount_median": float(df["amount"].median()),
        "sampled_amount_median": float(sampled["amount"].median()),
        "seed_date_min": str(df["payment_date"].min()),
        "sampled_date_min": str(sampled["payment_date"].min()),
        "seed_date_max": str(df["payment_date"].max()),
        "sampled_date_max": str(sampled["payment_date"].max()),
    }


def build_rental(seed_csv: Path, out_csv: Path, n_rows: int) -> dict:
    """对 rental 建模，并用 Inequality 约束保证 return_date > rental_date。

    未归还的行（return_date 为空）会破坏 Inequality 约束的前提，故训练时剔除，
    未归还比例由 SQL 侧按业务规则单独注入。
    """
    from sdv.cag import Inequality
    from sdv.metadata import Metadata
    from sdv.single_table import GaussianCopulaSynthesizer

    df = pd.read_csv(seed_csv, parse_dates=["rental_date", "return_date"])
    returned = df.dropna(subset=["return_date"])
    model_df = returned[["rental_date", "return_date"]].copy()

    metadata = Metadata.detect_from_dataframes({"rental": model_df})
    synth = GaussianCopulaSynthesizer(metadata, enforce_min_max_values=True)
    synth.add_constraints(
        [Inequality(low_column_name="rental_date", high_column_name="return_date")]
    )
    synth.fit(model_df)
    sampled = synth.sample(num_rows=n_rows)
    sampled.to_csv(out_csv, index=False)

    violations = int((sampled["return_date"] <= sampled["rental_date"]).sum())
    return {
        "seed_rows": len(df),
        "seed_returned_rows": len(returned),
        "sampled_rows": len(sampled),
        "inequality_violations": violations,
        "seed_open_ratio": round(1 - len(returned) / len(df), 4),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed-dir", default="/tmp/sdv_work")
    ap.add_argument("--out-dir", default="/tmp/sdv_work")
    ap.add_argument("--rows", type=int, default=20000)
    args = ap.parse_args()

    seed_dir, out_dir = Path(args.seed_dir), Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    import sdv

    print(f"sdv version: {sdv.__version__}")

    print("\n=== payment: GaussianCopulaSynthesizer ===")
    for k, v in build_payment(
        seed_dir / "seed_payment.csv", out_dir / "synth_payment.csv", args.rows
    ).items():
        print(f"  {k:24s} {v}")

    print("\n=== rental: GaussianCopula + Inequality(rental_date < return_date) ===")
    stats = build_rental(
        seed_dir / "seed_rental.csv", out_dir / "synth_rental.csv", args.rows
    )
    for k, v in stats.items():
        print(f"  {k:24s} {v}")

    if stats["inequality_violations"] != 0:
        print(
            f"\nFAIL: Inequality 约束被违反 {stats['inequality_violations']} 行",
            file=sys.stderr,
        )
        return 1

    print("\nPASS: 约束成立，CSV 已生成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
