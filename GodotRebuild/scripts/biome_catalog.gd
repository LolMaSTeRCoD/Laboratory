extends RefCounted
## Shared art direction for every arena. IDs are stable, independent of route geometry.
enum Kind { FOREST, JUNGLE, DESERT, AUTUMN, WINTER, VOLCANIC }
const CAMPAIGN := [Kind.FOREST,Kind.AUTUMN,Kind.JUNGLE,Kind.DESERT,Kind.WINTER,Kind.VOLCANIC,
	Kind.JUNGLE,Kind.FOREST,Kind.WINTER,Kind.DESERT,Kind.AUTUMN,Kind.VOLCANIC,
	Kind.WINTER,Kind.JUNGLE,Kind.AUTUMN,Kind.FOREST,Kind.DESERT,Kind.VOLCANIC]

static func for_arena(arena_index: int) -> Dictionary:
	var id: int=CAMPAIGN[posmod(arena_index,CAMPAIGN.size())]
	var p := {
		"id":id,"key":"forest","name":"Лесное лето","season":"summer","tree":"broadleaf",
		"ground":Color(0.14,0.23,0.085),"road":Color(0.38,0.325,0.245),
		"foliage_a":Color(0.075,0.22,0.045),"foliage_b":Color(0.30,0.43,0.10),
		"grass_a":Color(0.095,0.22,0.035),"grass_b":Color(0.30,0.41,0.08),
		"rock":Color(0.77,0.82,0.70),"trees":140,"grass":1.0,"ferns":240,
		"sun":Color(1.0,0.90,0.73),"sun_energy":1.10,"ambient":Color(0.59,0.70,0.58),
		"ambient_energy":0.72,"fog":Color(0.42,0.54,0.43),"fog_density":0.0018,
		"weather":"pollen","water":"water","water_tint":Color(0.035,0.14,0.12),
		"bird":"swallow","bird_color":Color(0.09,0.12,0.15),"ground_animal":"hedgehog",
		"clothes":Color(0.34,0.40,0.21),"hat":Color(0.43,0.29,0.12),"wardrobe":"linen",
		"chores":["herbs","mow","fish"],"house":Color(0.49,0.43,0.31)}
	match id:
		Kind.JUNGLE:
			p.merge({"key":"jungle","name":"Влажные джунгли","season":"wet","tree":"tropical",
				"ground":Color(0.055,0.15,0.065),"road":Color(0.30,0.25,0.19),
				"foliage_a":Color(0.025,0.18,0.075),"foliage_b":Color(0.16,0.41,0.12),
				"grass_a":Color(0.035,0.19,0.07),"grass_b":Color(0.19,0.43,0.12),
				"rock":Color(0.48,0.65,0.49),"trees":180,"grass":1.25,"ferns":390,
				"sun":Color(0.84,0.96,0.82),"sun_energy":0.92,"ambient":Color(0.36,0.62,0.48),
				"ambient_energy":0.78,"fog":Color(0.22,0.39,0.32),"fog_density":0.004,
				"weather":"rain","water_tint":Color(0.025,0.12,0.10),
				"bird":"parrot","bird_color":Color(0.075,0.54,0.23),"ground_animal":"lizard",
				"clothes":Color(0.42,0.41,0.20),"hat":Color(0.52,0.38,0.16),"wardrobe":"rain_cape",
				"chores":["herbs","gather","fish"],"house":Color(0.38,0.36,0.24)},true)
		Kind.DESERT:
			p.merge({"key":"desert","name":"Пустынный оазис","season":"dry","tree":"palm",
				"ground":Color(0.48,0.34,0.17),"road":Color(0.60,0.46,0.28),
				"foliage_a":Color(0.18,0.25,0.055),"foliage_b":Color(0.35,0.37,0.10),
				"grass_a":Color(0.32,0.27,0.09),"grass_b":Color(0.56,0.45,0.18),
				"rock":Color(0.88,0.69,0.45),"trees":48,"grass":0.15,"ferns":0,
				"sun":Color(1.0,0.81,0.53),"sun_energy":1.45,"ambient":Color(0.69,0.57,0.39),
				"ambient_energy":0.60,"fog":Color(0.63,0.45,0.28),"fog_density":0.0015,
				"weather":"dust","water_tint":Color(0.045,0.26,0.24),
				"bird":"kite","bird_color":Color(0.37,0.24,0.12),"ground_animal":"lizard",
				"clothes":Color(0.69,0.58,0.39),"hat":Color(0.79,0.69,0.48),"wardrobe":"headwrap",
				"chores":["water","gather","fish"],"house":Color(0.66,0.49,0.29)},true)
		Kind.AUTUMN:
			p.merge({"key":"autumn","name":"Золотая осень","season":"autumn",
				"ground":Color(0.27,0.22,0.07),"road":Color(0.38,0.30,0.22),
				"foliage_a":Color(0.42,0.12,0.025),"foliage_b":Color(0.80,0.42,0.045),
				"grass_a":Color(0.23,0.25,0.055),"grass_b":Color(0.52,0.40,0.11),
				"rock":Color(0.78,0.74,0.62),"grass":0.7,"ferns":110,
				"sun":Color(1.0,0.72,0.39),"sun_energy":1.02,"ambient":Color(0.64,0.58,0.46),
				"fog":Color(0.54,0.43,0.29),"fog_density":0.0025,
				"weather":"leaves","water_tint":Color(0.09,0.14,0.12),
				"bird":"crow","bird_color":Color(0.035,0.04,0.045),"ground_animal":"hedgehog",
				"clothes":Color(0.46,0.26,0.13),"hat":Color(0.27,0.16,0.09),"wardrobe":"wool",
				"chores":["harvest","rake","fish"],"house":Color(0.51,0.40,0.27)},true)
		Kind.WINTER:
			p.merge({"key":"winter","name":"Зимний перевал","season":"winter","tree":"conifer",
				"ground":Color(0.73,0.82,0.87),"road":Color(0.30,0.33,0.34),
				"foliage_a":Color(0.035,0.14,0.11),"foliage_b":Color(0.13,0.25,0.21),
				"grass_a":Color(0.38,0.40,0.27),"grass_b":Color(0.64,0.65,0.49),
				"rock":Color(0.71,0.77,0.82),"trees":155,"grass":0.10,"ferns":0,
				"sun":Color(0.73,0.84,1.0),"sun_energy":0.90,"ambient":Color(0.56,0.68,0.82),
				"ambient_energy":0.86,"fog":Color(0.65,0.74,0.84),"fog_density":0.0038,
				"weather":"snow","water":"ice","water_tint":Color(0.28,0.46,0.58),
				"bird":"raven","bird_color":Color(0.035,0.045,0.06),"ground_animal":"hare",
				"clothes":Color(0.20,0.29,0.36),"hat":Color(0.49,0.42,0.34),"wardrobe":"fur",
				"chores":["firewood","shovel","ice_fish"],"house":Color(0.43,0.41,0.37)},true)
		Kind.VOLCANIC:
			p.merge({"key":"volcanic","name":"Пепельные пустоши","season":"ash","tree":"charred",
				"ground":Color(0.075,0.064,0.058),"road":Color(0.30,0.24,0.20),
				"foliage_a":Color(0.06,0.055,0.05),"foliage_b":Color(0.15,0.11,0.075),
				"grass_a":Color(0.13,0.10,0.065),"grass_b":Color(0.25,0.18,0.09),
				"rock":Color(0.24,0.23,0.22),"trees":70,"grass":0.07,"ferns":0,
				"sun":Color(1.0,0.47,0.22),"sun_energy":1.05,"ambient":Color(0.39,0.27,0.24),
				"ambient_energy":0.70,"fog":Color(0.24,0.17,0.15),"fog_density":0.0045,
				"weather":"ash","water":"boiling","water_tint":Color(0.12,0.13,0.09),
				"bird":"bat","bird_color":Color(0.12,0.065,0.055),"ground_animal":"salamander",
				"clothes":Color(0.31,0.24,0.20),"hat":Color(0.21,0.17,0.15),"wardrobe":"ash_cape",
				"chores":["firewood","gather","water"],"house":Color(0.35,0.29,0.25)},true)
	return p
