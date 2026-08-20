import SwiftUI
import UIKit

/// 시스템 공유 시트. 만든 파일은 여기서 사용자가 직접 보낼 때만 기기 밖으로 나간다.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
