import Foundation

let chapterCount = 2_000
let body = String(repeating: "这是一段用于压力测试的中文小说正文。\n", count: 80)
let text = (1...chapterCount).map { "第\($0)章 测试章节\n\(body)" }.joined(separator: "\n")
try Data(text.utf8).write(to: URL(fileURLWithPath: "large-novel.txt"))
print("Generated UTF-16 length:", (text as NSString).length)
