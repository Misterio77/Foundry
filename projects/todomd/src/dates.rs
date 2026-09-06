use std::str::FromStr;

use anyhow::{Context, Result, bail};
use chrono::{
    DateTime, NaiveDate, NaiveDateTime, NaiveTime, Timelike, Utc,
    offset::{LocalResult, TimeZone},
};
use chrono_english::{Dialect, parse_date_string};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ZonedDateTime {
    instant: DateTime<Utc>,
    timezone: Tz,
}

impl ZonedDateTime {
    fn local(&self) -> DateTime<Tz> {
        self.instant.with_timezone(&self.timezone)
    }

    pub fn timezone(&self) -> Tz {
        self.timezone
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub enum DateValue {
    Date(NaiveDate),
    DateTime(ZonedDateTime),
}

impl DateValue {
    pub fn canonical(&self) -> String {
        match self {
            Self::Date(date) => date.format("%Y-%m-%d").to_string(),
            Self::DateTime(date_time) => date_time.local().format("%Y-%m-%d %H:%M").to_string(),
        }
    }

    pub fn marker(&self) -> String {
        match self {
            Self::Date(_) => self.canonical(),
            Self::DateTime(_) => format!("\"{}\"", self.canonical()),
        }
    }

    fn promote_to_datetime(&self, timezone: Tz) -> Result<Self> {
        match self {
            Self::Date(date) => {
                resolve_in_timezone(date.and_time(NaiveTime::MIN), timezone).map(Self::DateTime)
            }
            Self::DateTime(date_time) => Ok(Self::DateTime(date_time.clone())),
        }
    }

    fn as_comparable_datetime(&self, timezone: Tz) -> Result<DateTime<Utc>> {
        match self {
            Self::Date(date) => resolve_in_timezone(date.and_time(NaiveTime::MIN), timezone)
                .map(|value| value.instant),
            Self::DateTime(date_time) => Ok(date_time.instant),
        }
    }

    pub fn is_date(&self) -> bool {
        matches!(self, Self::Date(_))
    }

    pub fn ics_value(&self) -> String {
        match self {
            Self::Date(date) => date.format("%Y%m%d").to_string(),
            Self::DateTime(date_time) => date_time.local().format("%Y%m%dT%H%M%S").to_string(),
        }
    }

    pub fn timezone(&self) -> Option<Tz> {
        match self {
            Self::Date(_) => None,
            Self::DateTime(value) => Some(value.timezone()),
        }
    }
}

// Markdown exposes datetimes only to minute precision. Comparing the rendered
// form prevents unrelated edits from flattening source seconds or timezone
// representations that the dialect cannot express.
impl PartialEq for DateValue {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Date(left), Self::Date(right)) => left == right,
            (Self::DateTime(left), Self::DateTime(right)) => {
                let left = left.local();
                let right = right.local();
                left.date_naive() == right.date_naive()
                    && left.hour() == right.hour()
                    && left.minute() == right.minute()
            }
            _ => false,
        }
    }
}

impl Eq for DateValue {}

#[derive(Clone, Debug)]
pub struct DateContext {
    timezone_name: String,
    timezone: Tz,
    now: DateTime<Tz>,
}

impl DateContext {
    pub fn local_now() -> Result<Self> {
        Self::at(Utc::now())
    }

    pub fn at(now: DateTime<Utc>) -> Result<Self> {
        let timezone_name = iana_time_zone::get_timezone()
            .or_else(|_| std::env::var("TZ"))
            .context("failed to determine the local IANA timezone")?;
        Self::in_timezone(&timezone_name, now)
    }

    pub fn in_timezone(timezone_name: &str, now: DateTime<Utc>) -> Result<Self> {
        let timezone = Tz::from_str(timezone_name)
            .with_context(|| format!("unsupported IANA timezone {timezone_name:?}"))?;
        Ok(Self {
            timezone_name: timezone_name.to_owned(),
            timezone,
            now: now.with_timezone(&timezone),
        })
    }

    pub fn timezone_name(&self) -> &str {
        &self.timezone_name
    }

    pub fn timezone(&self) -> Tz {
        self.timezone
    }

    fn resolve_local(&self, local: NaiveDateTime) -> Result<ZonedDateTime> {
        resolve_in_timezone(local, self.timezone)
    }
}

fn resolve_in_timezone(local: NaiveDateTime, timezone: Tz) -> Result<ZonedDateTime> {
    match timezone.from_local_datetime(&local) {
        LocalResult::Single(value) => Ok(ZonedDateTime {
            instant: value.with_timezone(&Utc),
            timezone,
        }),
        // RFC 5545 resolves a repeated wall time to its first occurrence.
        LocalResult::Ambiguous(first, _) => Ok(ZonedDateTime {
            instant: first.with_timezone(&Utc),
            timezone,
        }),
        LocalResult::None => {
            bail!("local datetime {local} does not exist in {timezone}")
        }
    }
}

pub fn parse_markdown(input: &str) -> Result<DateValue> {
    parse_markdown_at(input, &DateContext::local_now()?)
}

pub fn parse_markdown_at(input: &str, context: &DateContext) -> Result<DateValue> {
    if input.contains('/') {
        bail!("slash-separated dates are ambiguous; use YYYY-MM-DD");
    }
    if let Ok(date) = NaiveDate::parse_from_str(input, "%Y-%m-%d") {
        return Ok(DateValue::Date(date));
    }

    for format in ["%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S"] {
        if let Ok(local) = NaiveDateTime::parse_from_str(input, format) {
            return context.resolve_local(local).map(DateValue::DateTime);
        }
    }

    if let Ok(date_time) = DateTime::parse_from_rfc3339(input) {
        if date_time.nanosecond() != 0 {
            bail!("fractional seconds cannot be represented by iCalendar DATE-TIME");
        }
        let instant = date_time.with_timezone(&Utc);
        let normalized =
            context.resolve_local(instant.with_timezone(&context.timezone).naive_local())?;
        if normalized.instant != instant {
            bail!(
                "timestamp selects the second occurrence of an ambiguous local datetime, which iCalendar TZID cannot represent"
            );
        }
        return Ok(DateValue::DateTime(normalized));
    }

    for format in ["%Y-%m-%dT%H:%M", "%Y-%m-%dT%H:%M:%S"] {
        if let Ok(local) = NaiveDateTime::parse_from_str(input, format) {
            return context.resolve_local(local).map(DateValue::DateTime);
        }
    }

    let midnight = context
        .timezone
        .from_local_datetime(&context.now.date_naive().and_time(NaiveTime::MIN))
        .single()
        .context("local midnight is ambiguous or nonexistent")?;
    if let Some((date_expression, time)) = part_of_day(input) {
        let date = parse_date_string(&date_expression, midnight, Dialect::Uk)
            .with_context(|| format!("invalid date expression {input:?}"))?
            .date_naive();
        return context
            .resolve_local(date.and_time(time))
            .map(DateValue::DateTime);
    }

    let has_time = has_explicit_time(input);
    let base = if has_time { context.now } else { midnight };
    let parsed = parse_date_string(input, base, Dialect::Uk)
        .with_context(|| format!("invalid date expression {input:?}"))?;
    if parsed.nanosecond() != 0 {
        bail!("fractional seconds cannot be represented by iCalendar DATE-TIME");
    }
    if has_time {
        Ok(DateValue::DateTime(ZonedDateTime {
            instant: parsed.with_timezone(&Utc),
            timezone: context.timezone,
        }))
    } else {
        Ok(DateValue::Date(parsed.date_naive()))
    }
}

fn part_of_day(input: &str) -> Option<(String, NaiveTime)> {
    let lower = input.to_lowercase();
    for (word, hour) in [
        ("morning", 9),
        ("noon", 12),
        ("afternoon", 15),
        ("evening", 18),
        ("tonight", 20),
        ("midnight", 0),
    ] {
        if lower == word {
            return Some(("today".to_owned(), NaiveTime::from_hms_opt(hour, 0, 0)?));
        }
        if let Some(prefix) = lower.strip_suffix(&format!(" {word}")) {
            return Some((prefix.to_owned(), NaiveTime::from_hms_opt(hour, 0, 0)?));
        }
    }
    None
}

fn has_explicit_time(input: &str) -> bool {
    let lower = input.to_lowercase();
    lower.contains(':')
        || lower.split_whitespace().any(|word| {
            word.strip_suffix("am")
                .or_else(|| word.strip_suffix("pm"))
                .is_some_and(|hour| hour.parse::<u8>().is_ok())
        })
        || lower == "now"
}

pub fn parse_ics(
    value: &str,
    value_type: Option<&str>,
    timezone_id: Option<&str>,
    local: &DateContext,
) -> Result<DateValue> {
    if value_type.is_some_and(|kind| kind.eq_ignore_ascii_case("DATE"))
        || (value_type.is_none()
            && value.len() == 8
            && value.bytes().all(|byte| byte.is_ascii_digit()))
    {
        return NaiveDate::parse_from_str(value, "%Y%m%d")
            .map(DateValue::Date)
            .context("invalid iCalendar DATE value");
    }

    if value.contains('.') {
        bail!("fractional iCalendar DATE-TIME values are unsupported");
    }
    let utc = value.strip_suffix('Z');
    let naive_value = utc.unwrap_or(value);
    let naive = ["%Y%m%dT%H%M%S", "%Y%m%dT%H%M"]
        .iter()
        .find_map(|format| NaiveDateTime::parse_from_str(naive_value, format).ok())
        .context("invalid iCalendar DATE-TIME value")?;

    let instant = if utc.is_some() {
        Utc.from_utc_datetime(&naive)
    } else if let Some(timezone_id) = timezone_id {
        let timezone = Tz::from_str(timezone_id)
            .with_context(|| format!("unsupported iCalendar TZID {timezone_id:?}"))?;
        resolve_in_timezone(naive, timezone)?.instant
    } else {
        local.resolve_local(naive)?.instant
    };
    let normalized = local.resolve_local(instant.with_timezone(&local.timezone).naive_local())?;
    if normalized.instant != instant {
        bail!("iCalendar timestamp selects the second occurrence of an ambiguous local datetime");
    }
    Ok(normalized.into())
}

impl From<ZonedDateTime> for DateValue {
    fn from(value: ZonedDateTime) -> Self {
        Self::DateTime(value)
    }
}

pub fn normalize_and_validate(
    start: &mut Option<DateValue>,
    due: &mut Option<DateValue>,
) -> Result<()> {
    if start.as_ref().is_some_and(DateValue::is_date)
        != due.as_ref().is_some_and(DateValue::is_date)
        && start.is_some()
        && due.is_some()
    {
        let timezone = start
            .as_ref()
            .and_then(DateValue::timezone)
            .or_else(|| due.as_ref().and_then(DateValue::timezone))
            .context("mixed date values have no timezone")?;
        if let Some(value) = start {
            *value = value.promote_to_datetime(timezone)?;
        }
        if let Some(value) = due {
            *value = value.promote_to_datetime(timezone)?;
        }
    }

    if let (Some(start), Some(due)) = (start, due) {
        let timezone = start
            .timezone()
            .or_else(|| due.timezone())
            .unwrap_or(chrono_tz::UTC);
        if due.as_comparable_datetime(timezone)? < start.as_comparable_datetime(timezone)? {
            bail!("task due date must not be earlier than its start date");
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use super::*;

    fn context() -> DateContext {
        DateContext::in_timezone(
            "America/Sao_Paulo",
            Utc.with_ymd_and_hms(2026, 9, 7, 15, 30, 0).unwrap(),
        )
        .unwrap()
    }

    #[test]
    fn canonicalizes_dates_and_datetimes() {
        assert_eq!(
            parse_markdown_at("2026-09-07", &context())
                .unwrap()
                .marker(),
            "2026-09-07"
        );
        assert_eq!(
            parse_markdown_at("2026-09-07 20:15", &context())
                .unwrap()
                .marker(),
            "\"2026-09-07 20:15\""
        );
    }

    #[test]
    fn converts_offset_timestamps_to_local_time_and_keeps_seconds() {
        let parsed = parse_markdown_at("2026-09-07T10:00:42+01:00", &context()).unwrap();

        assert_eq!(parsed.canonical(), "2026-09-07 06:00");
        assert_eq!(parsed.ics_value(), "20260907T060042");
    }

    #[test]
    fn parses_humanized_dates_with_same_weekday_meaning_today() {
        assert_eq!(
            parse_markdown_at("monday", &context()).unwrap().canonical(),
            "2026-09-07"
        );
        assert_eq!(
            parse_markdown_at("tomorrow morning", &context())
                .unwrap()
                .canonical(),
            "2026-09-08 09:00"
        );
        assert_eq!(
            parse_markdown_at("tonight", &context())
                .unwrap()
                .canonical(),
            "2026-09-07 20:00"
        );
    }

    #[test]
    fn rejects_fractional_seconds() {
        let error = parse_markdown_at("2026-09-07T10:00:42.5-03:00", &context()).unwrap_err();
        assert!(error.to_string().contains("fractional seconds"));
    }

    #[test]
    fn follows_icalendar_rules_for_ambiguous_local_datetimes() {
        let context = DateContext::in_timezone(
            "America/New_York",
            Utc.with_ymd_and_hms(2026, 1, 1, 12, 0, 0).unwrap(),
        )
        .unwrap();

        assert!(parse_markdown_at("2026-11-01 01:30", &context).is_ok());
        assert!(parse_markdown_at("2026-03-08 02:30", &context).is_err());
        assert!(parse_markdown_at("2026-11-01T01:30:00-04:00", &context).is_ok());
        assert!(parse_markdown_at("2026-11-01T01:30:00-05:00", &context).is_err());
    }

    #[test]
    fn parses_ics_timezones_and_floating_values() {
        let local = context();
        assert_eq!(
            parse_ics("20260907T100000", None, Some("Europe/London"), &local)
                .unwrap()
                .canonical(),
            "2026-09-07 06:00"
        );
        assert_eq!(
            parse_ics("20260907T100000", None, None, &local)
                .unwrap()
                .canonical(),
            "2026-09-07 10:00"
        );
    }

    #[test]
    fn rejects_fractional_ics_datetimes() {
        assert!(
            parse_ics(
                "20260907T100042.5",
                None,
                Some("America/Sao_Paulo"),
                &context()
            )
            .is_err()
        );
    }

    #[test]
    fn promotes_mixed_values_and_rejects_only_inversion() {
        let mut start = Some(DateValue::Date(
            NaiveDate::from_ymd_opt(2026, 9, 7).unwrap(),
        ));
        let mut due = Some(
            context()
                .resolve_local(
                    NaiveDate::from_ymd_opt(2026, 9, 7)
                        .unwrap()
                        .and_hms_opt(0, 0, 0)
                        .unwrap(),
                )
                .map(DateValue::DateTime)
                .unwrap(),
        );
        normalize_and_validate(&mut start, &mut due).unwrap();
        assert!(matches!(start, Some(DateValue::DateTime(_))));

        due = Some(
            context()
                .resolve_local(
                    NaiveDate::from_ymd_opt(2026, 9, 6)
                        .unwrap()
                        .and_hms_opt(23, 59, 0)
                        .unwrap(),
                )
                .map(DateValue::DateTime)
                .unwrap(),
        );
        assert!(normalize_and_validate(&mut start, &mut due).is_err());
    }
}
