extends RefCounted
## A játékos azonosítója regisztráció nélkül: egy kulcspár, amit a játék az első használatkor a
## játékos gépén készít (user://aether_azonosito/), és ami SOHA nem kerül a tárolóba vagy máshová.
## Ezzel írja alá a játékos a megosztott kutatását: bárki ellenőrizheti, hogy tényleg tőle jött,
## és senki más nem küldhet a nevében. Nincs jelszó, e-mail vagy más személyes adat.
##
## Használat:
##   var signed := Identity.sign_dict(eredmeny)     # "alairas" mezővel kiegészítve
##   Identity.verify_dict(signed)                    # true, ha az aláírás és a tartalom egyezik
##   Identity.short_id()                             # pl. "7F3A-91C2": a nyilvános kulcs ujjlenyomata

const DIR := "user://aether_azonosito"
const KEY_FILE := DIR + "/kulcs.key"       # titkos kulcs (csak ezen a gépen)
const PUB_FILE := DIR + "/kulcs.pub"       # nyilvános kulcs
const KEY_BITS := 2048
const FIELD := "alairas"

static var _key: CryptoKey


## A titkos kulcs (ha még nincs, most készül el, és elmentődik).
static func _private() -> CryptoKey:
	if _key != null:
		return _key
	var k := CryptoKey.new()
	if FileAccess.file_exists(KEY_FILE) and k.load(KEY_FILE) == OK:
		_key = k
		return _key
	DirAccess.make_dir_recursive_absolute(DIR)
	_key = Crypto.new().generate_rsa(KEY_BITS)
	_key.save(KEY_FILE)
	_key.save(PUB_FILE, true)
	return _key


static func has_identity() -> bool:
	return FileAccess.file_exists(KEY_FILE)


## A nyilvános kulcs szövegként (PEM): ezt bárki megkaphatja, ezzel ellenőrizhető az aláírás.
static func public_pem() -> String:
	return _private().save_to_string(true)


## Rövid, olvasható azonosító a nyilvános kulcs ujjlenyomatából (pl. "7F3A-91C2").
static func short_id(pem: String = "") -> String:
	var h := (pem if pem != "" else public_pem()).sha256_text().to_upper()
	return h.substr(0, 4) + "-" + h.substr(4, 4)


static func _digest(data: PackedByteArray) -> PackedByteArray:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(data)
	return hc.finish()


static func sign_bytes(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, _digest(data), _private()))


static func verify_bytes(data: PackedByteArray, signature_b64: String, pem: String) -> bool:
	var pub := CryptoKey.new()
	if pub.load_from_string(pem, true) != OK:
		return false
	var sig := Marshalls.base64_to_raw(signature_b64)
	if sig.is_empty():
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, _digest(data), sig, pub)


## Az aláírt tartalom: a szótár az aláírás mező nélkül, rendezett kulcsokkal, így ugyanaz a
## tartalom mindig ugyanazt a bájtsort adja.
## A számokat egységesen tört számként írja (a JSON beolvasás után minden szám tört szám lesz,
## így mentés és visszaolvasás után is ugyanazt a bájtsort kapjuk).
static func canonical(d: Dictionary) -> PackedByteArray:
	var c: Dictionary = _norm(d)
	c.erase(FIELD)
	return JSON.stringify(c, "", true).to_utf8_buffer()


static func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return float(v)
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[str(k)] = _norm(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_norm(x))
			return a
	return v


## A szótár másolata „alairas” mezővel: nyilvános kulcs, rövid azonosító, aláírás.
static func sign_dict(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out.erase(FIELD)
	var pem := public_pem()
	out[FIELD] = {"kulcs": pem, "azonosito": short_id(pem), "alairas": sign_bytes(canonical(out))}
	return out


## Igaz, ha a szótárban van aláírás, és az a tartalomhoz és a benne lévő kulcshoz tartozik.
## (Hogy a kulcs KIÉ, azt a közös archívum jegyzéke dönti el: ott a jóváhagyott azonosítók szerepelnek.)
static func verify_dict(d: Dictionary) -> bool:
	var s: Variant = d.get(FIELD)
	if typeof(s) != TYPE_DICTIONARY:
		return false
	var pem := str(s.get("kulcs", ""))
	if pem == "" or str(s.get("azonosito", "")) != short_id(pem):
		return false
	return verify_bytes(canonical(d), str(s.get("alairas", "")), pem)
