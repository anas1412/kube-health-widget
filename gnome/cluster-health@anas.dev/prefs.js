import Adw from 'gi://Adw';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

// Same files the cluster-health checker reads, so KDE and GNOME share one config.
const DIR = GLib.build_filenamev([GLib.get_user_config_dir(), 'cluster-health']);
const path = f => GLib.build_filenamev([DIR, f]);
const read = f => {
    try {
        return new TextDecoder().decode(GLib.file_get_contents(path(f))[1]);
    } catch (e) {
        return '';
    }
};

export default class ClusterHealthPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const page = new Adw.PreferencesPage();
        window.add(page);

        const clustersGroup = new Adw.PreferencesGroup({
            title: 'Clusters',
            description: 'Kubeconfig files, one path per line. The tab name is the file name.',
        });
        const buffer = new Gtk.TextBuffer({text: read('clusters').trim()});
        const view = new Gtk.TextView({buffer, monospace: true, top_margin: 8, bottom_margin: 8, left_margin: 8, right_margin: 8});
        const frame = new Gtk.Frame({child: view, height_request: 120});
        clustersGroup.add(frame);
        page.add(clustersGroup);

        const tg = read('telegram.env');
        const get = k => ((tg.match(new RegExp(`^${k}=(.*)$`, 'm')) || [])[1] || '').trim();
        const tgGroup = new Adw.PreferencesGroup({
            title: 'Telegram',
            description: 'Create a bot with @BotFather, message it once, then read the chat id from api.telegram.org/bot<TOKEN>/getUpdates.',
        });
        const token = new Adw.PasswordEntryRow({title: 'Bot token', text: get('TG_TOKEN')});
        const chat = new Adw.EntryRow({title: 'Chat id', text: get('TG_CHAT')});
        tgGroup.add(token);
        tgGroup.add(chat);
        page.add(tgGroup);

        const save = new Gtk.Button({label: 'Save', css_classes: ['suggested-action'], halign: Gtk.Align.END, margin_top: 12});
        save.connect('clicked', () => {
            GLib.mkdir_with_parents(DIR, 0o755);
            GLib.file_set_contents(path('clusters'), `${buffer.text.trim()}\n`);
            GLib.file_set_contents(path('telegram.env'), `TG_TOKEN=${token.text.trim()}\nTG_CHAT=${chat.text.trim()}\n`);
            GLib.chmod(path('telegram.env'), 0o600);
            GLib.spawn_command_line_async('systemctl --user start cluster-health.service --no-block');
            window.add_toast(new Adw.Toast({title: 'Saved'}));
        });
        tgGroup.add(save);
    }
}
