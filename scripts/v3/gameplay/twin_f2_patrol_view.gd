extends RefCounted
## Proposed protocol25 presentation contract. Never a client damage/AI command.
const KIND := "ambient_patrol_v1"
const ID := "F2:patrol_01"
const MAX_COUNTER := 9007199254740000
const KEYS := ["version","session_id","region","epoch","serial","actor","bullets"]
const ACTOR_KEYS := ["id","position","velocity","heading","health","max_health","armor","damage_serial","alive","phase","ceasefire","recoil","warning"]
const WARNING_KEYS := ["token","active","remaining_ms","origin","end","target_peer"]
const BULLET_KEYS := ["id","position","basis"]
const MAX_BULLETS := 128 # Original Host/V2 cap, not a new firing budget.
const BULLET_SCALE := Vector3(.45,.45,2.6)
const PHASES := ["patrol","notice","pursue","flank","search","lost","retreat","ceasefire","disabled"]
const REASONS := ["none","boss","radio","menu","wheel","travel","choice","vote","no_active_pilots","disabled","fault"]

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true # Feature disabled or outside F2; explicit packet key.
	if not _keys(value,KEYS) or not value.version is int or value.version!=1 or not value.region is String or value.region!="F2": return false
	if not value.session_id is String or value.session_id.is_empty() or value.session_id.length()>96: return false
	if not _integer(value.epoch,1,MAX_COUNTER) or not _integer(value.serial,0,MAX_COUNTER): return false
	var a: Variant=value.actor
	if not _keys(a,ACTOR_KEYS) or not a.id is String or a.id!=ID or not a.alive is bool or not a.phase is String or a.phase not in PHASES or not a.ceasefire is String or a.ceasefire not in REASONS: return false
	if not _point(a.position) or not a.velocity is Vector3 or not a.velocity.is_finite() or a.velocity.length()>100.0 or not _number(a.heading,-1.0e6,1.0e6): return false
	# Original EnemyActor scout limits, no HP/armor rebalance hidden in the view.
	if a.max_health!=32.0 or not _number(a.health,0.0,32.0) or not _number(a.armor,0.0,5.0) or not _integer(a.damage_serial,0,MAX_COUNTER) or not _number(a.recoil,0.0,.12): return false
	if a.alive!=(float(a.health)>0.0) or (not a.alive and (a.phase!="disabled" or a.ceasefire!="disabled")): return false
	if a.phase=="disabled" and a.alive: return false
	var w: Variant=a.warning
	if not _keys(w,WARNING_KEYS) or not w.active is bool or not _integer(w.token,0,MAX_COUNTER) or not _integer(w.remaining_ms,0,1000) or not _integer(w.target_peer,0,2147483647): return false
	if not _point(w.origin) or not _point(w.end,100.0,-100.0,100.0): return false
	if w.active and (not a.alive or a.ceasefire!="none" or w.token<1 or w.remaining_ms<1 or w.target_peer<1): return false
	if not w.active and (w.remaining_ms!=0 or w.target_peer!=0): return false
	return _bullets(value.bullets)

static func _bullets(rows: Variant) -> bool:
	if not rows is Array or rows.size()>MAX_BULLETS: return false
	var ids: Dictionary={}
	for row: Variant in rows:
		if not _keys(row,BULLET_KEYS) or not _integer(row.id,1,MAX_COUNTER) or ids.has(row.id): return false
		ids[row.id]=true
		# Original 3s * 18m/s projectile starting inside actual +/-40m F2.
		if not _point(row.position,100.0,-100.0,100.0) or not row.basis is Basis: return false
		var basis: Basis=row.basis
		for index: int in range(3):
			if not basis[index].is_finite() or absf(basis[index].length()-BULLET_SCALE[index])>.00001: return false
		var normalized: Basis=basis.orthonormalized()
		if absf(basis.x.normalized().dot(basis.y.normalized()))>.00001 or absf(basis.x.normalized().dot(basis.z.normalized()))>.00001 or absf(basis.y.normalized().dot(basis.z.normalized()))>.00001 or normalized.determinant()<0.0: return false
	return true

static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size()!=fields.size(): return false
	for key: Variant in value:
		if not key is String or key not in fields: return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return value is int and value>=low and value<=high

static func _point(value: Variant, maximum: float=40.0, minimum_y: float=-1.0, maximum_y: float=27.0) -> bool:
	return value is Vector3 and value.is_finite() and absf(value.x)<=maximum and absf(value.z)<=maximum and value.y>=minimum_y and value.y<=maximum_y
