# MLX Metal 内核库说明

`mlx.metallib` 是 MLX Swift 运行时的 Metal 着色器内核库。MLX 的 SwiftPM
CLI 构建不会自动把它放进产物目录，也没有随包生成的资源 bundle；运行时
`load_default_library()` 会优先在可执行文件同目录查找 `mlx.metallib`，
因此发布包需要显式复制该文件。

## 来源与校验

- 依赖：`mlx-swift` revision `dc43e62d7055353c7f99fa071a4e71d29dfddc44`（v0.31.4）
- 构建方式：用 Xcode 打开包含 `mlx-audio-swift` 的 SwiftPM 工程后，由
  Xcode 的 SwiftPM 集成生成 `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib`
- 本文件是上述 `default.metallib` 的字节级副本，重命名为 `mlx.metallib`
- SHA-256：`c55b3c363808fa8c9cfa8f8347ca1e1793d4380e1e5c3d72f04d939ee4b2bb2d`

## 更新依赖后如何重新生成

1. 更新 `Package.resolved` 中 `mlx-swift` 的 revision。
2. 用 Xcode 打开工程触发完整依赖构建，取出新生成的
   `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib`。
3. 覆盖本文件并更新上面的 revision 与 SHA-256。

该文件不是模型权重，不包含小说内容，仅包含 MLX 的 Metal 内核。
