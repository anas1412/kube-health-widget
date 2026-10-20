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

function run(args, input = null) {
    const flags = Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE |
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

export default class KubeHealthPrefs extends ExtensionPreferences {
    async fillPreferencesWindow(window) {
        let s = {clusters: '', settings: {}, muted_until: 0};
        try {
            s = JSON.parse(await run(['--get']));
        } catch (e) {
            window.add_toast(new Adw.Toast({title: `Could not load settings: is ${BIN} installed?`}));
        }
        const v = s.settings;

        const page = new Adw.PreferencesPage({title: 'General', icon_name: 'preferences-system-symbolic'});
        window.add(page);

        // Clusters
        const clustersGroup = new Adw.PreferencesGroup({title: 'Clusters'});
        const buffer = new Gtk.TextBuffer({text: s.clusters.trim()});
        const view = new Gtk.TextView({buffer, monospace: true, top_margin: 8, bottom_margin: 8, left_margin: 8, right_margin: 8});
        clustersGroup.add(new Gtk.Frame({child: view, height_request: 110}));
        clustersGroup.add(desc('One kubeconfig per line; the file name becomes the tab name. Alertmanager is detected ' +
            'automatically. To set it by hand, add it after the path: ~/.kube/prod.yml monitoring/alertmanager:9093'));
        page.add(clustersGroup);

        // Notifications
        const notifyGroup = new Adw.PreferencesGroup({title: 'Notifications'});
        const desktop = new Adw.SwitchRow({title: 'Desktop notifications', active: v.NOTIFY_DESKTOP !== '0'});
        const healthMin = Adw.SpinRow.new_with_range(0, 100, 1);
        healthMin.set({title: 'Notify when pod health is below (%)', value: parseInt(v.HEALTH_MIN || '95')});
        const muteNote = s.muted_until === -1 ? 'Muted until you unmute'
            : s.muted_until > 0 ? `Muted until ${GLib.DateTime.new_from_unix_local(s.muted_until).format('%H:%M')}` : '';
        const mute = new Adw.ComboRow({title: 'Mute', subtitle: muteNote, model: Gtk.StringList.new(MUTES.map(m => m[0]))});
        notifyGroup.add(desktop);
        notifyGroup.add(healthMin);
        notifyGroup.add(mute);
        page.add(notifyGroup);

        // Telegram
        const tgGroup = new Adw.PreferencesGroup({
            title: 'Telegram',
            description: 'Create a bot with @BotFather, message it once, then read message.chat.id from api.telegram.org/bot<TOKEN>/getUpdates.',
        });
        const tgToken = new Adw.PasswordEntryRow({title: 'Bot token', text: v.TG_TOKEN || ''});
        const tgChat = new Adw.EntryRow({title: 'Chat id', text: v.TG_CHAT || ''});
        tgGroup.add(tgToken);
        tgGroup.add(tgChat);
        page.add(tgGroup);

        // Webhooks
        const hookGroup = new Adw.PreferencesGroup({
            title: 'Webhooks',
            description: 'Messages are sent from this computer, so they stop while it is off or asleep.',
        });
        const slack = new Adw.PasswordEntryRow({title: 'Slack webhook URL', text: v.SLACK_WEBHOOK || ''});
        const mattermost = new Adw.PasswordEntryRow({title: 'Mattermost webhook URL', text: v.MATTERMOST_WEBHOOK || ''});
        const discord = new Adw.PasswordEntryRow({title: 'Discord webhook URL', text: v.DISCORD_WEBHOOK || ''});
        hookGroup.add(slack);
        hookGroup.add(mattermost);
        hookGroup.add(discord);
        page.add(hookGroup);

        const save = async () => {
            await run(['--set', '-'], [
                `NOTIFY_DESKTOP=${desktop.active ? 1 : 0}`, `HEALTH_MIN=${healthMin.value}`,
                `TG_TOKEN=${tgToken.text.trim()}`, `TG_CHAT=${tgChat.text.trim()}`,
                `SLACK_WEBHOOK=${slack.text.trim()}`, `MATTERMOST_WEBHOOK=${mattermost.text.trim()}`,
                `DISCORD_WEBHOOK=${discord.text.trim()}`,
            ].join('\n') + '\n');
            await run(['--clusters'], `${buffer.text.trim()}\n`);
            if (mute.selected > 0 || s.muted_until !== 0)
                await run(['--mute', MUTES[mute.selected][1]]);
            GLib.spawn_command_line_async('systemctl --user start kube-health.service --no-block');
        };

        // Actions
        const actions = new Adw.PreferencesGroup();
        const result = new Gtk.Label({wrap: true, xalign: 0, selectable: true, css_classes: ['monospace']});
        const box = new Gtk.Box({spacing: 12, halign: Gtk.Align.END, margin_top: 12});
        const testBtn = new Gtk.Button({label: 'Save and send test message'});
        const saveBtn = new Gtk.Button({label: 'Save', css_classes: ['suggested-action']});
        testBtn.connect('clicked', async () => {
            result.label = 'Sending…';
            await save();
            result.label = (await run(['--test'])).trim() || 'No notification targets configured';
        });
        saveBtn.connect('clicked', async () => {
            await save();
            window.add_toast(new Adw.Toast({title: 'Saved'}));
        });
        box.append(testBtn);
        box.append(saveBtn);
        actions.add(box);
        actions.add(result);
        page.add(actions);
    }
}
