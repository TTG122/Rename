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
    "名片", "二维码收款", "二维码", "收款账户",
]

PROMO_WORDS = [
    "返现", "领取", "立即", "最高", "专享", "免单", "抽中", "贴纸", "红包", "优惠",
    "抵扣", "积分", "券", "笔笔", "更多信息", "有礼", "体验金", "一键领", "查看",
    "购买", "推荐", "到手", "周边",
]

MASKED_PREFIXES = ("*", "＊")

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
    "支付成功", "付款成功", "交易成功", "转账成功", "已支付", "实付", "付款", "支付",
    "消费", "扣款", "支出", "转出", "已扣款", "完成支付",
]

# 一笔记录的「标题行」：一张图里出现多个，说明画面里不止一笔
BLOCK_TITLE_KEYWORDS = [
    "支付成功", "付款成功", "转账成功", "收款成功", "交易成功", "支付完成",
    "退款成功", "退款到账", "收款到账", "转账到账", "扣款成功", "还款成功", "已收款",
]

SENTENCE_MARKS = ["，", "。", "！", "？", "；", ",", "!", "?", ";", "、"]
SENTENCE_WORDS = [
    "已收款", "资金", "存入", "已存入", "请", "点击", "已到账", "注意",
    "支付成功", "转账成功", "收款成功", "交易成功",
]

PREFERRED_TIME_LABELS = ["收款时间", "支付时间", "付款时间", "交易时间", "扣款时间", "转账时间", "创建时间"]

# 页面字段名 / 状态说明，不是收支方向依据（转账付款页有「收款账户」「收款银行」）
NON_DIRECTIONAL_PHRASES = [
    "收款账户", "收款银行", "收款方全称", "收款方名称", "收款方备注", "收款方名片", "收款方画像",
    "收款方", "收款单位", "收款人", "付款账户", "付款银行", "付款方全称", "付款方",
    "转账单号", "交易单号", "商户单号", "订单编号", "订单号", "二维码收款",
    "银行处理中", "处理中",
]

DATE_PATTERN = r"(\d{4})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})\s*日?\s*(?:(\d{1,2})[:：](\d{2}))?"


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
    """只看连续数字的最长一段：银行短信里多个金额拼起来超过 12 位，但不是单号。"""
    runs = [len(m) for m in re.findall(r"\d+", text)]
    if not runs:
        return False
    longest = max(runs)
    if longest >= 12:
        return True
    has_label = any(lab in text for lab in ["单号", "订单", "流水", "凭证", "交易号", "编号"])
    return has_label and longest >= 8


SIGNED_LINE_RE = re.compile(r"^[+＋\-－]\s*[¥￥]?[\d,]+(?:\.\d{1,2})?$")
SIGNED_FULL_RE = re.compile(r"^[+＋\-－]\s*[¥￥]?\s*[\d,]+(?:\.\d{1,2})?\s*(?:元|块)?$")
PURE_AMOUNT_RE = re.compile(r"^[+＋\-－]?\s*[¥￥]?\s*[\d,]+(?:\.\d{1,2})?\s*(?:元|块)?$")


def extract_amount(lines):
    candidates = []
    safe_tokens = []
    notes = []
    pending = None  # (keyword, weight)：标签与金额分两行时，金额继承标签权重

    for index, line in enumerate(lines):
        clean = cleaned(line)
        if not clean.strip():
            continue
        if looks_like_order_number(clean):
            notes.append("跳过疑似单号行：" + line)
            continue
        tokens = amount_tokens(clean)
        if not tokens:
            label = clean.strip()
            if 2 <= len(label) <= 8:
                for kw, w in AMOUNT_KEYWORDS:
                    if kw in label:
                        pending = (kw, w)
                        break
            continue

        lowered = normalize(clean)
        prev = normalize(lines[index - 1]) if index > 0 else ""
        prev_is_balance = prev.endswith("余额") or prev == "可用额度"
        balance_pos = clean.find("余额")
        if balance_pos < 0:
            balance_pos = clean.find("可用额度")

        def is_balance(t):
            if prev_is_balance:
                return True
            if balance_pos >= 0:
                return t["start"] >= balance_pos
            return False

        prev_is_discount_label = bool(prev) and len(prev) <= 4 and any(
            normalize(k) in prev for k in DISCOUNT_KEYWORDS
        )
        line_is_discount = prev_is_discount_label or any(
            normalize(k) in lowered for k in DISCOUNT_KEYWORDS if k != "余额"
        )

        for t in tokens:
            if not is_balance(t):
                safe_tokens.append(t)

        trimmed = clean.strip()
        single = tokens[0] if len(tokens) == 1 else None
        if single and not line_is_discount and not is_balance(single) and SIGNED_LINE_RE.match(trimmed):
            candidates.append({"cents": single["cents"], "score": 98, "source": line})

        # 整行只有一个金额，是中国支付回执里的主金额行
        if single and not line_is_discount and not is_balance(single) and PURE_AMOUNT_RE.match(trimmed):
            score = 96 + (4 if index <= 2 else 0)
            if pending:
                inherited = (pending[1] + (6 if single["has_symbol"] else 0)
                             + (3 if single["has_yuan"] else 0) + 4)
                score = max(score, inherited)
            candidates.append({"cents": single["cents"], "score": score, "source": line})

        for keyword, weight in AMOUNT_KEYWORDS:
            pos = clean.lower().find(keyword.lower())
            if pos < 0:
                continue
            after = [t for t in tokens if t["start"] >= pos + len(keyword)] or [tokens[-1]]
            score = weight
            if line_is_discount or is_balance(after[0]):
                score -= 120
            if after[0]["has_symbol"]:
                score += 6
            if after[0]["has_yuan"]:
                score += 3
            candidates.append({"cents": after[0]["cents"], "score": score, "source": line})

        if not line_is_discount:
            sym = next((t for t in tokens if t["has_symbol"] and not is_balance(t)), None)
            if sym:
                candidates.append({"cents": sym["cents"], "score": 30, "source": line})

        pending = None

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


def _is_kana(ch: str) -> bool:
    return "\u3040" <= ch <= "\u30ff"


def clean_merchant(line: str) -> str:
    text = line
    for prefix in [
        "商户全称", "商户名称", "商户简称", "商家全称", "商家名称", "商家简称",
        "收款方全称", "收款方名称", "收款单位", "收款账户", "交易对方",
        "商户", "商家", "收款方", "名称", "备注",
    ]:
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
    if any(m in trimmed for m in SENTENCE_MARKS):
        return False
    if any(w in trimmed for w in SENTENCE_WORDS):
        return False
    if any(w in trimmed for w in PROMO_WORDS):
        return False
    if trimmed[0] in MASKED_PREFIXES:
        return False
    readable = sum(1 for ch in trimmed if ch.isalnum() or _is_cjk(ch) or _is_kana(ch))
    if readable / max(len(trimmed), 1) < 0.6:
        return False
    cjk = sum(1 for ch in trimmed if _is_cjk(ch))
    kana = sum(1 for ch in trimmed if _is_kana(ch))
    return cjk >= 2 or kana >= 2 or contains_known_brand(trimmed)


def extract_merchant(lines, debug=False):
    notes = []
    # 长标签必须排在短标签前面，否则「商户简称」会被「商户」截断
    label_prefixes = [
        "商户全称", "商户名称", "商户简称", "收款方全称", "收款方名称", "收款单位", "收款账户",
        "交易对方", "商家全称", "商家名称", "商家简称", "商户", "商家", "收款方", "对方",
    ]
    for index, raw in enumerate(lines):
        line = raw.strip()
        if line.startswith("收款方备注"):
            continue
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

    # 个人转账：付款-给XXX / 转账给XXX
    m = re.search(r"(?:付款|转账|收款)[-—－]?\s*给\s*([^，。、,;；\s]{1,20})", "\n".join(lines))
    if m:
        name = clean_merchant(m.group(1))
        if is_plausible_merchant(name):
            notes.append("商户来源：付款对象「给%s」" % name)
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
        # 分数太低说明没有任何正向证据，多半是页面说明文字
        if best[0] and best[1] >= 1.5:
            notes.append("商户来源评分：%.1f" % best[1])
            return best[0], notes
    notes.append("未识别到商户名")
    return "", notes


# ---------------------------------------------------------------- 方向 / 平台 / 单号 / 时间


def strip_non_directional(text: str) -> str:
    result = text
    for phrase in NON_DIRECTIONAL_PHRASES:
        result = result.replace(phrase, " ")
    result = re.sub(r"预计[^，。\n]{0,10}到账", " ", result)
    return result


def detect_signed_kind(text: str):
    plus = minus = 0
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if SIGNED_FULL_RE.match(line):
            if line[0] in "+＋":
                plus += 1
            elif line[0] in "-－":
                minus += 1
    if plus > 0 and minus == 0:
        return ("income", 0.90, "金额前缀为 + 号")
    if minus > 0 and plus == 0:
        return ("expense", 0.90, "金额前缀为 − 号")
    return None


def detect_kind(text: str):
    n = normalize(strip_non_directional(text))
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
    # 「零钱」是微信独有的说法（支付宝叫余额宝 / 余额）
    if "零钱" in n:
        return "wechat"
    if "支付宝" in n or "alipay" in n or "花呗" in n or "余额宝" in n:
        return "alipay"
    if "云闪付" in n or "银联" in n:
        return "unionPay"
    if "applepay" in n:
        return "applePay"
    if any(x in n for x in ["储蓄卡", "信用卡", "借记卡"]):
        return "bankCard"
    return "other"


def extract_order_number(text: str) -> str:
    m = re.search(r"(?:订单(?:编)?号|交易单号|商户单号|交易号|流水号|凭证号)\s*[:：]?\s*([A-Za-z0-9]{8,40})", text)
    return m.group(1) if m else ""


def _match_date(text: str):
    m = re.search(DATE_PATTERN, text)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4) or 0))


def extract_date(text: str):
    # 1) 带标签的时间优先：收款时间 / 支付时间 / 交易时间……
    for label in PREFERRED_TIME_LABELS:
        pos = text.find(label)
        if pos < 0:
            continue
        found = _match_date(text[pos + len(label): pos + len(label) + 48])
        if found:
            return found, True
    # 2) 全文第一个完整日期
    found = _match_date(text)
    if found:
        return found, True
    # 3) 只有时间
    m = re.search(r"(\d{1,2})[:：](\d{2})(?::\d{2})?", text)
    if m:
        return (0, 0, 0, int(m.group(1))), True
    return (0, 0, 0, 0), False


def is_block_title(line: str) -> bool:
    text = line.strip()
    if not (2 <= len(text) <= 12):
        return False
    if "¥" in text or "￥" in text:
        return False
    if any(ch.isdigit() for ch in text):
        return False
    n = normalize(text)
    for keyword in BLOCK_TITLE_KEYWORDS:
        k = normalize(keyword)
        if not k:
            continue
        if n == k or (n.endswith(k) and len(text) <= len(k) + 2):
            return True
    return False


def split_blocks(lines):
    blocks, current, has_title = [], [], False
    for line in lines:
        titled = is_block_title(line)
        if titled and has_title:
            blocks.append(current)
            current = [line]
            has_title = True
        else:
            current.append(line)
            if titled:
                has_title = True
    if current:
        blocks.append(current)
    return blocks


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

    blocks = split_blocks(lines)
    # 只有真正带金额的块才算一笔，避免 OCR 把标题重复一行就误判成两笔
    receipt_blocks = [b for b in blocks if any(amount_tokens(cleaned(l)) for l in b)]
    is_multi = len(receipt_blocks) > 1
    scope = receipt_blocks[0] if is_multi else lines
    joined = "\n".join(scope)

    kind, kind_conf, reason = detect_kind(joined)
    amount, amount_notes = extract_amount(scope)
    merchant, merchant_notes = extract_merchant(scope)
    date, date_parsed = extract_date(joined)
    notes = []
    if is_multi:
        notes.append("检测到 %d 笔记录，只解析最上面一笔；要记其他笔请单独截图" % len(receipt_blocks))
    r = {
        "kind": kind,
        "kind_conf": kind_conf,
        "kind_reason": reason,
        "amount": amount,
        "merchant": merchant,
        "platform": detect_platform(joined),
        "account": "零钱" if "零钱" in joined else "",
        "order": extract_order_number(joined),
        "date": date,
        "date_parsed": date_parsed,
        "blocks": len(receipt_blocks),
        "notes": notes + ["收支方向：" + reason] + amount_notes + merchant_notes,
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


# ---------------------------------------------------------------- 真机截图样本


@case("截图·相册里两笔（转账7300 + 支付6251）", """10:17
转账成功
¥7300.00
10:40
支付成功
¥6251.00""")
def _(r):
    return [
        ("识别到笔数", r["blocks"], 2),
        ("金额(分)", r["amount"], 730000),
        ("收支方向", r["kind"], "expense"),
        ("商户为空", r["merchant"], ""),
    ]


@case("截图·收款到账 1000（你已收款）", """你已收款，资金已存入零钱
¥1000.00
零钱余额
转账时间 2026年07月29日 09:17:55
收款时间 2026年07月29日 10:28:27""")
def _(r):
    return [
        ("金额(分)", r["amount"], 100000),
        ("收支方向", r["kind"], "income"),
        ("商户为空", r["merchant"], ""),
        ("取收款时间", r["date"], (2026, 7, 29, 10)),
        ("平台", r["platform"], "wechat"),
    ]


@case("截图·药店支付 96", """支付成功
意民平价大药房
¥96.00
完成""")
def _(r):
    return [
        ("金额(分)", r["amount"], 9600),
        ("收支方向", r["kind"], "expense"),
        ("商户含「意民」", "意民" in r["merchant"], True),
    ]


# ---------------------------------------------------------------- 第二批真机截图

ALIPAY_24 = """12:51
支付成功
回首页
¥24.00
*锶锶  ¥24.00
付款方式 支付宝小荷包(小红车)
支付宝积分+2 体验金+18 一键领
支付有礼
获得最高5元碰一下支付红包
立即领
丸美 小红笔眼霜4.0
到手超4支眼霜量 再送生日周边
立即购买
完成"""


@case("截图·支付宝24元（营销文案里有「5元」）", ALIPAY_24)
def _(r):
    return [
        ("金额(分)", r["amount"], 2400),
        ("收支方向", r["kind"], "expense"),
        ("平台", r["platform"], "alipay"),
        ("商户为空", r["merchant"], ""),
    ]


@case("截图·微信扫码付款给个人", """22:28
账单
扫二维码付款-给みや、
-130.00
当前状态 支付成功
收款方备注 二维码收款
支付方式 零钱通
转账时间 2026年8月12日 22:11:14
转账单号
10001073012026081200412311519112
对订单有疑惑 发起群收款
申请电子凭证""")
def _(r):
    return [
        ("金额(分)", r["amount"], 13000),
        ("收支方向", r["kind"], "expense"),
        ("商户为收款人", r["merchant"], "みや"),
        ("平台", r["platform"], "wechat"),
        ("取转账时间", r["date"], (2026, 8, 12, 22)),
    ]


@case("截图·淘宝账单 705（商户简称）", """21:10
淘宝平台商户
-705.00
当前状态 支付成功
支付时间 2025年10月2日 18:23:50
商户简称 淘宝平台商户
收单机构 财付通支付科技有限公司
支付方式 工商银行储蓄卡(0092)
由网联清算有限公司提供付款清算服务
交易单号 4440302262202510028845408022
商户单号 11180600725100219797815313210""")
def _(r):
    return [
        ("金额(分)", r["amount"], 70500),
        ("商户", r["merchant"], "淘宝平台商户"),
        ("取支付时间", r["date"], (2025, 10, 2, 18)),
    ]


@case("截图·转账成功 50 万（收款账户不是收入信号）", """完成
转账成功
预计10秒内到账，实际时间取决于收款银行。
转账金额 500,000.00元
收款账户 苏州悦贵房地产开发有限公司""")
def _(r):
    return [
        ("金额(分)", r["amount"], 50000000),
        ("收支方向", r["kind"], "expense"),
        ("商户", r["merchant"], "苏州悦贵房地产开发有限公司"),
    ]


@case("截图·抖音电商 16434.42（订单金额更大）", """16:39
账单详情
抖音电商商家
-16,434.42
交易成功
订单金额 16435.00
花呗立减 -0.58
支付时间 2026-07-05 16:30:23
付款方式 余额宝 11,434.42
花呗 5,000.00
组合支付
商品说明 抖音电商-订单编号
支付奖励 立即领取50积分
收款方全称 上海格物致品网络科技有限公司""")
def _(r):
    return [
        ("金额(分)", r["amount"], 1643442),
        ("收支方向", r["kind"], "expense"),
        ("商户", r["merchant"], "上海格物致品网络科技有限公司"),
    ]


@case("截图·抖音支付 487.20（还款金额 500 更大）", """08:17
支付成功
已提交银行处理
¥487.20
立减优惠 -¥12.80
还款进度 银行处理中，预计今天到账
还款金额 ¥500.00
更多信息
抖音支付 笔笔返现10%
最高1.8元生活缴费券
2元抖音打车券
+6抖音支付积分
完成""")
def _(r):
    return [
        ("金额(分)", r["amount"], 48720),
        ("收支方向", r["kind"], "expense"),
        ("商户为空", r["merchant"], ""),
    ]


@case("截图·深圳通 6.99（订单金额 7.00 更大）", """账单详情
深圳通
-6.99
自动付款成功
订单金额 ¥7.00
抖音支付立减 ¥0.01
付款方式 抖音支付(工行信用卡4735)
抽中奖品 得0.01元红包，点击查看
商品说明 抖音乘车码乘车-地铁2026-07-27 16:17:24
支付时间 2026-07-27 17:27:24
商户全称 深圳市深圳通有限公司""")
def _(r):
    return [
        ("金额(分)", r["amount"], 699),
        ("收支方向", r["kind"], "expense"),
        ("商户", r["merchant"], "深圳市深圳通有限公司"),
        ("取支付时间", r["date"], (2026, 7, 27, 17)),
    ]


@case("格式·实付与金额分两行", """支付成功
肯德基
订单金额
¥45.00
优惠
-¥9.00
实付
¥36.00""")
def _(r):
    return [
        ("金额(分)", r["amount"], 3600),
        ("商户", r["merchant"], "肯德基"),
    ]


@case("格式·银行短信（余额与消费金额同一行）",
      "您尾号1234的储蓄卡10月23日14:22消费人民币58.00元，余额1,204.20元。【招商银行】")
def _(r):
    return [
        ("金额(分)", r["amount"], 5800),
        ("收支方向", r["kind"], "expense"),
        ("平台", r["platform"], "bankCard"),
    ]


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
