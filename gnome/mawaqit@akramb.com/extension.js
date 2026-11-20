import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Geoclue from 'gi://Geoclue?version=2.0';
import Soup from 'gi://Soup?version=3.0';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {schedule} from './calendar.js';
import {dueNotifications} from './notifications.js';
import {remaining, prayerDetail, panelTitle, displayPrayers, nextSummary} from './presentation.js';
import {CONNECT_PROMPT, KIND_LABELS, calendarFromTimetable, kimonoLink, sourceLabel} from './kimono.js';

export default class MawaqitExtension extends Extension {
    enable() {
        this._alive = true;
        this._generation = (this._generation ?? 0) + 1;
        this._searchGeneration = (this._searchGeneration ?? 0) + 1;
        this._requests = new Set();
        this._lastNotificationCheck = Math.floor(Date.now() / 1000);
        this._notificationSeen = new Set();
        this._session = new Soup.Session({timeout: 20, user_agent: 'KimonoPrayer-GNOME/1.0'});
        this._file = Gio.File.new_for_path(GLib.build_filenamev([GLib.get_user_config_dir(), 'kimono-prayer', 'state.json']));
        try {
            const [ok, bytes] = this._file.load_contents(null);
            if (ok) this._state = JSON.parse(new TextDecoder().decode(bytes));
        } catch (_) { /* First launch has no saved mosque. */ }
        this._state ??= {};
        this._data = this._state.calendar;
        this._button = new PanelMenu.Button(0.0, 'Kimono Prayer');
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        box.add_child(new St.Icon({icon_name: 'weather-clear-night-symbolic', style_class: 'system-status-icon'}));
        this._panelLabel = new St.Label({text: '', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._panelLabel);
        this._button.add_child(box);
        this._button.menu.box.add_style_class_name('mawaqit-menu');
        this._searchEntry = this._entry('Mosque, city, coordinates or URL', () => this._search(), this._button.menu, true);
        this._searchEntry.set_primary_icon(new St.Icon({icon_name: 'system-search-symbolic'}));
        this._results = new PopupMenu.PopupMenuSection();
        this._button.menu.addMenuItem(this._results);
        this._prayerSeparator = new PopupMenu.PopupSeparatorMenuItem();
        this._button.menu.addMenuItem(this._prayerSeparator);
        this._title = this._text('');
        this._subtitle = this._text('');
        this._title.add_style_class_name('mawaqit-mosque');
        this._title.insert_child_at_index(this._icon('mark-location-symbolic'), 1);
        this._title.label.clutter_text.line_wrap = true;
        this._subtitle.add_style_class_name('mawaqit-subtitle');
        this._source = this._text('');
        this._source.add_style_class_name('mawaqit-source');
        this._source.label.clutter_text.line_wrap = true;
        this._source.label.clutter_text.ellipsize = 0;
        this._upcomingSummary = this._text('');
        this._upcomingSummary.add_style_class_name('mawaqit-upcoming-summary');
        this._todayHeading = this._text('TODAY’S PRAYERS');
        this._todayHeading.add_style_class_name('mawaqit-section-heading');
        this._rows = new PopupMenu.PopupMenuSection();
        this._button.menu.addMenuItem(this._rows);
        this._nightHeading = this._text('NIGHT & SUNRISE');
        this._nightHeading.add_style_class_name('mawaqit-section-heading');
        this._nightRows = new PopupMenu.PopupMenuSection();
        this._button.menu.addMenuItem(this._nightRows);
        this._notificationSwitch = new PopupMenu.PopupSwitchMenuItem('Notifications', this._state.notificationsEnabled !== false);
        this._notificationSwitch.connect('toggled', (_item, enabled) => {
            this._state.notificationsEnabled = enabled;
            this._lastNotificationCheck = Math.floor(Date.now() / 1000);
            this._save();
            this._render();
            if (enabled) Main.notify('Prayer notifications enabled', 'Alerts at prayer start and the last third of the night.');
        });
        this._button.menu.addMenuItem(this._notificationSwitch);
        this._notificationHint = this._text('');
        this._notificationHint.add_style_class_name('mawaqit-status');
        this._notificationHint.label.clutter_text.line_wrap = true;
        this._notificationHint.label.clutter_text.ellipsize = 0;
        this._button.menu.box.set_child_above_sibling(this._notificationHint.actor, this._notificationSwitch.actor);
        try {
            this._notificationSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.notifications'});
            this._notificationSettingsId = this._notificationSettings.connect('changed::show-banners', () => this._render());
        } catch (_) { /* Schema missing: assume banners are shown. */ }
        this._iconOnlySwitch = new PopupMenu.PopupSwitchMenuItem('Icon only in top bar', this._state.iconOnlyMenuBar === true);
        this._iconOnlySwitch.connect('toggled', (_item, enabled) => {
            this._state.iconOnlyMenuBar = enabled;
            this._save();
            this._render();
        });
        this._button.menu.addMenuItem(this._iconOnlySwitch);
        this._refreshAction = this._action('Refresh prayer times', () => this._refreshCurrent());
        this._refreshAction.insert_child_at_index(this._icon('view-refresh-symbolic'), 1);
        this._refreshAction.add_style_class_name('mawaqit-refresh');
        this._disconnectAction = this._action('Disconnect from Kimono', () => this._disconnect());
        this._disconnectAction.insert_child_at_index(this._icon('system-log-out-symbolic'), 1);
        this._disconnectAction.add_style_class_name('mawaqit-refresh');
        this._status = this._text(this._connected() ? 'Search for your mosque, paste its Mawaqit or MasjidBox link, or use where you are.' : CONNECT_PROMPT);
        this._status.label.connect('notify::text', () => {
            this._status.actor.visible = Boolean(this._status.label.text);
        });
        this._status.label.clutter_text.line_wrap = true;
        this._status.label.clutter_text.ellipsize = 0;
        this._status.add_style_class_name('mawaqit-status');
        this._locationHint = this._text('');
        this._locationHint.add_style_class_name('mawaqit-status');
        this._locationHint.label.clutter_text.line_wrap = true;
        this._locationHint.label.clutter_text.ellipsize = 0;
        this._button.menu.box.set_child_below_sibling(this._locationHint.actor, this._results.actor);
        try {
            this._locationSettings = new Gio.Settings({schema_id: 'org.gnome.system.location'});
            this._locationSettingsId = this._locationSettings.connect('changed::enabled', () => this._updateLocationAvailability());
        } catch (_) { /* Schema missing: location stays available and errors explain failures. */ }
        this._updateLocationAvailability();
        this._button.menu.connect('open-state-changed', (_menu, open) => {
            if (open) this._render();
            if (open && (!this._connected() || !this._hasLocation())) this._searchEntry.grab_key_focus();
        });
        Main.panel.addToStatusArea(this.uuid, this._button);
        this._render();
        if (this._connected()) this._refreshCurrent();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
            this._render();
            this._checkNotifications();
            if (this._connected() && Date.now() - (this._lastAttempt ?? 0) > 3600000)
                this._refreshCurrent();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _checkNotifications() {
        const since = this._lastNotificationCheck;
        this._lastNotificationCheck = Math.floor(Date.now() / 1000);
        if (!this._alive || !this._data || !this._hasLocation() || this._state.notificationsEnabled === false) return;
        try {
            const view = schedule(this._data);
            for (const event of dueNotifications(view, since, this._notificationSeen)) {
                const source = this._isCalculated() ? ' · Calculated' : '';
                Main.notify(event.title, `${this._state.place?.name ?? 'Kimono Prayer'} · ${event.body} (${view.timezone})${source}`);
                this._notificationSeen.add(event.id);
            }
            if (this._notificationSeen.size > 30)
                this._notificationSeen = new Set([...this._notificationSeen].slice(-30));
        } catch (error) { console.warn(`Prayer notification: ${error.message}`); }
    }

    _remaining(unix, now) {
        return remaining(unix, now);
    }

    _icon(name) {
        return new St.Icon({icon_name: name, style_class: 'mawaqit-icon', y_align: Clutter.ActorAlign.CENTER});
    }

    _text(text) {
        const item = new PopupMenu.PopupMenuItem(text, {reactive: false});
        item.add_style_class_name('mawaqit-info');
        this._button.menu.addMenuItem(item);
        return item;
    }

    _action(text, callback, menu = this._button.menu) {
        const item = new PopupMenu.PopupMenuItem(text);
        item.connect('activate', callback);
        menu.addMenuItem(item);
        return item;
    }

    _entry(hint, callback, menu = this._button.menu, withLocation = false) {
        const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const entry = new St.Entry({hint_text: hint, can_focus: true, x_expand: true, style_class: 'mawaqit-entry'});
        entry.clutter_text.connect('activate', callback);
        item.add_child(entry);
        if (withLocation) {
            this._locationButton = new St.Button({
                child: this._icon('find-location-symbolic'), can_focus: true,
                accessible_name: 'Use current location', style_class: 'mawaqit-location-button',
            });
            this._locationButton.connect('clicked', () => this._requestCurrentLocation());
            item.add_child(this._locationButton);
        }
        menu.addMenuItem(item);
        return entry;
    }

    // Everything goes through the person's Kimono Prayer link. Non-200 answers carry {error};
    // 401 means the link was renewed.
    async _request(url, {method = 'GET', body} = {}) {
        const message = Soup.Message.new(method, url);
        if (!message) throw new Error('The saved Kimono Prayer link is invalid.');
        const cancel = new Gio.Cancellable();
        this._requests.add(cancel);
        message.get_request_headers().append('Accept', 'application/json');
        if (body !== undefined)
            message.set_request_body_from_bytes('application/json', new GLib.Bytes(new TextEncoder().encode(JSON.stringify(body))));
        try {
            const bytes = await new Promise((resolve, reject) => {
                this._session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, cancel, (session, result) => {
                    try { resolve(session.send_and_read_finish(result)); } catch (error) { reject(error); }
                });
            });
            if (!this._alive) throw new Error('Extension disabled');
            const text = new TextDecoder().decode(bytes.get_data() ?? new Uint8Array());
            let payload = null;
            try { payload = JSON.parse(text); } catch (_) { /* Not JSON: said below. */ }
            if (message.status_code !== 200) {
                const error = new Error(payload?.error ?? (message.status_code === 401
                    ? 'This link no longer works. Connect again from Kimono Prayer.'
                    : `Kimono returned ${message.status_code}. Try again later.`));
                error.statusCode = message.status_code;
                throw error;
            }
            if (!payload) throw new Error('Kimono returned an unexpected response.');
            return payload;
        } finally { this._requests.delete(cancel); }
    }

    _error(error) {
        if (this._alive) this._status.label.text = error.message;
    }

    async _search() {
        const query = this._searchEntry.get_text().trim();
        const link = kimonoLink(query);
        if (link) {
            this._connect(link);
            return;
        }
        if (!this._connected()) {
            this._status.label.text = CONNECT_PROMPT;
            return;
        }
        if (query.length < 2) {
            this._error(new Error('Enter at least two letters, a mosque link or coordinates.'));
            return;
        }
        await this._findPlaces(`q=${encodeURIComponent(query)}`);
    }

    // Kimono answers with Mawaqit mosques, a pasted Mawaqit or MasjidBox mosque, and for a
    // position, times calculated for it.
    async _findPlaces(params) {
        const generation = ++this._searchGeneration;
        this._results.removeAll();
        try {
            this._status.label.text = 'Searching…';
            const {places} = await this._request(`${this._state.link}?${params}`);
            if (!this._alive || generation !== this._searchGeneration) return;
            if (!Array.isArray(places)) throw new Error('Kimono returned an unexpected response.');
            this._status.label.text = places.length ? `${places.length} found; showing up to 10.`
                : 'Nothing found. Try another search, a mosque’s Mawaqit or MasjidBox link, or your location.';
            for (const place of places.slice(0, 10)) {
                const item = new PopupMenu.PopupBaseMenuItem();
                item.add_style_class_name('mawaqit-result');
                item.add_child(this._icon(place.kind === 'calculated' ? 'find-location-symbolic' : 'mark-location-symbolic'));
                const details = new St.BoxLayout({vertical: true, x_expand: true});
                const name = new St.Label({text: place.name, style_class: 'mawaqit-result-name'});
                name.clutter_text.line_wrap = true;
                details.add_child(name);
                const where = [KIND_LABELS[place.kind], place.detail].filter(Boolean).join(' · ');
                if (where) {
                    const location = new St.Label({text: where, style_class: 'mawaqit-result-location'});
                    location.clutter_text.line_wrap = true;
                    details.add_child(location);
                }
                item.add_child(details);
                item.add_child(this._icon('go-next-symbolic'));
                item.connect('activate', () => this._choose(place));
                this._results.addMenuItem(item);
            }
        } catch (error) {
            if (generation === this._searchGeneration) this._fail(error);
        }
    }

    // Makes it the person's place in Kimono, so every device follows.
    _choose(place) {
        this._searchGeneration++;
        // Keep the current place and calendar until the replacement loads successfully.
        this._load({method: 'PUT', body: {id: place.id}});
    }

    _requestCurrentLocation() {
        if (this._locationCancel || !this._locationAvailable()) return;
        const cancel = new Gio.Cancellable();
        this._locationCancel = cancel;
        this._locationButton.reactive = false;
        this._status.label.text = 'Requesting your current location…';
        this._locationTimeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
            this._locationTimeout = null;
            cancel.cancel();
            this._finishLocation();
            this._error(new Error('Location request timed out. Try again or enter a city.'));
            return GLib.SOURCE_REMOVE;
        });
        try {
            Geoclue.Simple.new('org.gnome.Shell', Geoclue.AccuracyLevel.CITY, cancel, (_source, result) => {
                // Always finish the async result; ignore callbacks from an earlier enable/request.
                let geoclue;
                try {
                    geoclue = Geoclue.Simple.new_finish(result);
                    if (!this._alive || this._locationCancel !== cancel) {
                        geoclue.get_client()?.call_stop(null, null);
                        return;
                    }
                    const location = geoclue.get_location();
                    const latitude = location?.get_latitude();
                    const longitude = location?.get_longitude();
                    if (!Number.isFinite(latitude) || !Number.isFinite(longitude))
                        throw new Error('Location Services did not return valid coordinates.');
                    this._results.removeAll();
                    this._searchEntry.set_text(`${latitude.toFixed(4)}, ${longitude.toFixed(4)}`);
                    // The mosques around, and times calculated here in this computer's time zone.
                    const zone = GLib.TimeZone.new_local().get_identifier();
                    const tz = /^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/.test(zone ?? '') ? `&tz=${encodeURIComponent(zone)}` : '';
                    this._findPlaces(`lat=${latitude.toFixed(4)}&lon=${longitude.toFixed(4)}${tz}`);
                } catch (error) {
                    if (this._alive && this._locationCancel === cancel) this._locationError(error);
                } finally {
                    if (geoclue && this._locationCancel === cancel) geoclue.get_client()?.call_stop(null, null);
                    if (this._locationCancel === cancel) this._finishLocation();
                }
            });
        } catch (error) {
            this._finishLocation();
            this._locationError(error);
        }
    }

    _locationAvailable() {
        return this._locationSettings?.get_boolean('enabled') !== false;
    }

    // Gray out the location controls and say why when Location Services is off.
    _updateLocationAvailability() {
        const available = this._locationAvailable();
        this._locationHint.label.text = available ? ''
            : 'Location Services is off. Turn it on in Settings → Privacy → Location, or enter a city.';
        this._locationHint.actor.visible = !available;
        if (this._locationCancel) return;
        this._locationButton.reactive = available;
        this._locationButton.opacity = available ? 255 : 100;
    }

    _finishLocation() {
        if (this._locationTimeout) GLib.Source.remove(this._locationTimeout);
        this._locationTimeout = null;
        this._locationCancel = null;
        if (this._alive) this._updateLocationAvailability();
    }

    _locationError(error) {
        console.warn(`Kimono Prayer location request: ${error.message}`);
        this._error(new Error('Could not access your location. Enable Location Services for GNOME Shell in Settings → Privacy, or search for a city.'));
    }

    _connected() {
        return Boolean(this._state.link);
    }

    // A Kimono Prayer link replaces whatever was saved, keeping the switches, and loads at once.
    _connect(link) {
        this._generation++;
        this._searchGeneration++;
        this._state = {notificationsEnabled: this._state.notificationsEnabled !== false,
            iconOnlyMenuBar: this._state.iconOnlyMenuBar === true, link};
        this._data = null;
        this._notificationSeen.clear();
        this._lastNotificationCheck = Math.floor(Date.now() / 1000);
        this._results.removeAll();
        this._searchEntry.set_text('');
        this._status.label.text = '';
        this._save();
        this._render();
        this._refreshCurrent();
    }

    _disconnect() {
        this._generation++;
        this._searchGeneration++;
        this._state = {notificationsEnabled: this._state.notificationsEnabled !== false,
            iconOnlyMenuBar: this._state.iconOnlyMenuBar === true};
        this._data = null;
        this._results.removeAll();
        this._searchEntry.set_text('');
        this._status.label.text = CONNECT_PROMPT;
        this._save();
        this._render();
    }

    _hasLocation() {
        return Boolean(this._state.place);
    }

    _isCalculated() {
        return this._state.place?.kind === 'calculated';
    }

    _refreshCurrent() {
        this._load();
    }

    async _load(request = {}) {
        if (!this._connected() || !this._alive) return;
        const generation = ++this._generation;
        this._lastAttempt = Date.now();
        this._status.label.text = 'Loading prayer times…';
        try {
            const mine = await this._request(this._state.link, request);
            const data = mine.timetable ? calendarFromTimetable(mine.timetable) : null;
            if (data) schedule(data);
            if (!this._alive || generation !== this._generation) return;
            const samePlace = mine.place?.id === this._state.place?.id;
            if (!samePlace) {
                this._lastNotificationCheck = Math.floor(Date.now() / 1000);
                this._notificationSeen.clear();
            }
            this._state.place = mine.place ?? null;
            if (data) {
                this._data = data;
                Object.assign(this._state, {calendar: data, fetched: Date.now()});
                this._status.label.text = '';
                this._results.removeAll();
                this._searchEntry.set_text('');
            } else {
                if (!mine.place || !samePlace) {
                    this._data = null;
                    Object.assign(this._state, {calendar: null, fetched: null});
                }
                // Kimono knows the place but couldn't reach its times: the last ones stay.
                this._status.label.text = mine.place
                    ? mine.problem ?? 'Kimono couldn’t reach the prayer times. Try again in a moment.'
                    : 'Search for your mosque, or use where you are.';
            }
            this._save();
            this._render();
        } catch (error) {
            if (generation === this._generation) this._fail(error);
        }
    }

    // A renewed link answers 401: forget it, keep the times, and ask for the new one.
    _fail(error) {
        if (error.statusCode === 401 && this._alive) {
            this._state.link = null;
            this._results.removeAll();
            this._save();
            this._render();
        }
        this._error(error);
    }

    _save() {
        try {
            GLib.mkdir_with_parents(this._file.get_parent().get_path(), 0o700);
            this._file.replace_contents(JSON.stringify(this._state), null, false, Gio.FileCreateFlags.PRIVATE, null);
        } catch (error) { this._error(new Error(`Could not save your mosque: ${error.message}`)); }
    }

    _render() {
        const connected = this._connected();
        this._searchEntry.hint_text = connected ? 'Mosque, city, coordinates or URL' : 'Paste your Kimono Prayer link';
        this._locationButton.visible = connected;
        this._disconnectAction.actor.visible = connected;
        const active = this._hasLocation();
        for (const item of [this._prayerSeparator, this._title, this._subtitle, this._source, this._upcomingSummary, this._todayHeading, this._rows, this._nightHeading, this._nightRows, this._notificationSwitch, this._refreshAction])
            item.actor.visible = active;
        this._refreshAction.actor.visible = connected;
        const dnd = this._notificationSettings?.get_boolean('show-banners') === false;
        this._notificationHint.label.text = dnd
            ? 'Do Not Disturb is on, so prayer alerts won’t pop up. They still appear in the notification list.' : '';
        this._notificationHint.actor.visible = active && dnd && this._state.notificationsEnabled !== false;
        const calculated = this._isCalculated();
        this._source.actor.visible = active;
        this._status.actor.visible = Boolean(this._status.label.text);
        this._upcomingSummary.actor.visible = false;
        this._panelLabel.text = '';
        this._panelLabel.visible = false;
        if (!this._data) return;
        try {
            const view = schedule(this._data);
            this._rows.removeAll();
            this._title.label.text = this._state.place?.name ?? 'Kimono Prayer';
            const cached = Date.now() - this._state.fetched > 3600000 ? ' · cached' : '';
            this._subtitle.label.text = `${view.date} · ${view.timezone}${cached}`;
            const detail = this._state.place?.detail;
            this._source.label.text = [sourceLabel(this._state.place), detail].filter(Boolean).join(' · ')
                + (calculated ? '\nMay differ from your local mosque or religious authority.' : '');
            const {current, night, now} = view;
            const nextDescription = nextSummary(view);
            const panelStatus = panelTitle(view);
            this._upcomingSummary.label.text = nextDescription;
            this._upcomingSummary.actor.visible = Boolean(nextDescription);
            this._panelLabel.text = panelStatus;
            this._panelLabel.visible = Boolean(panelStatus) && this._state.iconOnlyMenuBar !== true;
            const icons = ['weather-clear-night-symbolic', 'weather-clear-symbolic',
                'weather-clear-symbolic', 'weather-few-clouds-symbolic',
                'weather-few-clouds-night-symbolic', 'weather-clear-night-symbolic'];
            for (const prayer of displayPrayers(view)) {
                const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
                item.add_style_class_name('mawaqit-prayer-row');
                item.add_style_class_name('mawaqit-info');
                const index = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'].indexOf(prayer.name);
                item.add_child(this._icon(icons[index]));
                if (prayer === current) {
                    item.add_style_class_name('mawaqit-current');
                    const details = new St.BoxLayout({vertical: true, x_expand: true});
                    const headline = new St.BoxLayout({x_expand: true, style_class: 'mawaqit-current-headline'});
                    headline.add_child(new St.Label({text: prayer.name, x_expand: true}));
                    headline.add_child(new St.Label({text: prayer.time}));
                    details.add_child(headline);
                    const end = new St.Label({text: `Ends at ${prayer.endTime}${prayer.name === 'Isha' ? ' · Islamic midnight' : ''}`, style_class: 'mawaqit-current-detail'});
                    end.clutter_text.line_wrap = true;
                    details.add_child(end);
                    item.add_child(details);
                } else {
                    item.add_child(new St.Label({text: prayer.name, x_expand: true, y_align: Clutter.ActorAlign.CENTER}));
                    const status = prayerDetail(prayer, view);
                    item.add_child(new St.Label({text: status, style_class: 'mawaqit-prayer-detail', y_align: Clutter.ActorAlign.CENTER}));
                    if (prayer === view.next) item.add_style_class_name('mawaqit-next');
                    else if (prayer.end <= now) item.add_style_class_name('mawaqit-past');
                    item.add_child(new St.Label({text: prayer.time, style_class: 'mawaqit-prayer-time', y_align: Clutter.ActorAlign.CENTER}));
                }
                this._rows.addMenuItem(item);
            }
            this._nightRows.removeAll();
            const {milestones} = view;
            for (const [key, name, time, start] of [
                ['midnight', 'Islamic midnight', milestones.midnightTime, milestones.midnight],
                ['lastThird', 'Last third', milestones.lastThirdTime, milestones.lastThird],
                ['sunrise', 'Sunrise', milestones.sunriseTime, milestones.sunrise],
            ]) {
                const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
                item.add_style_class_name('mawaqit-night-row');
                item.add_child(new St.Label({text: name, x_expand: true, y_align: Clutter.ActorAlign.CENTER}));
                const selected = milestones.phase === key;
                const status = selected ? `in ${this._remaining(start, now)}`
                    : milestones.active && start <= now ? 'Passed' : '';
                item.add_child(new St.Label({text: status, style_class: 'mawaqit-prayer-detail', y_align: Clutter.ActorAlign.CENTER}));
                item.add_child(new St.Label({text: time, style_class: 'mawaqit-prayer-time', y_align: Clutter.ActorAlign.CENTER}));
                if (selected) item.add_style_class_name('mawaqit-night-active');
                else item.add_style_class_name('mawaqit-past');
                this._nightRows.addMenuItem(item);
            }
        } catch (error) {
            this._rows.removeAll();
            this._nightRows.removeAll();
            this._nightHeading.actor.visible = false;
            this._source.actor.visible = false;
            this._panelLabel.visible = false;
            this._upcomingSummary.actor.visible = false;
            this._error(error);
        }
    }

    disable() {
        this._alive = false;
        if (this._locationSettingsId) this._locationSettings.disconnect(this._locationSettingsId);
        if (this._notificationSettingsId) this._notificationSettings.disconnect(this._notificationSettingsId);
        this._notificationSettings = null;
        this._locationSettings = null;
        this._generation++;
        this._searchGeneration++;
        if (this._timer) GLib.Source.remove(this._timer);
        this._timer = null;
        for (const request of this._requests) request.cancel();
        this._session.abort();
        this._locationCancel?.cancel();
        this._finishLocation();
        this._button.destroy();
        this._button = null;
        this._state = null;
        this._data = null;
    }
}
