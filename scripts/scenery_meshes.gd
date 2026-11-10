class_name SnowMeshes
extends RefCounted
## Procedural scenery meshes built once at startup, no downloaded assets.
## Trees: tiered drooping conifers with snow-loaded upper boughs, plus cheap far
## LODs. Rocks: noise-displaced, flat-shaded faceted boulders whose exact vertices
## also become their convex colliders.
const TRUNK_RADIUS := 0.3      # x tree scale; visible solid trunk == collider
const TRUNK_SOLID_HEIGHT := 4.8 # x tree scale; canopy above/around it is non-solid

static func _hash(n: float) -> float:
	return fposmod(sin(n * 127.1 + 311.7) * 43758.5453, 1.0)

## Tree vertex colour: rgb = bark/foliage tint multiplier, a = snow cover 0..1.
## UV.x = 0 for bark, 1 for foliage (shader picks material).
static func conifer(seed: int, height: float, width: float, tiers: int, droop: float, snow: float, segments := 11) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Trunk: exact solid cylinder up to the collider height, tapering above.
	var trunk_top := height * 0.82
	var rings := [[0.0, TRUNK_RADIUS], [TRUNK_SOLID_HEIGHT, TRUNK_RADIUS], [trunk_top, 0.05]]
	for r in rings.size() - 1:
		var y0: float = rings[r][0]
		var y1: float = rings[r + 1][0]
		var r0: float = rings[r][1]
		var r1: float = rings[r + 1][1]
		for i in 8:
			var a0 := TAU * i / 8.0
			var a1 := TAU * (i + 1) / 8.0
			var p := [Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0), Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
			var n0 := Vector3(cos(a0), 0.1, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), 0.1, sin(a1)).normalized()
			for v in [[p[0], n0], [p[2], n1], [p[1], n1], [p[0], n0], [p[3], n0], [p[2], n1]]:
				st.set_color(Color(1, 1, 1, 0.0))
				st.set_uv(Vector2(0, 0))
				st.set_normal(v[1])
				st.add_vertex(v[0])
	# Foliage tiers: each a drooping skirt with jagged bough tips and a dark underside.
	var base_y := height * 0.14
	for t in tiers:
		var f := float(t) / tiers
		var y_bottom := lerpf(base_y, height * 0.88, f)
		var tier_h := (height - base_y) / tiers * 1.75
		var radius := width * pow(1.0 - f, 0.95) * rng.randf_range(0.88, 1.08) + 0.25
		var apex := Vector3(0, minf(y_bottom + tier_h, height), 0)
		var inner := Vector3(0, y_bottom + tier_h * 0.18, 0)
		var ring: Array[Vector3] = []
		var count := segments + (t % 2)
		var spin := rng.randf() * TAU
		for i in count:
			var a := spin + TAU * i / count + rng.randf_range(-0.12, 0.12)
			var tip := i % 2 == 0
			var r := radius * (1.0 if tip else rng.randf_range(0.62, 0.74))
			var sag := droop * r * (0.55 if tip else 0.25) + rng.randf_range(-0.12, 0.12)
			ring.append(Vector3(cos(a) * r, y_bottom - sag, sin(a) * r))
		var tier_snow := clampf(snow * (0.65 + f * 0.6) * rng.randf_range(0.8, 1.15), 0.0, 1.0)
		for i in count:
			var a := ring[i]
			var b := ring[(i + 1) % count]
			# Upper surface: snow-loaded toward the bough centre, green at the tips.
			var top_n := (b - a).cross(apex - a).normalized()
			if top_n.y < 0.0: top_n = -top_n
			top_n = (top_n + Vector3.UP * 0.6).normalized()
			var shade := rng.randf_range(0.82, 1.12)
			for v in [[apex, tier_snow, 1.05], [a, tier_snow * 0.55, 0.9], [b, tier_snow * 0.55, 0.9]]:
				st.set_color(Color(shade * v[2], shade * v[2], shade * v[2], v[1]))
				st.set_uv(Vector2(1, 0))
				st.set_normal(top_n)
				st.add_vertex(v[0])
			# Underside: shadowed needles, no snow.
			var under_n := (a - inner).cross(b - inner).normalized()
			if under_n.y > 0.0: under_n = -under_n
			under_n = (under_n + (a + b).normalized() * 0.8).normalized()
			for v in [inner, b, a]:
				st.set_color(Color(0.55, 0.55, 0.55, 0.0))
				st.set_uv(Vector2(1, 0))
				st.set_normal(under_n)
				st.add_vertex(v)
	# Snow-capped leader.
	var top := Vector3(0, height * 1.02, 0)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 1) / 5.0
		var p0 := Vector3(cos(a0) * 0.35, height * 0.9, sin(a0) * 0.35)
		var p1 := Vector3(cos(a1) * 0.35, height * 0.9, sin(a1) * 0.35)
		var n := (p1 - p0).cross(top - p0).normalized()
		if n.y < 0: n = -n
		for v in [top, p0, p1]:
			st.set_color(Color(1, 1, 1, snow))
			st.set_uv(Vector2(1, 0))
			st.set_normal(n)
			st.add_vertex(v)
	st.index()
	return st.commit()

## Far LOD: two stacked cones, still snow-dusted, ~30 triangles.
static func conifer_far(height: float, width: float, snow: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cone in [[height * 0.12, height * 0.62, width], [height * 0.5, height * 1.02, width * 0.62]]:
		var y0: float = cone[0]
		var y1: float = cone[1]
		var r: float = cone[2]
		for i in 7:
			var a0 := TAU * i / 7.0
			var a1 := TAU * (i + 1) / 7.0
			var p0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
			var apex := Vector3(0, y1, 0)
			var n := (p1 - p0).cross(apex - p0).normalized()
			if n.y < 0: n = -n
			for v in [[apex, snow], [p0, snow * 0.4], [p1, snow * 0.4]]:
				st.set_color(Color(1, 1, 1, v[1]))
				st.set_uv(Vector2(1, 0))
				st.set_normal(n)
				st.add_vertex(v[0])
	return st.commit()

## Faceted boulder. Returns [mesh, points]; points are the exact unit-scale
## vertices used for both the visual and the convex collider.
static func boulder(seed: int, detail := 1) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces := [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	for d in detail:
		var next_faces := []
		var cache := {}
		for f in faces:
			var mids := []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not cache.has(key):
					verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					cache[key] = verts.size() - 1
				mids.append(cache[key])
			next_faces.append([f[0], mids[0], mids[2]])
			next_faces.append([f[1], mids[1], mids[0]])
			next_faces.append([f[2], mids[2], mids[1]])
			next_faces.append([mids[0], mids[1], mids[2]])
		faces = next_faces
	var s := float(seed)
	var points := PackedVector3Array()
	for v in verts:
		var n := 1.0
		n += 0.22 * sin(v.x * 3.1 + s) * sin(v.y * 2.7 + s * 1.7) + 0.14 * sin(v.z * 5.3 + s * 0.6)
		n += 0.1 * sin(v.x * 8.0 + v.z * 7.0 + s * 3.1)
		var p := v * n
		# Flattened, cleaved base sits into the snow; a sheared top face reads as stone.
		p.y = maxf(p.y, -0.55)
		if p.y > 0.5 + 0.2 * sin(s):
			p.y = lerpf(p.y, 0.5 + 0.2 * sin(s), 0.6)
		points.append(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a := points[f[0]]
		var b := points[f[1]]
		var c := points[f[2]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(a + b + c) < 0.0:
			n = -n
			var tmp := b
			b = c
			c = tmp
		for v in [a, c, b]:
			st.set_normal(n)
			st.add_vertex(v)
	return [st.commit(), points]
