extends SceneTree

func _initialize() -> void:
	for path in ["res://models/spaceship.glb", "res://models/drone.glb"]:
		print("\n======================================== ", path)
		var ps: PackedScene = load(path)
		if ps == null:
			print("  FAILED TO LOAD"); continue
		var root: Node = ps.instantiate()
		get_root().add_child(root)
		_analyze(path, root)
		root.queue_free()
	quit()

func _collect(node: Node, root: Node3D, out: PackedVector3Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var xform: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				out.append(xform * v)
	for c in node.get_children():
		_collect(c, root, out)

func _analyze(path: String, root: Node3D) -> void:
	var verts := PackedVector3Array()
	_collect(root, root, verts)
	if verts.is_empty():
		print("  no verts"); return

	var mn := verts[0]
	var mx := verts[0]
	var centroid := Vector3.ZERO
	for v in verts:
		mn = mn.min(v); mx = mx.max(v); centroid += v
	centroid /= verts.size()
	var sizev := mx - mn
	print("  verts=%d  AABB.size=%s  centroid=%s" % [verts.size(), str(sizev.snapped(Vector3.ONE*0.001)), str(centroid.snapped(Vector3.ONE*0.001))])

	# For each axis, measure taper: mean perpendicular radius of the extreme 12%
	# of vertices at the +end and -end. The NOSE end has the smaller radius.
	var axis_names := ["X", "Y", "Z"]
	for a in 3:
		var sorted := _sorted_by_axis(verts, a)
		var n := sorted.size()
		var k := maxi(1, int(n * 0.12))
		var rad_minus := _mean_perp_radius(sorted.slice(0, k), a, centroid)
		var rad_plus := _mean_perp_radius(sorted.slice(n - k, n), a, centroid)
		var nose: String = ("-" + str(axis_names[a])) if rad_minus < rad_plus else ("+" + str(axis_names[a]))
		print("    axis %s: extent=%.3f  rad(-end)=%.3f  rad(+end)=%.3f  -> pointy/nose toward %s" % [
			axis_names[a], sizev[a], rad_minus, rad_plus, nose])

func _sorted_by_axis(verts: PackedVector3Array, a: int) -> PackedVector3Array:
	var arr := Array(verts)
	arr.sort_custom(func(p, q): return p[a] < q[a])
	var out := PackedVector3Array()
	for v in arr: out.append(v)
	return out

func _mean_perp_radius(slice: PackedVector3Array, a: int, centroid: Vector3) -> float:
	if slice.is_empty(): return 0.0
	var total := 0.0
	for v in slice:
		var d := v - centroid
		d[a] = 0.0   # drop the along-axis component → perpendicular radius
		total += d.length()
	return total / slice.size()
