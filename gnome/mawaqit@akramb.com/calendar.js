import GLib from 'gi://GLib';

export const NAMES = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

export function parseCalendar(html) {
    const assignment = /(?:var|let|const)\s+confData\s*=\s*/.exec(html);
    if (!assignment)
        throw new Error('Mawaqit did not return a prayer calendar. Try again later.');
    // Scan the JSON object without confusing braces or semicolons in quoted messages.
    const start = assignment.index + assignment[0].length;
    let depth = 0, quoted = false, escaped = false;
    for (let i = start; i < html.length; i++) {
        const c = html[i];
        if (quoted) {
            if (escaped) escaped = false;
            else if (c === '\\') escaped = true;
            else if (c === '"') quoted = false;
        } else if (c === '"') quoted = true;
        else if (c === '{') depth++;
        else if (c === '}' && --depth === 0) {
            const data = JSON.parse(html.slice(start, i + 1));
            if (!data.timezone || !Array.isArray(data.calendar) || data.calendar.length !== 12)
                throw new Error('This mosque has an unsupported prayer calendar.');
            return data;
        }
    }
    throw new Error('The prayer calendar is incomplete.');
}

export function parseCalculatedCalendar(payload) {
    if (!payload || payload.code !== 200 || !payload.data || typeof payload.data !== 'object')
        throw new Error('The calculated prayer-time service returned an unexpected response.');
    const calendar = Array.from({length: 12}, () => ({}));
    let timezone = null, method = null;
    for (let month = 1; month <= 12; month++) {
        const days = payload.data[String(month)];
        if (!Array.isArray(days) || !days.length)
            throw new Error('Calculated prayer times are incomplete for this year.');
        for (const item of days) {
            const day = Number(item?.date?.gregorian?.day);
            if (!Number.isInteger(day) || day < 1 || day > 31 || !item?.timings)
                throw new Error('A calculated prayer-time entry is invalid.');
            const times = NAMES.map(name => {
                const match = /^(\d{1,2}:\d{2})/.exec(item.timings[name]);
                if (!match) throw new Error('A calculated prayer time is invalid.');
                return match[1];
            });
            calendar[month - 1][String(day)] = times;
            timezone ??= item.meta?.timezone;
            method ??= item.meta?.method?.name;
        }
    }
    if (!timezone || !GLib.TimeZone.new_identifier(timezone))
        throw new Error('The calculated location has an invalid timezone.');
    return {calendar: {timezone, calendar}, method: method ?? 'Automatic local method'};
}

export function schedule(data, now = GLib.DateTime.new_now_utc()) {
    const zone = GLib.TimeZone.new_identifier(data.timezone);
    if (!zone) throw new Error('The mosque timezone is invalid.');
    const local = now.to_timezone(zone);
    const days = [local.add_days(-1), local, local.add_days(1)];
    const schedules = days.map(date => {
        const times = data.calendar[date.get_month() - 1]?.[String(date.get_day_of_month())];
        if (!Array.isArray(times) || times.length < 6)
            throw new Error('No prayer times available for this date.');
        return NAMES.map((name, i) => {
            if (!/^\d{1,2}:\d{2}$/.test(times[i])) throw new Error('Invalid prayer time.');
            const [hour, minute] = times[i].split(':').map(Number);
            if (hour > 23 || minute > 59) throw new Error('Invalid prayer time.');
            const instant = GLib.DateTime.new(zone, date.get_year(), date.get_month(),
                date.get_day_of_month(), hour, minute, 0);
            return {name, time: times[i], unix: instant.to_unix(), sunrise: i === 1};
        });
    });
    const timestamp = now.to_unix();
    const formatTime = unix => GLib.DateTime.new_from_unix_utc(Math.floor(unix)).to_timezone(zone).format('%H:%M');
    const nights = schedules.slice(0, 2).map((prayers, index) => {
        const start = prayers[4].unix;
        const end = schedules[index + 1][0].unix;
        if (end <= start) throw new Error('Invalid sunset-to-Fajr night interval.');
        const midnight = start + (end - start) / 2;
        const lastThird = start + (end - start) * 2 / 3;
        return {start, end, midnight, lastThird, midnightTime: formatTime(midnight),
            lastThirdTime: formatTime(lastThird), endTime: formatTime(end)};
    });
    const windows = schedules.slice(0, 2).map((prayers, index) => prayers.map((prayer, i) => {
        if (prayer.sunrise) return prayer;
        const end = i === 5 ? nights[index].midnight : prayers[i + 1].unix;
        return {...prayer, end, endTime: formatTime(end), dayOffset: index - 1};
    }));
    const today = windows[1];
    const next = [...today, ...schedules[2]].find(p => !p.sunrise && p.unix > timestamp);
    const current = windows.flat().find(p => !p.sunrise && p.unix <= timestamp && timestamp < p.end) ?? null;
    // Before Fajr, use yesterday's sunset so night status survives civil midnight.
    const night = timestamp < schedules[1][0].unix ? nights[0] : nights[1];
    night.active = night.start <= timestamp && timestamp < night.end;
    night.lastThirdActive = night.lastThird <= timestamp && timestamp < night.end;
    // The displayed night cycle lasts from Isha through sunrise, including Fajr.
    const cycleIndex = timestamp < schedules[1][1].unix ? 0 : 1;
    const cycleNight = nights[cycleIndex];
    const sunrise = schedules[cycleIndex + 1][1];
    const cycleActive = timestamp >= schedules[cycleIndex][5].unix && timestamp < sunrise.unix;
    const milestones = {midnight: cycleNight.midnight, midnightTime: cycleNight.midnightTime,
        lastThird: cycleNight.lastThird, lastThirdTime: cycleNight.lastThirdTime,
        sunrise: sunrise.unix, sunriseTime: sunrise.time, active: cycleActive,
        phase: !cycleActive ? null : timestamp < cycleNight.midnight ? 'midnight'
            : timestamp < cycleNight.lastThird ? 'lastThird' : 'sunrise'};
    return {today, next, current, night, milestones, now: timestamp,
        date: local.format('%A, %e %B'), timezone: data.timezone};
}

export function mosqueSlug(value) {
    const text = value.trim();
    const match = /^https:\/\/mawaqit\.net\/(?:[a-z]{2}\/)?(?:m\/)?([a-zA-Z0-9_-]+)\/?$/.exec(text);
    const slug = match ? match[1] : text;
    if (!/^[a-zA-Z0-9_-]+$/.test(slug)) throw new Error('Enter a mosque slug or its Mawaqit URL.');
    return slug;
}
