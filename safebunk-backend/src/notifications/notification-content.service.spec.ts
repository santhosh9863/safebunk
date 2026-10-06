import { NotificationContentService } from './notification-content.service';
import { NotificationEventPayload } from './notification-events';
import { NotificationPreferencesDto } from './dto/notification-preferences.dto';

describe('NotificationContentService — gender-aware variants', () => {
  const service = new NotificationContentService();
  const prefs = (gender: string): NotificationPreferencesDto => ({ gender: gender as never });

  const build = (type: string, gender: string, percentage?: number) =>
    service.build(
      { type: type as NotificationEventPayload['type'], percentage } as NotificationEventPayload,
      prefs(gender),
    );

  it('Sunday chill addresses the student per gender', () => {
    expect(build('sundayChill', 'male').title).toBe('It\'s Sunday. Rest, king. 👑');
    expect(build('sundayChill', 'female').title).toBe('It\'s Sunday. Rest, queen. 👑');
    expect(build('sundayChill', '').title).toBe('It\'s Sunday. Rest, legend. 👑');
  });

  it('classStarting uses bro/sis/bestie per gender', () => {
    expect(build('classStarting', 'male').title).toBe('Move it, bro. 😭');
    expect(build('classStarting', 'female').title).toBe('Move it, sis. 😭');
    expect(build('classStarting', '').title).toBe('Move it, bestie. 😭');
  });

  it('perfectAttendance body varies per gender', () => {
    expect(build('perfectAttendance', 'male').body).toContain('Bro practically');
    expect(build('perfectAttendance', 'female').body).toContain('She practically');
    expect(build('perfectAttendance', '').body).toContain('Certified campus dweller');
  });

  it('class roasts are gender-neutral — no invented "her" anywhere', () => {
    const male = build('classReminder30Min', 'male');
    const female = build('classReminder30Min', 'female');
    expect(male.title).toBe(female.title);
    expect(male.title).toBe('Class is waiting. 👀');
    expect(build('classReminder10Min', '').title).toBe("Don't ghost the class. 💀");
    expect(build('classReminder5Min', '').title).toBe('Class is getting impatient. 😭');
    expect(build('classMissed', '').title).toBe('Left the class waiting. 💀');
    expect(build('attendanceImproved', '').title).toBe('Attendance noticed. 👀');
    expect(build('timetableUpdated', '').title).toBe('Plans changed. 👀');
  });

  it('absent roast without a faculty name uses the neutral fallback', () => {
    expect(build('attendanceMarkedAbsent', 'male').title).toBe('Class waited. You ghosted. 💀');
    expect(build('attendanceMarkedAbsent', 'female').title).toBe('Class waited. You ghosted. 💀');
  });

  it('absent roast names the faculty respectfully when known', () => {
    const buildAbsent = (gender: string, staffName: string) =>
      service.build(
        {
          type: 'attendanceMarkedAbsent' as NotificationEventPayload['type'],
          subjectName: 'Math',
          staffName,
        } as NotificationEventPayload,
        prefs(gender),
      );

    // No honorific → neutral "Prof." (never invents a gender).
    expect(buildAbsent('male', 'Arun').title).toBe('Prof. Arun just marked you absent, bro! 💀');
    expect(buildAbsent('female', 'Arun').title).toBe('Prof. Arun just marked you absent, sis! 💀');
    expect(buildAbsent('', 'Arun').title).toBe('Prof. Arun just marked you absent, bestie! 💀');

    // Honorifics → gender-correct tags.
    expect(buildAbsent('male', 'Mr. Arun').title).toBe('Arun sir just marked you absent, bro! 💀');
    expect(buildAbsent('female', 'Mrs. Divya').title).toBe("Divya ma'am just marked you absent, sis! 💀");
    expect(buildAbsent('male', 'Ms. Neha').title).toBe("Neha ma'am just marked you absent, bro! 💀");
    expect(buildAbsent('male', 'Dr. Ravi').title).toBe('Prof. Ravi just marked you absent, bro! 💀');
  });

  it('class reminders carry the faculty name when available', () => {
    const withTeacher = service.build(
      {
        type: 'classReminder10Min' as NotificationEventPayload['type'],
        subjectName: 'Math',
        staffName: 'Arun',
      } as NotificationEventPayload,
      prefs('male'),
    );
    expect(withTeacher.body).toBe('Math with Prof. Arun starts in 10 minutes.');

    const withoutTeacher = build('classReminder10Min', 'male');
    expect(withoutTeacher.body).toBe('this class starts in 10 minutes.');
  });

  it('wrap-up carries present/total stats and is gender-neutral', () => {
    const content = service.build(
      {
        type: 'dayWrapUp' as NotificationEventPayload['type'],
        presentCount: 5,
        totalCount: 6,
      } as NotificationEventPayload,
      prefs('male'),
    );
    expect(content.title).toContain('5/6');
    expect(content.body).toContain('attended 5 of 6');
  });

  it('neutral mode has no gender wording at all', () => {
    const content = service.build(
      { type: 'sundayChill' as NotificationEventPayload['type'] },
      { gender: 'male', roastingEnabled: false } as NotificationPreferencesDto,
    );
    expect(content.title).toBe('Sunday');
    expect(content.title).not.toContain('king');
  });
});
