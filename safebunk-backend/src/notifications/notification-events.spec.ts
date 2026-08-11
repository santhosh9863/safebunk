import { channelIdFor, ttlSecondsFor } from './notification-events';

describe('notification event metadata', () => {
  describe('ttlSecondsFor', () => {
    it('gives class reminders a short TTL so stale reminders never arrive late', () => {
      expect(ttlSecondsFor('classReminder30Min')).toBe(10 * 60);
      expect(ttlSecondsFor('classReminder10Min')).toBe(10 * 60);
      expect(ttlSecondsFor('classReminder5Min')).toBe(10 * 60);
      expect(ttlSecondsFor('classStarting')).toBe(10 * 60);
      expect(ttlSecondsFor('classMissed')).toBe(10 * 60);
    });

    it('gives state notifications a longer delivery window', () => {
      expect(ttlSecondsFor('attendanceMarkedPresent')).toBe(60 * 60);
      expect(ttlSecondsFor('enteredDangerZone')).toBe(60 * 60);
      expect(ttlSecondsFor('timetableUpdated')).toBe(60 * 60);
    });
  });

  describe('channelIdFor', () => {
    it('routes urgent events to the alert channel', () => {
      expect(channelIdFor('enteredDangerZone')).toBe('attendance_alerts');
      expect(channelIdFor('classMissed')).toBe('attendance_alerts');
    });

    it('routes everything else to reminders', () => {
      expect(channelIdFor('classStarting')).toBe('reminders');
      expect(channelIdFor('attendanceMarkedPresent')).toBe('reminders');
    });
  });
});
