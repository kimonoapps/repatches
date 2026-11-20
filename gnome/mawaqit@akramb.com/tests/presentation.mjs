import assert from 'node:assert/strict';
import {remaining, prayerDetail, panelTitle, displayPrayers, nextSummary} from '../presentation.js';

const maghrib = {name: 'Maghrib', unix: 0, end: 3600, endTime: '20:31'};
const isha = {name: 'Isha', unix: 3600, end: 18000, endTime: '00:31'};
const view = {now: 2760, current: maghrib, next: isha,
    milestones: {active: false, midnight: 18000, lastThird: 24000, sunrise: 36000},
    night: {end: 30000}};
assert.equal(prayerDetail(isha, view), 'in 14min');
assert.equal(prayerDetail(maghrib, view), 'Ends 20:31');
assert.equal(panelTitle(view), 'Isha in 14min');
assert.equal(prayerDetail(maghrib, {...view, now: 3600}), 'Ended 20:31');
assert.equal(remaining(7200, 0), '2h00min');
const night = {...view, milestones: {...view.milestones, active: true}};
assert.equal(panelTitle({...night, now: 14400}), 'Midnight in 1h00min');
assert.equal(panelTitle({...night, now: 18000}), 'Last third in 1h40min');
assert.equal(panelTitle({...night, now: 24000}), 'Fajr in 1h40min');
assert.equal(panelTitle({...night, now: 30000}), 'Sunrise in 1h40min');
assert.equal(panelTitle({...view, next: null}), '');
assert.equal(remaining(8100, 0), '2h15min');
assert.equal(remaining(3900, 0), '1h05min');
const fajr = {name: 'Fajr', time: '05:00', unix: 100};
const yesterdayIsha = {name: 'Isha', time: '20:00', unix: -50, end: 50};
const todayIsha = {name: 'Isha', time: '20:00', unix: 900};
const overnight = {today: [fajr, todayIsha], current: yesterdayIsha, next: fajr};
assert.deepEqual(displayPrayers(overnight), [fajr, yesterdayIsha]);
assert.equal(nextSummary(overnight), '');
const tomorrowFajr = {name: 'Fajr', time: '05:01', unix: 2000};
assert.equal(nextSummary({today: [fajr], next: tomorrowFajr}), 'Next: Fajr at 05:01 tomorrow');
console.log('Prayer-row ownership and all panel milestone phases passed.');
