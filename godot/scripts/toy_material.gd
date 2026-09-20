extends RefCounted


static func create(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = preload("res://assets/textures/toy-plastic-codex.png")
	mat.roughness = .28
	mat.metallic = 0.0
	mat.metallic_specular = .5
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(2, 2, 2)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat
