# SheetSentry 项目申报书

## 基本信息

- 项目名称：SheetSentry：可复现 Excel 计算切片与模型审计
- 参赛者：莫淮隆
- 联系方式：18070649514
- GitHub 仓库链接：https://github.com/mhlagent/sheetsentry
- 项目方向：MoonBit 数据处理 / 可复现计算切片
- 是否为移植项目：否，原创项目

## 项目简介

SheetSentry 使用 MoonBit 解决一个明确问题：给定 Excel 中的目标单元格，从大型工作簿中提取一个最小、可独立打开、可复现该计算结果的工作簿。

它沿公式依赖收集必要前驱，只复制相关 sheet 和 cell，生成独立 `.xlsx` 与 SHA-256 manifest，并通过 `verify-slice` 重新打开切片验证目标值。项目适用于审计、模型交接、监管报送、调试和敏感数据最小化共享。

与 MoonCell 等公式分析工具不同，SheetSentry 的交付物不是“分析结论”，而是可独立打开的模型子集；公式规则、图查询和环检测仅作为辅助层。

## 核心功能范围

- 计算切片：支持单目标、多目标、传递前驱闭包和深度限制，只保留必要工作表和单元格；
- 引用解析：支持 A1、绝对引用、区域、跨工作表引用、命名区域；
- 动态引用：支持字面量 `INDIRECT("Sheet!A1")` 和常量 `OFFSET(A1,r,c)`；
- 结构化引用：解析工作簿表格，支持 `Table[Column]`、`@Column`、`#Data`、`#Headers`、`#Totals`，并在切片中重写为 A1 区域；
- 外部依赖：通过 `--external book.xlsx=path` 导入被引用值到 `__ext__*` 工作表，并重写公式；
- 可复现 manifest：记录源/切片 SHA-256、最小性指标、包含/排除单元格、目标前后值、`verified`、`calc_verified`、`complete`、未解析项和外部单元格；
- 独立重算：对切片中的目标公式重新计算并对比原始缓存值；
- 最小性验证：统计总使用单元格、切片使用单元格和排除单元格，并验证切片范围等于目标的可达闭包；
- 切片验证：`verify-slice` 校验切片 SHA-256、全部目标值和目标数量；
- 切片证书：生成自包含 HTML，列出目标、哈希、sheet、未解析项和验证结果；
- 辅助审计：10 条可选规则、baseline、JSON 配置、terminal/JSON/SARIF/HTML 报告、DOT/Mermaid 图导出。

## 预期验收产物

- Mooncakes：`mhlagent/sheetsentry@0.7.0`；
- `slice` 与 `verify-slice` CLI，以及可复用的 MoonBit API；
- 68 个 MoonBit 测试，GitHub Actions 全绿；
- 示例切片、manifest、HTML/JSON/SARIF 报告；
- Apache-2.0 许可证和完整 README。

## 与 MoonCell 的边界

- MoonCell 侧重公式异常、版本比较、影响预览和人工审核，不写回 XLSX；
- SheetSentry 侧重计算切片、独立工作簿重构和可复现验证；
- 图查询、环检测和规则配置不作为核心创新主张，只服务于切片与审计。

## 验收指标

- `moon test --target native`：68 个测试全部通过；
- `Summary!B3` 切片包含 12 个单元格、2 个 sheet，排除无关的 `Tax` / `Scratch`，`verified=true`、`complete=true`；
- 多目标切片同时包含 `Summary!B3` 和 `Summary!B10`，`verify-slice` 返回 2/2 目标通过、2/2 独立重算通过且切片哈希一致；
- 多目标切片保留 13/65 个已使用单元格，排除 52 个，`minimality_verified=true`；
- 结构化引用 `Summary!B10` 切片完整，公式重写为 `Opex!$B$2:$B$6`；
- 命名区域 `Summary!B11` 切片完整，并保留 `RevenueInput` 定义；
- `INDIRECT` / `OFFSET` 目标可解析并完整切片；
- 外部工作簿 `Summary!B14` 带映射时 `complete=true`；
- 深度截断切片明确返回 `complete=false`；
- `moon publish` 成功发布 `0.7.0`。

## 移植或参考说明

- 原项目名称：无直接上游项目；参考 `moonbitlang/mbtexcel`（Go excelize 的 MoonBit 移植）；
- MoonCell 是相邻的公式分析项目，本项目未复制其代码；
- 本项目许可证：Apache-2.0；
- 运行时切片、哈希与验证完全确定性，不依赖 LLM 或外部 AI 服务。
