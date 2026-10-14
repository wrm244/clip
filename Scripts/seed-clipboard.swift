import AppKit
import Foundation

// 按内容清单依次写入系统剪贴板，模拟真实用户的连续复制动作，
// 让 Clip 的 changeCount 轮询把每一条都当成独立记录收进去。
// 注意：绝不能写入 com.river.clip.marker，那是 Clip 自己回填用的防回环标记。

struct Seed: Decodable {
    var mode: String        // string | textfile | image | files | rtf
    var value: String?
    var bold: String?
    var path: String?
    var paths: [String]?
}

func writeString(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}

func writeRTF(plain: String, bold: String?) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(plain, forType: .string)

    func esc(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "{": out += "\\{"
            case "}": out += "\\}"
            default: out.append(ch)
            }
        }
        return out
    }

    var body = ""
    if let bold, !bold.isEmpty, let r = plain.range(of: bold) {
        let head = String(plain[plain.startIndex..<r.lowerBound])
        let tail = String(plain[r.upperBound...])
        body = esc(head) + "{\\b " + esc(bold) + "\\b0}" + esc(tail)
    } else {
        body = esc(plain)
    }

    let rtf = "{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fswitch\\fmodern Helvetica;}}\\f0\\fs24 " + body + "}"
    pb.setData(rtf.data(using: .utf8)!, forType: .rtf)
}

func writeImage(path: String) -> Bool {
    guard let img = NSImage(contentsOfFile: path),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    let pb = NSPasteboard.general
    pb.clearContents()
    // 只放 PNG/TIFF，不放 file URL —— 否则会被归类成「文件」而不是「图片」
    pb.setData(png, forType: .png)
    pb.setData(tiff, forType: .tiff)
    return true
}

func writeFiles(paths: [String]) {
    let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) as NSURL }
    guard !urls.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects(urls)
}

// MARK: - 入口

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, args[0] == "run" else {
    FileHandle.standardError.write("usage: clipseed run <content.json>\n".data(using: .utf8)!)
    exit(2)
}

let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let seeds = try JSONDecoder().decode([Seed].self, from: data)

let gap: UInt32 = args.count >= 3 ? (UInt32(args[2]) ?? 1000) : 1000

for (i, seed) in seeds.enumerated() {
    var label = ""
    switch seed.mode {
    case "string", "textfile":
        let text: String
        if seed.mode == "string" {
            text = seed.value ?? ""
        } else {
            guard let p = seed.path, let d = try? Data(contentsOf: URL(fileURLWithPath: p)) else {
                FileHandle.standardError.write("skip (unreadable): \(seed.path ?? "?")\n".data(using: .utf8)!)
                continue
            }
            text = String(data: d, encoding: .utf8) ?? ""
        }
        writeString(text)
        label = String(text.prefix(28)).replacingOccurrences(of: "\n", with: " ")
    case "rtf":
        writeRTF(plain: seed.value ?? "", bold: seed.bold)
        label = "RTF " + String((seed.value ?? "").prefix(24))
    case "image":
        guard let p = seed.path, writeImage(path: p) else {
            FileHandle.standardError.write("skip (bad image): \(seed.path ?? "?")\n".data(using: .utf8)!)
            continue
        }
        label = "图片 " + (seed.path ?? "")
    case "files":
        writeFiles(paths: seed.paths ?? [])
        label = "文件 x\((seed.paths ?? []).count)"
    default:
        continue
    }

    print(String(format: "[%2d/%2d] %@", i + 1, seeds.count, label))
    fflush(stdout)
    Thread.sleep(forTimeInterval: Double(gap) / 1000.0)
}

print("done — \(seeds.count) items")