using System;
using System.Windows.Media;
using TheStyk.Models;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;

namespace TheStyk.UI
{
    public static class Theme
    {
        public static Color GetColor(NoteColor color)
        {
            return color switch
            {
                NoteColor.yellow => ParseColorHex("#FFE066"),
                NoteColor.pink => ParseColorHex("#FFB3C7"),
                NoteColor.blue => ParseColorHex("#9AD1FF"),
                NoteColor.green => ParseColorHex("#B5E8A0"),
                NoteColor.orange => ParseColorHex("#FFC97A"),
                NoteColor.purple => ParseColorHex("#D9BBFF"),
                _ => ParseColorHex("#FFE066")
            };
        }

        public static SolidColorBrush GetBrush(NoteColor color, double opacity = 1.0)
        {
            var c = GetColor(color);
            c.A = (byte)(opacity * 255);
            var brush = new SolidColorBrush(c);
            brush.Freeze();
            return brush;
        }

        public static SolidColorBrush GetTextBrush()
        {
            var brush = new SolidColorBrush(ParseColorHex("#1C1C1E"));
            brush.Freeze();
            return brush;
        }

        public static FontFamily GetFontFamily(NoteFontID fontID)
        {
            return fontID switch
            {
                NoteFontID.system => new FontFamily("Segoe UI"),
                NoteFontID.rounded => new FontFamily("Segoe UI Semibold, Arial Rounded MT Bold"),
                NoteFontID.serif => new FontFamily("Georgia, Times New Roman"),
                NoteFontID.mono => new FontFamily("Consolas, Courier New"),
                NoteFontID.hand => new FontFamily("Segoe Print, Ink Free, Comic Sans MS"),
                _ => new FontFamily("Segoe UI")
            };
        }

        public static string GetLabel(NoteColor color)
        {
            return color switch
            {
                NoteColor.yellow => "Amarelo",
                NoteColor.pink => "Rosa",
                NoteColor.blue => "Azul",
                NoteColor.green => "Verde",
                NoteColor.orange => "Laranja",
                NoteColor.purple => "Roxo",
                _ => "Amarelo"
            };
        }

        private static Color ParseColorHex(string hex)
        {
            return (Color)System.Windows.Media.ColorConverter.ConvertFromString(hex);
        }
    }
}
