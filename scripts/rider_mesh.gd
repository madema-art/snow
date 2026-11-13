class_name SnowRiderMesh
extends RefCounted
## Small mesh builder for the procedural rider: tubes swept along a path with
## elliptical or rounded-box cross-sections, optional end caps, per-vertex colour
## (colour blocking, seams, stripes) and smooth normals. Several sweeps can be
## added to one builder so a whole garment is one mesh and one draw call.
var st := SurfaceTool.new()
var count := 0

func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

## Sweep a tube along `path`.
## `ru`/`rw`: half-sizes per path point along `side` (made perpendicular to the
## path) and along tangent x side. `shape`: superellipse exponent (2 = ellipse,
## 4..8 = rounded box). `color`: a Color, or Callable(v: Vector3, i: int, a: float)
## returning one (v = local vertex, i = path index, a = angle around the tube).
## `warp`: optional Callable(v: Vector3) -> Vector3 applied before colouring.
func sweep(path: Array, ru: Array, rw: Array, side: Vector3, color, around := 14, shape := 2.0, caps := true, xform := Transform3D.IDENTITY, warp := Callable()) -> void:
	var n := path.size()
	var base := count
	var local := PackedVector3Array()
	var tangents: Array[Vector3] = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[n - 1] - path[n - 2]
		else:
			t = (path[i + 1] - path[i]).normalized() + (path[i] - path[i - 1]).normalized()
		t = t.normalized()
		tangents.append(t)
		var u := (side - t * side.dot(t)).normalized()
		var w := t.cross(u)
		for j in around:
			var a := TAU * j / around
			var c := cos(a)
			var s := sin(a)
			var cu := signf(c) * pow(absf(c), 2.0 / shape)
			var sw := signf(s) * pow(absf(s), 2.0 / shape)
			var v: Vector3 = path[i] + u * (float(ru[i]) * cu) + w * (float(rw[i]) * sw)
			if warp.is_valid():
				v = warp.call(v)
			local.append(v)
			st.set_color(color.call(v, i, a) if color is Callable else color)
			st.add_vertex(xform * v)
			count += 1
	# Wind every sweep the same way round: outward faces are front faces.
	var m := clampi(n / 2, 0, n - 2)
	var q0 := local[m * around]
	var q1 := local[m * around + 1]
	var p0 := local[(m + 1) * around]
	var centre: Vector3 = path[m]
	var flip := (p0 - q0).cross(q1 - q0).dot(q0 - centre) > 0.0
	for i in n - 1:
		for j in around:
			var a0 := base + i * around + j
			var a1 := base + i * around + (j + 1) % around
			tri(a0, a0 + around, a1, flip)
			tri(a1, a0 + around, a1 + around, flip)
	if caps:
		for end in [0, n - 1]:
			var dir: Vector3 = -tangents[0] if end == 0 else tangents[n - 1]
			var dome := minf(float(ru[end]), float(rw[end])) * 0.35
			var pole: Vector3 = path[end] + dir * dome
			if warp.is_valid():
				pole = warp.call(pole)
			st.set_color(color.call(pole, end, 0.0) if color is Callable else color)
			st.add_vertex(xform * pole)
			var pi_index := count
			count += 1
			for j in around:
				var r0: int = base + end * around + j
				var r1: int = base + end * around + (j + 1) % around
				# Same orientation rule as the sides, reversed at the start cap.
				tri(r0, r1, pi_index, flip == (end == 0))

func tri(a: int, b: int, c: int, flip: bool) -> void:
	if flip:
		st.add_index(a)
		st.add_index(c)
		st.add_index(b)
	else:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)

## A straight tube along +Y from rings of [y, ru(x), rw(z), cx, cz].
func column(rings: Array, color, around := 14, shape := 2.0, caps := true, xform := Transform3D.IDENTITY, warp := Callable()) -> void:
	var path := []
	var ru := []
	var rw := []
	for r in rings:
		path.append(Vector3(r[3] if r.size() > 3 else 0.0, r[0], r[4] if r.size() > 4 else 0.0))
		ru.append(r[1])
		rw.append(r[2])
	sweep(path, ru, rw, Vector3.RIGHT, color, around, shape, caps, xform, warp)

## Insert interpolated rings just either side of each height in `ys`, so a
## colour edge there is crisp instead of smeared across a long ring gap.
static func cut(rings: Array, ys: Array) -> Array:
	var out := rings.duplicate(true)
	for y in ys:
		for e in [-0.003, 0.003]:
			var at: float = y + e
			for i in out.size() - 1:
				var a: Array = out[i]
				var b: Array = out[i + 1]
				if a[0] < at and b[0] > at:
					var t: float = (at - a[0]) / (b[0] - a[0])
					var r := [at]
					for k in range(1, maxi(a.size(), b.size())):
						r.append(lerpf(a[k] if k < a.size() else 0.0, b[k] if k < b.size() else 0.0, t))
					out.insert(i + 1, r)
					break
	return out

## A thin strip lying on the front (-X) of a column, e.g. a zip.
func front_strip(rings: Array, y0: float, y1: float, half_width: float, color) -> void:
	var path := []
	for r in rings:
		if r[0] >= y0 and r[0] <= y1:
			path.append(Vector3((r[3] if r.size() > 3 else 0.0) - r[1] - 0.003, r[0], 0.0))
	if path.size() >= 2:
		sweep(path, fill(path.size(), half_width), fill(path.size(), 0.004), Vector3.BACK, color, 6, 4.0)

static func fill(n: int, value: float) -> Array:
	var a := []
	a.resize(n)
	a.fill(value)
	return a

## An ellipsoid (rings follow a circle profile).
func ellipsoid(centre: Vector3, radii: Vector3, color, around := 14, rings := 7, xform := Transform3D.IDENTITY) -> void:
	var r := []
	for i in rings:
		var k := -1.0 + 2.0 * (i + 0.5) / rings
		var s := sqrt(maxf(0.0, 1.0 - k * k))
		r.append([centre.y + k * radii.y, radii.x * s, radii.z * s, centre.x, centre.z])
	column(r, color, around, 2.0, true, xform)

## A rounded box centred at `centre`.
func box(centre: Vector3, size: Vector3, color, shape := 6.0, xform := Transform3D.IDENTITY) -> void:
	var h := size * 0.5
	column([[centre.y - h.y, h.x, h.z, centre.x, centre.z], [centre.y - h.y * 0.8, h.x, h.z, centre.x, centre.z], [centre.y + h.y * 0.8, h.x, h.z, centre.x, centre.z], [centre.y + h.y, h.x, h.z, centre.x, centre.z]], color, 16, shape, true, xform)

func commit() -> ArrayMesh:
	st.generate_normals()
	return st.commit()
