use serde::{Deserialize, Serialize};

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

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Task {
    pub id: TaskId,
    pub summary: String,
    pub completed: bool,
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EditedTask {
    pub id: Option<TaskId>,
    pub summary: String,
    pub completed: bool,
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
