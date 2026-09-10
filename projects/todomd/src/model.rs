use serde::{Deserialize, Serialize};

use crate::dates::DateValue;

#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub struct TaskId(String);

impl TaskId {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Priority as the Markdown dialect exposes it. iCalendar allows 1-9, which
/// buckets into these three levels plus "unset".
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Priority {
    #[default]
    None,
    Low,
    Medium,
    High,
}

impl Priority {
    /// Buckets an iCalendar `PRIORITY` value. Out-of-range and unparseable
    /// values read as unset; they are only rewritten if the marker changes.
    pub fn from_ics(value: &str) -> Self {
        match value.trim().parse::<u8>() {
            Ok(1..=4) => Self::High,
            Ok(5) => Self::Medium,
            Ok(6..=9) => Self::Low,
            _ => Self::None,
        }
    }

    /// The canonical iCalendar value, or `None` when the property is dropped.
    pub fn to_ics(self) -> Option<&'static str> {
        match self {
            Self::None => Option::None,
            Self::Low => Some("9"),
            Self::Medium => Some("5"),
            Self::High => Some("1"),
        }
    }

    pub fn marker(self) -> &'static str {
        match self {
            Self::None => "",
            Self::Low => "!",
            Self::Medium => "!!",
            Self::High => "!!!",
        }
    }

    pub fn from_marker(marker: &str) -> Option<Self> {
        match marker {
            "" => Some(Self::None),
            "!" => Some(Self::Low),
            "!!" => Some(Self::Medium),
            "!!!" => Some(Self::High),
            _ => Option::None,
        }
    }

    /// How the change preview names the level.
    pub fn label(self) -> &'static str {
        match self {
            Self::None => "none",
            _ => self.marker(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Task {
    pub id: TaskId,
    pub summary: String,
    pub completed: bool,
    #[serde(default)]
    pub priority: Priority,
    /// The canonical category set, sorted and deduplicated.
    #[serde(default)]
    pub categories: Vec<String>,
    /// The renderable parent. Empty, dangling, and hidden source relationships
    /// are normalized to `None` and preserved unless indentation changes.
    #[serde(default)]
    pub parent: Option<TaskId>,
    #[serde(default)]
    pub start: Option<DateValue>,
    #[serde(default)]
    pub due: Option<DateValue>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TaskList {
    pub name: String,
    pub tasks: Vec<Task>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct TaskState {
    pub lists: Vec<TaskList>,
}

/// A parent named by an existing VTODO UID or by a new task's session-local
/// draft identity.
#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub enum TaskReference {
    Existing(TaskId),
    Draft(usize),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EditedTask {
    pub id: Option<TaskId>,
    pub summary: String,
    pub completed: bool,
    pub priority: Priority,
    pub categories: Vec<String>,
    pub parent: Option<TaskReference>,
    pub start: Option<DateValue>,
    pub due: Option<DateValue>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EditedTaskList {
    pub name: String,
    pub tasks: Vec<EditedTask>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EditedTaskState {
    pub lists: Vec<EditedTaskList>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buckets_every_icalendar_priority() {
        // The values that actually occur in real vdirs, plus junk.
        assert_eq!(Priority::from_ics("1"), Priority::High);
        assert_eq!(Priority::from_ics("2"), Priority::High);
        assert_eq!(Priority::from_ics("3"), Priority::High);
        assert_eq!(Priority::from_ics("4"), Priority::High);
        assert_eq!(Priority::from_ics("5"), Priority::Medium);
        assert_eq!(Priority::from_ics("8"), Priority::Low);
        assert_eq!(Priority::from_ics("9"), Priority::Low);
        assert_eq!(Priority::from_ics("0"), Priority::None);
        assert_eq!(Priority::from_ics("nonsense"), Priority::None);
    }

    #[test]
    fn round_trips_markers() {
        for priority in [
            Priority::None,
            Priority::Low,
            Priority::Medium,
            Priority::High,
        ] {
            assert_eq!(Priority::from_marker(priority.marker()), Some(priority));
        }
        assert_eq!(Priority::from_marker("!!!!"), None);
    }

    #[test]
    fn writes_canonical_values() {
        assert_eq!(Priority::High.to_ics(), Some("1"));
        assert_eq!(Priority::Medium.to_ics(), Some("5"));
        assert_eq!(Priority::Low.to_ics(), Some("9"));
        assert_eq!(Priority::None.to_ics(), None);
    }
}
