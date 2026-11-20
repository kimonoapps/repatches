// The personal link Kimono Prayer hands out (https://<kimono>/api/v1/prayer/feed/<token>), pasted
// as is or wrapped in mawaqit-kimono://connect?link=<link>. It stands in for signing in.
// No imports, so the tests run under plain node as well as gjs.

export const CONNECT_PROMPT = 'Paste your link from Kimono Prayer and press Enter.';

const FEED = /^(https?):\/\/([^/?#\s]+)(\/api\/v1\/prayer\/feed\/[A-Za-z0-9_-]+)\/?(?:[?#]\S*)?$/i;
const CONNECT = /^mawaqit-kimono:\/\/connect\/?\?(\S*)$/i;

/** The feed link in `text`, normalised, or null. */
export function kimonoLink(text) {
    let value = String(text ?? '').trim();
    const connect = CONNECT.exec(value);
    if (connect) {
        const param = connect[1].split('&').find(part => part.startsWith('link='));
        if (!param) return null;
        try { value = decodeURIComponent(param.slice(5).replace(/\+/g, ' ')).trim(); } catch (_) { return null; }
    }
    const match = FEED.exec(value);
    return match ? `${match[1].toLowerCase()}://${match[2]}${match[3]}` : null;
}

export const KIND_LABELS = {mawaqit: 'Mawaqit', masjidbox: 'MasjidBox', calculated: 'Calculated'};

/** "Kimono · Mawaqit" and so on: where a place's times come from. */
export function sourceLabel(place) {
    return ['Kimono', KIND_LABELS[place?.kind]].filter(Boolean).join(' · ');
}

/**
 * Kimono's timetable ({timezone, days: [{date: 'YYYY-MM-DD', times: [6 × 'HH:MM']}]}) in the
 * yearly calendar shape schedule() reads: calendar[month - 1]['<day>']. The feed runs from
 * yesterday to a few weeks ahead, so no month appears for two different years.
 */
export function calendarFromTimetable(timetable) {
    if (!timetable || typeof timetable.timezone !== 'string' || !Array.isArray(timetable.days))
        throw new Error('Kimono returned an unexpected response.');
    const calendar = Array.from({length: 12}, () => ({}));
    for (const day of timetable.days) {
        const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day?.date ?? '');
        const month = match ? Number(match[2]) : 0, date = match ? Number(match[3]) : 0;
        if (month < 1 || month > 12 || date < 1 || date > 31 || !Array.isArray(day.times) || day.times.length !== 6)
            throw new Error('Kimono sent a day of prayer times it couldn’t read.');
        calendar[month - 1][String(date)] = day.times;
    }
    return {timezone: timetable.timezone, calendar};
}
