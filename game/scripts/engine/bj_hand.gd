class_name BjHand
extends RefCounted

## 手牌计算：点数、软/硬、黑杰克、爆牌、可行动性。
##
## 移植自 dsh-deepseek-blackjack/src/engine/hand.js。
## 这一层是整局规则的地基，必须对"多张 A 到底降哪一张"给出唯一答案。
##
## 两个软牌口径都保留（原版就是两套，混用会出 bug）：
##   - is_soft()     宽松口径：手上有 A 且没爆牌 → soft（展示用）
##   - has_soft_ace() 严格口径：确实存在一张仍按 11 计的 A（策略判定必须用这个）
## 原版曾经把两者混用，导致硬 17（10+6+A）被当成软 17 继续要牌 —— 这是个真 bug。


## 一次遍历算出总点数、A 的张数、被降级的 A 张数。
static func evaluate(cards: Array) -> Dictionary:
	var total := 0
	var aces := 0
	for card in cards:
		if not BjCards.is_card(card):
			continue
		total += BjCards.rank_value(card["rank"])
		if card["rank"] == "A":
			aces += 1
	var demoted := 0
	while total > 21 and demoted < aces:
		total -= 10
		demoted += 1
	return {"total": total, "aces": aces, "demoted": demoted}


static func value(cards: Array) -> int:
	return evaluate(cards)["total"]


## 宽松口径的软牌（展示用：手上有 A 且未爆）。
static func is_soft(cards: Array) -> bool:
	var info := evaluate(cards)
	return info["aces"] > 0 and info["total"] <= 21


## 严格口径：确实存在一张仍按 11 计的 A。
## `A + 6` → true；`10 + 6 + A`（A 已降为 1）→ false；爆牌 → false。
static func has_soft_ace(cards: Array) -> bool:
	var info := evaluate(cards)
	return info["total"] <= 21 and info["demoted"] < info["aces"]


## 黑杰克：**恰好两张**且合计 21。
## `A + A + 9`（3 张）也是 21，但不是 BJ，不能拿 3:2 赔付 —— 21 点最常见的规则漏洞。
static func is_blackjack(cards: Array) -> bool:
	return cards.size() == 2 and value(cards) == 21


static func is_bust(cards: Array) -> bool:
	return value(cards) > 21


## 能否加注（DOUBLE）：恰好两张且未爆。
static func can_double(cards: Array) -> bool:
	return cards.size() == 2 and not is_bust(cards)


## 能否要牌：未爆即可（停牌由状态机的 done 标记管控）。
static func can_hit(cards: Array) -> bool:
	return not is_bust(cards)


## 展示用的一句话，如 `16 点（软牌）` / `22 点 · 爆牌` / `21 点 · 黑杰克`。
static func describe(cards: Array) -> String:
	var total := value(cards)
	if is_bust(cards):
		return "%d 点 · 爆牌" % total
	if is_blackjack(cards):
		return "%d 点 · 黑杰克" % total
	var out := "%d 点" % total
	if is_soft(cards):
		out += "（软牌）"
	return out
