//
//  BrandLexicon.swift
//  轻点记账
//
//  本机品牌/关键词词典。是「规则分类」的核心知识库，
//  同时被 OCR 解析器用来判断哪一行才是真正的商户名。
//
//  维护方式：直接改数组即可，不需要重新训练模型。
//  如需换成 Core ML 模型，见 tools/train_text_classifier.swift。
//

import Foundation

enum BrandLexicon {
    struct Entry {
        let keywords: [String]
        let category: String
        /// 基础权重，越长越具体的词权重越高
        let weight: Double
    }

    static let entries: [Entry] = [
        // MARK: 吃饭
        Entry(keywords: [
            "星巴克", "starbucks", "瑞幸", "luckin", "麦当劳", "mcdonald", "肯德基", "kfc",
            "必胜客", "pizzahut", "汉堡王", "burgerking", "赛百味", "subway",
            "喜茶", "奈雪", "蜜雪冰城", "茶百道", "古茗", "沪上阿姨", "霸王茶姬", "书亦",
            "海底捞", "西贝", "太二", "老乡鸡", "真功夫", "吉野家", "永和大王", "沙县",
            "兰州拉面", "米线", "麻辣烫", "火锅", "烧烤", "烤肉", "日料", "寿司", "拉面",
            "餐厅", "饭店", "餐饮", "小吃", "面馆", "食堂", "食品", "烘焙", "面包", "蛋糕",
            "咖啡", "奶茶", "果茶", "早餐", "午餐", "晚餐", "夜宵", "外卖",
            "美团外卖", "饿了么", "大众点评", "叮咚买菜", "盒马", "钱大妈",
            "全家", "罗森", "便利蜂", "7-11", "7-eleven", "美宜佳"
        ], category: "吃饭", weight: 1.0),

        // MARK: 加油
        Entry(keywords: [
            "中国石化", "中石化", "中国石油", "中石油", "壳牌", "sinopec", "petrochina", "shell",
            "加油站", "加油", "油站", "中国海油", "中海油", "道达尔", "充电桩", "特来电",
            "星星充电", "国网电动", "小桔充电", "蔚来充电", "特斯拉超充"
        ], category: "加油", weight: 1.0),

        // MARK: 游戏
        Entry(keywords: [
            "steam", "腾讯游戏", "网易游戏", "王者荣耀", "和平精英", "原神", "米哈游", "miHoYo",
            "崩坏", "星穹铁道", "绝区零", "蛋仔派对", "迷你世界", "光遇", "第五人格", "英雄联盟",
            "league of legends", "valorant", "csgo", "cs2", "dota", "epic games", "playstation",
            "psn", "nintendo", "switch", "xbox", "游戏", "点卡", "游戏充值", "元宝", "钻石",
            "装备", "皮肤", "月卡", "battle.net", "暴雪", "炉石", "梦幻西游", "穿越火线", "cf"
        ], category: "游戏", weight: 1.0),

        // MARK: 购物
        Entry(keywords: [
            "淘宝", "天猫", "taobao", "tmall", "京东", "jd.com", "拼多多", "pinduoduo",
            "唯品会", "抖音商城", "小红书", "闲鱼", "苏宁", "国美", "得物", "网易严选",
            "优衣库", "uniqlo", "无印良品", "muji", "宜家", "ikea", "名创优品", "miniso",
            "沃尔玛", "walmart", "家乐福", "永辉", "华润万家", "大润发", "山姆", "sam's club",
            "costco", "屈臣氏", "丝芙兰", "sephora", "zara", "h&m", "nike", "adidas",
            "小米之家", "apple store", "苹果商店", "华为商城", "oppo", "vivo",
            "商场", "百货", "超市", "便利店", "五金", "建材", "家具", "服装", "鞋", "箱包",
            "化妆品", "数码", "旗舰店", "专卖店"
        ], category: "购物", weight: 0.9),

        // MARK: 交通
        Entry(keywords: [
            "滴滴", "didi", "曹操出行", "t3出行", "t3出行", "花小猪", "高德打车", "首汽约车",
            "出租车", "打车", "网约车", "地铁", "轨道交通", "公交", "公交集团", "一卡通",
            "高铁", "火车", "12306", "铁路", "机票", "航空", "机场", "国航", "东航", "南航",
            "停车", "停车场", "高速", "通行费", "etc", "过路费", "加油卡", "共享单车",
            "哈啰", "青桔", "摩拜", "美团单车", "uber", "加油费", "车费", "洗车", "保养"
        ], category: "交通", weight: 1.0),

        // MARK: 娱乐
        Entry(keywords: [
            "电影", "影院", "影城", "猫眼", "淘票票", "万达", "cgv", "ktv", "唱吧", "演唱会",
            "大麦", "摩天轮", "剧本杀", "密室", "桌游", "网吧", "网咖", "电玩城", "台球",
            "爱奇艺", "腾讯视频", "优酷", "芒果tv", "bilibili", "哔哩哔哩", "b站",
            "netflix", "spotify", "youtube", "网易云音乐", "qq音乐", "酷狗",
            "健身", "健身房", "游泳", "球馆", "滑冰", "温泉", "洗浴", "按摩", "足疗",
            "会员", "视频会员", "超级会员", "年卡"
        ], category: "娱乐", weight: 0.9),

        // MARK: 房租
        Entry(keywords: [
            "房租", "租金", "押金", "物业费", "物业管理", "中介费", "贝壳", "链家", "自如",
            "蛋壳", "房东", "公寓", "租房", "房贷", "按揭"
        ], category: "房租", weight: 1.0),

        // MARK: 水电
        Entry(keywords: [
            "电费", "水费", "燃气费", "天然气", "煤气", "取暖费", "暖气费", "供热",
            "话费", "手机充值", "宽带", "流量", "中国移动", "中国联通", "中国电信",
            "国家电网", "电力公司", "自来水", "燃气公司", "生活缴费", "缴费", "充值中心",
            "物业费缴纳", "宽带费", "有线电视"
        ], category: "水电", weight: 1.0),

        // MARK: 医疗
        Entry(keywords: [
            "医院", "药店", "药房", "大药房", "诊所", "门诊", "挂号", "体检", "口腔",
            "牙科", "眼科", "中医", "卫生院", "卫生服务", "医药", "药品", "医疗",
            "平安好医生", "微医", "丁香", "疫苗", "住院", "手术", "康复"
        ], category: "医疗", weight: 1.0),

        // MARK: 教育
        Entry(keywords: [
            "学费", "培训", "课程", "网课", "补习", "辅导", "学校", "幼儿园", "大学",
            "考试", "报名费", "教材", "书店", "图书", "当当", "文具", "学习",
            "得到", "极客时间", "混沌", "coursera", "udemy", "慕课", "知识付费",
            "证书", "驾校", "托福", "雅思"
        ], category: "教育", weight: 0.9),

        // MARK: 旅游
        Entry(keywords: [
            "携程", "ctrip", "去哪儿", "飞猪", "同程", "马蜂窝", "酒店", "民宿", "客栈",
            "airbnb", "爱彼迎", "华住", "如家", "汉庭", "亚朵", "希尔顿", "万豪", "洲际",
            "门票", "景区", "旅行", "旅游", "度假", "agoda", "booking", "途家",
            "机票预订", "签证", "导游"
        ], category: "旅游", weight: 1.0),

        // MARK: 人情
        Entry(keywords: [
            "红包", "礼金", "份子钱", "随礼", "送礼", "礼物", "婚礼", "喜宴", "生日",
            "请客", "孝敬", "赡养", "捐赠", "公益", "募捐"
        ], category: "人情", weight: 0.9),

        // MARK: 工作支出
        Entry(keywords: [
            "办公", "打印", "复印", "快递", "顺丰", "中通", "圆通", "韵达", "邮费",
            "名片", "差旅", "会议", "云服务", "阿里云", "腾讯云", "aws", "azure",
            "github", "figma", "adobe", "notion", "openai", "chatgpt", "订阅",
            "域名", "服务器", "软件", "saas", "报销", "发票", "工商", "财税"
        ], category: "工作支出", weight: 0.9),

        // MARK: 收入类
        Entry(keywords: [
            "工资", "薪资", "薪水", "奖金", "绩效", "提成", "补贴", "津贴", "分红",
            "利息", "收益", "理财", "基金", "股票", "退款", "退回", "返现", "到账",
            "报销款", "劳务", "稿费", "兼职"
        ], category: "工资收入", weight: 1.0)
    ]

    /// 归类关键词 → 分类名
    static func category(for text: String) -> (name: String, score: Double)? {
        let normalized = TextNormalizer.normalize(text)
        guard !normalized.isEmpty else { return nil }

        var best: (name: String, score: Double)?
        for entry in entries {
            for keyword in entry.keywords {
                let key = TextNormalizer.normalize(keyword)
                guard !key.isEmpty, normalized.contains(key) else { continue }
                // 命中词越长越可信
                let lengthBonus = min(Double(key.count) / 12.0, 0.35)
                let score = entry.weight + lengthBonus
                if best == nil || score > best!.score {
                    best = (entry.category, score)
                }
            }
        }
        guard let best else { return nil }
        return (best.name, min(best.score, 1.4))
    }

    /// 整段文字中所有命中的分类（用于多维度打分）
    static func allCategoryHits(in text: String) -> [String: Double] {
        let normalized = TextNormalizer.normalize(text)
        guard !normalized.isEmpty else { return [:] }
        var hits: [String: Double] = [:]
        for entry in entries {
            for keyword in entry.keywords {
                let key = TextNormalizer.normalize(keyword)
                guard !key.isEmpty, normalized.contains(key) else { continue }
                let score = entry.weight + min(Double(key.count) / 12.0, 0.35)
                hits[entry.category] = max(hits[entry.category] ?? 0, score)
            }
        }
        return hits
    }

    /// 是否是已知品牌（用于商户名候选打分）
    static func containsKnownBrand(_ text: String) -> Bool {
        category(for: text) != nil
    }

    /// 所有分类名
    static var allCategoryNames: [String] {
        Array(Set(entries.map(\.category)))
    }
}
