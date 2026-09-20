extends RefCounted

static var _textures: Dictionary = {}

static func grain(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var noise:=FastNoiseLite.new()
	noise.seed=137 if kind=="plaster" else (421 if kind=="wood" else 683)
	noise.frequency=0.055 if kind=="plaster" else 0.16
	noise.fractal_octaves=2
	var image:=Image.create(128,128,false,Image.FORMAT_RGB8)
	for y: int in range(128):
		for x: int in range(128):
			var n: float=noise.get_noise_2d(x*0.18 if kind=="wood" else x,y)
			var value: float=0.92+n*0.10
			if kind=="wood": value=0.87+n*0.20
			image.set_pixel(x,y,Color(value,value,value))
	image.generate_mipmaps()
	var texture:=ImageTexture.create_from_image(image)
	_textures[kind]=texture
	return texture

static func apply(material: StandardMaterial3D,kind: String,scale: float=1.0) -> void:
	material.albedo_texture=grain(kind)
	material.uv1_triplanar=true
	material.uv1_world_triplanar=true
	material.uv1_scale=Vector3.ONE*scale
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness=0.93 if kind=="plaster" else 0.83
