import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

// Settings live in ~/.config/kube-health (shared with KDE); all reads and writes go through
// the kube-health command, called with an argv array so nothing passes through a shell.
const BIN = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'kube-health']);
const MUTES = [['Not muted', 'off'], ['1 hour', '3600'], ['4 hours', '14400'], ['8 hours', '28800'],
    ['24 hours', '86400'], ['Until I unmute', 'forever']];
// Notification rules: NOTIFY_<key>=0 turns one off. limit names the threshold setting shown next to it.
const RULES = [
    {key: 'API', text: 'A cluster API is unreachable'},
    {key: 'WATCHDOG', text: 'Watchdog is missing (alerting is down)'},
    {key: 'CRITICAL', text: 'A critical alert fires'},
    {key: 'NODE_NOTREADY', text: 'A node becomes NotReady'},
    {key: 'NODE_PRESSURE', text: 'A node has memory, disk or PID pressure'},
    {key: 'NODE_CPU', text: "A node's CPU reaches (%)", limit: 'NODE_CPU_MAX', def: 90},
    {key: 'NODE_MEM', text: "A node's RAM reaches (%)", limit: 'NODE_MEM_MAX', def: 90},
    {key: 'POD_HEALTH', text: 'Pod health drops below (%)', limit: 'HEALTH_MIN', def: 95},
    {key: 'CRASHLOOP', text: 'A pod is in CrashLoopBackOff or OOMKilled'},
    {key: 'PIPELINES', text: 'A pipeline fails (and when it is fixed)'},
];
const MAX_MATCHES = 10;

function run(args, input = null) {
    const flags = Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE |
        (input === null ? 0 : Gio.SubprocessFlags.STDIN_PIPE);
    const proc = Gio.Subprocess.new([BIN, ...args], flags);
    return new Promise((resolve, reject) => {
        proc.communicate_utf8_async(input, null, (p, res) => {
            try {
                resolve(p.communicate_utf8_finish(res)[1] ?? '');
            } catch (e) {
                reject(e);
            }
        });
    });
}

const desc = text => new Gtk.Label({label: text, wrap: true, xalign: 0, css_classes: ['dim-label', 'caption'], margin_top: 6});
const repoName = id => id.replace(/^[a-z]+:/, '').replace(/@.*$/, '');

export default class KubeHealthPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const page = new Adw.PreferencesPage({title: 'General', icon_name: 'preferences-system-symbolic'});
        window.add(page);
        let mutedUntil = 0;

        // ---- Clusters ----
        const clustersGroup = new Adw.PreferencesGroup({title: 'Clusters'});
        const buffer = new Gtk.TextBuffer();
        const view = new Gtk.TextView({buffer, monospace: true, top_margin: 8, bottom_margin: 8, left_margin: 8, right_margin: 8});
        clustersGroup.add(new Gtk.Frame({child: view, height_request: 100}));
        clustersGroup.add(desc('One kubeconfig per line; the file name becomes the tab name. Alertmanager is detected ' +
            'automatically. To set it by hand, add it after the path: ~/.kube/prod.yml monitoring/alertmanager:9093'));
        page.add(clustersGroup);

        // ---- CI pipelines: no search shows tracked repos, searching shows the first matches ----
        const repoGroup = new Adw.PreferencesGroup({
            title: 'CI pipelines',
            description: 'Lists what your gh (GitHub) and glab (GitLab) logins can see. A repo is added on its default ' +
                'branch; edit its branches field to track more, e.g. main, develop.',
        });
        const search = new Gtk.SearchEntry({placeholder_text: 'Loading repositories from gh and glab…', margin_bottom: 6});
        const list = new Gtk.ListBox({selection_mode: Gtk.SelectionMode.NONE, css_classes: ['boxed-list']});
        const listNote = new Gtk.Label({xalign: 0, css_classes: ['dim-label'], margin_top: 6});
        const history = Adw.SpinRow.new_with_range(0, 20, 1);
        history.set({title: 'Recent runs per repo', subtitle: 'Shown when you open a repo in the menu. 0 hides them.', value: 5});
        const mrs = new Adw.SwitchRow({title: 'Show open merge / pull requests', subtitle: 'With their pipeline status', active: true});
        repoGroup.add(search);
        repoGroup.add(list);
        repoGroup.add(listNote);
        repoGroup.add(history);
        repoGroup.add(mrs);
        page.add(repoGroup);

        // Repos are kind:repo@branch ids; tracked maps kind:repo -> list of branches.
        const base = id => id.replace(/@[^@]*$/, '');
        const tracked = new Map();
        const rows = new Map();   // kind:repo -> row
        let loaded = false;
        const addRow = (id, name, source) => {
            const b = base(id), defBranch = id.split('@').pop();
            if (rows.has(b))
                return;
            const row = new Adw.SwitchRow({title: name, subtitle: `${source}, ${defBranch}`, active: tracked.has(b)});
            const branches = new Gtk.Entry({placeholder_text: 'branches', width_chars: 14, valign: Gtk.Align.CENTER,
                tooltip_text: 'Branches to track, comma-separated, e.g. main, develop',
                text: (tracked.get(b) ?? [defBranch]).join(', '), visible: tracked.has(b)});
            branches.connect('changed', () => {
                const list2 = branches.text.split(',').map(s => s.trim()).filter(s => s);
                if (list2.length && tracked.has(b))
                    tracked.set(b, list2);
            });
            row.connect('notify::active', () => {
                if (row.active && !tracked.has(b))
                    tracked.set(b, [defBranch]);
                else if (!row.active)
                    tracked.delete(b);
                branches.text = (tracked.get(b) ?? [defBranch]).join(', ');
                branches.visible = row.active;
            });
            row.add_suffix(branches);
            rows.set(b, row);
            list.append(row);
        };
        const filter = () => {
            const q = search.text.trim().toLowerCase();
            let shown = 0, matches = 0;
            for (const [b, row] of rows) {
                const match = q ? repoName(b).toLowerCase().includes(q) : tracked.has(b);
                if (match)
                    matches++;
                row.visible = match && (!q || shown < MAX_MATCHES);
                if (row.visible)
                    shown++;
            }
            list.visible = shown > 0;
            listNote.label = q
                ? (matches === 0 ? (loaded ? 'No matches' : 'Still loading…')
                    : matches > MAX_MATCHES ? `${matches - MAX_MATCHES} more, refine your search` : '')
                : (tracked.size === 0 ? 'None yet. Search above to add repositories.' : '');
            listNote.visible = listNote.label !== '';
        };
        search.connect('search-changed', filter);

        // ---- Notify me when ----
        const rulesGroup = new Adw.PreferencesGroup({
            title: 'Notify me when',
            description: 'Each problem is sent once when it starts and once when it is resolved. ' +
                'Node CPU and RAM only count as resolved 5 points below the limit, so a node at the edge does not flap.',
        });
        const ruleRows = {}, limitSpins = {};
        for (const r of RULES) {
            const row = new Adw.SwitchRow({title: r.text, active: true});
            if (r.limit) {
                const spin = Gtk.SpinButton.new_with_range(1, 100, 1);
                spin.set({value: r.def, valign: Gtk.Align.CENTER});
                row.bind_property('active', spin, 'sensitive', 2 /* SYNC_CREATE */);
                row.add_suffix(spin);
                limitSpins[r.limit] = spin;
            }
            ruleRows[r.key] = row;
            rulesGroup.add(row);
        }
        page.add(rulesGroup);

        // ---- Delivery ----
        const deliveryGroup = new Adw.PreferencesGroup({
            title: 'Delivery',
            description: 'Messages are sent from this computer, so they stop while it is off or asleep.',
        });
        const desktop = new Adw.SwitchRow({title: 'Desktop notifications', active: true});
        const mute = new Adw.ComboRow({title: 'Mute', model: Gtk.StringList.new(MUTES.map(m => m[0]))});
        const tgToken = new Adw.PasswordEntryRow({title: 'Telegram bot token (from @BotFather)'});
        const tgChat = new Adw.EntryRow({title: 'Telegram chat id'});
        const slack = new Adw.PasswordEntryRow({title: 'Slack webhook URL'});
        const mattermost = new Adw.PasswordEntryRow({title: 'Mattermost webhook URL'});
        const discord = new Adw.PasswordEntryRow({title: 'Discord webhook URL'});
        for (const w of [desktop, mute, tgToken, tgChat, slack, mattermost, discord])
            deliveryGroup.add(w);
        page.add(deliveryGroup);

        const save = async () => {
            const lines = RULES.map(r => `NOTIFY_${r.key}=${ruleRows[r.key].active ? 1 : 0}`)
                .concat(Object.entries(limitSpins).map(([k, s]) => `${k}=${s.get_value_as_int()}`))
                .concat([`PIPE_HISTORY=${history.value}`, `PIPE_MRS=${mrs.active ? 1 : 0}`])
                .concat([`NOTIFY_DESKTOP=${desktop.active ? 1 : 0}`,
                    `TG_TOKEN=${tgToken.text.trim()}`, `TG_CHAT=${tgChat.text.trim()}`,
                    `SLACK_WEBHOOK=${slack.text.trim()}`, `MATTERMOST_WEBHOOK=${mattermost.text.trim()}`,
                    `DISCORD_WEBHOOK=${discord.text.trim()}`]);
            await run(['--set', '-'], `${lines.join('\n')}\n`);
            await run(['--clusters'], `${buffer.text.trim()}\n`);
            await run(['--repos'], `${[...tracked].flatMap(([b, brs]) => brs.map(br => `${b}@${br}`)).join('\n')}\n`);
            if (mute.selected > 0 || mutedUntil !== 0)
                await run(['--mute', MUTES[mute.selected][1]]);
            GLib.spawn_command_line_async('systemctl --user start kube-health.service --no-block');
        };

        // ---- Actions ----
        const actions = new Adw.PreferencesGroup();
        const result = new Gtk.Label({wrap: true, xalign: 0, selectable: true, css_classes: ['monospace']});
        const box = new Gtk.Box({spacing: 12, halign: Gtk.Align.END, margin_top: 12});
        const testBtn = new Gtk.Button({label: 'Save and send test message'});
        const saveBtn = new Gtk.Button({label: 'Save', css_classes: ['suggested-action']});
        testBtn.connect('clicked', () => {
            result.label = 'Sending…';
            save().then(() => run(['--test'])).then(out => {
                result.label = out.trim() || 'No notification targets configured';
            });
        });
        saveBtn.connect('clicked', () => save().then(() => window.add_toast(new Adw.Toast({title: 'Saved'}))));
        box.append(testBtn);
        box.append(saveBtn);
        actions.add(box);
        actions.add(result);
        page.add(actions);

        // Load current settings, then the (slower) repository list.
        run(['--get']).then(out => {
            const s = JSON.parse(out), v = s.settings;
            buffer.text = s.clusters.trim();
            for (const r of RULES)
                ruleRows[r.key].active = v[`NOTIFY_${r.key}`] !== '0';
            for (const r of RULES.filter(x => x.limit))
                limitSpins[r.limit].value = parseInt(v[r.limit] || `${r.def}`);
            desktop.active = v.NOTIFY_DESKTOP !== '0';
            history.value = parseInt(v.PIPE_HISTORY || '5');
            mrs.active = v.PIPE_MRS !== '0';
            tgToken.text = v.TG_TOKEN || '';
            tgChat.text = v.TG_CHAT || '';
            slack.text = v.SLACK_WEBHOOK || '';
            mattermost.text = v.MATTERMOST_WEBHOOK || '';
            discord.text = v.DISCORD_WEBHOOK || '';
            mutedUntil = s.muted_until;
            mute.subtitle = mutedUntil === -1 ? 'Muted until you unmute'
                : mutedUntil > 0 ? `Muted until ${GLib.DateTime.new_from_unix_local(mutedUntil).format('%H:%M')}` : '';
            for (const id of s.repos)
                tracked.set(base(id), (tracked.get(base(id)) ?? []).concat([id.split('@').pop()]));
            for (const id of s.repos)
                addRow(id, repoName(id), id.split(':')[0]);
            filter();
            return run(['--list-repos']);
        }).then(out => {
            const repos = JSON.parse(out);
            for (const r of repos)
                addRow(r.id, r.name, r.source);
            loaded = true;
            search.placeholder_text = `Search ${repos.length} repositories`;
            filter();
        }).catch(() => window.add_toast(new Adw.Toast({title: `Could not load settings: is ${BIN} installed?`})));
    }
}
