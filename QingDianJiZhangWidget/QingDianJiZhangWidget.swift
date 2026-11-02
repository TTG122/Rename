//
//  QingDianJiZhangWidget.swift
//  轻点记账 · 桌面小组件
//
//  小组件进程不打开 SwiftData 主库，只读 App 写好的 JSON 快照，稳定且快。
//

import WidgetKit
import SwiftUI

// MARK: - 数据

struct WidgetSnapshot: Codable {
    struct CategorySlice: Codable, Identifiable {
        var id: String { name }
        let name: String
        let colorHex: String
        let amountCents: Int
    }

    let updatedAt: Date
    let todayExpenseCents: Int
    let todayIncomeCents: Int
    let monthExpenseCents: Int
    let monthIncomeCents: Int
    let monthBudgetCents: Int
    let monthKey: String
    let topCategories: [CategorySlice]
    let lastTransactionTitle: String
    let lastTransactionAmountCents: Int
    let lastTransactionTime: Date

    static let placeholder = WidgetSnapshot(
        updatedAt: .now,
        todayExpenseCents: 8600,
        todayIncomeCents: 0,
        monthExpenseCents: 568_000,
        monthIncomeCents: 1_200_000,
        monthBudgetCents: 800_000,
        monthKey: "",
        topCategories: [
            CategorySlice(name: "吃饭", colorHex: "#FF9F0A", amountCents: 156_000),
            CategorySlice(name: "购物", colorHex: "#FF6B6B", amountCents: 98_000),
            CategorySlice(name: "交通", colorHex: "#4C9AFF", amountCents: 46_000)
        ],
        lastTransactionTitle: "星巴克",
        lastTransactionAmountCents: 3600,
        lastTransactionTime: .now
    )
}

enum WidgetStore {
    static let appGroupIdentifier = "group.com.qingdianjizhang.app"

    static func read() -> WidgetSnapshot {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier),
              let data = try? Data(contentsOf: base.appendingPathComponent("widget-snapshot.json"))
        else {
            return .placeholder
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .placeholder
    }
}

// MARK: - Timeline

struct QingDianEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct QingDianProvider: TimelineProvider {
    func placeholder(in context: Context) -> QingDianEntry {
        QingDianEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QingDianEntry) -> Void) {
        completion(QingDianEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QingDianEntry>) -> Void) {
        let entry = QingDianEntry(date: .now, snapshot: WidgetStore.read())
        // 每 30 分钟刷一次；App 每次记账也会主动 reload
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 颜色

private enum WidgetTheme {
    static let brand = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let expense = Color(red: 0.95, green: 0.42, blue: 0.31)
    static let income = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let secondary = Color.secondary
}

private extension Color {
    init?(widgetHex: String) {
        var s = widgetHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 视图

struct QingDianWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QingDianEntry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.brand)
                Text("今日")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetTheme.secondary)
                Spacer()
            }

            Text("¥\(money(entry.snapshot.todayExpenseCents))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.expense)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("本月 ¥\(money(entry.snapshot.monthExpenseCents))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetTheme.secondary)

            if entry.snapshot.monthBudgetCents > 0 {
                progressBar
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetTheme.brand)
                    Text("本月支出")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetTheme.secondary)
                }

                Text("¥\(money(entry.snapshot.monthExpenseCents))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.expense)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("今日 ¥\(money(entry.snapshot.todayExpenseCents))")
                    Text("收入 ¥\(money(entry.snapshot.monthIncomeCents))")
                }
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.secondary)

                Spacer(minLength: 0)

                if entry.snapshot.monthBudgetCents > 0 {
                    progressBar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.snapshot.topCategories.prefix(3)) { slice in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(widgetHex: slice.colorHex) ?? WidgetTheme.brand)
                            .frame(width: 5, height: 5)
                        Text(slice.name)
                            .font(.system(size: 10))
                            .foregroundStyle(WidgetTheme.secondary)
                        Spacer(minLength: 2)
                        Text(money(slice.amountCents))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                }
                Spacer(minLength: 0)
                Text("双击背面记一笔")
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.brand)
            }
            .frame(width: 108, alignment: .leading)
        }
    }

    private var progressBar: some View {
        let budget = max(entry.snapshot.monthBudgetCents, 1)
        let ratio = min(Double(entry.snapshot.monthExpenseCents) / Double(budget), 1)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(ratio > 1 ? WidgetTheme.expense : WidgetTheme.brand)
                    .frame(width: geometry.size.width * ratio)
            }
        }
        .frame(height: 4)
    }

    private func money(_ cents: Int) -> String {
        let yuan = Double(cents) / 100
        if yuan >= 10_000 {
            return String(format: "%.1f万", yuan / 10_000)
        }
        return String(format: "%.0f", yuan)
    }
}

// MARK: - Widget

struct QingDianJiZhangWidget: Widget {
    let kind: String = "QingDianJiZhangWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QingDianProvider()) { entry in
            QingDianWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("本月花销")
        .description("一眼看到本月支出、今日花销和分类占比。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct QingDianWidgetBundle: WidgetBundle {
    var body: some Widget {
        QingDianJiZhangWidget()
    }
}
