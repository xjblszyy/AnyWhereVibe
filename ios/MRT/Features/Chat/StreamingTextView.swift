import SwiftUI

struct StreamingTextView: View {
    let content: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GHSpacing.sm) {
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value):
                    Text(value)
                        .font(GHTypography.body)
                        .foregroundStyle(GHColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let value):
                    GHCodeBlock(code: value, language: language)
                }
            }

            if isStreaming {
                Text("▍")
                    .font(GHTypography.code)
                    .foregroundStyle(GHColors.accentBlue)
            }
        }
    }

    private var parsedBlocks: [ContentBlock] {
        let pieces = content.components(separatedBy: "```")
        guard pieces.count > 1 else {
            return [.text(content)]
        }

        return pieces.enumerated().compactMap { index, piece in
            if index.isMultiple(of: 2) {
                return piece.isEmpty ? nil : .text(piece)
            }

            let lines = piece.split(separator: "\n", omittingEmptySubsequences: false)
            let language = lines.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = lines.dropFirst().joined(separator: "\n")
            return .code(language: language?.isEmpty == true ? nil : language, value: body)
        }
    }

    private enum ContentBlock {
        case text(String)
        case code(language: String?, value: String)
    }
}
