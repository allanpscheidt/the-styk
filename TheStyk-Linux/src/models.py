from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, List
import uuid

class NoteColor(str, Enum):
    yellow = "yellow"
    pink = "pink"
    blue = "blue"
    green = "green"
    orange = "orange"
    purple = "purple"

class NoteFontID(str, Enum):
    system = "system"
    rounded = "rounded"
    serif = "serif"
    mono = "mono"
    hand = "hand"

@dataclass
class NoteStyle:
    color: NoteColor = NoteColor.yellow
    fontID: NoteFontID = NoteFontID.system
    fontSize: float = 14.0

    def to_dict(self):
        return {
            "color": self.color.value,
            "fontID": self.fontID.value,
            "fontSize": self.fontSize
        }

    @classmethod
    def from_dict(cls, d: dict) -> "NoteStyle":
        color_val = d.get("color", "yellow")
        font_val = d.get("fontID", "system")
        try:
            color = NoteColor(color_val)
        except ValueError:
            color = NoteColor.yellow
        try:
            font_id = NoteFontID(font_val)
        except ValueError:
            font_id = NoteFontID.system
        return cls(
            color=color,
            fontID=font_id,
            fontSize=float(d.get("fontSize", 14.0))
        )

@dataclass
class NoteFrame:
    x: float
    y: float
    w: float
    h: float

    def to_dict(self):
        return {
            "x": self.x,
            "y": self.y,
            "w": self.w,
            "h": self.h
        }

    @classmethod
    def from_dict(cls, d: dict) -> "NoteFrame":
        return cls(
            x=float(d.get("x", 0.0)),
            y=float(d.get("y", 0.0)),
            w=float(d.get("w", 260.0)),
            h=float(d.get("h", 240.0))
        )

@dataclass
class Note:
    id: uuid.UUID
    folder: str
    text: str
    style: NoteStyle
    frame: NoteFrame
    created: datetime
    modified: datetime

    def to_dict(self):
        return {
            "id": str(self.id),
            "folder": self.folder,
            "text": self.text,
            "style": self.style.to_dict(),
            "frame": self.frame.to_dict(),
            "created": format_iso_datetime(self.created),
            "modified": format_iso_datetime(self.modified)
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Note":
        nid = uuid.UUID(d["id"]) if isinstance(d.get("id"), str) else d["id"]
        return cls(
            id=nid,
            folder=d.get("folder", ""),
            text=d.get("text", ""),
            style=NoteStyle.from_dict(d.get("style", {})),
            frame=NoteFrame.from_dict(d.get("frame", {})),
            created=parse_iso_datetime(d.get("created")),
            modified=parse_iso_datetime(d.get("modified"))
        )

@dataclass
class IndexEntry:
    id: uuid.UUID
    folder: str
    snippet: str
    color: NoteColor
    modified: datetime
    orphaned: Optional[bool] = None

    def to_dict(self):
        res = {
            "id": str(self.id),
            "folder": self.folder,
            "snippet": self.snippet,
            "color": self.color.value,
            "modified": format_iso_datetime(self.modified)
        }
        if self.orphaned is not None:
            res["orphaned"] = self.orphaned
        return res

    @classmethod
    def from_dict(cls, d: dict) -> "IndexEntry":
        nid = uuid.UUID(d["id"]) if isinstance(d.get("id"), str) else d["id"]
        color_val = d.get("color", "yellow")
        try:
            color = NoteColor(color_val)
        except ValueError:
            color = NoteColor.yellow
        return cls(
            id=nid,
            folder=d.get("folder", ""),
            snippet=d.get("snippet", ""),
            color=color,
            modified=parse_iso_datetime(d.get("modified")),
            orphaned=d.get("orphaned")
        )

@dataclass
class TrashEntry:
    id: uuid.UUID
    folder: str
    snippet: str
    color: NoteColor
    deletedAt: datetime

    def to_dict(self):
        return {
            "id": str(self.id),
            "folder": self.folder,
            "snippet": self.snippet,
            "color": self.color.value,
            "deletedAt": format_iso_datetime(self.deletedAt)
        }

    @classmethod
    def from_dict(cls, d: dict) -> "TrashEntry":
        nid = uuid.UUID(d["id"]) if isinstance(d.get("id"), str) else d["id"]
        color_val = d.get("color", "yellow")
        try:
            color = NoteColor(color_val)
        except ValueError:
            color = NoteColor.yellow
        return cls(
            id=nid,
            folder=d.get("folder", ""),
            snippet=d.get("snippet", ""),
            color=color,
            deletedAt=parse_iso_datetime(d.get("deletedAt"))
        )

def parse_iso_datetime(s: Optional[str]) -> datetime:
    if not s:
        return datetime.utcnow()
    # Normalize Z to +00:00 for fromisoformat in older python versions
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
        # Convert to naive UTC datetime if timezone-aware
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except ValueError:
        return datetime.utcnow()

def format_iso_datetime(dt: datetime) -> str:
    # Ensure it ends with Z to represent UTC/Zulu time standardly
    s = dt.isoformat()
    if "+" in s:
        # If it has offset, keep it, but if it is +00:00, replace with Z
        if s.endswith("+00:00"):
            s = s[:-6] + "Z"
    else:
        s += "Z"
    return s
