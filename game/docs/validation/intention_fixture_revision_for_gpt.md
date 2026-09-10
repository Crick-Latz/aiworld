# 意图修复 R1：修正测试前提，保留产品失败记录

日期：2026-09-09。接续 `intention_revalidation_for_gpt.md`，未修改其历史结果。
HEAD 仍为 `655f93087fee703f9347ca6dee4516d1873b6cd3`；保留上轮全部未提交修复。

## 本轮范围

不改资源、人格、softmax、效用或生产策略。只修三项验收夹具和两处错误退出码，
并观察事先固定的小样本。旧 P1.5/P1.6 自然剧情断言保留，不改阈值、不改 seed。

### P6.1 RD：不同观察必须得到不同知识，同样观察允许相同知识

旧测试假定两个同点出生的 NPC 在 400 tick 后必然知道不同浆果。这不是知识隔离契约。
新夹具复制两位 actor，分别替换为独立 SpatialBeliefMap：A 只知道 berry|10,11，
B 只知道 berry|20,21；真实 ContextBuilder 输出必须精确等于各自集合。
再只让 B 观察 berry|22,23，断言 B 集合变化、A 完整 ctx 不变、世界不变。
不修改自然 sim 的 actor 或世界，不向生产适配器增加测试分支。

反向破坏：临时让 ContextBuilder 读取 sim 的第一个 actor，而非参数 actor，
RD 与 RB 均 FAIL；恢复后 RD PASS，整个 suite 15/15。

### P6.2 RU5：真的构造满考虑集，再检查挤位

改用独立初始模拟中的 actor 和明确主观观察、需求、库存。所有候选仍由真实 Registry
和 Planner 生成；没有手写 utility，也没有改生产资源。此夹具只测试决策，不执行世界动作。
先跑 OFF，要求 forage_berries 明确在 ignored 中且考虑集已满；再以同一 RNG seed 500
跑 LIVE，要求 SWAPPED_IN 且原 utility 在 [0,0.3) 内。移除原来的 80 次 RNG 尝试。
RU6 复用同一个夹具的真实候选，避免跨 sim 构造视图。

反向破坏：仅禁用生产 salient 分支，RU5 在 precondition=true 下 FAIL（swapped=false）；
恢复后整个 suite 33/33。它验证的是考虑集接线，不保证 softmax 选中该行动。

### P4 ThreadIR：固定数量，不允许因无自然线程而跳过

保留自然模拟确定性门，再发出一个明确标注为 fixture 的 promise_made 事件。
两套独立 ThreadEngine 都需找到包含该真实事件 seq 的线程，再比较非空 ThreadIR。
无论自然样本有没有线程，都执行该门；清单因此由 16 固定为 17，不是仅改计数。
反向夹具：将期望源 seq 设为不存在的 -1，IR 门 FAIL；恢复后 suite 17/17。
不把测试内事件称为自然涌现。

### 退出码

P6.1 与 P6.2 原来无论 `_fail` 多少都 `quit(0)`。改为 `quit(0 if _fail == 0 else 1)`。
上轮严格 runner 已通过 stdout/SUMMARY 捕获失败；此改动防止直接运行者仅看 exit 误判。
额外通过两个 .tmp 测试子类各自注入一个断言失败：shadow-exit-red.log 为 14/1、
bridge-exit-red.log 为 32/1，两个实际进程均 exit 1。该检查只验证退出码传播；
前述 source mutation 才是机制红绿证据，二者不混称。

## 生产恢复核查

所有反向破坏均已撤销。DecisionEngine SHA-256 恢复为
`A2E7E2EF693DB9F924BBECC9FFE040C87F2A6D7D9D79AFCCE53250FFA35E0FC8`。
ContextBuilder 相对 HEAD 的 git 内容 diff 为空（恢复时有行尾规范化；不算语义改动）。
没有留下 TEMP negative control 或 missing evidence control。

## 全量回归与样本

最终严格回归：**27 套件 / 765 PASS / 3 FAIL，exit 1**。无套件数量不匹配。
失败仅剩旧 P1.5 `g_context_adapts`、P1.6 `k_refusals_happen`、`k_wild_epistemic_chain`。
阈值、seed 和三个断言均未修改；它们仍阻断默认严格验收。
P6.1=15/15、P6.2=33/33、P4=17/17、制作完整链=27/27、意图新门=14/14。
边界检查 6/6、BOUNDARY_OK；git diff --check 通过（仅 CRLF 提示）。
没有 SCRIPT ERROR；P3 原有坏 JSON 故障注入仍打印既知 ERROR，由严格脚本按既有规则识别。

**R1 的测试前提与退出码修复完成；整体意图修改尚未达到原严格验收，未提交、未关闭。**
不能称作“旧断言零回退”。本轮从上轮 5 个 FAIL + 1 个计数错误，收敛为 3 个原样保留的产品场景 FAIL。

产品观察脚本：`test/intention_story_samples.gd`，只描述，不加入回归通过计数：

- 环境对照固定 777/778/779 ×1200 tick；沿用旧测试的 rich/scarce 配置及 TVD 0.15 标记。
- 社会样本固定 30014/30015/30016 ×1500 tick，同点出生；不注入拒绝/认识事件。
- 保存原始相关事件及 source_event_ids。出现拒绝与认识行动两种事件，不等于已证明因果链。
- 不因结果不好重试、不选择“最好看的种子”，不据三个样本宣称总体成功率。

证据目录：`.tmp/review-CODEX-intention-fixtures/`。保留日志与 JSON，尚未验收，不做破坏式清理。

### 固定样本结果（已完成，非验收替代）

环境对照 TVD：777=0.135041593920099；778=0.140092879256966；779=0.111750321568406。
三者都低于原 >0.15 阈值，不应再把原失败简单说成“一颗运气不好的种子”。
该指标按事件类型频率计算，是否真正测到期望的环境适应需另行评估；本轮不降低阈值。

社会样本：

| seed | 接受请求 | 拒绝请求 | 认识行动 | 观察到的其他发展 |
|---|---:|---:|---:|---|
| 30014 | 1 | 0 | 7 | promise_made=1、promise_broken=1 |
| 30015 | 0 | 2 | 0 | 社交 30 次，未观察到认识行动 |
| 30016 | 0 | 7（食物5+水2） | 26 | reason_claimed=3、reason_deflected=3、institution_established=2 |

认识行动此处只计 reason_asked / observing_person / asked_about，计数定义与旧 K 门一致。
不是每一次拒绝都应必然引起追问，更不是所有人都必须产生不同知识。

30016 的三条明确源引用链（不是按时间邻近拼接）：

- seq369/t370：卡德加拒绝薇拉求食 → seq373/t374：薇拉询问（source=[369]）
  → seq374/t374：卡德加声称“我自己也没粮了”（source=[373]）。声明不等于世界真值证明。
- seq420/t413：欧恩拒绝薇拉 → seq533/t511：薇拉追问（source=[420]）
  → seq534/t511：欧恩回避回应（source=[533]）。间隔 98 tick 的源链仍保留。
- seq567/t541：欧恩拒绝卡德加 → seq569/t543：卡德加追问（source=[567]）
  → seq570/t543：欧恩回避回应（source=[569]）。

由此证明至少这次自然运行确实存在拒绝→追问→回应链；没有拿 30016 替换旧测试的 30014。
原始事件见 story-samples.json。它不证明整体游戏已足够有趣，也不证明每个种子都有完整链。

正式副本：`docs/validation/data/intention_story_samples_20260909.json`（与 .tmp 生成物同内容）。

## 后续执行节奏

不要为了已知的三个自然样本失败，在每次改文档/夹具后重复全量长回归。
先跑受影响的定向测试；改变生产行为或准备 checkpoint 时再跑一次完整门禁。
当前不引入真实 LLM API，不启用计划执行默认开关，不让美术/UI 分支介入模拟代码。

建议下一个有界工作包：评估“沿用旧意图时沿用旧 utility”是否导致合法却已无收益的重复。
先以最新候选 utility 与承诺 utility 作对照记录，再决定是否刷新机会成本；不改人格/softmax 参数。
这属于显式行为策略变更，不能偷塞进本轮测试修复，也不保证能恢复 TVD 或旧拒绝剧情。
