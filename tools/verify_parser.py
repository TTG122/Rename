#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
在 Windows / Linux 上校验 ReceiptParser 的判定逻辑（替代 xcodebuild test）。

为什么需要它：ReceiptParser 是纯规则实现，不依赖 UIKit，逻辑可以原样复刻到 Python。
本脚本按 Swift 源码 1:1 移植了「清洗 → 取金额 → 判方向 → 取商户」的决策路径，
并跑 QingDianJiZhangTests/ReceiptParserTests.swift 里的全部断言。

用法：
    python tools/verify_parser.py          # 跑全部用例
    python tools/verify_parser.py --debug  # 同时打印每条的判定依据

注意：这是「逻辑等价验证」，不能替代真机/Xcode 编译。
      改了 ReceiptParser.swift 的规则时，请同步改这里，否则两边会漂移。
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# ---------------------------------------------------------------- 基础工具


def normalize(text: str) -> str:
    """对应 TextNormalizer.normalize：小写、去空白、去标点符号。"""
    s = text.lower()
    s = re.sub(r"[\s]", "", s)
    s = re.sub(r"[!-/:-@\[-`{-~]", "", s)  # ASCII 标点与符号
    s = re.sub(r"[\u2000-\u206F\u3000-\u303F\uFF00-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF40\uFF5B-\uFF65]", "", s)
    return s


def blank_out(pattern: str, text: str) -> str:
    return re.sub(pattern, " ", text, flags=re.I)


def cleaned(line: str) -> str:
    text = line
    text = blank_out(r"\d{4}\s*[-/年.]\s*\d{1,2}\s*[-/月.]\s*\d{1,2}\s*日?", text)
    text = blank_out(r"\d{1,2}\s*[-/月]\s*\d{1,2}\s*日?", text)
    text = blank_out(r"\d{1,2}:\d{2}(:\d{2})?", text)
    text = blank_out(r"\d{3,4}-\d{7,8}", text)
    text = blank_out(r"[A-Za-z0-9]{14,}", text)
    text = blank_out(r"\d{9,}", text)
    return text


def cents_from_text(text: str):
    s = text.replace(",", "").replace("，", "").replace("¥", "").replace("￥", "").strip()
    try:
        v = float(s)
    except ValueError:
        return None
    if not (0 <= v < 100_000_000):
        return None
    return int(round(v * 100))


# ---------------------------------------------------------------- 词表

AMOUNT_KEYWORDS = [
    ("实付款", 100), ("实付", 100), ("实际支付", 100), ("实际付款", 100), ("已付款", 96),
    ("退款金额", 96), ("退款", 92),
    ("支付金额", 95), ("付款金额", 95), ("交易金额", 92), ("订单金额", 90),
    ("应付金额", 88), ("消费金额", 88), ("扣款金额", 88), ("本期应还", 80),
    ("小计", 72), ("合计", 68), ("总计", 66), ("总额", 62), ("金额", 52),
    ("支付", 44), ("付款", 44), ("消费", 40), ("扣款", 40),
]

DISCOUNT_KEYWORDS = [
    "优惠", "折扣", "立减", "红包抵扣", "券", "减免", "返现", "余额",
    "积分", "手续费", "服务费", "找零", "抹零",
]

MERCHANT_BLACKLIST = [
    "支付成功", "付款成功", "交易成功", "支付完成", "已支付", "付款成功页",
    "账单详情", "订单详情", "微信支付", "支付宝", "云闪付", "apple pay",
    "收银台", "确认付款", "立即支付", "查看详情", "查看更多", "交易单号",
    "商户单号", "订单号", "订单编号", "账单", "合计", "总计", "实付", "金额",
    "优惠", "退款", "客服", "帮助中心", "支付方式", "付款方式", "商品", "数量",
    "单价", "时间", "备注", "我的", "首页", "恭喜", "完成", "返回", "银联",
    "银行卡", "订单", "详情", "全部", "收起", "复制", "分享", "评价", "再来一单",
    "查看账单", "安全保障", "中国大陆", "服务中心", "发票", "联系商家", "申请售后",
    "积分", "余额", "零钱", "钱包", "收款方", "付款方", "转账", "银行",
    "类型", "状态", "说明", "明细", "零钱明细", "交易详情", "退款详情", "账单详情", "全部账单",
]

MERCHANT_SUFFIX_HINTS = [
    "店", "餐厅", "饭馆", "超市", "公司", "有限", "酒店", "咖啡", "商城", "商行",
    "影院", "药房", "药店", "医院", "门诊", "中心", "广场", "大厦", "集团", "食品",
    "便利店", "菜馆", "酒家", "茶", "馆", "坊", "铺", "站", "行", "社", "堂", "轩",
]

INCOME_KEYWORDS = [
    "收款成功", "已收款", "收款到账", "收款", "收入", "退款成功", "已退款", "退款到账",
    "退款", "退回", "退货退款",
    "工资", "薪资", "奖金", "红包到账", "到账", "入账", "转入", "返现", "提现",
]

EXPENSE_KEYWORDS = [
    "支付成功", "付款成功", "交易成功", "已支付", "实付", "付款", "支付",
    "消费", "扣款", "支出", "转出", "已扣款", "完成支付",
]


def load_brand_keywords():
    """直接从 Swift 源码里读品牌词典，避免两处维护导致漂移。"""
    path = os.path.join(ROOT, "QingDianJiZhang", "Services", "Classification", "BrandLexicon.swift")
    if not os.path.exists(path):
        return []
    src = open(path, encoding="utf-8").read()
    words = []
    for block in re.findall(r"Entry\(keywords:\s*\[(.*?)\]", src, re.S):
        words.extend(re.findall(r'"([^"]+)"', block))
    return words


BRAND_KEYWORDS = load_brand_keywords()


def contains_known_brand(text: str) -> bool:
    n = normalize(text)
    return any(normalize(w) and normalize(w) in n for w in BRAND_KEYWORDS)


# ---------------------------------------------------------------- 金额

TOKEN_RE = re.compile(r"(?:¥|￥|RMB|CNY)?\s*(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s*(元|块)?", re.I)


def amount_tokens(text: str):
    out = []
    for m in TOKEN_RE.finditer(text):
        cents = cents_from_text(m.group(1))
        if cents is None or not (1 <= cents <= 100_000_000):
            continue
        value = m.group(0).upper()
        out.append({
            "cents": cents,
            "start": m.start(),
            "end": m.end(),
            "has_symbol": ("¥" in value) or ("￥" in value) or ("RMB" in value) or ("CNY" in value),
            "has_yuan": bool(m.group(2)),
            "has_frac": "." in m.group(1),
        })
    return out


def looks_like_order_number(text: str) -> bool:
    digits = "".join(ch for ch in text if ch.isdigit())
    if not digits:
        return False
    if len(digits) >= 12:
        return True
    has_label = any(lab in text for lab in ["单号", "订单", "流水", "凭证", "交易号", "编号"])
    return has_label and len(digits) >= 8


SIGNED_LINE_RE = re.compile(r"^[+＋\-－]\s*[¥￥]?\s*[\d,]+(?:\.\d{1,2})?$")


def extract_amount(lines):
    candidates = []
    safe_tokens = []
    notes = []

    for index, line in enumerate(lines):
        clean = cleaned(line)
        if not clean.strip():
            continue
        if looks_like_order_number(clean):
            notes.append("跳过疑似单号行：" + line)
            continue
        tokens = amount_tokens(clean)
        if not tokens:
            continue

        lowered = normalize(clean)
        prev = normalize(lines[index - 1]) if index > 0 else ""
        is_balance = ("余额" in lowered) or ("可用额度" in lowered) or prev in ("余额", "可用额度")
        is_discount = is_balance or any(normalize(k) in lowered for k in DISCOUNT_KEYWORDS)

        if not is_balance:
            safe_tokens.extend(tokens)

        trimmed = clean.strip()
        if (not is_discount) and SIGNED_LINE_RE.match(trimmed):
            candidates.append({"cents": tokens[0]["cents"], "score": 98, "source": line})

        for keyword, weight in AMOUNT_KEYWORDS:
            pos = clean.lower().find(keyword.lower())
            if pos < 0:
                continue
            after = [t for t in tokens if t["start"] >= pos + len(keyword)] or [tokens[-1]]
            score = weight - 120 if is_discount else weight
            if after[0]["has_symbol"]:
                score += 6
            if after[0]["has_yuan"]:
                score += 3
            candidates.append({"cents": after[0]["cents"], "score": score, "source": line})

        if not is_discount:
            sym = next((t for t in tokens if t["has_symbol"]), None)
            if sym:
                candidates.append({"cents": sym["cents"], "score": 30, "source": line})

    if candidates:
        best = max(candidates, key=lambda c: c["score"])
        if best["score"] > 0:
            notes.append("金额来源：%s（权重 %d）" % (best["source"], best["score"]))
            return best["cents"], notes

    usable = [t for t in safe_tokens if t["has_symbol"] or t["has_yuan"] or t["has_frac"]]
    if usable:
        best = max(usable, key=lambda t: t["cents"])
        notes.append("金额兜底：取带符号或小数的最大金额 %.2f" % (best["cents"] / 100))
        return best["cents"], notes
    notes.append("未识别到可信金额，请手动填写")
    return None, notes


# ---------------------------------------------------------------- 商户

BLOCKED_TOKENS = ["单号", "编号", "流水", "凭证", "订单号", "交易号"]


def _is_cjk(ch: str) -> bool:
    return "\u4e00" <= ch <= "\u9fff"


def clean_merchant(line: str) -> str:
    text = line
    for prefix in ["商户名称", "商户全称", "收款方", "商户", "商家名称", "商家", "交易对方", "名称", "备注"]:
        if text.startswith(prefix):
            text = text[len(prefix):]
    text = text.strip(" :：-—|·、,，")
    for suffix in ["充值", "消费", "支付", "付款", "转账", "退款", "扣款"]:
        if text.endswith(suffix) and len(text) > len(suffix) + 1:
            text = text[: -len(suffix)]
    text = text.strip()
    return text[:24]


def is_plausible_merchant(text: str) -> bool:
    trimmed = text.strip()
    if not (2 <= len(trimmed) <= 40):
        return False
    lowered = normalize(trimmed)
    if not lowered:
        return False
    if any(lowered == normalize(b) for b in MERCHANT_BLACKLIST):
        return False
    if any(tok in trimmed for tok in BLOCKED_TOKENS):
        return False
    readable = sum(1 for ch in trimmed if ch.isalnum() or _is_cjk(ch))
    if readable / max(len(trimmed), 1) < 0.6:
        return False
    cjk = sum(1 for ch in trimmed if _is_cjk(ch))
    return cjk >= 2 or contains_known_brand(trimmed)


def extract_merchant(lines, debug=False):
    notes = []
    label_prefixes = ["商户名称", "商户全称", "交易对方", "收款方", "商家名称", "商户", "商家", "对方"]
    for index, raw in enumerate(lines):
        line = raw.strip()
        for prefix in label_prefixes:
            if line.startswith(prefix):
                value = line[len(prefix):].strip(" :：-—|·、,，")
                if not value and index + 1 < len(lines):
                    value = lines[index + 1].strip()
                name = clean_merchant(value)
                if is_plausible_merchant(name):
                    notes.append("商户来源：标签「%s」" % prefix)
                    return name, notes
    for index, raw in enumerate(lines):
        line = raw.strip()
        if not line.startswith("备注"):
            continue
        value = line[2:].strip(" :：-—|·、,，")
        if not value and index + 1 < len(lines):
            value = lines[index + 1].strip()
        name = clean_merchant(value)
        if is_plausible_merchant(name):
            notes.append("商户来源：备注")
            return name, notes

    candidates = []
    total = max(len(lines), 1)
    for index, raw in enumerate(lines):
        line = raw.strip()
        if not (2 <= len(line) <= 40):
            continue
        if not is_plausible_merchant(line):
            continue
        if sum(1 for ch in line if _is_cjk(ch)) < 3:
            continue
        ratio = index / total
        lowered = normalize(line)
        score = 0.0
        if any(normalize(b) in lowered for b in MERCHANT_BLACKLIST):
            score -= 10
        if contains_known_brand(line):
            score += 2.4
        if any(h in line for h in MERCHANT_SUFFIX_HINTS):
            score += 1.3
        if ratio < 0.45:
            score += 0.9
        if ratio > 0.85:
            score -= 0.6
        if "¥" in line or "￥" in line:
            score -= 1.2
        if re.search(r"\d{1,2}:\d{2}", line):
            score -= 3
        if re.search(r"\d{4}[-/年]", line):
            score -= 3
        digits = sum(1 for ch in line if ch.isdigit())
        if digits > 3:
            score -= 1.6
        if 2 <= len(line) <= 22:
            score += 0.5
        if any(_is_cjk(ch) for ch in line):
            score += 0.4
        if line.startswith("商户") or line.startswith("收款方"):
            score += 1.2
        if score > 0:
            candidates.append((clean_merchant(line), score))
    if candidates:
        best = max(candidates, key=lambda c: c[1])
        if best[0]:
            notes.append("商户来源评分：%.1f" % best[1])
            return best[0], notes
    notes.append("未识别到商户名")
    return "", notes


# ---------------------------------------------------------------- 方向 / 平台 / 单号 / 时间


def detect_signed_kind(text: str):
    plus = minus = 0
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line[0] in "+＋" and re.search(r"^[+＋\-－]\s*[¥￥]?\s*\d", line):
            plus += 1
        elif line[0] in "-－" and re.search(r"^[+＋\-－]\s*[¥￥]?\s*\d", line):
            minus += 1
    if plus > 0 and minus == 0:
        return ("income", 0.90, "金额前缀为 + 号")
    if minus > 0 and plus == 0:
        return ("expense", 0.90, "金额前缀为 − 号")
    return None


def detect_kind(text: str):
    n = normalize(text)
    income_hits = [k for k in INCOME_KEYWORDS if normalize(k) in n]
    expense_hits = [k for k in EXPENSE_KEYWORDS if normalize(k) in n]

    if any(x in n for x in ["退款成功", "已退款", "退款到账", "退货退款"]):
        return ("income", 0.95, "命中退款关键词")
    signed = detect_signed_kind(text)
    if signed:
        return signed
    if len(income_hits) > len(expense_hits):
        return ("income", min(0.95, 0.68 + len(income_hits) * 0.06), "命中「%s」" % income_hits[0])
    if len(expense_hits) > len(income_hits):
        return ("expense", min(0.96, 0.72 + len(expense_hits) * 0.05), "命中「%s」" % expense_hits[0])
    if not expense_hits and not income_hits:
        return ("expense", 0.45, "没有明确方向关键词")
    return ("expense", 0.55, "收支关键词数量相当")


def detect_platform(text: str) -> str:
    n = normalize(text)
    if "微信支付" in n or "wxpay" in n or ("微信" in n and "支付" in n):
        return "wechat"
    if "支付宝" in n or "alipay" in n or "花呗" in n or "余额宝" in n:
        return "alipay"
    if "云闪付" in n or "银联" in n:
        return "unionPay"
    if "applepay" in n or "applepay" in n:
        return "applePay"
    if any(x in n for x in ["储蓄卡", "信用卡", "借记卡"]):
        return "bankCard"
    return "other"


def extract_order_number(text: str) -> str:
    m = re.search(r"(?:订单(?:编)?号|交易单号|商户单号|交易号|流水号|凭证号)\s*[:：]?\s*([A-Za-z0-9]{8,40})", text)
    return m.group(1) if m else ""


def extract_date(text: str):
    m = re.search(r"(\d{4})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})\s*日?\s*(?:(\d{1,2})[:：](\d{2}))?", text)
    if m:
        return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4) or 0)), True
    m = re.search(r"(\d{1,2})[:：](\d{2})(?::\d{2})?", text)
    if m:
        return (0, 0, 0, int(m.group(1))), True
    return (0, 0, 0, 0), False


def overall_confidence(r) -> float:
    score = 0.10
    if (r["amount"] or 0) > 0:
        score += 0.38
    if r["merchant"]:
        score += 0.20
    if r["kind_conf"] >= 0.8:
        score += 0.10
    if r["platform"] != "other":
        score += 0.08
    if r["date_parsed"]:
        score += 0.05
    if r["order"]:
        score += 0.05
    if r["amount"] is None:
        score -= 0.25
    return min(max(score, 0.05), 0.99)


def parse(text: str):
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    joined = "\n".join(lines)
    kind, kind_conf, reason = detect_kind(joined)
    amount, amount_notes = extract_amount(lines)
    merchant, merchant_notes = extract_merchant(lines)
    date, date_parsed = extract_date(joined)
    r = {
        "kind": kind,
        "kind_conf": kind_conf,
        "kind_reason": reason,
        "amount": amount,
        "merchant": merchant,
        "platform": detect_platform(joined),
        "account": "",
        "order": extract_order_number(joined),
        "date": date,
        "date_parsed": date_parsed,
        "notes": ["收支方向：" + reason] + amount_notes + merchant_notes,
    }
    r["confidence"] = overall_confidence(r)
    return r


# ---------------------------------------------------------------- 用例

WECHAT_TEXT = """支付成功
星巴克(国贸店)
¥36.00
微信支付
招商银行储蓄卡(1234)
2026-11-02 09:12:33
商户单号 4200002026110200123"""

WALLET_REFUND = """零钱明细
退款
+4.00
类型
退款
时间
2026年10月31日 18:40:54
交易单号
142745160226022110097341626253429895
余额
¥4.20
备注
京津冀互联互通卡 充值"""

CASES = []


def case(name, text):
    def deco(fn):
        CASES.append((name, text, fn))
        return fn
    return deco


@case("微信支付成功页", WECHAT_TEXT)
def _(r):
    return [
        ("收支方向", r["kind"], "expense"),
        ("金额(分)", r["amount"], 3600),
        ("平台", r["platform"], "wechat"),
        ("商户含「星巴克」", "星巴克" in r["merchant"], True),
        ("订单号非空", bool(r["order"]), True),
        ("综合置信度 > 0.6", r["confidence"] > 0.6, True),
    ]


@case("优惠叠加不取错金额", """支付成功
麦当劳
订单金额 ¥45.00
优惠 -¥9.00
实付金额 ¥36.00
支付宝""")
def _(r):
    return [
        ("金额(分)", r["amount"], 3600),
        ("平台", r["platform"], "alipay"),
    ]


@case("退款成功判收入", """退款成功
淘宝
退款金额 ¥128.00
已退回到支付宝余额""")
def _(r):
    return [
        ("收支方向", r["kind"], "income"),
        ("金额(分)", r["amount"], 12800),
        ("平台", r["platform"], "alipay"),
    ]


@case("单号不当金额", """支付成功
滴滴出行
交易单号 2026110222001234567890
¥23.50
微信支付""")
def _(r):
    return [("金额(分)", r["amount"], 2350)]


@case("日期解析", WECHAT_TEXT)
def _(r):
    return [
        ("解析到日期", r["date_parsed"], True),
        ("年月日时", r["date"], (2026, 11, 2, 9)),
    ]


@case("无方向关键词低置信", "星巴克 36.00")
def _(r):
    return [("方向置信度 < 0.7", r["kind_conf"] < 0.7, True)]


@case("回归·零钱退款金额", WALLET_REFUND)
def _(r):
    return [("金额(分)", r["amount"], 400)]


@case("回归·零钱退款方向", WALLET_REFUND)
def _(r):
    return [
        ("收支方向", r["kind"], "income"),
        ("方向置信度 > 0.7", r["kind_conf"] > 0.7, True),
    ]


@case("回归·零钱退款商户", WALLET_REFUND)
def _(r):
    return [
        ("商户含「京津冀」", "京津冀" in r["merchant"], True),
        ("商户不含「充值」", "充值" in r["merchant"], False),
    ]


@case("回归·余额不当金额", """零钱明细
支出
-12.80
余额
¥1,204.20""")
def _(r):
    return [
        ("金额(分)", r["amount"], 1280),
        ("收支方向", r["kind"], "expense"),
    ]


@case("回归·单号被拆段", """零钱明细
支出
-3.50
交易单号
1427 4516 0226 0221 1009 7341 6262 5342 9895""")
def _(r):
    return [("金额(分)", r["amount"], 350)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--debug", action="store_true", help="打印每条用例的判定依据")
    args = ap.parse_args()

    passed = failed = 0
    for name, text, checker in CASES:
        r = parse(text)
        rows = checker(r)
        ok = all(actual == expect for _, actual, expect in rows)
        mark = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        print("[%s] %s" % (mark, name))
        if not ok or args.debug:
            for label, actual, expect in rows:
                flag = "" if actual == expect else "   <-- 期望 %r" % (expect,)
                print("        %-16s %r%s" % (label, actual, flag))
            if args.debug:
                print("        商户=%r 金额=%s 方向=%s" % (r["merchant"], r["amount"], r["kind"]))
                for n in r["notes"]:
                    print("        · " + n)
    print("\n共 %d 条断言组：%d 通过，%d 失败" % (len(CASES), passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
