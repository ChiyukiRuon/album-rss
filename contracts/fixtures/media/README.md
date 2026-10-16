# contracts/fixtures/media

图片与视频提取的 golden fixtures：正文 HTML、原文地址、服务地址与附件，以及期望的媒体（地址、宽高、说明、视频类型与封面）和段落。用于保证两端对同一正文的提取顺序与结果一致。

两端读取同一组文件：

- Web：`apps/web/src/lib/parseEntry.test.ts`（jsdom 环境）
- Swift：`swift/AlbumCore/Tests/AlbumCoreTests/EntryParserTests.swift`

修改或新增样例后，两端的测试都要通过。样例不得包含真实凭据或私人订阅内容。
