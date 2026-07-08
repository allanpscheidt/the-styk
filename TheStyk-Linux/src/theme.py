from models import NoteColor, NoteFontID

# Hex colors
COLORS = {
    NoteColor.yellow: "#FFE066",
    NoteColor.pink: "#FFB3C7",
    NoteColor.blue: "#9AD1FF",
    NoteColor.green: "#B5E8A0",
    NoteColor.orange: "#FFC97A",
    NoteColor.purple: "#D9BBFF",
}

LABELS = {
    NoteColor.yellow: "Amarelo",
    NoteColor.pink: "Rosa",
    NoteColor.blue: "Azul",
    NoteColor.green: "Verde",
    NoteColor.orange: "Laranja",
    NoteColor.purple: "Roxo",
}

FONTS = {
    NoteFontID.system: "Cantarell, Ubuntu, DejaVu Sans, sans-serif",
    NoteFontID.rounded: "Cantarell, Ubuntu, sans-serif",  # GTK doesn't have standard rounded, so we will use heavier weight or system font
    NoteFontID.serif: "DejaVu Serif, Times New Roman, serif",
    NoteFontID.mono: "DejaVu Sans Mono, Monospace, monospace",
    NoteFontID.hand: "Purisa, Comic Sans MS, cursive",
}

TEXT_COLOR = "#1C1C1E"

def get_color_hex(color: NoteColor) -> str:
    return COLORS.get(color, COLORS[NoteColor.yellow])

def get_label(color: NoteColor) -> str:
    return LABELS.get(color, LABELS[NoteColor.yellow])

def get_font_family(font_id: NoteFontID) -> str:
    return FONTS.get(font_id, FONTS[NoteFontID.system])

def get_rgb_color(color: NoteColor) -> tuple:
    hex_val = get_color_hex(color).lstrip("#")
    return tuple(int(hex_val[i:i+2], 16) / 255.0 for i in (0, 2, 4))

def get_css(color: NoteColor, font_id: NoteFontID, font_size: float) -> str:
    bg_color = get_color_hex(color)
    font_family = get_font_family(font_id)
    font_weight = "bold" if font_id == NoteFontID.rounded else "normal"
    
    # We can customize the CSS for GTK widgets:
    # - main note window background color with 12px border radius
    # - text view transparent and comfortable padding
    css = f"""
    .note-window {{
        background-color: transparent;
    }}
    textview, textview text, scrolledwindow, scrolledwindow viewport {{
        background-color: transparent;
        background: transparent;
        background-image: none;
    }}
    .note-textview {{
        color: {TEXT_COLOR};
        font-family: {font_family};
        font-size: {font_size}pt;
        font-weight: {font_weight};
    }}
    .note-toolbar {{
        background-color: rgba(255, 255, 255, 0.15);
        border-radius: 8px 8px 0px 0px;
    }}
    .note-button {{
        background-color: transparent;
        border: none;
        color: {TEXT_COLOR};
        border-radius: 4px;
        padding: 2px 6px;
    }}
    .note-button:hover {{
        background-color: rgba(0, 0, 0, 0.05);
    }}
    """
    return css
