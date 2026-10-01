class_name BjCards
extends RefCounted

## 牌 / 花色 / 点数 / Hi-Lo 计数。
##
## 移植自 dsh-deepseek-blackjack/src/engine/cards.js。
## 纯静态工具：无状态、无 IO、无随机。
##
## 为什么牌是 Dictionary 而不是字符串：渲染层要按 suit/rank 分别取字模，
## 字符串会让渲染层到处做解析。固定成 {rank, suit} 这个最小形状。

const SUITS: Array[String] = ["S", "H", "D", "C"]
const RANKS: Array[String] = [
	"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K",
]

const SUIT_SYMBOL := {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const SYMBOL_SUIT := {"♠": "S", "♥": "H", "♦": "D", "♣": "C"}

## A 先按 11 算；降级逻辑在 BjHand 里（因为要看整手牌）。
const RANK_VALUE := {
	"A": 11, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
	"8": 8, "9": 9, "10": 10, "J": 10, "Q": 10, "K": 10,
}

## Hi-Lo：小牌为正（利于闲家），大牌与 A 为负。
const HI_LO := {
	"A": -1, "2": 1, "3": 1, "4": 1, "5": 1, "6": 1, "7": 0,
	"8": 0, "9": 0, "10": -1, "J": -1, "Q": -1, "K": -1,
}


static func rank_value(rank: String) -> int:
	if not RANK_VALUE.has(rank):
		push_error("未知的点数：%s" % rank)
		return 0
	return RANK_VALUE[rank]


## 造一张牌。返回普通 Dictionary —— GDScript 里没有免费冻结，
## 约定：引擎内部只读，谁都不许改手里的牌面。
static func make(rank: String, suit: String) -> Dictionary:
	if not RANK_VALUE.has(rank):
		push_error("未知的点数：%s" % rank)
	if not SUITS.has(suit):
		push_error("未知的花色：%s" % suit)
	return {"rank": rank, "suit": suit}


## 防御性校验，用于反序列化与测试夹具。
static func is_card(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var card: Dictionary = value
	if not (card.has("rank") and card.has("suit")):
		return false
	if not RANK_VALUE.has(card["rank"]):
		return false
	return SUITS.has(card["suit"])


## 可读文本，如 `♠A`。只用于调试、事件日志与断言失败时的可读性。
static func card_text(card: Variant) -> String:
	if not is_card(card):
		return "??"
	return "%s%s" % [SUIT_SYMBOL[card["suit"]], card["rank"]]


## 手牌转文本，如 `♠8 ♦K`；空手牌给 `（无）`。
static func hand_text(cards: Array) -> String:
	if cards.is_empty():
		return "（无）"
	var parts: PackedStringArray = []
	for card in cards:
		parts.append(card_text(card))
	return " ".join(parts)


## 解析 `"SA"` / `"s10"` / `"♠A"`。测试里"按顺序摆牌"必须一眼可读。
static func parse(text: String) -> Dictionary:
	if text.length() < 2:
		push_error("无法解析牌面：%s" % text)
		return {}
	var head := text.substr(0, 1).to_upper()
	var suit := ""
	if SYMBOL_SUIT.has(head):
		suit = SYMBOL_SUIT[head]
	elif SUITS.has(head):
		suit = head
	else:
		push_error("无法解析花色：%s" % text)
		return {}
	var rank := text.substr(1).to_upper()
	if not RANK_VALUE.has(rank):
		push_error("无法解析点数：%s" % text)
		return {}
	return make(rank, suit)


## 造一副 52 张（不含大小王）。
static func full_deck() -> Array:
	var cards: Array = []
	for suit in SUITS:
		for rank in RANKS:
			cards.append(make(rank, suit))
	return cards


## 把 `"SA 10H"` 这种空格分隔的牌序解析成数组（测试夹具用）。
static func parse_hand(text: String) -> Array:
	var cards: Array = []
	for token in text.split(" ", false):
		var card := parse(token.strip_edges())
		if not card.is_empty():
			cards.append(card)
	return cards


static func hi_lo(card: Dictionary) -> int:
	if not card.has("rank") or not HI_LO.has(card["rank"]):
		push_error("无法计算 Hi-Lo：%s" % str(card))
		return 0
	return HI_LO[card["rank"]]
