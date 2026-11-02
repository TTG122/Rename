//
//  train_text_classifier.swift
//  轻点记账 · 可选增强
//
//  用 CreateML 训练一个本地文本分类模型，让分类多一层「模型判断」。
//  不训练也完全能用——App 的规则词典已经覆盖了绝大多数日常商户。
//
//  运行环境：macOS（CreateML 只能在 macOS 上跑）
//
//  用法：
//    swift tools/train_text_classifier.swift
//    # 产物：tools/QingDianTextClassifier.mlmodel
//    # 把 .mlmodel 拖进 Xcode 工程的 QingDianJiZhang 目录（勾选 app target）
//    # 重新编译后，CoreMLTextClassifier 会自动加载它
//
//  注意：训练样本是脚本里内联的「商户名 → 分类」，你可以按自己的消费习惯继续加。
//

import Foundation
import CreateML

#if canImport(CreateML)

// MARK: - 训练数据

/// 分类 → 该分类下的商户 / 关键词样本
let trainingData: [String: [String]] = [
    "吃饭": [
        "星巴克", "瑞幸咖啡", "麦当劳", "肯德基", "必胜客", "汉堡王",
        "海底捞", "西贝莜面村", "太二酸菜鱼", "老乡鸡", "真功夫",
        "美团外卖", "饿了么", "大众点评", "喜茶", "奈雪的茶", "蜜雪冰城",
        "兰州拉面", "沙县小吃", "黄焖鸡米饭", "麻辣烫", "烧烤", "火锅",
        "公司食堂", "楼下便利店", "早餐店", "面包新语", "好利来"
    ],
    "加油": [
        "中国石化", "中国石油", "中石化", "中石油", "壳牌加油站",
        "中国海油", "加油站", "加满95号", "加满92号", "特来电充电", "星星充电"
    ],
    "游戏": [
        "Steam", "腾讯游戏", "网易游戏", "王者荣耀", "和平精英", "原神",
        "米哈游", "崩坏星穹铁道", "蛋仔派对", "英雄联盟", "点券充值",
        "游戏月卡", "PlayStation", "Nintendo Switch", "Xbox"
    ],
    "购物": [
        "淘宝", "天猫", "京东", "拼多多", "唯品会", "抖音商城", "小红书",
        "得物", "闲鱼", "优衣库", "无印良品", "宜家", "山姆会员店",
        "沃尔玛", "永辉超市", "屈臣氏", "丝芙兰", "名创优品"
    ],
    "交通": [
        "滴滴出行", "高德打车", "曹操出行", "T3出行", "花小猪",
        "地铁", "公交", "12306", "高铁票", "机票", "机场大巴",
        "停车费", "高速通行费", "共享单车", "哈啰单车", "洗车"
    ],
    "娱乐": [
        "万达影城", "猫眼电影", "淘票票", "KTV", "剧本杀", "密室逃脱",
        "爱奇艺会员", "腾讯视频会员", "哔哩哔哩大会员", "网易云音乐",
        "健身房", "游泳馆", "羽毛球馆", "演唱会门票", "大麦网"
    ],
    "房租": [
        "房租", "押金", "物业费", "中介费", "链家", "自如", "贝壳找房"
    ],
    "水电": [
        "电费", "水费", "燃气费", "暖气费", "话费充值", "宽带费",
        "国家电网", "中国移动", "中国联通", "中国电信", "生活缴费"
    ],
    "医疗": [
        "医院挂号", "门诊", "药店", "大药房", "体检中心", "口腔诊所",
        "牙科", "眼科", "社区卫生服务中心", "疫苗接种"
    ],
    "教育": [
        "学费", "培训班", "网课", "书店", "当当网", "文具店",
        "驾校", "考试报名费", "得到APP", "极客时间"
    ],
    "旅游": [
        "携程", "去哪儿", "飞猪", "酒店预订", "民宿", "Airbnb",
        "景区门票", "跟团游", "签证费"
    ],
    "人情": [
        "红包", "礼金", "份子钱", "生日礼物", "婚礼随礼", "请客吃饭"
    ],
    "工作支出": [
        "顺丰快递", "打印复印", "办公用品", "云服务器", "阿里云",
        "腾讯云", "域名续费", "Adobe订阅", "Figma订阅", "差旅报销"
    ],
    "工资收入": [
        "工资", "月薪", "年终奖", "绩效奖金", "报销到账", "退款",
        "利息收入", "基金收益", "红包收入"
    ],
    "其他": [
        "不明支出", "杂项", "其他消费", "临时支出"
    ]
]

// MARK: - 组装 DataFrame

var rows: [(text: String, label: String)] = []
for (label, samples) in trainingData {
    for sample in samples {
        rows.append((text: sample, label: label))
    }
    // 用「分类名 + 样本」再派生一条，增加样本量
    for sample in samples {
        rows.append((text: "\(label) \(sample)", label: label))
    }
}

let table = DataFrame(rows.map { ["text": $0.text, "label": $0.label] })

print("样本数：\(table.rows.count)，分类数：\(Set(rows.map(\.label)).count)")

// MARK: - 训练

do {
    let classifier = try MLTextClassifier(
        trainingData: table,
        textColumn: "text",
        labelColumn: "label"
    )

    let metrics = classifier.trainingMetrics
    print(String(format: "训练准确率：%.1f%%", metrics.classificationError.isNaN ? 0 : (1 - metrics.classificationError) * 100))
    print(String(format: "验证准确率：%.1f%%", (1 - classifier.validationMetrics.classificationError) * 100))

    // 导出
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let outputURL = scriptURL.appendingPathComponent("QingDianTextClassifier.mlmodel")

    try classifier.write(to: outputURL)
    print("已生成：\(outputURL.path)")
    print("下一步：把生成的 .mlmodel 拖进 Xcode 的 QingDianJiZhang 目录，勾选 app target，重新编译即可生效。")

    // 简单自测
    for sample in ["星巴克", "中石化", "Steam 充值", "滴滴打车", "国家电网电费"] {
        if let prediction = try? classifier.prediction(from: sample) {
            print("  \(sample) → \(prediction)")
        }
    }
} catch {
    print("训练失败：\(error)")
    exit(1)
}

#else

print("这个脚本需要在 macOS 上运行（CreateML 仅支持 macOS）。")
print("在没有模型的情况下，轻点记账会完全使用内置规则词典，功能不受影响。")

#endif
