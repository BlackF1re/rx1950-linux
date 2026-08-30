/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Small, extensible GPE-style control center for the HP iPAQ rx1950. */
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

#define CONTROL "/usr/sbin/rx1950-control"

typedef void (*PageFunc)(GtkWidget *parent);
typedef struct { const char *id, *title, *icon; PageFunc open; } Applet;

static gchar *runv(const gchar *a, const gchar *b, const gchar *c,
                   const gchar *d, GError **error)
{
    gchar *out = NULL, *err = NULL;
    gint status = 0;
    gchar *argv[] = {(gchar *)CONTROL, (gchar *)a, (gchar *)b,
                    (gchar *)c, (gchar *)d, NULL};
    gint n = 1;
    while (n < 5 && argv[n]) n++;
    argv[n] = NULL;
    if (!g_spawn_sync(NULL, argv, NULL, 0, NULL, NULL, &out, &err,
                      &status, error) || status != 0) {
        if (!*error)
            g_set_error(error, G_SPAWN_ERROR, G_SPAWN_ERROR_FAILED, "%s",
                        (err && *err) ? err : "Command failed");
        g_free(out);
        out = NULL;
    }
    g_free(err);
    return out;
}

static void error_box(GtkWindow *parent, const gchar *message)
{
    GtkWidget *d = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL,
        GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "%s", message);
    gtk_dialog_run(GTK_DIALOG(d));
    gtk_widget_destroy(d);
}

static gchar *run(GtkWindow *parent, const gchar *a, const gchar *b,
                  const gchar *c, const gchar *d)
{
    GError *e = NULL;
    gchar *out = runv(a, b, c, d, &e);
    if (e) { error_box(parent, e->message); g_error_free(e); }
    return out;
}

static GtkWidget *page(GtkWidget *parent, const gchar *title)
{
    GtkWidget *w = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GtkWidget *v = gtk_vbox_new(FALSE, 7);
    gtk_window_set_title(GTK_WINDOW(w), title);
    gtk_window_set_default_size(GTK_WINDOW(w), 238, 270);
    gtk_window_set_transient_for(GTK_WINDOW(w), GTK_WINDOW(parent));
    gtk_container_set_border_width(GTK_CONTAINER(v), 8);
    gtk_container_add(GTK_CONTAINER(w), v);
    g_object_set_data(G_OBJECT(w), "box", v);
    return w;
}

static GtkWidget *button(GtkWidget *box, const gchar *label,
                         GCallback cb, gpointer data)
{
    GtkWidget *b = gtk_button_new_with_label(label);
    gtk_widget_set_size_request(b, -1, 38);
    g_signal_connect(b, "clicked", cb, data);
    gtk_box_pack_start(GTK_BOX(box), b, FALSE, FALSE, 0);
    return b;
}

static void action_cb(GtkButton *unused, gpointer data)
{
    GtkWidget *w = GTK_WIDGET(data);
    const gchar *action = g_object_get_data(G_OBJECT(w), "action");
    gchar *out;
    (void)unused;
    out = run(GTK_WINDOW(w), action, NULL, NULL, NULL);
    g_free(out);
}

static void wifi_connect(GtkButton *unused, gpointer data)
{
    GtkWidget *w = GTK_WIDGET(data), *d, *box, *combo, *secure, *pass;
    gchar *scan, **names, *ssid = NULL, *out;
    gint i;
    (void)unused;
    scan = run(GTK_WINDOW(w), "wifi-scan", NULL, NULL, NULL);
    if (!scan) return;
    d = gtk_dialog_new_with_buttons("Connect to Wi-Fi", GTK_WINDOW(w),
        GTK_DIALOG_MODAL, GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL,
        GTK_STOCK_OK, GTK_RESPONSE_OK, NULL);
    box = GTK_DIALOG(d)->vbox;
    combo = gtk_combo_box_new_text();
    names = g_strsplit(scan, "\n", -1);
    for (i = 0; names[i]; i++) if (*names[i]) gtk_combo_box_append_text(GTK_COMBO_BOX(combo), names[i]);
    gtk_combo_box_set_active(GTK_COMBO_BOX(combo), 0);
    secure = gtk_check_button_new_with_label("WPA/WPA2 protected");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(secure), TRUE);
    pass = gtk_entry_new();
    gtk_entry_set_visibility(GTK_ENTRY(pass), FALSE);
    gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 4);
    gtk_box_pack_start(GTK_BOX(box), secure, FALSE, FALSE, 4);
    gtk_box_pack_start(GTK_BOX(box), pass, FALSE, FALSE, 4);
    gtk_widget_show_all(d);
    if (gtk_dialog_run(GTK_DIALOG(d)) == GTK_RESPONSE_OK) {
        ssid = gtk_combo_box_get_active_text(GTK_COMBO_BOX(combo));
        if (ssid) {
            if (gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(secure)))
                out = run(GTK_WINDOW(w), "wifi-psk", ssid,
                          gtk_entry_get_text(GTK_ENTRY(pass)), NULL);
            else out = run(GTK_WINDOW(w), "wifi-open", ssid, NULL, NULL);
            if (out) {
                GtkWidget *m = gtk_message_dialog_new(GTK_WINDOW(w), GTK_DIALOG_MODAL,
                    GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE, "%s", out);
                gtk_dialog_run(GTK_DIALOG(m)); gtk_widget_destroy(m); g_free(out);
            }
            g_free(ssid);
        }
    }
    gtk_widget_destroy(d); g_strfreev(names); g_free(scan);
}

static void open_wifi(GtkWidget *parent)
{
    GtkWidget *w = page(parent, "Wi-Fi"), *v = g_object_get_data(G_OBJECT(w), "box"), *l;
    gchar *s = run(GTK_WINDOW(w), "wifi-status", NULL, NULL, NULL);
    l = gtk_label_new(s ? s : "Wi-Fi unavailable");
    gtk_label_set_line_wrap(GTK_LABEL(l), TRUE);
    gtk_box_pack_start(GTK_BOX(v), l, TRUE, TRUE, 0); g_free(s);
    button(v, "Scan and connect", G_CALLBACK(wifi_connect), w);
    g_object_set_data(G_OBJECT(w), "action", "wifi-disconnect");
    button(v, "Disconnect", G_CALLBACK(action_cb), w);
    gtk_widget_show_all(w);
}

static void scale_changed(GtkRange *range, gpointer data)
{
    GtkWidget *w = gtk_widget_get_toplevel(GTK_WIDGET(range));
    const gchar *kind = data;
    gchar value[8];
    g_snprintf(value, sizeof(value), "%d", (int)gtk_range_get_value(range));
    gchar *out = run(GTK_WINDOW(w), kind, value, NULL, NULL); g_free(out);
}

static void open_scale(GtkWidget *parent, const gchar *title, const gchar *get,
                       const gchar *set)
{
    GtkWidget *w = page(parent, title), *v = g_object_get_data(G_OBJECT(w), "box"), *s;
    gchar *cur = run(GTK_WINDOW(w), get, NULL, NULL, NULL);
    s = gtk_hscale_new_with_range(0, 100, 5);
    gtk_range_set_value(GTK_RANGE(s), cur ? atoi(cur) : 50);
    gtk_scale_set_value_pos(GTK_SCALE(s), GTK_POS_TOP);
    gtk_box_pack_start(GTK_BOX(v), s, FALSE, FALSE, 18);
    g_signal_connect(s, "value-changed", G_CALLBACK(scale_changed), (gpointer)set);
    g_free(cur); gtk_widget_show_all(w);
}

static void open_display(GtkWidget *p) { open_scale(p, "Display", "brightness-get", "brightness-set"); }
static void open_sound(GtkWidget *p) { open_scale(p, "Sound", "volume-get", "volume-set"); }

static void theme_changed(GtkComboBox *combo, gpointer data)
{
    GtkWidget *w = GTK_WIDGET(data);
    gchar *theme = gtk_combo_box_get_active_text(combo);
    gchar *out = run(GTK_WINDOW(w), "theme", theme, NULL, NULL);
    g_free(out); g_free(theme);
}

static void open_appearance(GtkWidget *parent)
{
    static const char *themes[] = {"MBOpus", "Default", "blondie", NULL};
    GtkWidget *w = page(parent, "Appearance"), *v = g_object_get_data(G_OBJECT(w), "box"), *c, *l;
    gchar *cur = run(GTK_WINDOW(w), "theme-get", NULL, NULL, NULL); gint i, active = 0;
    gtk_box_pack_start(GTK_BOX(v), gtk_label_new("Window theme"), FALSE, FALSE, 3);
    c = gtk_combo_box_new_text();
    for (i = 0; themes[i]; i++) {
        gtk_combo_box_append_text(GTK_COMBO_BOX(c), themes[i]);
        if (cur && !g_strcmp0(g_strstrip(cur), themes[i])) active = i;
    }
    gtk_combo_box_set_active(GTK_COMBO_BOX(c), active);
    gtk_box_pack_start(GTK_BOX(v), c, FALSE, FALSE, 3);
    g_signal_connect(c, "changed", G_CALLBACK(theme_changed), w);
    l = gtk_label_new("Changes apply immediately and persist after reboot.");
    gtk_label_set_line_wrap(GTK_LABEL(l), TRUE);
    gtk_box_pack_start(GTK_BOX(v), l, FALSE, FALSE, 8);
    g_free(cur); gtk_widget_show_all(w);
}

static void keyboard_changed(GtkComboBox *combo, gpointer data)
{
    GtkWidget *w = GTK_WIDGET(data);
    gchar *layout = gtk_combo_box_get_active_text(combo);
    gchar *out = run(GTK_WINDOW(w), "keyboard", layout, NULL, NULL);
    g_free(out); g_free(layout);
}

static void open_keyboard(GtkWidget *parent)
{
    static const char *layouts[] = {"us", "ru", "fr", "fi", "dvorak", "extended", "numpad", NULL};
    GtkWidget *w = page(parent, "Keyboard"), *v = g_object_get_data(G_OBJECT(w), "box"), *c;
    gchar *cur = run(GTK_WINDOW(w), "keyboard-get", NULL, NULL, NULL); gint i, active = 0;
    c = gtk_combo_box_new_text();
    for (i = 0; layouts[i]; i++) { gtk_combo_box_append_text(GTK_COMBO_BOX(c), layouts[i]); if (cur && !g_strcmp0(g_strstrip(cur), layouts[i])) active=i; }
    gtk_combo_box_set_active(GTK_COMBO_BOX(c), active);
    gtk_box_pack_start(GTK_BOX(v), gtk_label_new("On-screen keyboard layout"), FALSE, FALSE, 3);
    gtk_box_pack_start(GTK_BOX(v), c, FALSE, FALSE, 3);
    g_signal_connect(c, "changed", G_CALLBACK(keyboard_changed), w);
    g_object_set_data(G_OBJECT(w), "action", "keyboard-toggle");
    button(v, "Show / hide keyboard", G_CALLBACK(action_cb), w);
    g_free(cur); gtk_widget_show_all(w);
}

static const char *key_names[] = {"KEY_POWER", "KEY_F1", "KEY_F2", "KEY_F3", "KEY_F4", "KEY_F5", NULL};
static const char *key_actions[] = {
    "", "/usr/bin/rx1950-launch /usr/bin/gpe-conf",
    "/usr/bin/rx1950-launch /usr/bin/gpe-conf wifi",
    "/usr/bin/rx1950-launch /usr/bin/xcalc",
    "/usr/bin/rx1950-launch /usr/bin/xedit",
    "/usr/bin/rx1950-launch /usr/bin/mb-applet-xterm-wrapper.sh",
    "/usr/bin/rx1950-keyboard toggle", "/usr/sbin/rx1950-control suspend", NULL
};
static void keys_save(GtkButton *unused, gpointer data)
{
    GtkWidget *w = GTK_WIDGET(data); gint i; gchar *out;
    (void)unused;
    for (i=0; key_names[i]; i++) {
        GtkWidget *e = g_object_get_data(G_OBJECT(w), key_names[i]);
        out = run(GTK_WINDOW(w), "key-set", key_names[i], gtk_entry_get_text(GTK_ENTRY(e)), NULL);
        g_free(out);
    }
    out = run(GTK_WINDOW(w), "key-reload", NULL, NULL, NULL);
    g_free(out);
}

static void confirmed_action(GtkButton *unused, gpointer data)
{
    GtkWidget *w = gtk_widget_get_toplevel(GTK_WIDGET(unused));
    const gchar *action = data;
    GtkWidget *d = gtk_message_dialog_new(GTK_WINDOW(w), GTK_DIALOG_MODAL,
        GTK_MESSAGE_QUESTION, GTK_BUTTONS_OK_CANCEL,
        "Really %s the device?", !strcmp(action, "reboot") ? "restart" : "power off");
    if (gtk_dialog_run(GTK_DIALOG(d)) == GTK_RESPONSE_OK) {
        gchar *out = run(GTK_WINDOW(w), action, NULL, NULL, NULL);
        g_free(out);
    }
    gtk_widget_destroy(d);
}

static void open_keys(GtkWidget *parent)
{
    GtkWidget *w = page(parent, "Hardware buttons"), *v = g_object_get_data(G_OBJECT(w), "box"), *t;
    gint i; t = gtk_table_new(6, 2, FALSE);
    for (i=0; key_names[i]; i++) {
        GtkWidget *l = gtk_label_new(key_names[i]+4), *c = gtk_combo_box_entry_new_text(), *e;
        gint j;
        gchar *cur = run(GTK_WINDOW(w), "key-get", key_names[i], NULL, NULL);
        for (j = 0; key_actions[j]; j++) gtk_combo_box_append_text(GTK_COMBO_BOX(c), key_actions[j]);
        e = gtk_bin_get_child(GTK_BIN(c));
        if (cur) gtk_entry_set_text(GTK_ENTRY(e), g_strstrip(cur));
        gtk_table_attach(GTK_TABLE(t), l, 0, 1, i, i+1, GTK_FILL, GTK_FILL, 3, 2);
        gtk_table_attach(GTK_TABLE(t), c, 1, 2, i, i+1, GTK_EXPAND|GTK_FILL, GTK_FILL, 3, 2);
        g_object_set_data(G_OBJECT(w), key_names[i], e); g_free(cur);
    }
    gtk_box_pack_start(GTK_BOX(v), t, TRUE, TRUE, 0);
    button(v, "Save assignments", G_CALLBACK(keys_save), w); gtk_widget_show_all(w);
}

static void blank_changed(GtkComboBox *combo, gpointer data)
{
    static const char *values[] = {"0", "30", "60", "120", "300"};
    GtkWidget *w = GTK_WIDGET(data); gint i = gtk_combo_box_get_active(combo);
    gchar *out = run(GTK_WINDOW(w), "blank-set", values[i < 0 ? 0 : i], NULL, NULL); g_free(out);
}

static void open_power(GtkWidget *parent)
{
    GtkWidget *w = page(parent, "Power and battery"), *v = g_object_get_data(G_OBJECT(w), "box"), *l, *c, *h;
    gchar *info = run(GTK_WINDOW(w), "power-info", NULL, NULL, NULL);
    l = gtk_label_new(info ? info : "Battery data unavailable"); gtk_label_set_line_wrap(GTK_LABEL(l), TRUE);
    gtk_box_pack_start(GTK_BOX(v), l, FALSE, FALSE, 2); g_free(info);
    c = gtk_combo_box_new_text();
    gtk_combo_box_append_text(GTK_COMBO_BOX(c), "Never blank"); gtk_combo_box_append_text(GTK_COMBO_BOX(c), "30 seconds");
    gtk_combo_box_append_text(GTK_COMBO_BOX(c), "1 minute"); gtk_combo_box_append_text(GTK_COMBO_BOX(c), "2 minutes");
    gtk_combo_box_append_text(GTK_COMBO_BOX(c), "5 minutes"); gtk_combo_box_set_active(GTK_COMBO_BOX(c), 2);
    gtk_box_pack_start(GTK_BOX(v), c, FALSE, FALSE, 2); g_signal_connect(c, "changed", G_CALLBACK(blank_changed), w);
    g_object_set_data(G_OBJECT(w), "action", "suspend"); button(v, "Suspend", G_CALLBACK(action_cb), w);
    h = gtk_hbox_new(TRUE, 4);
    button(h, "Restart", G_CALLBACK(confirmed_action), "reboot");
    button(h, "Shut down", G_CALLBACK(confirmed_action), "poweroff");
    gtk_box_pack_start(GTK_BOX(v), h, FALSE, FALSE, 0);
    gtk_widget_show_all(w);
}

static void timezone_apply(GtkButton *unused, gpointer data)
{
    GtkWidget *w = gtk_widget_get_toplevel(GTK_WIDGET(unused));
    const gchar *zone = gtk_entry_get_text(GTK_ENTRY(data));
    gchar *out = run(GTK_WINDOW(w), "timezone", zone, NULL, NULL); g_free(out);
}

static void open_time(GtkWidget *parent)
{
    GtkWidget *w = page(parent, "Date and time"), *v = g_object_get_data(G_OBJECT(w), "box"), *e;
    gchar *zone = run(GTK_WINDOW(w), "timezone-get", NULL, NULL, NULL);
    e = gtk_entry_new(); gtk_entry_set_text(GTK_ENTRY(e), zone ? g_strstrip(zone) : "Etc/UTC");
    gtk_box_pack_start(GTK_BOX(v), gtk_label_new("Timezone (for example Asia/Tomsk)"), FALSE, FALSE, 2);
    gtk_box_pack_start(GTK_BOX(v), e, FALSE, FALSE, 2);
    button(v, "Apply timezone", G_CALLBACK(timezone_apply), e);
    g_object_set_data(G_OBJECT(w), "action", "time-sync"); button(v, "Synchronize clock", G_CALLBACK(action_cb), w);
    g_free(zone); gtk_widget_show_all(w);
}

static void open_info(GtkWidget *parent)
{
    GtkWidget *w = page(parent, "System information"), *v = g_object_get_data(G_OBJECT(w), "box"), *view, *sw;
    GtkTextBuffer *buf; gchar *s = run(GTK_WINDOW(w), "status", NULL, NULL, NULL);
    view = gtk_text_view_new(); gtk_text_view_set_editable(GTK_TEXT_VIEW(view), FALSE); gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
    buf = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)); gtk_text_buffer_set_text(buf, s ? s : "Unavailable", -1);
    sw = gtk_scrolled_window_new(NULL, NULL); gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(sw), view); gtk_box_pack_start(GTK_BOX(v), sw, TRUE, TRUE, 0); g_free(s); gtk_widget_show_all(w);
}

static void open_calibrate(GtkWidget *parent)
{
    GError *e = NULL; gchar *argv[] = {(gchar *)CONTROL, "calibrate", NULL};
    if (!g_spawn_async(NULL, argv, NULL, 0, NULL, NULL, NULL, &e)) { error_box(GTK_WINDOW(parent), e->message); g_error_free(e); }
}

static Applet applets[] = {
    {"wifi", "Wi-Fi", "network-wireless", open_wifi}, {"display", "Display", "video-display", open_display},
    {"sound", "Sound", "audio-volume-high", open_sound}, {"appearance", "Appearance", "preferences-desktop-theme", open_appearance},
    {"keyboard", "Keyboard", "input-keyboard", open_keyboard},
    {"keys", "Buttons", "preferences-desktop-keyboard-shortcuts", open_keys}, {"power", "Power", "battery", open_power},
    {"time", "Date / time", "appointment", open_time}, {"info", "System", "computer", open_info},
    {"calibrate", "Touchscreen", "input-mouse", open_calibrate},
    {NULL, NULL, NULL, NULL}
};

static GtkWidget *main_window;
static void applet_clicked(GtkButton *unused, gpointer data) { (void)unused; ((Applet *)data)->open(main_window); }

int main(int argc, char **argv)
{
    GtkWidget *table; gint i;
    gtk_init(&argc, &argv);
    main_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(main_window), "rx1950 Control Center");
    gtk_window_set_default_size(GTK_WINDOW(main_window), 238, 270);
    g_signal_connect(main_window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    table = gtk_table_new(5, 2, TRUE); gtk_container_set_border_width(GTK_CONTAINER(table), 6);
    for (i=0; applets[i].id; i++) {
        GtkWidget *b = gtk_button_new_with_label(applets[i].title);
        gtk_widget_set_size_request(b, 108, 55); g_signal_connect(b, "clicked", G_CALLBACK(applet_clicked), &applets[i]);
        gtk_table_attach_defaults(GTK_TABLE(table), b, i%2, i%2+1, i/2, i/2+1);
    }
    gtk_container_add(GTK_CONTAINER(main_window), table); gtk_widget_show_all(main_window);
    if (argc > 1) for (i=0; applets[i].id; i++) if (!strcmp(argv[1], applets[i].id)) { applets[i].open(main_window); break; }
    gtk_main(); return 0;
}
