//
//  ShareViewController.swift
//  轻点记账 · 分享扩展
//
//  在微信 / 支付宝 / 相册里点「分享」→ 选「轻点记账」，截图会落到 App Group
//  的收件箱，然后尝试唤起主 App 直接弹出识别面板。
//
//  如果系统不允许扩展唤起宿主 App（不同 iOS 版本表现不同），收件箱里的图片
//  会在下次打开 App 时自动处理，不会丢。
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        Task { await handleSharedItems() }
    }

    // MARK: - UI

    private func configureUI() {
        view.backgroundColor = .clear

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "正在发送到轻点记账…"
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        card.addSubview(spinner)
        card.addSubview(statusLabel)
        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 240),

            spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
    }

    // MARK: - 处理分享内容

    private func handleSharedItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(with: "没有收到内容")
            return
        }

        var savedCount = 0

        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = await loadImageData(from: provider),
                       SharedInboxSupport.enqueue(imageData: data, source: "share") != nil {
                        savedCount += 1
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider),
                       !text.isEmpty,
                       SharedInboxSupport.enqueue(text: text, source: "share") != nil {
                        savedCount += 1
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let text = await loadText(from: provider),
                       !text.isEmpty,
                       SharedInboxSupport.enqueue(text: text, source: "share") != nil {
                        savedCount += 1
                    }
                }
            }
        }

        if savedCount == 0 {
            finish(with: "没有识别到可用的截图")
            return
        }

        statusLabel.text = "已发送 \(savedCount) 项，正在打开轻点记账…"
        openHostApp()
        finish(with: "已发送 \(savedCount) 项\n如果没有自动跳转，请手动打开轻点记账")
    }

    // MARK: - 读取附件

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - 唤起主 App

    private func openHostApp() {
        guard let url = URL(string: "qingdianjizhang://import") else { return }

        // 首选官方 API
        extensionContext?.open(url) { [weak self] success in
            if !success {
                // 部分 iOS 版本分享扩展不允许直接 open，走 responder chain 兜底
                self?.openViaResponderChain(url)
            }
        }
    }

    private func openViaResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    private func finish(with message: String) {
        statusLabel.text = message
        spinner.stopAnimating()
        spinner.isHidden = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
