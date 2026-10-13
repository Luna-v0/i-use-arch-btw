#version 440

// Paint the bar's module content with a horizontally scrolling gradient.
// The content texture is used only for its alpha -- the glyph shapes become a
// window onto the gradient rather than being drawn in their own colour.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    // How many times the palette ramp repeats across the bar. 1 spreads a
    // single ramp end to end, which reads as almost flat on a 3440px bar;
    // 2-3 makes the colour travel obvious.
    float repeats;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D grad;

void main() {
    vec4 src = texture(source, qt_TexCoord0);
    vec3 g = texture(grad, vec2(fract(qt_TexCoord0.x * repeats - phase), 0.5)).rgb;

    // Qt Quick composites premultiplied, so scale colour by the coverage we
    // inherited from the glyph. Anti-aliased edges and the 0.45-opacity
    // "dimmed" widget state both survive because they live in src.a.
    fragColor = vec4(g * src.a, src.a) * qt_Opacity;
}
