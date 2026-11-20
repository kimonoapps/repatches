import assert from 'node:assert/strict';
import {calendarFromTimetable, kimonoLink, sourceLabel} from '../kimono.js';

const link = 'https://kimono.example/api/v1/prayer/feed/abc_DEF-123';
assert.equal(kimonoLink(`  ${link}\n`), link, 'A pasted link');
assert.equal(kimonoLink(`mawaqit-kimono://connect?link=${encodeURIComponent(link)}`), link, 'The connect address');
assert.equal(kimonoLink(`${link}?q=paris`), link, 'A query is dropped');
assert.equal(kimonoLink('https://kimono.example/prayer'), null, 'Another Kimono page');
assert.equal(kimonoLink('ftp://kimono.example/api/v1/prayer/feed/abc'), null, 'Another scheme');
assert.equal(kimonoLink(`mawaqit-kimono://other?link=${encodeURIComponent(link)}`), null, 'Another action');
assert.equal(kimonoLink('Paris'), null, 'Words');

const times = ['06:20', '07:40', '12:10', '14:20', '16:30', '18:00'];
const feed = calendarFromTimetable({timezone: 'America/Toronto',
    days: ['2026-12-31', '2027-01-01'].map(date => ({date, times, iqama: null, jumua: []}))});
assert.equal(feed.timezone, 'America/Toronto');
assert.deepEqual(feed.calendar[11]['31'], times, 'December 31st in the last month');
assert.deepEqual(feed.calendar[0]['1'], times, 'January 1st in the first, keyed without a leading zero');
assert.throws(() => calendarFromTimetable({timezone: 'America/Toronto', days: [{date: '2026-12-31', times: ['06:20']}]}), 'A short day');
assert.throws(() => calendarFromTimetable(null), 'No timetable');
assert.equal(sourceLabel({kind: 'masjidbox'}), 'Kimono · MasjidBox');
assert.equal(sourceLabel({kind: 'calculated'}), 'Kimono · Calculated');
console.log('Kimono tests passed');
