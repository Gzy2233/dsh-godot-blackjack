class_name BjTokens
extends RefCounted

## 筹码（token）显示格式化。
##
## 移植自 dsh-deepseek-blackjack/src/host/tokens.js。
##
## 规则：1 亿 = 10000 万 = 10^8，**故意禁用科学计数法**。
##   ≥ 1亿 → X亿（<100 保留 1 位小数，≥100 取整）
##   ≥ 1万 → X万（<1000 保留 1 位小数，≥1000 取整）
##   否则   → 整数 + 千位分隔
## 末尾的 ".0" 一律抹掉：`1亿` 而不是 `1.0亿`。
##
## 注意：**提示词里给模型看的是原始整数**，只有 UI 走这里。
## 精确数字在推理层，人类单位在展示层。

const YI := 100_000_000
const WAN := 10_000


## 抹掉末尾的 0（只在有小数点时动手）。
static func _trim_zero(text: String) -> String:
	if not text.contains("."):
		return text
	var out := text
	while out.ends_with("0"):
		out = out.substr(0, out.length() - 1)
	if out.ends_with("."):
		out = out.substr(0, out.length() - 1)
	return out


## 千位分隔（手写，避免依赖 Locale）。
static func _group(abs_value: int) -> String:
	var digits := str(abs_value)
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


## 人类可读的 token 数，如 `1.2亿` / `500万` / `1,500`。
static func format(amount: int) -> String:
	var sign_text := "-" if amount < 0 else ""
	var abs_value := absi(amount)
	if abs_value >= YI:
		var yi_value := float(abs_value) / float(YI)
		var text := "%.0f" % yi_value if yi_value >= 100.0 else "%.1f" % yi_value
		return "%s%s亿" % [sign_text, _trim_zero(text)]
	if abs_value >= WAN:
		var wan_value := float(abs_value) / float(WAN)
		var text := "%.0f" % wan_value if wan_value >= 1000.0 else "%.1f" % wan_value
		return "%s%s万" % [sign_text, _trim_zero(text)]
	return "%s%s" % [sign_text, _group(abs_value)]


## 精确数字（悬停/结算详情用），如 `120,000,000`。
static func format_exact(amount: int) -> String:
	var sign_text := "-" if amount < 0 else ""
	return "%s%s" % [sign_text, _group(absi(amount))]


## 带符号的净收益，如 `+500万` / `-1.2亿` / `±0`。
static func format_delta(amount: int) -> String:
	if amount == 0:
		return "±0"
	return "%s%s" % ["+" if amount > 0 else "-", format(absi(amount))]


## 配置助手：写 yi(1) 比写 100000000 不容易错。
static func yi(count: float) -> int:
	return int(round(count * float(YI)))


static func wan(count: float) -> int:
	return int(round(count * float(WAN)))
