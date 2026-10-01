class_name BjShoe
extends RefCounted

## 牌靴：4 副 = 208 张，Fisher-Yates 洗牌，发牌只推进游标。
##
## 移植自 dsh-deepseek-blackjack/src/engine/shoe.js。
##
## 为什么洗牌用注入的 RandomNumberGenerator 而不是全局 randi：
## 单测要能复现某一手牌，否则规则回归就变成碰运气。注入后
## `rng.seed = 12345` 就能得到完全确定的牌序。

const DECKS_PER_SHOE := 4
const SHOE_SIZE := 52 * DECKS_PER_SHOE
## 低于这个剩余张数就该换靴（设计文档 §2.1 的 25% 阈值）。
const RESHUFFLE_BELOW := 52

var cards: Array = []
var cursor: int = 0


## 造一靴洗好的牌。rng 为空则自己建一个（未播种 = 真随机）。
static func create(rng: RandomNumberGenerator = null) -> BjShoe:
	var shoe := BjShoe.new()
	var source := rng
	if source == null:
		source = RandomNumberGenerator.new()
		source.randomize()
	var deck: Array = []
	for _deck in range(DECKS_PER_SHOE):
		deck.append_array(BjCards.full_deck())
	# Fisher-Yates：从后往前，每个位置与 [0, i] 的均匀整数交换。
	for i in range(deck.size() - 1, 0, -1):
		var j := source.randi_range(0, i)
		var tmp: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	shoe.cards = deck
	shoe.cursor = 0
	return shoe


## 按给定顺序造一靴（不洗牌）。确定性牌局（测试 / 彩蛋剧本）的唯一入口。
static func stacked(ordered_cards: Array) -> BjShoe:
	var shoe := BjShoe.new()
	shoe.cards = ordered_cards.duplicate()
	shoe.cursor = 0
	return shoe


func remaining() -> int:
	return cards.size() - cursor


func needs_reshuffle() -> bool:
	return remaining() < RESHUFFLE_BELOW


## 从靴顶抽一张。空靴返回空 Dictionary（不报错 —— 牌靴耗尽属于
## "调用方该处理的局面"，状态机负责把它翻成错误）。
func draw() -> Dictionary:
	if remaining() <= 0:
		return {}
	var card: Dictionary = cards[cursor]
	cursor += 1
	return card


## 深拷贝（存档 / 测试里想保住原顺序时用）。
func clone() -> BjShoe:
	var shoe := BjShoe.new()
	shoe.cards = cards.duplicate()
	shoe.cursor = cursor
	return shoe
