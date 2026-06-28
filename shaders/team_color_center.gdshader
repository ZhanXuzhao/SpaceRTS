shader_type canvas_item;

uniform vec4 team_color : source_color;
// 横线高度占比 (0~1)，船高10% = 0.1
uniform float stripe_height : hint_range(0.0, 0.5) = 0.1;
// 边缘羽化宽度

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// 硬边缘：在横线内染色，否则保持原色
	float weight = abs(UV.y - 0.5) < stripe_height * 0.5 ? 1.0 : 0.0;
	
	// 染色 = 贴图颜色 × 队伍颜色，仅横线区域生效
	vec3 tinted = tex_color.rgb * team_color.rgb;
	COLOR = vec4(mix(tex_color.rgb, tinted, weight), tex_color.a);
}
