//
//  ActivityView.swift
//  轻点记账
//
//  系统分享面板包装。用于导出 CSV / Excel / PDF / 长图、以及分享月报。
//

import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.permittedArrowDirections = []
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 简单的分享触发状态
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
