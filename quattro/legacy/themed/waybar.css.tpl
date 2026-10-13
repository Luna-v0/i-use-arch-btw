/* User override of omarchy's waybar template.
 * The default only defines @foreground/@background, but this user's
 * ~/.config/waybar/style.css also uses @accent (window#waybar background).
 * Without @accent the rule is invalid and the bar renders TRANSPARENT — so
 * define it (plus the palette) here to give the bar a solid background. */
@define-color foreground {{ foreground }};
@define-color background {{ background }};
@define-color accent {{ accent }};
@define-color color0 {{ color0 }};
@define-color color1 {{ color1 }};
@define-color color2 {{ color2 }};
@define-color color3 {{ color3 }};
@define-color color4 {{ color4 }};
@define-color color5 {{ color5 }};
@define-color color6 {{ color6 }};
