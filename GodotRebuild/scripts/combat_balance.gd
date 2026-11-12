extends RefCounted
## Shared campaign rules. Arena indices are zero-based; waves are one-based.
## Rewards deliberately grow much slower than effective enemy health.
const ENEMIES := {
	"goblin":{"name":"Гоблин-разведчик","health":0.82,"armor":0.0,"reward":10,"speed":6.2},
	"orc":{"name":"Орк Мордора","health":1.0,"armor":4.0,"reward":12,"speed":4.9},
	"uruk":{"name":"Урук-хай","health":1.18,"armor":13.0,"reward":15,"speed":4.7},
	"warg":{"name":"Варг","health":0.90,"armor":2.0,"reward":14,"speed":8.2},
	"troll":{"name":"Пещерный тролль","health":2.60,"armor":20.0,"reward":24,"speed":3.1},
	"nazgul":{"name":"Назгул","health":1.50,"armor":11.0,"reward":26,"speed":6.1},
	"boss_troll":{"name":"Владыка пещер · босс арены","health":13.5,"armor":32.0,"reward":160,"speed":2.65}
}
const CHAIN_FALLOFF := 0.65
const MAX_CHAIN_HOPS := 3

static func armor_multiplier(armor: float, ignore_fraction: float = 0.0) -> float:
	var effective := maxf(0.0,armor)*(1.0-clampf(ignore_fraction,0.0,1.0))
	return 100.0/(100.0+effective)

static func enemy_stats(kind: String, wave: int, arena: int, is_boss: bool = false) -> Dictionary:
	var template: Dictionary = ENEMIES.get(kind,ENEMIES.orc)
	var w := float(clampi(wave,1,15))
	var a := float(clampi(arena,0,17))
	var health := (40.0+15.0*w+1.9*w*w)*float(template.health)*(1.0+0.04*a)
	var armor := minf(65.0,float(template.armor)+0.65*(w-1.0)+0.25*a)
	var reward := roundi(float(template.reward)*(1.0+minf(0.15,(w-1.0)*0.008+a*0.002)))
	if is_boss and kind != "boss_troll":
		health *= 2.1
		armor += 6.0
		reward = 52+wave*2
	return {"kind":kind,"name":str(template.name) if not is_boss or kind == "boss_troll" else "Элитный "+str(template.name).to_lower(),"hp":health,"max_hp":health,"armor":armor,"reward":reward,"speed":float(template.speed)*(1.0+0.012*a),"boss":is_boss,"life_damage":5 if kind == "boss_troll" else 2 if is_boss else 1}

static func wave_count(wave: int, _arena: int) -> int:
	return 6+clampi(wave,1,15)*2

static func wave_reward(wave: int, _arena: int) -> int:
	return 40+clampi(wave,1,15)*3

static func spawn_kind(wave: int, remaining: int) -> String:
	if remaining == 0 and wave >= 15:
		return "boss_troll"
	if remaining == 0 and wave%5 == 0:
		return "troll"
	if wave < 3:
		return "goblin" if remaining%2 == 0 else "orc"
	if wave < 6:
		return "warg" if remaining%3 == 0 else "uruk"
	if wave < 10:
		return "troll" if remaining%4 == 0 else "uruk"
	return "nazgul" if remaining%5 == 0 else "troll" if remaining%3 == 0 else "uruk"

static func capstone_description(hero: int) -> String:
	return ["Тройной удар · игнорирует 45% брони","Цепь: 100% → 65% → 42% → 27% урона","Ожог: ещё 30% урона за 3 с","Нить судьбы: союзники игнорируют 15% брони","Ледяной плен · боссы устойчивее к замедлению","Хлопковый таран: −14 брони на 3 с"][clampi(hero,0,5)]
