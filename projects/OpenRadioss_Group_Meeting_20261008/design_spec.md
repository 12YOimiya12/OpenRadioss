<!-- ppt-master-schema: design-spec/v1 -->
# OpenRadioss Monthly Group Meeting - Design Spec

## I. Project Information

| Item | Value |
| --- | --- |
| Project Name | OpenRadioss Monthly Group Meeting |
| Canvas Format | PPT 16:9 (1280 × 720) |
| Page Count | 9 |
| Primary Language | zh-CN |
| Target Audience | 课题组成员与导师，具备计算力学和有限元仿真基础 |
| Communication Intent | 按工作递进汇报本月进展：先说明 OpenRadioss 本机构建与基础跑通，再展示工程算例，重点讲清 KF LAW99 从工具链迁移、数值验证到可视化后处理的闭环，并区分已验证内容与尚待验证的研究问题。 |
| Desired Audience Outcome | 听众能够复述本月完成的技术闭环、判断各项验证结论的适用边界，并对参数标定、损伤正则化等后续工作形成共同认识。 |
| Core Message / Ask / Action | 一个月内，工作从 OpenRadioss 本机可构建推进到 KF LAW99 可编译、可验证、可求解并可后处理；当前证明的是软件接口与数值闭环，材料预测能力仍需实验标定和模型完善。 |
| Delivery Context | 课题组现场口头汇报，预计 10–15 分钟并留出讨论时间；会后作为阶段进展记录。 |
| Artifact Afterlife | 供组会讨论、阶段工作归档及后续任务交接；关键数值和未完成项需能独立阅读。 |
| Reading Mode | presentation |
| Content Strategy | 以 summary.md 为事实边界，突出三阶段主线与关键证据；压缩命令、路径和配置细节。准确标注气囊算例在 A042 处手工中断，区分材料点 8/8 检查与 3 项 NOT_CERTIFIED，不把接口闭环等同于实验标定或复杂冲击验证。 |
| Design Style | Briefing 模式，Sketch Notes 视觉风格；白底上的轻手绘分隔、柔和色块与清晰标注，服务于中性事实汇报。 |
| AI Image Acquisition Path | Not applicable; image usage is none |
| Generation Mode | continuous |
| Spec Refinement | disabled |
| Speaker Notes | enabled — final Stage-2 proactive policy |
| Custom Animations | disabled — final Stage-2 proactive policy |
| Narration Audio | disabled — final Stage-2 proactive policy |
| Created Date | 2026-10-08 |

- **Template Application**: 保留已确认的 16:9 画布，采用 Academic Research 的证据链与限制说明；使用 Google 蓝、绿、黄作为克制的视觉色彩参考，但不放置 Google 字标或 G 标，避免暗示品牌关联。Moments Square 仅参考其清晰的标题区与内容分区，不复用方形 Master、Layout 或原型 SVG；所有页面按 OpenRadioss 内容重新组织为横向自由版式并以平面结构导出，跳过其图片中心与全幅图片原型。

## II. Canvas Specification

| Property | Value |
| --- | --- |
| Format | PPT 16:9 |
| Dimensions | 1280 × 720 px |
| viewBox | `0 0 1280 720` |
| Margins | 64 px left/right; 48 px top/bottom |
| Content Area | x=64..1216, y=48..672 |

## III. Visual Theme

### Theme Style

- **Mode**: briefing
- **Visual style**: sketch-notes
- **Theme**: OpenRadioss 工程研究月度进展；Google 品牌颜色仅按确认的调色板使用，不呈现 Google 标识或品牌署名。
- **Tone**: 友好、平实、可核查；轻手绘线条和浅色标记维持亲和感，事实和状态仍保持清楚。

### Color Scheme

| Role | HEX | Purpose |
| --- | --- | --- |
| Background | #FFFFFF | 主画布 |
| Secondary background | #F8F9FA | 柔和分区与信息底色 |
| Primary | #4285F4 | 主要阶段、求解链条 |
| Accent | #34A853 | 已完成或正常求解状态 |
| Secondary accent | #FBBC05 | 注意事项与未完成状态 |
| Body text | #202124 | 正文与标题 |
| Secondary text | #5F6368 | 注释、单位和来源 |
| Divider | #DADCE0 | 轻手绘规则线及分区边界 |

### Mode and Style Behavior

- **Mode Behavior**: 以主题标题中性组织资料，按时间与技术阶段分组；并列工作平等呈现，数字附单位和状态，观察结果与未认证事项分开。
- **Visual Style Behavior**: 在精确对齐的宽屏栅格上加入少量不规则手绘下划线、箭头和圆形阶段号；用蓝、绿、黄的浅色调承载阶段或状态，保持无阴影、无渐变，避免卡片堆叠。

## IV. Typography System

### Font Plan

| Role | Character (Reference) | Primary | English if non-English | Fallback tail |
| --- | --- | --- | --- | --- |
| Title | 清晰的中文无衬线标题 | Microsoft YaHei | Segoe UI | sans-serif |
| Body | 投影可读的中文无衬线正文字体 | Microsoft YaHei | Segoe UI | sans-serif |

- **Title stack**: Microsoft YaHei, Segoe UI, sans-serif
- **Body stack**: Microsoft YaHei, Segoe UI, sans-serif

### Font Size Hierarchy

| Purpose | Anchor Size (px) |
| --- | ---: |
| Body | 32 |
| Title | 56 |
| Subtitle | 44 |
| Annotation | 24 |

## V. Layout Principles

### Deck-wide Direction

- **Hierarchy direction**: 页标题标识主题；一条关键事实或阶段结论先进入视线，再读证据和边界，页脚给出来源或进度。
- **Composition tendency**: 以横向单主轴为主，流程和比较按内容组织；轻手绘规则与标签作注记，不让装饰承担数据含义。
- **Cross-page continuity**: 固定标题与页码位置；阶段色按“构建蓝、已完成绿、待验证黄”使用，跨页保持语义一致。
- **Spacing posture**: 开放；结果与验证页按需提高密度但保持同一栅格。
- **Spacing anchors**: page margin 64 px; block gap 24 px; column gutter 32 px; corner radius 4 px; body leading 1.35×.

## VI. Icon Usage Specification

- **Primary bundled library**: none
- **Brand-logo library**: 不使用；Google 标识与本项目无关联。

| Icon Path | Suitable Scenarios |
| --- | --- |

## VII. Visualization Reference List

| Page | Family | Template | Usage |
| --- | --- | --- | --- |

## VIII. Image Resource List

| Filename | Dimensions | Ratio | Purpose | Type | Image pattern | Crop Policy | Acquire Via | Status | Reference | text_policy | page_role |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## IX. Content Outline

### Part 1: 工作进展与求解器基础

#### Slide 01 - OpenRadioss 本机二次开发进展

- **Audience move**: 从了解一个月完成多项工作，转向掌握从求解器构建到 LAW99 后处理的整体主线。
- **Relationships**: 本机构建与跑通 → 工程级算例 → KF LAW99 适配和闭环；三阶段依时间先后衔接。
- **Composition**: 主标题与一句话概述为焦点，底部用三段短路径提示汇报范围。
- **Title**: OpenRadioss 本机二次开发进展
- **Core message**: 本月工作覆盖求解器本机构建、工程算例和 KF LAW99 本机适配验证。
- **Content**: 时间范围 2026-09-08 至 2026-10-08 · 9 次提交 · 主线从“源码能编译”推进到“用户本构可运行并可后处理”。
- **Cover impact (binding)**: 以“从源码能编译，到本构结果可查看”为封面钩子；横向时间带为可调整构图参考。
- **Fact IDs**: summary.period, summary.commits, summary.overall
- **page_rhythm**: anchor

#### Slide 02 - 本月工作的三阶段进展

- **Audience move**: 从获得总览，转向看清阶段之间的依赖关系和产出。
- **Relationships**: 本机构建与跑通 → 工程算例 → LAW99 二次开发；每阶段承接上一阶段的可运行环境。
- **Composition**: 三阶段按时间横向排列，完成时间和主要产出在各阶段内成对出现。
- **Title**: 本月工作的三阶段进展
- **Core message**: 9 月上旬构建求解器，9 月下旬跑工程算例并完成 LAW99 本机适配。
- **Content**: 09-09—09-17 求解器构建与跑通 / 09-22—09-25 工程算例 / 09-27—09-30 KF LAW99 适配验证；阶段产出分别为 starter/engine、动画结果、一键脚本与可后处理算例。
- **Fact IDs**: summary.timeline
- **page_rhythm**: breathing

#### Slide 03 - MinGW gfortran 求解器构建

- **Audience move**: 从时间线总览，转向理解无 Visual Studio 环境下本机构建的关键问题与验证。
- **Relationships**: CMake 条件判断修复 → Starter/Engine 分别构建 → 冒烟测试与 LS-DYNA 输入兼容性检查。
- **Composition**: 上部列出工具链和构建结果，下部显示两项跑通验证。
- **Title**: MinGW gfortran 求解器构建
- **Core message**: 本机生成 Starter 与 Engine，并通过基础端到端运行检查。
- **Content**: 修复 CMake 变量比较的引号问题；engine_win64_gf.exe 36.4 MB、starter_win64_gf.exe 23.5 MB；TWISBEAM smoke；minimal.key 输入卡兼容性；配置 VS Code 调试入口。
- **Fact IDs**: summary.build, summary.smoke, summary.compatibility
- **page_rhythm**: dense

### Part 2: 工程算例与用户本构适配

#### Slide 04 - 工程算例运行记录

- **Audience move**: 从求解器基础测试，转向辨认实际工程算例的规模、输出和完成状态。
- **Relationships**: Bird Strike 与 Airbag Deployment 为并列算例；前者自然终止，后者仅生成部分帧后手工中断。
- **Composition**: 两算例左右对照，运行状态与帧数并列，气囊中断状态显著标出。
- **Title**: 工程算例运行记录
- **Core message**: 鸟撞风挡完成求解；气囊展开生成 61 帧但此次运行未自然终止。
- **Content**: Bird Strike：Starter 0 errors，Engine NORMAL TERMINATION，16,634 cycles，3,042 s，266 MB，101 帧；Airbag：LS-DYNA 输入卡，61 帧，日志写到 A042 时 CTRL-C 中断。
- **Fact IDs**: summary.birdstrike, summary.airbag
- **page_rhythm**: dense

#### Slide 05 - KF LAW99 动态用户本构接入

- **Audience move**: 从工程算例，转向理解用户本构如何进入 OpenRadioss 运行链路及迁移范围。
- **Relationships**: `/MAT/USER02` → 内部 ILAW=99 → 动态库回调；MSVC 项目迁移至 MinGW DLL 构建但求解器接口保持不变。
- **Composition**: 运行调用关系为主，参数和状态变量作为两组附属规模信息。
- **Title**: KF LAW99 动态用户本构接入
- **Core message**: KF 模型由 USER02 材料卡映射到 LAW99，并通过动态用户库调用。
- **Content**: 25 个 KF 输入参数 · 8 个状态变量 · 原环境 MSVC/VS2022，本机 MinGW gfortran；无需重编译求解器、修改项目源码或测试卡；DLL 文件名一致。
- **Fact IDs**: summary.kf_model, summary.migration
- **page_rhythm**: anchor

#### Slide 06 - 本机适配与自动化运行流程

- **Audience move**: 从接口原理，转向掌握本机如何构建 DLL、执行验证和准备兼容运行目录。
- **Relationships**: Ninja 构建用户库 → 材料点验证 → 运行时镜像与求解器 → T01/动画后处理；步骤依序衔接。
- **Composition**: 横向流程突出工具依赖，技术细节只在关键节点注释。
- **Title**: 本机适配与自动化运行流程
- **Core message**: 一键脚本串起 DLL 构建、材料点验证、单砖求解和结果准备。
- **Content**: Ninja 避免中文路径下 mingw32-make 的编码问题 · libgcc runtime 需与 DLL 同目录供 Python ctypes 加载 · 运行镜像为现有 GF 求解器创建兼容名称 · `--skip-build` 跳过写死的 VS DLL build gate。
- **Fact IDs**: summary.local_adaptation, summary.runtime_mirror, summary.pitfalls
- **page_rhythm**: dense

#### Slide 07 - 材料点与单砖验证结果

- **Audience move**: 从自动化流程，转向区分材料点数值检查和有限元求解闭环所验证的内容。
- **Relationships**: 材料点矩阵 8/8 PASS；Step 11 中 4 项自动化门 PASS、3 项 NOT_CERTIFIED；单砖求解支持接口闭环证据。
- **Composition**: 左侧展示 8/8 和单砖求解信号，右侧说明 Step 11 状态及适用范围。
- **Title**: 材料点与单砖验证结果
- **Core message**: 材料点行为和单砖求解链路通过自动检查，认证范围仍有边界。
- **Content**: 8 项：静水压缩、大静水压缩、单轴压缩、单轴拉伸、简单剪切、应变率效应、客观性、冲击率扫描；P-alpha 一致性最大相对误差 0；32/64 步应力差 1.704e-03；单砖 Starter 0 errors、Engine NORMAL TERMINATION、8 cycles、T01 CSV 4×55。
- **Fact IDs**: summary.material_matrix, summary.step11, summary.single_brick
- **page_rhythm**: dense

### Part 3: 后处理证据与后续工作

#### Slide 08 - Python GUI 与应力后处理

- **Audience move**: 从求解器验证，转向理解 Python GUI 如何连接作业提交、结果转换与应力后处理。
- **Relationships**: Python/Tk GUI 选择算例并管理求解队列 → 输出 A 动画与时程数据 → HyperView 读取多单元应力结果并显示云图；H3D v24 中的 KF 内部变量受查看器版本限制。
- **Composition**: 左侧说明 GUI 的作业与转换能力，右侧说明应力结果分析；底部交代 A 动画可用路径与 H3D 版本边界。
- **Title**: Python GUI 与应力后处理
- **Core message**: Python GUI 串起求解与结果转换，HyperView 可对多单元结果开展应力分析并查看空间云图。
- **Content**: Python/Tk GUI 支持输入 deck 选择、线程/MPI 参数、作业队列、动画转 VTK 与时程转 CSV；HyperWorks 14 的 RADIOSS A reader 可查看 Stress 张量分量、Von Mises 与 Plastic Strain；160 单元轴压算例呈现空间应力梯度；当前 H3D writer 输出 v24，HW14 不可读，较新版本可查看 KF UVAR。
- **Fact IDs**: summary.hyperview, summary.h3d, summary.postprocessable_examples, openradioss_gui.features, summary.axial_results
- **page_rhythm**: breathing

#### Slide 09 - 下一阶段：VS2022 环境适配

- **Audience move**: 从已完成的本机数值闭环，转向复现并核对 OpenRadioss 在 VS2022 工具链下的构建与运行。
- **Relationships**: 配置 VS2022 编译工具链 → 构建 Starter / Engine → 重建 LAW99 用户库并复验算例 → 与当前 MinGW 结果对照。
- **Composition**: 按环境、求解器、用户本构三步纵向推进，以可复现的跨工具链验证作为收束。
- **Title**: 下一阶段：VS2022 环境适配
- **Core message**: 在 VS2022 环境完成 OpenRadioss 构建适配，并复验现有 LAW99 闭环。
- **Content**: 核对 VS2022、CMake 与项目所需编译器/依赖配置；构建并检查 Starter 与 Engine；重建 LAW99 动态用户库，重跑 8 项材料点矩阵、单砖和多单元算例；对比 MinGW 版本的构建、运行状态和关键数值；整理平台差异与可复现步骤。
- **Closing impact (binding)**: 邀请组会讨论 VS2022 环境和编译器依赖的准备顺序。
- **Fact IDs**: summary.build, summary.local_adaptation, summary.validation
- **page_rhythm**: breathing

## X. Speaker Notes Requirements

- **Generation**: enabled
- **Filename**: match each SVG filename under `notes/`.
- **Content**: 每页按当前事实说明图表、定义必要缩写，并明确观察、解释与未验证事项的区别；仅使用 summary.md 中的事实，不补造材料数据或外部基准。
- **Total duration**: 10–15 分钟，保留讨论时间。
- **Notes style**: 平实、清楚、适合口头组会汇报。
- **Presentation purpose**: 按工作递进汇报本月进展，说明 OpenRadioss 本机构建、工程算例和 KF LAW99 闭环，并共同认识当前验证边界及后续研究工作。
