use std::{collections::BTreeSet, path::Path};

use anyhow::{Context as _, Result};
use chrono::Utc;

use super::{
    markdown::{self, IdentityManifest},
    planner::{self, ChangePlan, Reconciliation, TaskChange},
    transaction,
};
use crate::{
    config::Config,
    model::{EditedTaskState, TaskId, TaskState},
    repository::{self, Scope, SourceSnapshot},
    view::View,
};

pub struct Context<'a> {
    pub root: &'a Path,
    pub config: &'a Config,
    pub lists: &'a [String],
    pub scope: Scope,
    pub view: &'a View,
    pub baseline: &'a TaskState,
    pub recovery_baseline: &'a TaskState,
    pub manifest: &'a IdentityManifest,
}

pub enum Prepared {
    NoChange {
        baseline: TaskState,
        recovery: TaskState,
    },
    Inbound {
        current: TaskState,
        recovery: TaskState,
    },
    Outgoing(Outgoing),
    Conflict,
}

pub struct Outgoing {
    pub plan: ChangePlan,
    sources: SourceSnapshot,
    retained_tasks: BTreeSet<TaskId>,
}

pub struct Applied {
    pub state: TaskState,
    pub recovery: TaskState,
    pub retained_tasks: BTreeSet<TaskId>,
}

pub fn validate(context: &Context<'_>, text: &str) -> Result<()> {
    let edited = parse(context, text)?;
    let (baseline, _) = reconciliation_baseline(context, &edited);
    planner::reconcile(&baseline, &edited, &baseline)?;
    Ok(())
}

pub fn prepare(
    context: &Context<'_>,
    text: &str,
    retained_tasks: &BTreeSet<TaskId>,
) -> Result<Prepared> {
    let edited = parse(context, text)?;
    let (baseline, mut required_tasks) = reconciliation_baseline(context, &edited);
    required_tasks.extend(completed_roots(context));
    required_tasks.extend(retained_tasks.iter().cloned());
    let (current, sources, recovery) = load_current(context, &required_tasks)?;

    Ok(match planner::reconcile(&baseline, &edited, &current)? {
        Reconciliation::NoChange => Prepared::NoChange { baseline, recovery },
        Reconciliation::Inbound => Prepared::Inbound { current, recovery },
        Reconciliation::Outgoing(plan) => Prepared::Outgoing(Outgoing {
            plan,
            sources,
            retained_tasks: required_tasks,
        }),
        Reconciliation::Conflict => Prepared::Conflict,
    })
}

pub fn apply(context: &Context<'_>, mut outgoing: Outgoing) -> Result<Applied> {
    for change in &outgoing.plan.changes {
        if let TaskChange::Update { id, before, after } = change
            && !before.completed
            && after.completed
        {
            outgoing.retained_tasks.insert(id.clone());
        }
    }

    let staged = transaction::stage(&outgoing.plan, &outgoing.sources, context.root, Utc::now())?;
    transaction::apply(&staged, &outgoing.sources)?;
    let (state, accepted_sources, recovery) = load_current(context, &outgoing.retained_tasks)
        .context("source changes were applied, but the accepted state could not be read")?;
    transaction::verify_applied(&staged, &outgoing.sources, &accepted_sources)
        .context("source changes were applied, but concurrent changes prevented acceptance")?;

    Ok(Applied {
        state,
        recovery,
        retained_tasks: outgoing.retained_tasks,
    })
}

fn parse(context: &Context<'_>, text: &str) -> Result<EditedTaskState> {
    markdown::parse_with_view(text, context.baseline, context.manifest, context.view)
}

fn reconciliation_baseline(
    context: &Context<'_>,
    edited: &EditedTaskState,
) -> (TaskState, BTreeSet<TaskId>) {
    let required_tasks = identities_outside(edited, context.baseline);
    let mut baseline = context.baseline.clone();
    add_tasks(&mut baseline, context.recovery_baseline, &required_tasks);
    (baseline, required_tasks)
}

fn completed_roots(context: &Context<'_>) -> BTreeSet<TaskId> {
    if context.scope == Scope::All {
        return BTreeSet::new();
    }
    context
        .baseline
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .filter(|task| task.completed && task.parent.is_none())
        .map(|task| task.id.clone())
        .collect()
}

fn load_current(
    context: &Context<'_>,
    required_tasks: &BTreeSet<TaskId>,
) -> Result<(TaskState, SourceSnapshot, TaskState)> {
    let (mut current, sources, recovery) = repository::load_lists_for_reconciliation(
        context.config,
        context.lists,
        context.scope,
        required_tasks,
    )?;
    if context.scope != Scope::All {
        add_tasks(&mut current, &recovery, required_tasks);
    }
    Ok((current, sources, recovery))
}

fn identities_outside(edited: &EditedTaskState, baseline: &TaskState) -> BTreeSet<TaskId> {
    let baseline_ids = baseline
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .map(|task| &task.id)
        .collect::<BTreeSet<_>>();
    edited
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .filter_map(|task| task.id.as_ref())
        .filter(|id| !baseline_ids.contains(id))
        .cloned()
        .collect()
}

fn add_tasks(target: &mut TaskState, source: &TaskState, ids: &BTreeSet<TaskId>) {
    for source_list in &source.lists {
        let Some(target_list) = target
            .lists
            .iter_mut()
            .find(|list| list.name == source_list.name)
        else {
            continue;
        };
        for task in &source_list.tasks {
            if ids.contains(&task.id) && !target_list.tasks.iter().any(|item| item.id == task.id) {
                target_list.tasks.push(task.clone());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{fs, path::PathBuf};

    use tempfile::TempDir;

    use super::*;
    use crate::edit::{
        SessionOptions, create_session,
        session::{self, LoadedSession, Session},
    };

    struct Fixture {
        _directory: TempDir,
        list: PathBuf,
        _session: Session,
        loaded: LoadedSession,
    }

    impl Fixture {
        fn new(scope: Scope) -> Self {
            let directory = tempfile::tempdir().unwrap();
            let list = directory.path().join("work");
            fs::create_dir(&list).unwrap();
            fs::write(list.join("displayname"), "Work\n").unwrap();
            for (id, summary, completed, parent) in [
                ("active", "Active", false, None),
                ("done", "Done", true, None),
                ("hidden", "Hidden child", false, Some("done")),
            ] {
                write_task(&list, id, summary, completed, parent);
            }
            let config = Config::new(vec![directory.path().to_path_buf()]).unwrap();
            let created = create_session(
                &config,
                &["Work".to_owned()],
                SessionOptions {
                    scope,
                    ..SessionOptions::default()
                },
            )
            .unwrap();
            let loaded = session::load(created.session.path()).unwrap();
            Self {
                _directory: directory,
                list,
                _session: created.session,
                loaded,
            }
        }

        fn context(&self) -> Context<'_> {
            Context {
                root: &self.loaded.root,
                config: &self.loaded.metadata.config,
                lists: &self.loaded.metadata.lists,
                scope: self.loaded.metadata.scope,
                view: &self.loaded.metadata.view,
                baseline: &self.loaded.baseline,
                recovery_baseline: &self.loaded.recovery_baseline,
                manifest: &self.loaded.manifest,
            }
        }

        fn accept(&mut self, applied: &Applied) {
            let accepted = session::render_accepted(
                &self.loaded.metadata.view,
                &self.loaded.manifest,
                applied.state.clone(),
                applied.recovery.clone(),
            )
            .unwrap();
            self.loaded.baseline = accepted.baseline;
            self.loaded.recovery_baseline = accepted.recovery_baseline;
            self.loaded.manifest = accepted.manifest;
            self.loaded.accepted_text = accepted.text;
        }
    }

    fn write_task(list: &Path, id: &str, summary: &str, completed: bool, parent: Option<&str>) {
        let status = if completed {
            "STATUS:COMPLETED\r\n"
        } else {
            ""
        };
        let parent = parent.map_or(String::new(), |parent| format!("RELATED-TO:{parent}\r\n"));
        fs::write(list.join(format!("{id}.ics")), format!(
            "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:{id}\r\nSUMMARY:{summary}\r\n{status}{parent}END:VTODO\r\nEND:VCALENDAR\r\n"
        )).unwrap();
    }

    fn assert_task(state: &TaskState, id: &str, summary: &str, completed: bool) {
        let task = state
            .lists
            .iter()
            .flat_map(|list| &list.tasks)
            .find(|task| task.id.as_str() == id)
            .unwrap();
        assert_eq!(task.summary, summary);
        assert_eq!(task.completed, completed);
    }

    #[test]
    fn no_change_prepares_recovery_in_one_source_scan_in_both_scopes() {
        for scope in [Scope::Active, Scope::All] {
            let fixture = Fixture::new(scope);
            let before = repository::source_read_count();
            let Prepared::NoChange { baseline, recovery } = prepare(
                &fixture.context(),
                &fixture.loaded.accepted_text,
                &BTreeSet::new(),
            )
            .unwrap() else {
                panic!("expected no change");
            };
            assert_eq!(repository::source_read_count() - before, 3);
            assert_eq!(baseline, fixture.loaded.baseline);
            assert_eq!(recovery, fixture.loaded.recovery_baseline);
            assert_task(&recovery, "done", "Done", true);
            assert_task(&recovery, "hidden", "Hidden child", false);
        }
    }

    #[test]
    fn inbound_carries_current_and_recovery_from_the_same_source_scan() {
        for scope in [Scope::Active, Scope::All] {
            let fixture = Fixture::new(scope);
            write_task(&fixture.list, "active", "Inbound active", false, None);
            write_task(
                &fixture.list,
                "hidden",
                "Inbound hidden",
                false,
                Some("done"),
            );
            let before = repository::source_read_count();
            let Prepared::Inbound { current, recovery } = prepare(
                &fixture.context(),
                &fixture.loaded.accepted_text,
                &BTreeSet::new(),
            )
            .unwrap() else {
                panic!("expected inbound change");
            };
            assert_eq!(repository::source_read_count() - before, 3);
            assert_task(&current, "active", "Inbound active", false);
            assert_task(&recovery, "active", "Inbound active", false);
            assert_task(&recovery, "hidden", "Inbound hidden", false);

            // Acceptance must use the recovery already paired with current,
            // not pick up a later source revision through another read.
            write_task(&fixture.list, "active", "Later active", false, None);
            write_task(&fixture.list, "hidden", "Later hidden", false, Some("done"));
            let accepted = session::render_accepted(
                &fixture.loaded.metadata.view,
                &fixture.loaded.manifest,
                current,
                recovery,
            )
            .unwrap();
            assert_task(&accepted.baseline, "active", "Inbound active", false);
            assert_task(
                &accepted.recovery_baseline,
                "active",
                "Inbound active",
                false,
            );
            assert_task(
                &accepted.recovery_baseline,
                "hidden",
                "Inbound hidden",
                false,
            );
            assert_eq!(repository::source_read_count() - before, 3);
        }
    }

    #[test]
    fn outgoing_reads_once_per_phase_and_keeps_retained_task_source_mappings() {
        for scope in [Scope::Active, Scope::All] {
            let mut fixture = Fixture::new(scope);
            let untouched = ["done", "hidden"].map(|id| {
                (
                    fixture.list.join(format!("{id}.ics")),
                    fs::read(fixture.list.join(format!("{id}.ics"))).unwrap(),
                )
            });
            let completed = fixture
                .loaded
                .accepted_text
                .replace("- [ ] Active", "- [x] Active");
            assert_ne!(completed, fixture.loaded.accepted_text);
            let before = repository::source_read_count();
            let Prepared::Outgoing(outgoing) =
                prepare(&fixture.context(), &completed, &BTreeSet::new()).unwrap()
            else {
                panic!("expected outgoing completion");
            };
            assert_eq!(repository::source_read_count() - before, 3);
            let applied = apply(&fixture.context(), outgoing).unwrap();
            assert_eq!(repository::source_read_count() - before, 6);
            assert_task(&applied.state, "active", "Active", true);
            assert_task(&applied.recovery, "active", "Active", true);
            assert_task(&applied.recovery, "hidden", "Hidden child", false);
            assert!(applied.retained_tasks.contains(&TaskId::new("active")));
            fixture.accept(&applied);

            // The completed root is outside the active projection on disk, but
            // remains editable in this session and must still resolve to its file.
            let edited = fixture
                .loaded
                .accepted_text
                .replace("Active", "Edited completed root");
            let before = repository::source_read_count();
            let Prepared::Outgoing(outgoing) =
                prepare(&fixture.context(), &edited, &applied.retained_tasks).unwrap()
            else {
                panic!("expected outgoing retained-task edit");
            };
            assert_eq!(repository::source_read_count() - before, 3);
            assert_eq!(
                outgoing.sources.task_files.get(&TaskId::new("active")),
                Some(&fixture.list.join("active.ics"))
            );
            let applied = apply(&fixture.context(), outgoing).unwrap();
            assert_eq!(repository::source_read_count() - before, 6);
            assert_task(&applied.state, "active", "Edited completed root", true);
            assert_task(&applied.recovery, "active", "Edited completed root", true);
            for (path, bytes) in untouched {
                assert_eq!(fs::read(path).unwrap(), bytes);
            }

            fixture.accept(&applied);
            let before = repository::source_read_count();
            let Prepared::NoChange { baseline, recovery } = prepare(
                &fixture.context(),
                &fixture.loaded.accepted_text,
                &applied.retained_tasks,
            )
            .unwrap() else {
                panic!("expected no change with a retained completed root");
            };
            assert_eq!(repository::source_read_count() - before, 3);
            assert_task(&baseline, "active", "Edited completed root", true);
            assert_task(&recovery, "active", "Edited completed root", true);
        }
    }
}
