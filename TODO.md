## v0.1 最小 demo

- [x] 先收敛最小核心数据结构：`Point` / `Stroke`
- [x] 只做最基础的交互：添加笔画、套索选择笔画、删除笔画
- [x] 先打通一个宿主最小 demo：浏览器扩展
- [x] 浏览器扩展中完成 Zig WASM ABI 到前端交互的最小闭环
- [ ] lit 前端页面
- [ ] VSCode 扩展作为同阶段次要宿主，放在浏览器 demo 跑通之后
- [ ] 暂时不做图层、时间线、文档树等完整 Grease Pencil 系统
- [ ] 暂时不做 Blender 插件集成
- [ ] 暂时不做 tilt / twist / eraser 等扩展硬件字段
- [ ] 暂时只做内存态，不做存储方案

### 人工refactor

接口/字段设计很重要

- [ ] zig-protobuf 生成 .zig接口文件，并实施 客户端/服务端 双架构
- [ ] zig 编译为 .so与.wasm
- [ ] 编写lit前端组件
- [ ] protobuf 生成 js 脚本(纯客户端)
- [ ] 组装为 xpi/crx -> vscode .vsix -> blender拓展

## v0.2 数据模型扩展 & Blender 对齐

- [ ] 参考 [grease_pencil.cc](vendor/upbge-blender/makesdna/DNA_grease_pencil_types.h#L221)，逐步引入 `Drawing` / `Layer` / `Frame` 等结构
  - [grease_pencil.cc](vendor/upbge-blender/blenkernel/intern/grease_pencil.cc:380)
  - [DNA_curves_types.h](vendor/upbge-blender/makesdna/DNA_curves_types.h)
  - [DNA_curve_types.h](vendor/upbge-blender/makesdna/DNA_curve_types.h)
  - [DNA_attribute_types.h](vendor/upbge-blender/makesdna/DNA_attribute_types.h)
  - [curves_geometry.cc](vendor/upbge-blender/blenkernel/intern/curves_geometry.cc:45)
- [ ] 只对齐当前功能真正需要的字段，不一次性照搬 Blender 全部数据模型
- [ ] 方案探索：如何植入 Blender；维护两套 Grease Pencil 是否值得
- [ ] 明确 Blender C/C++ 侧实现与 Zig 自有实现之间的 ABI / 数据结构边界

## v0.3 存储 & 通信协议

- [ ] 先定义文件存储和消息传输共用的 schema，可考虑 protobuf v3
- [ ] 明确 proto 只承载可持久化/可同步的文档语义，不承载 ABI、allocator、缓存和脏标记
- [ ] 明确导入导出边界、运行时间同步策略、内存所有权和版本兼容策略
- [ ] 在 schema 稳定后，再探索客户端 / 服务端双架构
- [ ] 评估多 wasm 实例方案：
      仅保留最顶层 wasm；
      其余实例导出到顶层工作空间并卸载多余服务；
      只保留双向消息管道；
      子 wasm 定期备份并支持顶部 wasm 退出后的恢复导入

## v0.4 硬件输入 & 体验优化

- [ ] 引入压感、倾角等笔专有硬件字段
- [ ] 在已有宿主上补齐体验优化，而不是先扩新架构
