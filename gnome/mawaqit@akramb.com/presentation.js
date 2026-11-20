// Shared presentation rules keep each countdown attached to its own event.
export function remaining(unix, now) {
    const minutes = Math.max(1, Math.ceil((unix - now) / 60));
    return minutes >= 60
        ? `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, '0')}min`
        : `${minutes}min`;
}

export function prayerDetail(prayer, view) {
    if (prayer === view.next) return `in ${remaining(prayer.unix, view.now)}`;
    return prayer.end <= view.now ? `Ended ${prayer.endTime}` : `Ends ${prayer.endTime}`;
}

// Overnight, the open prayer replaces today's row of the same name instead of adding a row.
export function displayPrayers(view) {
    const {current} = view;
    return view.today.filter(p => !p.sunrise)
        .map(p => current && current.name === p.name && !view.today.includes(current) ? current : p);
}

export function nextSummary(view) {
    if (!view.next || view.today.includes(view.next)) return '';
    return `Next: ${view.next.name} at ${view.next.time} tomorrow`;
}

export function panelTitle(view) {
    const {milestones, night, now} = view;
    if (milestones.active && now < milestones.midnight)
        return `Midnight in ${remaining(milestones.midnight, now)}`;
    if (milestones.active && now < milestones.lastThird)
        return `Last third in ${remaining(milestones.lastThird, now)}`;
    if (milestones.active && now < night.end)
        return `Fajr in ${remaining(night.end, now)}`;
    if (milestones.active)
        return `Sunrise in ${remaining(milestones.sunrise, now)}`;
    return view.next ? `${view.next.name} in ${remaining(view.next.unix, now)}` : '';
}
