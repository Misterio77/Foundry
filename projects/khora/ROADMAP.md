# Khora roadmap

Planned improvements, ordered roughly from least to most implementation complexity.
The order reflects engineering dependencies rather than product priority.

1. **Event details — done.** Open an event from any view and show its complete
   time, calendar, location, description, URL, organizer, and attendees.
2. **Keyboard navigation — done.** Previous/next period, Today, view switching,
   refresh, and zoom shortcuts.
3. **Session persistence — done.** Remember the selected view, zoom, sidebar
   width, collapsed accounts, and visible calendars across restarts.
4. **Filesystem monitoring — done.** Refresh when local vdir files change,
   without requiring the toolbar refresh button.
5. **Forward agenda — done.** A lazily loaded, continuously scrolling agenda
   starts at the selected date.
6. **Overlapping event layout — done.** Simultaneous timed events occupy
   adjacent lanes instead of drawing on top of each other.
7. **Mini-calendar indicators — done.** A custom sidebar month widget shows up
   to three calendar-colored event dots on each visible date.
8. **Month view** — build a full month grid with compact event chips, overflow
   counts, and navigation consistent with the day and week grids.
9. **Search** — search expanded local occurrences and jump from results to the
   relevant date or event.
10. **Event creation** — create timed and all-day events in writable calendars,
    including basic recurrence and reminders.
11. **Event editing and deletion** — update or remove existing events while
    handling recurring-event scope safely.
12. **Drag, drop, and resize** — move events between times and calendars and
    resize their duration directly in day/week views.
13. **Advanced recurrence editor** — expose richer RFC 5545 recurrence rules,
    exceptions, and occurrence-level changes.
14. **Optional synchronization actions** — run vdirsyncer explicitly and show
    progress/errors without making network synchronization Khora's default job.
