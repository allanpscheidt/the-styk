using System;
using System.Text.Json.Serialization;

namespace TheStyk.Models
{
    public enum NoteColor
    {
        yellow,
        pink,
        blue,
        green,
        orange,
        purple
    }

    public enum NoteFontID
    {
        system,
        rounded,
        serif,
        mono,
        hand
    }

    public struct NoteStyle
    {
        [JsonPropertyName("color")]
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public NoteColor Color { get; set; }

        [JsonPropertyName("fontID")]
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public NoteFontID FontID { get; set; }

        [JsonPropertyName("fontSize")]
        public double FontSize { get; set; }
    }

    public struct NoteFrame
    {
        [JsonPropertyName("x")]
        public double X { get; set; }

        [JsonPropertyName("y")]
        public double Y { get; set; }

        [JsonPropertyName("w")]
        public double W { get; set; }

        [JsonPropertyName("h")]
        public double H { get; set; }
    }

    public class Note
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; }

        [JsonPropertyName("folder")]
        public string Folder { get; set; } = string.Empty;

        [JsonPropertyName("text")]
        public string Text { get; set; } = string.Empty;

        [JsonPropertyName("style")]
        public NoteStyle Style { get; set; }

        [JsonPropertyName("frame")]
        public NoteFrame Frame { get; set; }

        [JsonPropertyName("created")]
        public DateTime Created { get; set; }

        [JsonPropertyName("modified")]
        public DateTime Modified { get; set; }
    }

    public class IndexEntry
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; }

        [JsonPropertyName("folder")]
        public string Folder { get; set; } = string.Empty;

        [JsonPropertyName("snippet")]
        public string Snippet { get; set; } = string.Empty;

        [JsonPropertyName("color")]
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public NoteColor Color { get; set; }

        [JsonPropertyName("modified")]
        public DateTime Modified { get; set; }

        [JsonPropertyName("orphaned")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public bool? Orphaned { get; set; }
    }

    public class IndexRoot
    {
        [JsonPropertyName("version")]
        public int Version { get; set; } = 1;

        [JsonPropertyName("notes")]
        public System.Collections.Generic.List<IndexEntry> Notes { get; set; } = new();
    }

    public class TrashEntry
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; }

        [JsonPropertyName("folder")]
        public string Folder { get; set; } = string.Empty;

        [JsonPropertyName("snippet")]
        public string Snippet { get; set; } = string.Empty;

        [JsonPropertyName("color")]
        [JsonConverter(typeof(JsonStringEnumConverter))]
        public NoteColor Color { get; set; }

        [JsonPropertyName("deletedAt")]
        public DateTime DeletedAt { get; set; }
    }

    public class TrashRoot
    {
        [JsonPropertyName("version")]
        public int Version { get; set; } = 1;

        [JsonPropertyName("trash")]
        public System.Collections.Generic.List<TrashEntry> Trash { get; set; } = new();
    }
}
