/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Touch-oriented, on-demand control center for the HP iPAQ rx1950. */
#include <gtk/gtk.h>
#include <stdlib.h>
#include <string.h>

#define CONTROL "/usr/sbin/rx1950-control"
#define PAGE_W 238
#define PAGE_H 264

typedef void (*PageFunc)(GtkWidget *parent);
typedef struct { const char *id; const char *title; PageFunc open; } Applet;
typedef struct { gchar *key; GtkWidget *entry; } KeyRow;

static GtkWidget *main_window;

static void show_error(GtkWindow *parent, const gchar *message)
{
    GtkWidget *d = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL,
        GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "%s", message ? message : "Operation failed");
    gtk_dialog_run(GTK_DIALOG(d));
    gtk_widget_destroy(d);
}

static void show_info(GtkWindow *parent, const gchar *message)
{
    GtkWidget *d = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL,
        GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE, "%s", message ? message : "Done");
    gtk_dialog_run(GTK_DIALOG(d));
    gtk_widget_destroy(d);
}

static gchar *run_control(GtkWindow *parent, const gchar *a, const gchar *b,
                          const gchar *c, const gchar *d)
{
    gchar *out = NULL, *err = NULL;
    gint status = 0;
    GError *error = NULL;
    gchar *argv[] = {(gchar *)CONTROL, (gchar *)a, (gchar *)b,
                     (gchar *)c, (gchar *)d, NULL};

    if (!g_spawn_sync(NULL, argv, NULL, 0, NULL, NULL, &out, &err, &status, &error) || status != 0) {
        const gchar *message = error ? error->message : ((err && *err) ? err : "The requested operation failed.");
        show_error(parent, message);
        if (error) g_error_free(error);
        g_free(out); out = NULL;
    }
    g_free(err);
    return out;
}

static GtkWidget *page(GtkWidget *parent, const gchar *title, GtkWidget **box)
{
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget *view = gtk_vbox_new(FALSE, 7);
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), PAGE_W, PAGE_H);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
    gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(parent));
    gtk_container_set_border_width(GTK_CONTAINER(view), 8);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_add_with_viewport(GTK_SCROLLED_WINDOW(scroll), view);
    gtk_container_add(GTK_CONTAINER(window), scroll);
    *box = view;
    return window;
}

static GtkWidget *touch_button(GtkWidget *box, const gchar *label, GCallback cb, gpointer data)
{
    GtkWidget *button = gtk_button_new_with_label(label);
    gtk_widget_set_size_request(button, -1, 38);
    g_signal_connect(button, "clicked", cb, data);
    gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
    return button;
}

static GtkWidget *left_label(const gchar *text)
{
    GtkWidget *label = gtk_label_new(text);
    gtk_misc_set_alignment(GTK_MISC(label), 0.0, 0.5);
    gtk_label_set_line_wrap(GTK_LABEL(label), TRUE);
    return label;
}

static void action_cb(GtkButton *button, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data);
    const gchar *action = g_object_get_data(G_OBJECT(button), "action");
    gchar *out = run_control(GTK_WINDOW(window), action, NULL, NULL, NULL);
    g_free(out);
}

static gchar **control_lines(GtkWindow *parent, const gchar *operation)
{
    gchar *out = run_control(parent, operation, NULL, NULL, NULL);
    gchar **lines;
    if (!out) return NULL;
    lines = g_strsplit(out, "\n", -1);
    g_free(out);
    return lines;
}

static GtkWidget *combo_from_lines(gchar **lines, const gchar *current)
{
    GtkWidget *combo = gtk_combo_box_new_text();
    gint i, active = -1, count = 0;
    if (lines) {
        for (i = 0; lines[i]; i++) {
            if (!*lines[i]) continue;
            gtk_combo_box_append_text(GTK_COMBO_BOX(combo), lines[i]);
            if (current && !strcmp(lines[i], current)) active = count;
            count++;
        }
    }
    if (active < 0 && count) active = 0;
    if (active >= 0) gtk_combo_box_set_active(GTK_COMBO_BOX(combo), active);
    return combo;
}

/* Wi-Fi */
static void wifi_country_apply(GtkButton *button, gpointer data)
{
    GtkWidget *entry = GTK_WIDGET(data);
    GtkWidget *window = gtk_widget_get_toplevel(GTK_WIDGET(button));
    gchar *out = run_control(GTK_WINDOW(window), "wifi-country-set", gtk_entry_get_text(GTK_ENTRY(entry)), NULL, NULL);
    g_free(out);
}

static void wifi_connect_cb(GtkButton *button, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data), *dialog, *box, *combo, *secure, *password;
    gchar *scan, **names;
    gint i;
    (void)button;
    scan = run_control(GTK_WINDOW(window), "wifi-scan", NULL, NULL, NULL);
    if (!scan) return;
    dialog = gtk_dialog_new_with_buttons("Connect to Wi-Fi", GTK_WINDOW(window), GTK_DIALOG_MODAL,
        GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL, GTK_STOCK_OK, GTK_RESPONSE_OK, NULL);
    box = GTK_DIALOG(dialog)->vbox;
    combo = gtk_combo_box_new_text();
    names = g_strsplit(scan, "\n", -1);
    for (i = 0; names[i]; i++) if (*names[i]) gtk_combo_box_append_text(GTK_COMBO_BOX(combo), names[i]);
    gtk_combo_box_set_active(GTK_COMBO_BOX(combo), 0);
    secure = gtk_check_button_new_with_label("WPA/WPA2 protected");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(secure), TRUE);
    password = gtk_entry_new();
    gtk_entry_set_visibility(GTK_ENTRY(password), FALSE);
    gtk_box_pack_start(GTK_BOX(box), left_label("Network"), FALSE, FALSE, 2);
    gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 2);
    gtk_box_pack_start(GTK_BOX(box), secure, FALSE, FALSE, 2);
    gtk_box_pack_start(GTK_BOX(box), left_label("Password"), FALSE, FALSE, 2);
    gtk_box_pack_start(GTK_BOX(box), password, FALSE, FALSE, 2);
    gtk_widget_show_all(dialog);
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_OK) {
        gchar *ssid = gtk_combo_box_get_active_text(GTK_COMBO_BOX(combo));
        if (ssid && *ssid) {
            gchar *out = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(secure)) ?
                run_control(GTK_WINDOW(window), "wifi-psk", ssid, gtk_entry_get_text(GTK_ENTRY(password)), NULL) :
                run_control(GTK_WINDOW(window), "wifi-open", ssid, NULL, NULL);
            if (out && *out) show_info(GTK_WINDOW(window), out);
            g_free(out);
        }
        g_free(ssid);
    }
    gtk_widget_destroy(dialog); g_strfreev(names); g_free(scan);
}

static void open_wifi(GtkWidget *parent)
{
    GtkWidget *window, *box, *country, *disconnect;
    gchar *status, *cc;
    window = page(parent, "Wi-Fi", &box);
    status = run_control(GTK_WINDOW(window), "wifi-status", NULL, NULL, NULL);
    gtk_box_pack_start(GTK_BOX(box), left_label(status ? status : "Wi-Fi unavailable"), FALSE, FALSE, 0); g_free(status);
    gtk_box_pack_start(GTK_BOX(box), left_label("Regulatory country (ISO code; blank = kernel/world default)"), FALSE, FALSE, 0);
    country = gtk_entry_new(); cc = run_control(GTK_WINDOW(window), "wifi-country-get", NULL, NULL, NULL);
    if (cc) gtk_entry_set_text(GTK_ENTRY(country), g_strstrip(cc));
    gtk_entry_set_max_length(GTK_ENTRY(country), 2);
    gtk_box_pack_start(GTK_BOX(box), country, FALSE, FALSE, 0);
    touch_button(box, "Apply country", G_CALLBACK(wifi_country_apply), country);
    touch_button(box, "Scan and connect", G_CALLBACK(wifi_connect_cb), window);
    disconnect = touch_button(box, "Disconnect", G_CALLBACK(action_cb), window);
    g_object_set_data(G_OBJECT(disconnect), "action", "wifi-disconnect");
    g_free(cc); gtk_widget_show_all(window);
}

/* Display and global scale */
static void brightness_changed_cb(GtkRange *range, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar value[8], *out;
    g_snprintf(value, sizeof(value), "%d", (int)gtk_range_get_value(range));
    out = run_control(GTK_WINDOW(window), "brightness-set", value, NULL, NULL); g_free(out);
}

static void dpi_apply_cb(GtkButton *button, gpointer data)
{
    GtkWidget *spin = GTK_WIDGET(data), *window = gtk_widget_get_toplevel(GTK_WIDGET(button));
    gchar value[8], *out;
    g_snprintf(value, sizeof(value), "%d", gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(spin)));
    out = run_control(GTK_WINDOW(window), "dpi-set", value, NULL, NULL); g_free(out);
}

static void open_display(GtkWidget *parent)
{
    GtkWidget *window, *box, *scale, *dpi, *restart; gchar *current, *dpi_value;
    window = page(parent, "Display", &box);
    gtk_box_pack_start(GTK_BOX(box), left_label("Brightness"), FALSE, FALSE, 0);
    current = run_control(GTK_WINDOW(window), "brightness-get", NULL, NULL, NULL);
    scale = gtk_hscale_new_with_range(0, 100, 5); gtk_range_set_value(GTK_RANGE(scale), current ? atoi(current) : 50);
    gtk_scale_set_value_pos(GTK_SCALE(scale), GTK_POS_TOP); gtk_box_pack_start(GTK_BOX(box), scale, FALSE, FALSE, 2);
    g_signal_connect(scale, "value-changed", G_CALLBACK(brightness_changed_cb), window); g_free(current);

    gtk_box_pack_start(GTK_BOX(box), left_label("Interface DPI (fonts and widget scale; 96 is default)"), FALSE, FALSE, 4);
    dpi = gtk_spin_button_new_with_range(60, 200, 4); dpi_value = run_control(GTK_WINDOW(window), "dpi-get", NULL, NULL, NULL);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(dpi), dpi_value ? atoi(dpi_value) : 96); gtk_box_pack_start(GTK_BOX(box), dpi, FALSE, FALSE, 0);
    touch_button(box, "Apply DPI", G_CALLBACK(dpi_apply_cb), dpi);
    restart = touch_button(box, "Restart graphical session", G_CALLBACK(action_cb), window);
    g_object_set_data(G_OBJECT(restart), "action", "ui-restart");
    gtk_box_pack_start(GTK_BOX(box), left_label("A DPI change takes effect after restarting the graphical session; applications are closed."), FALSE, FALSE, 2);
    g_free(dpi_value); gtk_widget_show_all(window);
}

/* Sound */
static void volume_changed_cb(GtkRange *range, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar value[8], *out;
    g_snprintf(value, sizeof(value), "%d", (int)gtk_range_get_value(range));
    out = run_control(GTK_WINDOW(window), "volume-set", value, NULL, NULL); g_free(out);
}
static void open_sound(GtkWidget *parent)
{
    GtkWidget *window, *box, *scale, *test; gchar *current;
    window = page(parent, "Sound", &box); current = run_control(GTK_WINDOW(window), "volume-get", NULL, NULL, NULL);
    scale = gtk_hscale_new_with_range(0, 100, 5); gtk_range_set_value(GTK_RANGE(scale), current ? atoi(current) : 50);
    gtk_scale_set_value_pos(GTK_SCALE(scale), GTK_POS_TOP); gtk_box_pack_start(GTK_BOX(box), scale, FALSE, FALSE, 12);
    g_signal_connect(scale, "value-changed", G_CALLBACK(volume_changed_cb), window);
    test = touch_button(box, "Test speaker", G_CALLBACK(action_cb), window); g_object_set_data(G_OBJECT(test), "action", "audio-test");
    g_free(current); gtk_widget_show_all(window);
}

/* Appearance */
static void theme_changed_cb(GtkComboBox *combo, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar *theme = gtk_combo_box_get_active_text(combo), *out;
    if (!theme) return; out = run_control(GTK_WINDOW(window), "theme", theme, NULL, NULL); g_free(out); g_free(theme);
}
static void open_appearance(GtkWidget *parent)
{
    GtkWidget *window, *box, *combo; gchar *current; gchar **themes;
    window = page(parent, "Appearance", &box); current = run_control(GTK_WINDOW(window), "theme-get", NULL, NULL, NULL);
    if (current) g_strstrip(current); themes = control_lines(GTK_WINDOW(window), "theme-list");
    gtk_box_pack_start(GTK_BOX(box), left_label("JWM theme"), FALSE, FALSE, 0);
    combo = combo_from_lines(themes, current); gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 0);
    g_signal_connect(combo, "changed", G_CALLBACK(theme_changed_cb), window);
    gtk_box_pack_start(GTK_BOX(box), left_label("Themes are discovered from /usr/share/jwm/themes; additional themes appear automatically."), FALSE, FALSE, 6);
    g_strfreev(themes); g_free(current); gtk_widget_show_all(window);
}

/* Keyboard */
static void keyboard_layout_changed(GtkComboBox *combo, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar *layout = gtk_combo_box_get_active_text(combo), *out;
    if (!layout) return; out = run_control(GTK_WINDOW(window), "keyboard", layout, NULL, NULL); g_free(out); g_free(layout);
}
static void keyboard_language_apply(GtkButton *button, gpointer data)
{
    GtkWidget *entry = GTK_WIDGET(data), *window = gtk_widget_get_toplevel(GTK_WIDGET(button));
    gchar *out = run_control(GTK_WINDOW(window), "keyboard-language", gtk_entry_get_text(GTK_ENTRY(entry)), NULL, NULL); g_free(out);
}
static void open_keyboard(GtkWidget *parent)
{
    GtkWidget *window, *box, *combo, *entry, *button; gchar *current, *lang; gchar **layouts;
    window = page(parent, "On-screen keyboard", &box);
    current = run_control(GTK_WINDOW(window), "keyboard-get", NULL, NULL, NULL); if (current) g_strstrip(current);
    layouts = control_lines(GTK_WINDOW(window), "keyboard-list");
    gtk_box_pack_start(GTK_BOX(box), left_label("Installed layout file"), FALSE, FALSE, 0);
    combo = combo_from_lines(layouts, current); gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 0);
    g_signal_connect(combo, "changed", G_CALLBACK(keyboard_layout_changed), window);
    gtk_box_pack_start(GTK_BOX(box), left_label("Locale passed to Matchbox Keyboard"), FALSE, FALSE, 0);
    entry = gtk_entry_new(); lang = run_control(GTK_WINDOW(window), "keyboard-language-get", NULL, NULL, NULL);
    if (lang) gtk_entry_set_text(GTK_ENTRY(entry), g_strstrip(lang)); gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 0);
    touch_button(box, "Apply locale", G_CALLBACK(keyboard_language_apply), entry);
    button = touch_button(box, "Show / hide keyboard", G_CALLBACK(action_cb), window); g_object_set_data(G_OBJECT(button), "action", "keyboard-toggle");
    g_strfreev(layouts); g_free(current); g_free(lang); gtk_widget_show_all(window);
}

/* Hardware buttons: keys are data-driven, commands intentionally free-form. */
static void keyrow_free(gpointer p) { KeyRow *r = p; if (r) { g_free(r->key); g_free(r); } }
static void keys_save_cb(GtkButton *button, gpointer data)
{
    GtkWidget *window = gtk_widget_get_toplevel(GTK_WIDGET(button)); GPtrArray *rows = data; guint i;
    for (i = 0; i < rows->len; i++) {
        KeyRow *row = g_ptr_array_index(rows, i); gchar *out = run_control(GTK_WINDOW(window), "key-set", row->key, gtk_entry_get_text(GTK_ENTRY(row->entry)), NULL); g_free(out);
    }
    { gchar *out = run_control(GTK_WINDOW(window), "key-reload", NULL, NULL, NULL); g_free(out); }
}
static void open_keys(GtkWidget *parent)
{
    GtkWidget *window, *box; gchar **keys; gint i; GPtrArray *rows;
    window = page(parent, "Hardware buttons", &box); keys = control_lines(GTK_WINDOW(window), "key-list");
    rows = g_ptr_array_new_with_free_func(keyrow_free);
    if (keys) for (i = 0; keys[i]; i++) if (*keys[i]) {
        KeyRow *row = g_new0(KeyRow, 1); gchar *current;
        row->key = g_strdup(keys[i]); row->entry = gtk_entry_new(); current = run_control(GTK_WINDOW(window), "key-get", row->key, NULL, NULL);
        if (current) gtk_entry_set_text(GTK_ENTRY(row->entry), g_strstrip(current));
        gtk_box_pack_start(GTK_BOX(box), left_label(row->key), FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(box), row->entry, FALSE, FALSE, 0); g_ptr_array_add(rows, row); g_free(current);
    }
    gtk_box_pack_start(GTK_BOX(box), left_label("Commands are ordinary triggerhappy command lines; they are not limited to the applications shipped in the base image."), FALSE, FALSE, 5);
    touch_button(box, "Save assignments", G_CALLBACK(keys_save_cb), rows);
    g_object_set_data_full(G_OBJECT(window), "key-rows", rows, (GDestroyNotify)g_ptr_array_unref);
    g_strfreev(keys); gtk_widget_show_all(window);
}

/* Power */
static void blank_changed_cb(GtkSpinButton *spin, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar value[16], *out;
    g_snprintf(value, sizeof(value), "%d", gtk_spin_button_get_value_as_int(spin));
    out = run_control(GTK_WINDOW(window), "blank-set", value, NULL, NULL); g_free(out);
}
static void confirmed_action_cb(GtkButton *button, gpointer data)
{
    GtkWidget *window = gtk_widget_get_toplevel(GTK_WIDGET(button)); const gchar *action = data;
    const gchar *verb = !strcmp(action, "reboot") ? "restart" : "power off";
    GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(window), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_OK_CANCEL, "Really %s the device?", verb);
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_OK) { gchar *out = run_control(GTK_WINDOW(window), action, NULL, NULL, NULL); g_free(out); }
    gtk_widget_destroy(dialog);
}
static void open_power(GtkWidget *parent)
{
    GtkWidget *window, *box, *spin, *suspend, *buttons; gchar *info, *blank;
    window = page(parent, "Power and battery", &box); info = run_control(GTK_WINDOW(window), "power-info", NULL, NULL, NULL);
    gtk_box_pack_start(GTK_BOX(box), left_label(info ? info : "Battery data unavailable"), FALSE, FALSE, 2); g_free(info);
    gtk_box_pack_start(GTK_BOX(box), left_label("Screen timeout, seconds (0 = never)"), FALSE, FALSE, 0);
    spin = gtk_spin_button_new_with_range(0, 3600, 30); blank = run_control(GTK_WINDOW(window), "blank-get", NULL, NULL, NULL);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(spin), blank ? atoi(blank) : 60); gtk_box_pack_start(GTK_BOX(box), spin, FALSE, FALSE, 0);
    g_signal_connect(spin, "value-changed", G_CALLBACK(blank_changed_cb), window); g_free(blank);
    suspend = touch_button(box, "Suspend", G_CALLBACK(action_cb), window); g_object_set_data(G_OBJECT(suspend), "action", "suspend");
    buttons = gtk_hbox_new(TRUE, 4); touch_button(buttons, "Restart", G_CALLBACK(confirmed_action_cb), (gpointer)"reboot");
    touch_button(buttons, "Power off", G_CALLBACK(confirmed_action_cb), (gpointer)"poweroff"); gtk_box_pack_start(GTK_BOX(box), buttons, FALSE, FALSE, 0);
    gtk_widget_show_all(window);
}

/* Time */
static void timezone_apply_cb(GtkButton *button, gpointer data)
{
    GtkWidget *window = gtk_widget_get_toplevel(GTK_WIDGET(button));
    gchar *out = run_control(GTK_WINDOW(window), "timezone", gtk_entry_get_text(GTK_ENTRY(data)), NULL, NULL); g_free(out);
}
static void open_time(GtkWidget *parent)
{
    GtkWidget *window, *box, *entry, *sync; gchar *zone;
    window = page(parent, "Date and time", &box); zone = run_control(GTK_WINDOW(window), "timezone-get", NULL, NULL, NULL);
    gtk_box_pack_start(GTK_BOX(box), left_label("Timezone (Region/City from /usr/share/zoneinfo)"), FALSE, FALSE, 2);
    entry = gtk_entry_new(); gtk_entry_set_text(GTK_ENTRY(entry), zone ? g_strstrip(zone) : "Etc/UTC"); gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 2);
    touch_button(box, "Apply timezone", G_CALLBACK(timezone_apply_cb), entry);
    sync = touch_button(box, "Synchronize clock", G_CALLBACK(action_cb), window); g_object_set_data(G_OBJECT(sync), "action", "time-sync");
    g_free(zone); gtk_widget_show_all(window);
}

/* Generic information pages */
static void open_text_page(GtkWidget *parent, const gchar *title, const gchar *operation)
{
    GtkWidget *window, *box, *view, *scroll; GtkTextBuffer *buffer; gchar *text;
    window = page(parent, title, &box); text = run_control(GTK_WINDOW(window), operation, NULL, NULL, NULL);
    view = gtk_text_view_new(); gtk_text_view_set_editable(GTK_TEXT_VIEW(view), FALSE); gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(view), FALSE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR); buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    gtk_text_buffer_set_text(buffer, text ? text : "Unavailable", -1); scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC); gtk_container_add(GTK_CONTAINER(scroll), view);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0); g_free(text); gtk_widget_show_all(window);
}
static void open_info(GtkWidget *parent) { open_text_page(parent, "System information", "status"); }
static void open_storage(GtkWidget *parent) { open_text_page(parent, "Storage", "storage"); }

static void open_calibrate(GtkWidget *parent)
{
    gchar *out = run_control(GTK_WINDOW(parent), "calibrate", NULL, NULL, NULL);
    if (out) { show_info(GTK_WINDOW(parent), *out ? out : "Touchscreen calibration completed."); g_free(out); }
}

/* Desktop / panel */
static void panel_height_changed(GtkSpinButton *spin, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar value[8], *out;
    g_snprintf(value, sizeof(value), "%d", gtk_spin_button_get_value_as_int(spin));
    out = run_control(GTK_WINDOW(window), "panel-height-set", value, NULL, NULL); g_free(out);
}
static void panel_autohide_changed(GtkComboBox *combo, gpointer data)
{
    GtkWidget *window = GTK_WIDGET(data); gchar *mode = gtk_combo_box_get_active_text(combo), *out;
    if (!mode) return; out = run_control(GTK_WINDOW(window), "panel-autohide-set", mode, NULL, NULL); g_free(out); g_free(mode);
}
static void desktop_edit_cb(GtkButton *button, gpointer data)
{
    GError *error = NULL; gchar *argv[] = {"/usr/bin/leafpad", "/root/.jwmrc", NULL}; (void)button;
    if (!g_spawn_async(NULL, argv, NULL, 0, NULL, NULL, NULL, &error)) { show_error(GTK_WINDOW(data), error->message); g_error_free(error); }
}
static void open_desktop(GtkWidget *parent)
{
    GtkWidget *window, *box, *height, *autohide, *reload; gchar *h, *mode; gint active = 0;
    window = page(parent, "Desktop", &box);
    gtk_box_pack_start(GTK_BOX(box), left_label("Lower panel height"), FALSE, FALSE, 0);
    height = gtk_spin_button_new_with_range(24, 64, 2); h = run_control(GTK_WINDOW(window), "panel-height-get", NULL, NULL, NULL);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(height), h ? atoi(h) : 32); gtk_box_pack_start(GTK_BOX(box), height, FALSE, FALSE, 0);
    g_signal_connect(height, "value-changed", G_CALLBACK(panel_height_changed), window);

    gtk_box_pack_start(GTK_BOX(box), left_label("Panel auto-hide"), FALSE, FALSE, 0);
    autohide = gtk_combo_box_new_text(); gtk_combo_box_append_text(GTK_COMBO_BOX(autohide), "off"); gtk_combo_box_append_text(GTK_COMBO_BOX(autohide), "bottom");
    mode = run_control(GTK_WINDOW(window), "panel-autohide-get", NULL, NULL, NULL); if (mode && !strcmp(g_strstrip(mode), "bottom")) active = 1;
    gtk_combo_box_set_active(GTK_COMBO_BOX(autohide), active); gtk_box_pack_start(GTK_BOX(box), autohide, FALSE, FALSE, 0);
    g_signal_connect(autohide, "changed", G_CALLBACK(panel_autohide_changed), window);

    gtk_box_pack_start(GTK_BOX(box), left_label("Applications come from XDG .desktop files. ~/.jwmrc remains the advanced user-owned JWM configuration; the managed lower panel is generated from /etc/default/rx1950-ui."), FALSE, FALSE, 4);
    touch_button(box, "Edit advanced JWM config", G_CALLBACK(desktop_edit_cb), window);
    reload = touch_button(box, "Reload JWM", G_CALLBACK(action_cb), window); g_object_set_data(G_OBJECT(reload), "action", "jwm-reload");
    g_free(h); g_free(mode); gtk_widget_show_all(window);
}

static Applet applets[] = {
    {"wifi", "Wi-Fi", open_wifi}, {"display", "Display", open_display},
    {"sound", "Sound", open_sound}, {"appearance", "Appearance", open_appearance},
    {"keyboard", "Keyboard", open_keyboard}, {"keys", "Buttons", open_keys},
    {"power", "Power", open_power}, {"time", "Date / time", open_time},
    {"calibrate", "Touchscreen", open_calibrate}, {"storage", "Storage", open_storage},
    {"desktop", "Desktop", open_desktop}, {"info", "System", open_info}, {NULL, NULL, NULL}
};
static void applet_clicked_cb(GtkButton *button, gpointer data) { (void)button; ((Applet *)data)->open(main_window); }

int main(int argc, char **argv)
{
    GtkWidget *scroll, *table; gint i;
    gtk_init(&argc, &argv); main_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(main_window), "Settings"); gtk_window_set_default_size(GTK_WINDOW(main_window), PAGE_W, PAGE_H);
    gtk_window_set_position(GTK_WINDOW(main_window), GTK_WIN_POS_CENTER); g_signal_connect(main_window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
    scroll = gtk_scrolled_window_new(NULL, NULL); gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    table = gtk_table_new(6, 2, TRUE); gtk_container_set_border_width(GTK_CONTAINER(table), 6);
    for (i = 0; applets[i].id; i++) {
        GtkWidget *button = gtk_button_new_with_label(applets[i].title); gtk_widget_set_size_request(button, 108, 48);
        g_signal_connect(button, "clicked", G_CALLBACK(applet_clicked_cb), &applets[i]);
        gtk_table_attach_defaults(GTK_TABLE(table), button, i % 2, i % 2 + 1, i / 2, i / 2 + 1);
    }
    gtk_scrolled_window_add_with_viewport(GTK_SCROLLED_WINDOW(scroll), table); gtk_container_add(GTK_CONTAINER(main_window), scroll); gtk_widget_show_all(main_window);
    if (argc > 1) for (i = 0; applets[i].id; i++) if (!strcmp(argv[1], applets[i].id)) { applets[i].open(main_window); break; }
    gtk_main(); return 0;
}
