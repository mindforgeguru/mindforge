/// The school's calendar and clock (IST, UTC+5:30), whatever the phone's
/// timezone is.
///
/// Dashboards asked the server for "today" by the phone's own date. For a
/// parent abroad (8 PM in New York is already the next morning in India) that
/// showed yesterday's timetable and homework as today's. The server answers in
/// school time (backend `school_time.py`), so the app must ask in school time
/// too. There is no per-school timezone yet; when one is added, thread it
/// through here and in the backend helper.
library;

const Duration _schoolOffset = Duration(hours: 5, minutes: 30);

/// The current school wall-clock time, as a plain DateTime whose
/// year/month/day/hour/minute are IST. Use it for "what day / which period is
/// it at school", not for measuring elapsed time.
DateTime schoolNow() {
  final t = DateTime.now().toUtc().add(_schoolOffset);
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second,
      t.millisecond);
}

/// How long until one minute past the next school midnight, computed in UTC so
/// the phone's own DST changes can't skew it.
Duration untilNextSchoolDay() {
  final nowUtc = DateTime.now().toUtc();
  final s = nowUtc.add(_schoolOffset);
  final nextUtc =
      DateTime.utc(s.year, s.month, s.day + 1, 0, 1).subtract(_schoolOffset);
  return nextUtc.difference(nowUtc);
}
