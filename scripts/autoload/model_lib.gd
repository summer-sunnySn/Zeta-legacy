## Zeta Legacy — Runtime Model Library (autoload: ModelLib)
## The Godot editor importer SEGFAULTS on this device (help-cache regen), so we
## cannot import .glb assets the normal way. Instead this autoload loads a .glb
## ONCE via GLTFDocument at runtime, packs the result into a PackedScene, and
## caches it — every later request just instantiates the cached scene cheaply
## (mesh + textures are shared resources, only the node tree is duplicated).
##
## Handles animated models too: the generated scene keeps its AnimationPlayer,
## so play_loop() can spin a UFO's rings, etc.
extends Node

var _cache: Dictionary = {}        # path -> PackedScene (or null if it failed)

## Return a fresh instance of the model at `path`, or null on failure.
func instance_model(path: String) -> Node3D:
	var ps := _get_packed(path)
	if ps == null:
		return null
	return ps.instantiate() as Node3D

func _get_packed(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_warning("ModelLib: file not found '%s'" % path)
		_cache[path] = null
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		_cache[path] = null
		return null
	var scn: Node = doc.generate_scene(state)
	if scn == null:
		_cache[path] = null
		return null
	# Every descendant must be owned by the root for PackedScene.pack() to keep
	# it (GLTFDocument leaves owners unset).
	_own_all(scn, scn)
	var ps := PackedScene.new()
	var ok := ps.pack(scn)
	scn.queue_free()
	if ok != OK:
		_cache[path] = null
		return null
	_cache[path] = ps
	return ps

func _own_all(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own_all(c, root)

## Auto-centre + uniform-scale a model so its longest side == `target_len`.
## Must be called AFTER the model is inside the tree. Returns the scale used.
func fit(model: Node3D, target_len: float) -> float:
	var inv := model.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for mi in _all_meshes(model):
		var rel: Transform3D = inv * mi.global_transform
		var a: AABB = rel * mi.get_aabb()
		if first:
			merged = a
			first = false
		else:
			merged = merged.merge(a)
	if first or merged.size == Vector3.ZERO:
		return 1.0
	var longest := maxf(merged.size.x, maxf(merged.size.y, merged.size.z))
	var s := target_len / maxf(longest, 0.001)
	model.scale = Vector3(s, s, s)
	model.position = -merged.get_center() * s
	return s

func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out

## Loop the model's first baked animation (UFO rings, engine glow, …).
func play_loop(model: Node3D, speed: float = 1.0) -> void:
	var ap := _find_anim_player(model)
	if ap == null:
		return
	var names := ap.get_animation_list()
	if names.is_empty():
		return
	var anim := ap.get_animation(names[0])
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.speed_scale = speed
	ap.play(names[0])

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
