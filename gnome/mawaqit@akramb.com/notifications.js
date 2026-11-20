// Only announce freshly crossed boundaries; do not replay events after suspend.
export function dueNotifications(view, since, seen = new Set()) {
    const events = view.today.filter(p => !p.sunrise).map(p => ({
        id: `prayer:${p.name}:${p.unix}`, at: p.unix,
        title: `${p.name} time`, body: `Ends at ${p.endTime}${p.name === 'Isha' ? ' · Islamic midnight' : ''}`,
    }));
    events.push({id: `last-third:${view.night.lastThird}`, at: view.night.lastThird,
        title: 'Last third of the night', body: `Until Fajr at ${view.night.endTime}`});
    return events.filter(e => e.at > since && e.at <= view.now && view.now - e.at <= 90 && !seen.has(e.id));
}
