extends CanvasLayer

# Global graphics style — autoloaded as StyleManager.
#
# A full-screen post-processing pass on a high CanvasLayer, so one shader
# restyles every scene (menu, kitchen, farm) consistently:
#   "classic"   — the hand-drawn look, untouched (shader disabled)
#   "pixel"     — chunky mosaic + posterized palette + scanlines, retro
#   "hyperreal" — cinematic grade: saturation, contrast, warm tint,
#                 highlight bloom, vignette and film grain
#
# Cycle it from Settings with [G]; the choice persists in settings.json.

const STYLES := ["classic", "pixel", "hyperreal"]
const STYLE_NAMES := {
	"classic": "Classic",
	"pixel": "Pixel Art",
	"hyperreal": "Hyperreal",
}

var _rect: ColorRect
var _mat: ShaderMaterial

func _ready():
	layer = 100  # above gameplay and the HUD layer (10)

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_linear : hint_screen_texture, filter_linear;
uniform sampler2D screen_nearest : hint_screen_texture, filter_nearest;
uniform int style = 0;          // 1 = pixel, 2 = hyperreal
uniform float pixel_size = 4.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col;
	if (style == 1) {
		vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 block = (floor(uv * res / pixel_size) + 0.5) * pixel_size / res;
		col = texture(screen_nearest, block);
		col.rgb = floor(col.rgb * 6.0 + 0.5) / 6.0;
		float scan = mod(floor(uv.y * res.y / pixel_size), 2.0);
		col.rgb *= 1.0 - 0.06 * scan;
	} else {
		col = texture(screen_linear, uv);
		float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		vec3 c = mix(vec3(lum), col.rgb, 1.28);
		c = (c - 0.5) * 1.12 + 0.5;
		c *= vec3(1.05, 1.0, 0.95);
		c += smoothstep(0.72, 1.0, lum) * 0.09;
		float d = distance(uv, vec2(0.5));
		c *= 1.0 - smoothstep(0.45, 0.9, d) * 0.32;
		float g = fract(sin(dot(uv + fract(TIME), vec2(12.9898, 78.233))) * 43758.5453);
		c += (g - 0.5) * 0.018;
		col.rgb = clamp(c, 0.0, 1.0);
	}
	COLOR = col;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = shader

	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	apply(SaveDataManager.settings.get("graphics_style", "classic"))

func current() -> String:
	return SaveDataManager.settings.get("graphics_style", "classic")

func current_name() -> String:
	return STYLE_NAMES.get(current(), "Classic")

func cycle() -> String:
	var next: String = STYLES[(STYLES.find(current()) + 1) % STYLES.size()]
	SaveDataManager.update_setting("graphics_style", next)
	apply(next)
	return next

func apply(style: String):
	match style:
		"pixel":
			_rect.visible = true
			_mat.set_shader_parameter("style", 1)
		"hyperreal":
			_rect.visible = true
			_mat.set_shader_parameter("style", 2)
		_:
			_rect.visible = false
