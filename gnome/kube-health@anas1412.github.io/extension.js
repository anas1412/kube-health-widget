import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const STATUS = GLib.build_filenamev([GLib.get_user_cache_dir(), 'kube-health', 'status.json']);
const POD_DOT = {ok: '🟢', pending: '🟠', bad: '🔴', done: '⚪'};
const bad = c => !c.up || c.watchdog === false;
const pct = c => c.pods.pct == null ? '?' : `${c.pods.pct}%`;
const dot = c => bad(c) ? '🔴'
    : ((c.pods.pct ?? 100) < 95 || c.alerts.some(a => a.severity === 'critical') || (c.nodes?.notready.length ?? 0) > 0) ? '🟠'
    : '🟢';
const SEVERITIES = ['', 'critical', 'warning', 'info'];
const BIN = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'kube-health']);
const MUTES = [['Mute for 1 hour', '3600'], ['Mute for 4 hours', '14400'], ['Mute for 8 hours', '28800'],
    ['Mute for 24 hours', '86400'], ['Mute until I unmute', 'forever']];
const muteText = m => m === -1 ? 'Muted until you unmute'
    : `Muted until ${GLib.DateTime.new_from_unix_local(m).format('%H:%M')}`;

export default class KubeHealth extends Extension {
    enable() {
        this._status = null;
        this._nsFilter = '';
        this._problemsOnly = false;
        this._sevFilter = '';
        this._button = new PanelMenu.Button(0.0, 'Kube Health', false);
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        box.add_child(new St.Icon({
            gicon: Gio.icon_new_for_string(`${this.path}/kube-health.svg`),
            style_class: 'system-status-icon',
        }));
        this._label = new St.Label({text: '…', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._label);
        this._button.add_child(box);
        this._button.menu.connect('open-state-changed', (_m, open) => open && this._build());
        Main.panel.addToStatusArea(this.uuid, this._button);
        this._load();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 15, () => { this._load(); return GLib.SOURCE_CONTINUE; });
    }

    disable() {
        GLib.source_remove(this._timer);
        this._button.destroy();
        this._button = this._label = this._status = null;
    }

    _load() {
        try {
            const [, bytes] = Gio.File.new_for_path(STATUS).load_contents(null);
            this._status = JSON.parse(new TextDecoder().decode(bytes));
        } catch (e) {
            this._status = null;
        }
        const cs = this._status?.clusters ?? [];
        const worst = cs.slice().sort((a, b) => (bad(b) - bad(a)) || ((a.pods.pct ?? 100) - (b.pods.pct ?? 100)))[0];
        this._label.text = (!worst ? '⚪ ?' : `${dot(worst)} ${bad(worst) ? 'DOWN' : pct(worst)}`) +
            (this._status?.muted_until ? ' 🔕' : '');
    }

    _mute(arg) {
        const proc = Gio.Subprocess.new([BIN, '--mute', arg], Gio.SubprocessFlags.NONE);
        proc.wait_async(null, () => this._load());
    }

    _build() {
        const menu = this._button.menu;
        menu.removeAll();
        if (!this._status) {
            menu.addMenuItem(new PopupMenu.PopupMenuItem(`No data in ${STATUS}`, {reactive: false}));
            return;
        }

        // Namespace filter applies to every cluster's pod list.
        const entryItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const entry = new St.Entry({hint_text: 'Filter pods by namespace…', text: this._nsFilter, can_focus: true, x_expand: true});
        entry.clutter_text.connect('text-changed', () => {
            this._nsFilter = entry.text.trim();
            this._fillPods();
        });
        entryItem.add_child(entry);
        menu.addMenuItem(entryItem);

        const problems = new PopupMenu.PopupSwitchMenuItem('Problem pods only', this._problemsOnly);
        problems.connect('toggled', (_i, on) => {
            this._problemsOnly = on;
            this._fillPods();
        });
        menu.addMenuItem(problems);

        // Severity filter is applied when the menu is (re)built.
        const sevMenu = new PopupMenu.PopupSubMenuMenuItem(`Alert severity: ${this._sevFilter || 'all'}`);
        for (const s of SEVERITIES) {
            const item = new PopupMenu.PopupMenuItem(s || 'all');
            item.setOrnament(s === this._sevFilter ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
            item.connect('activate', () => { this._sevFilter = s; });
            sevMenu.menu.addMenuItem(item);
        }
        menu.addMenuItem(sevMenu);

        this._podMenus = [];
        for (const c of this._status.clusters) {
            menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem(`${dot(c)} ${c.name}`));
            menu.addMenuItem(new PopupMenu.PopupMenuItem(
                `API ${c.up ? '✅' : '🔴 unreachable'}   Watchdog ${c.watchdog === null ? 'n/a' : c.watchdog ? '✅' : '🔴 missing'}   ` +
                `Pods ${c.pods.healthy}/${c.pods.total} (${pct(c)})`, {reactive: false}));
            if (c.nodes) {
                const nr = c.nodes.notready;
                menu.addMenuItem(new PopupMenu.PopupMenuItem(
                    `Nodes ${c.nodes.total - nr.length}/${c.nodes.total}${nr.length ? `   🟠 NotReady: ${nr.join(', ')}` : ''}`,
                    {reactive: false}));
            }

            const sub = (title, lines) => {
                const s = new PopupMenu.PopupSubMenuMenuItem(title);
                for (const l of lines)
                    s.menu.addMenuItem(new PopupMenu.PopupMenuItem(l, {reactive: false}));
                menu.addMenuItem(s);
                return s;
            };
            const icon = s => s === 'critical' ? '🔴' : s === 'warning' ? '🟠' : '⚪';
            this._podMenus.push([c, sub('Recent pods', [])]);
            const alerts = c.alerts.filter(a => !this._sevFilter || a.severity === this._sevFilter);
            sub(`Alerts (${alerts.length})`, alerts.map(a => `${icon(a.severity)} ${a.name} ${a.ns} · ${a.msg}`));
            sub(`Warnings (${c.events.length})`, c.events.map(e => `🟠 ${e.age} ${e.reason} ${e.ns}/${e.obj} · ${e.msg}`));
        }
        this._fillPods();

        menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem(`Updated ${this._status.updated}`));
        const refresh = new PopupMenu.PopupMenuItem('Refresh now');
        refresh.connect('activate', () => {
            GLib.spawn_command_line_async('systemctl --user start kube-health.service');
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 12, () => { this._load(); return GLib.SOURCE_REMOVE; });
        });
        menu.addMenuItem(refresh);

        const muted = this._status.muted_until ?? 0;
        const muteMenu = new PopupMenu.PopupSubMenuMenuItem(muted ? `🔕 ${muteText(muted)}` : 'Mute notifications');
        if (muted) {
            const unmute = new PopupMenu.PopupMenuItem('Unmute');
            unmute.connect('activate', () => this._mute('off'));
            muteMenu.menu.addMenuItem(unmute);
        }
        for (const [label, arg] of MUTES) {
            const item = new PopupMenu.PopupMenuItem(label);
            item.connect('activate', () => this._mute(arg));
            muteMenu.menu.addMenuItem(item);
        }
        menu.addMenuItem(muteMenu);

        const settings = new PopupMenu.PopupMenuItem('Settings…');
        settings.connect('activate', () => this.openPreferences());
        menu.addMenuItem(settings);
    }

    _fillPods() {
        for (const [c, s] of this._podMenus) {
            s.menu.removeAll();
            const pods = c.pods.recent
                .filter(p => p.ns.includes(this._nsFilter))
                .filter(p => !this._problemsOnly || p.state === 'bad' || p.state === 'pending')
                .slice(0, 50);
            s.label.text = `Recent pods (${pods.length}${this._nsFilter ? ` in *${this._nsFilter}*` : ''})`;
            for (const p of pods) {
                s.menu.addMenuItem(new PopupMenu.PopupMenuItem(
                    `${POD_DOT[p.state] ?? '⚪'} ${p.age}  ${p.ns}/${p.name}  ${p.reason || p.phase} ${p.ready}${p.restarts ? '  ↻' + p.restarts : ''}`,
                    {reactive: false}));
            }
        }
    }
}
