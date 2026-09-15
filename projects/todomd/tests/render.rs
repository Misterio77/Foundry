use std::path::PathBuf;

use todomd::{config::Config, edit::render_lists, repository::Scope};

#[test]
fn renders_requested_lists_in_order() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/calendars");
    let config = Config::new(vec![root]).unwrap();
    let requested = vec!["Postgrad".to_owned(), "Personal".to_owned()];

    let rendered = render_lists(&config, &requested, Scope::Active).unwrap();

    assert_eq!(
        rendered.markdown,
        "# Postgrad\n\n\
- [ ] -2026-09-10 Write paper draft <!--t1-->\n\
\n\
# Personal\n\n\
- [ ] Buy milk, bread <!--t2-->\n"
    );
    assert_eq!(rendered.sources.files.len(), 5);
    assert_eq!(rendered.sources.task_files.len(), 2);
    assert!(
        rendered
            .sources
            .files
            .values()
            .all(|source| source.sha256 != [0; 32])
    );
    assert!(
        rendered
            .sources
            .files
            .values()
            .any(|source| source.list_name == "Postgrad")
    );
}

#[test]
fn reports_missing_lists() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/calendars");
    let config = Config::new(vec![root]).unwrap();

    let error = render_lists(&config, &["Missing".to_owned()], Scope::Active).unwrap_err();

    assert!(error.to_string().contains("was not found"));
}
