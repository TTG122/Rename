#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
在 Windows / Linux 上校验 ImportService（账单导入）的解析逻辑。

为什么需要它：本机没有 Xcode，没法跑 xcodebuild test；而导入逻辑是纯规则，
可以原样复刻到 Python，用真实的微信账单跑一遍，看「笔数 / 金额 / 时间」对不对。

用法：
    python tools/verify_import.py                     # 只跑内置用例
    python tools/verify_import.py 账单.xlsx            # 额外跑真实微信账单
    python tools/verify_import.py 账单.xlsx --legacy   # 同时跑旧逻辑做对照

注意：改了 ImportService.swift 的规则时请同步改这里，否则两边会漂移。
"""

import argparse
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"

# ---------------------------------------------------------------- xlsx 读取（对应 XLSXReader）


def _column_index(reference: str) -> int:
    index = 0
    for ch in "".join(c for c in reference if c.isalpha()).upper():
        index = index * 26 + (ord(ch) - 64)
    return max(index - 1, 0)


def xlsx_rows(path: str):
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        shared = ["".join(t.text or "" for t in si.iter(NS + "t")) for si in root.findall(NS + "si")]

    sheets = sorted(n for n in z.namelist() if n.startswith("xl/worksheets/") and n.endswith(".xml"))
    root = ET.fromstring(z.read(sheets[0]))

    rows = []
    for row in root.iter(NS + "row"):
        current = []
        for cell in row.findall(NS + "c"):
            cell_type = cell.get("t") or ""
            ref = cell.get("r") or ""
            index = _column_index(ref) if ref else len(current)
            value_node = cell.find(NS + "v")
            inline = cell.find(NS + "is")
            if cell_type == "s" and value_node is not None and value_node.text is not None:
                idx = int(value_node.text)
                value = shared[idx] if idx < len(shared) else ""
            elif cell_type == "inlineStr" and inline is not None:
                value = "".join(t.text or "" for t in inline.iter(NS + "t"))
            elif value_node is not None:
                value = value_node.text or ""
            else:
                value = ""
            if len(current) <= index:
                current.extend([""] * (index - len(current) + 1))
            current[index] = value
        rows.append(current)

    rows = [r for r in rows if any(c.strip() for c in r)]
    width = max((len(r) for r in rows), default=0)
    return [r + [""] * (width - len(r)) for r in rows]


# ---------------------------------------------------------------- CSV（对应 parseCSV）


def parse_csv(text: str):
    rows, row, field, in_quotes, i = [], [], "", False, 0
    def flush_field():
        nonlocal field
        row.append(field)
        field = ""
    while i < len(text):
        ch = text[i]
        if in_quotes:
            if ch == '"':
                if i + 1 < len(text) and text[i + 1] == '"':
                    field += '"'
                    i += 2
                    continue
                in_quotes = False
                i += 1
                continue
            field += ch
            i += 1
            continue
        if ch == '"':
            in_quotes = True
        elif ch == ",":
            flush_field()
        elif ch == "\r":
            pass
        elif ch == "\n":
            flush_field()
            rows.append(row)
            row = []
        else:
            field += ch
        i += 1
    if field or row:
        row.append(field)
        rows.append(row)
    return [[c.strip() for c in r] for r in rows]


# ---------------------------------------------------------------- 列识别

KEYWORD_SETS = [
    ("dateTime", ["交易时间", "交易日期", "付款时间", "记账时间", "日期", "时间"]),
    ("kind", ["收/支", "收支类型", "收支", "类型", "借贷标志"]),
    ("amount", ["金额(元)", "金额（元）", "交易金额", "发生额", "金额"]),
    ("merchant", ["交易对方", "商户名称", "对方名称", "收款方", "交易对象", "商户", "对方"]),
    ("item", ["商品说明", "商品名称", "商品", "摘要", "交易说明"]),
    ("category", ["交易分类", "分类"]),
    ("account", ["收/付款方式", "支付方式", "付款方式", "账户", "银行卡"]),
    ("orderNumber", ["交易订单号", "交易单号", "商户单号", "订单号"]),
    ("note", ["备注"]),
    ("status", ["当前状态", "交易状态", "状态"]),
]


def normalize(text: str) -> str:
    s = text.lower()
    s = re.sub(r"\s", "", s)
    s = re.sub(r"[!-/:-@\[-`{-~]", "", s)
    s = re.sub(r"[\u2000-\u206F\u3000-\u303F\uFF00-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF40\uFF5B-\uFF65]", "", s)
    return s


def detect_columns(rows, legacy=False):
    best = None
    for row_index, row in enumerate(rows[:40]):
        mapping, score = {"headerIndex": row_index}, 0
        normalized_row = [normalize(c) for c in row]
        for key, keywords in KEYWORD_SETS:
            matched = None
            if not legacy:
                for keyword in keywords:
                    k = normalize(keyword)
                    if not k:
                        continue
                    if k in normalized_row:
                        matched = normalized_row.index(k)
                        break
            if matched is None:
                for column_index, cell in enumerate(normalized_row):
                    if not cell:
                        continue
                    if any(normalize(kw) and normalize(kw) in cell for kw in keywords):
                        matched = column_index
                        break
            if matched is not None:
                mapping[key] = matched
                score += 1
        mapping["score"] = score
        if score >= 3 and (best is None or score > best["score"]):
            best = mapping
    return best


# ---------------------------------------------------------------- 日期


def excel_serial_date(text: str):
    try:
        serial = float(text)
    except ValueError:
        return None
    if not (1 <= serial <= 2_958_465):
        return None
    import datetime
    whole = int(serial)
    base = datetime.datetime(1899, 12, 30) + datetime.timedelta(days=whole)
    return base + datetime.timedelta(seconds=round((serial - whole) * 86400))


TEXT_DATE_FORMATS = ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y/%m/%d %H:%M:%S",
                     "%Y/%m/%d %H:%M", "%Y-%m-%d", "%Y/%m/%d"]


def parse_date(text: str, legacy=False):
    if not text:
        return None
    text = text.strip()
    if not legacy:
        converted = excel_serial_date(text)
        if converted:
            return converted
    import datetime
    for fmt in TEXT_DATE_FORMATS:
        try:
            return datetime.datetime.strptime(text, fmt)
        except ValueError:
            continue
    return None


# ---------------------------------------------------------------- 组装


def clean_cell(text: str) -> str:
    t = text.strip()
    if t in ("/", "-", "—", "--", "无", "N/A", "n/a"):
        return ""
    return t


def clean_amount(text: str) -> str:
    return text.replace("¥", "").replace("￥", "").replace("元", "").replace(",", "").strip()


def clean_merchant(text: str) -> str:
    if "/" in text:
        text = text.split("/")[0]
    return text.strip()


def detect_format(rows) -> str:
    joined = "".join(c for r in rows[:20] for c in r)
    if "微信" in joined:
        return "微信支付账单"
    if "支付宝" in joined:
        return "支付宝账单"
    if "银行" in joined:
        return "银行账单"
    return "通用账单"


def build(rows, legacy=False):
    result = {"drafts": [], "warnings": [], "skipped": 0, "duplicates": 0, "neutral": 0,
              "format": "Excel 账单" if legacy else detect_format(rows)}
    mapping = detect_columns(rows, legacy=legacy)
    if not mapping:
        result["warnings"].append("没找到表头行")
        return result, mapping

    seen = set()
    for row in rows[mapping["headerIndex"] + 1:]:
        def value(key):
            index = mapping.get(key)
            if index is None or index >= len(row):
                return ""
            return row[index].strip()

        amount_text = value("amount")
        try:
            cents = round(float(clean_amount(amount_text)) * 100)
        except ValueError:
            if any(c.strip() for c in row):
                result["skipped"] += 1
            continue
        if cents <= 0:
            if any(c.strip() for c in row):
                result["skipped"] += 1
            continue

        kind_text = clean_cell(value("kind")) if not legacy else value("kind")
        if legacy:
            status = value("status")
            if "关闭" in status or "失败" in status or "已退款" in status:
                result["skipped"] += 1
                continue
            kind = "expense"
            if "收入" in kind_text or "收款" in kind_text or "转入" in kind_text:
                kind = "income"
            elif "不计" in kind_text:
                result["skipped"] += 1
                continue
            occurred = parse_date(value("dateTime"), legacy=True)
            merchant = clean_merchant(value("merchant"))
            item, note = value("item"), value("note")
            account = value("account")
        else:
            kind_text = value("kind")
            if kind_text in ("/", "／") or "不计" in kind_text:
                result["neutral"] += 1
                continue
            kind = "expense"
            if "收入" in kind_text or "收款" in kind_text or "转入" in kind_text:
                kind = "income"
            status = clean_cell(value("status"))
            if any(dead in status for dead in ["交易关闭", "已关闭", "支付失败", "交易失败",
                                               "已撤销", "已取消", "已失效"]):
                result["skipped"] += 1
                continue
            occurred = parse_date(value("dateTime"))
            merchant = clean_merchant(clean_cell(value("merchant")))
            item, note = clean_cell(value("item")), clean_cell(value("note"))
            account = clean_cell(value("account"))

        order = value("orderNumber")
        if not legacy and order:
            key = "no:" + order
        else:
            stamp = int(occurred.timestamp() // 180) if occurred else 0
            key = "%d|%s|%d" % (cents, normalize(merchant), stamp)
        if key in seen:
            result["duplicates"] += 1
            continue
        seen.add(key)

        result["drafts"].append({
            "kind": kind, "cents": cents, "merchant": merchant, "item": item,
            "note": note, "account": account, "order": order, "at": occurred,
            "platform": "wechat" if ("微信" in result["format"] or "零钱" in row_string(row))
                        else "other",
        })

    if not legacy and result["neutral"]:
        result["warnings"].append("已跳过 %d 笔中性交易" % result["neutral"])
    if not result["drafts"]:
        result["warnings"].append("没有解析出任何账单")
    return result, mapping


def row_string(row):
    return " ".join(row)


# ---------------------------------------------------------------- 断言


def summarize(result):
    drafts = result["drafts"]
    income = [d for d in drafts if d["kind"] == "income"]
    expense = [d for d in drafts if d["kind"] == "expense"]
    return {
        "笔数": len(drafts),
        "收入笔数": len(income),
        "收入金额": round(sum(d["cents"] for d in income) / 100, 2),
        "支出笔数": len(expense),
        "支出金额": round(sum(d["cents"] for d in expense) / 100, 2),
        "中性跳过": result["neutral"],
        "跳过": result["skipped"],
        "文件内重复": result["duplicates"],
        "格式": result["format"],
    }


def check(name, actual, expect):
    ok = actual == expect
    print("  [%s] %-22s %r%s" % ("PASS" if ok else "FAIL", name, actual,
                                 "" if ok else "   期望 %r" % (expect,)))
    return ok


WECHAT_SAMPLE = """微信支付账单明细
微信昵称：[测试]
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-08-02 10:17:00,商户消费,依纯便利店,/,支出,¥1.00,零钱通,支付成功,4500000579202610309265247099,1011343602151793354614010800890,/
2026-08-02 11:20:00,转账,味佳美餐厅,转账备注:微信转账,支出,9.00,零钱,对方已收钱,53010003393032202610310720440475,1000050001202610310635403867414,/
2026-08-03 09:00:00,二维码收款,张三,收款方备注:二维码收款,收入,30.00,零钱,已收钱,53110002120225202608031234982793,10001073012026080301235186163612,/
2026-08-03 10:00:00,转入零钱通-来自浦发银行(6354),/,/,/,500.00,浦发银行储蓄卡(6354),支付成功,4500000452202610128293109052,18000079832610120182042865417895,/
2026-08-04 12:00:00,商户消费,某某商店,/,支出,30.00,零钱,已全额退款,4500000268202608032089859622,20260803191950U78038516450543165,/
2026-08-04 12:05:00,某某商店-退款,某某商店,某某商店,收入,30.00,零钱,已全额退款,50102109062026103028556082469,,/
2026-08-05 08:00:00,商户消费,美团平台商户,美团外卖,支出,30.90,零钱,交易关闭,4500000268202608032089859623,20260803191950U78038516450543166,/
"""


def run_builtin():
    rows = parse_csv(WECHAT_SAMPLE)
    result, mapping = build(rows)
    print("内置用例（微信 CSV，含中性交易 / 全额退款 / 已关闭）")
    ok = True
    ok &= check("表头行号", mapping["headerIndex"], 3)
    ok &= check("收支列索引", mapping["kind"], 4)
    ok &= check("金额列索引", mapping["amount"], 5)
    ok &= check("导入笔数", len(result["drafts"]), 5)
    ok &= check("收入笔数", sum(1 for d in result["drafts"] if d["kind"] == "income"), 2)
    ok &= check("中性跳过", result["neutral"], 1)
    ok &= check("关闭行跳过", result["skipped"], 1)
    ok &= check("日期已解析", all(d["at"] is not None for d in result["drafts"]), True)
    ok &= check("首笔时间", str(result["drafts"][0]["at"]), "2026-08-02 10:17:00")
    ok &= check("备注占位符已清空", result["drafts"][0]["note"], "")
    ok &= check("收款人行", result["drafts"][2]["merchant"], "张三")
    return ok


def run_real(path, legacy=False):
    rows = xlsx_rows(path)
    result, mapping = build(rows, legacy=legacy)
    s = summarize(result)
    tag = "旧逻辑" if legacy else "新逻辑"
    print("\n真实账单（%s）%s" % (os.path.basename(path), tag))
    print("  表头行号: %s | 列映射: %s" % (mapping["headerIndex"] if mapping else None,
                                       {k: v for k, v in (mapping or {}).items() if k not in ("headerIndex", "score")}))
    for k, v in s.items():
        print("  %-8s %s" % (k, v))
    dates = [d["at"] for d in result["drafts"] if d["at"]]
    if dates:
        print("  时间范围: %s ~ %s" % (min(dates), max(dates)))
    return s, result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xlsx", nargs="?", help="微信账单 xlsx 路径")
    ap.add_argument("--legacy", action="store_true", help="同时跑旧逻辑做对照")
    args = ap.parse_args()

    ok = run_builtin()

    if args.xlsx:
        if args.legacy:
            run_real(args.xlsx, legacy=True)
        summary, result = run_real(args.xlsx)
        print("\n关键校验（新逻辑）")
        ok &= check("笔数 = 183-2 中性", summary["笔数"], 181)
        ok &= check("收入笔数", summary["收入笔数"], 22)
        ok &= check("收入合计(元)", summary["收入金额"], 2018.84)
        ok &= check("支出笔数", summary["支出笔数"], 159)
        ok &= check("支出合计(元)", summary["支出金额"], 7016.89)
        ok &= check("格式识别", summary["格式"], "微信支付账单")
        ok &= check("时间全部解析", all(d["at"] for d in result["drafts"]), True)
        ok &= check("平台全为微信", all(d["platform"] == "wechat" for d in result["drafts"]), True)

    print("\n%s" % ("全部通过" if ok else "有失败项"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
