shader_type canvas_item;

// 弹体边缘颜色（默认亮黄）
uniform vec4 edge_color : source_color = vec4(1.0, 0.8, 0.0, 1.0);
// 中心颜色（亮白）
uniform vec4 center_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 渐变过渡宽度 (0~1)，0=无渐变硬边缘，1=全程渐变
uniform float transition_width : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	// 取原始纹理的 alpha 来保留形状（胶囊裁切）
	vec4 tex = texture(TEXTURE, UV);
	float alpha = tex.a;

	// 沿垂直方向（UV.y）计算到中心的距离：0=中心，1=上下两端
	float dist_to_center = abs(UV.y - 0.5) * 2.0;

	// 渐变混合因子：中心附近为 white，逐渐过渡到 edge_color
	float t = smoothstep(0.0, transition_width, dist_to_center);
	vec3 final_color = mix(center_color.rgb, edge_color.rgb, t);

	COLOR = vec4(final_color, alpha);
}
