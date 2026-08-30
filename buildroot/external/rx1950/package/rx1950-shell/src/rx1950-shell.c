/* Minimal resident shell for a 240x320 X11 PDA. No toolkit, images or IPC. */
#define _POSIX_C_SOURCE 200809L
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define SCREEN_W 240
#define SCREEN_H 320
#define PANEL_H 28
#define MENU_W 168
#define ITEM_H 34
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

typedef struct {
    const char *name;
    const char *command;
    const char *glyph;
} App;

static const App apps[] = {
    { "Terminal",   "mb-applet-xterm-wrapper.sh", "T" },
    { "Wi-Fi",      "rx1950-wifi-launcher",      "W" },
    { "Settings",   "rx1950-settings-launcher",  "S" },
    { "Keyboard",   "rx1950-keyboard toggle",    "K" },
    { "Calculator", "xcalc",                     "+" },
    { "Editor",     "xedit",                     "E" }
};

static Display *dpy;
static int screen_no;
static Window root, desktop, panel, menu_win;
static GC gc;
static XFontStruct *font;
static Atom a_type, a_desktop, a_dock, a_strut, a_strut_partial, a_active, a_name;
static Atom a_utf8, a_wm_delete;
static unsigned long bg, panel_bg, tile, accent, fg, muted;
static int menu_open;
static char status_text[64];
static char task_text[48];
static Window active_client;

static unsigned long color(const char *name, unsigned long fallback)
{
    XColor exact, value;
    Colormap map = DefaultColormap(dpy, screen_no);
    return XAllocNamedColor(dpy, map, name, &value, &exact) ? value.pixel : fallback;
}

static void rect(Window w, unsigned long c, int x, int y, unsigned int width,
                 unsigned int height)
{
    XSetForeground(dpy, gc, c);
    XFillRectangle(dpy, w, gc, x, y, width, height);
}

static void text_at(Window w, unsigned long c, int x, int y, const char *s)
{
    XSetForeground(dpy, gc, c);
    XDrawString(dpy, w, gc, x, y, s, (int)strlen(s));
}

static void centered(Window w, unsigned long c, int x, int width, int y,
                     const char *s)
{
    int tw = XTextWidth(font, s, (int)strlen(s));
    text_at(w, c, x + (width - tw) / 2, y, s);
}

static void set_window_type(Window w, Atom type)
{
    XChangeProperty(dpy, w, a_type, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *)&type, 1);
}

static void spawn(const char *command)
{
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        execl("/bin/sh", "sh", "-c", command, (char *)NULL);
        _exit(127);
    }
}

static int read_line(const char *path, char *out, size_t size)
{
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    if (!fgets(out, (int)size, f)) out[0] = '\0';
    fclose(f);
    out[strcspn(out, "\r\n")] = '\0';
    return out[0] != '\0';
}

static int battery_capacity(void)
{
    DIR *dir = opendir("/sys/class/power_supply");
    struct dirent *entry;
    char path[512], value[16];
    int result = -1;
    if (!dir) return -1;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "/sys/class/power_supply/%s/capacity",
                 entry->d_name);
        if (read_line(path, value, sizeof(value))) {
            result = atoi(value);
            break;
        }
    }
    closedir(dir);
    return result;
}

static long memory_available_kb(void)
{
    FILE *f = fopen("/proc/meminfo", "r");
    char key[32], unit[16];
    long value, fallback = 0;
    if (!f) return -1;
    while (fscanf(f, "%31s %ld %15s", key, &value, unit) == 3) {
        if (!strcmp(key, "MemAvailable:")) { fclose(f); return value; }
        if (!strcmp(key, "MemFree:") || !strcmp(key, "Cached:")) fallback += value;
    }
    fclose(f);
    return fallback;
}

static void update_status(void)
{
    char wifi[16] = "down";
    int bat = battery_capacity();
    long mem = memory_available_kb();
    time_t now = time(NULL);
    struct tm local;
    char clock_text[8];
    read_line("/sys/class/net/wlan0/operstate", wifi, sizeof(wifi));
    localtime_r(&now, &local);
    strftime(clock_text, sizeof(clock_text), "%H:%M", &local);
    if (bat >= 0)
        snprintf(status_text, sizeof(status_text), "%s  B%d  %s  %ldM",
                 clock_text, bat, !strcmp(wifi, "up") ? "WiFi" : "--", mem / 1024);
    else
        snprintf(status_text, sizeof(status_text), "%s  %s  %ldM", clock_text,
                 !strcmp(wifi, "up") ? "WiFi" : "--", mem / 1024);
}

static char *window_name(Window w)
{
    Atom actual;
    int format;
    unsigned long count, left;
    unsigned char *data = NULL;
    if (!w) return NULL;
    if (XGetWindowProperty(dpy, w, a_name, 0, 64, False, a_utf8, &actual,
                           &format, &count, &left, &data) == Success && data)
        return (char *)data;
    if (data) XFree(data);
    data = NULL;
    if (XFetchName(dpy, w, (char **)&data) && data) return (char *)data;
    return NULL;
}

static void update_task(void)
{
    Atom actual;
    int format;
    unsigned long count, left;
    unsigned char *data = NULL;
    char *name;
    active_client = None;
    strcpy(task_text, "Home");
    if (XGetWindowProperty(dpy, root, a_active, 0, 1, False, XA_WINDOW,
                           &actual, &format, &count, &left, &data) == Success &&
        data && count == 1)
        active_client = *(Window *)data;
    if (data) XFree(data);
    if (!active_client || active_client == desktop || active_client == panel ||
        active_client == menu_win) return;
    name = window_name(active_client);
    if (!name) return;
    snprintf(task_text, sizeof(task_text), "%.38s", name);
    XFree(name);
}

static void draw_tile(Window w, int x, int y, int width, int height,
                      const App *app)
{
    rect(w, tile, x + 2, y + 2, (unsigned int)(width - 4), (unsigned int)(height - 4));
    rect(w, accent, x + width / 2 - 14, y + 9, 28, 28);
    centered(w, fg, x + width / 2 - 14, 28, y + 28, app->glyph);
    centered(w, fg, x, width, y + height - 10, app->name);
}

static void draw_desktop(void)
{
    size_t i;
    rect(desktop, bg, 0, 0, SCREEN_W, SCREEN_H - PANEL_H);
    text_at(desktop, fg, 10, 18, "rx1950");
    text_at(desktop, muted, 10, 34, status_text);
    for (i = 0; i < ARRAY_SIZE(apps); ++i) {
        int col = (int)i % 3, row = (int)i / 3;
        draw_tile(desktop, col * 80, 48 + row * 86, 80, 76, &apps[i]);
    }
}

static void draw_panel(void)
{
    rect(panel, panel_bg, 0, 0, SCREEN_W, PANEL_H);
    rect(panel, accent, 0, 0, 52, PANEL_H);
    centered(panel, fg, 0, 52, 19, "Start");
    centered(panel, fg, 54, 100, 19, task_text);
    text_at(panel, fg, 160, 19, "Kbd");
    text_at(panel, fg, 207, 19, "X");
}

static void draw_menu(void)
{
    size_t i;
    rect(menu_win, panel_bg, 0, 0, MENU_W, ITEM_H * ARRAY_SIZE(apps));
    for (i = 0; i < ARRAY_SIZE(apps); ++i) {
        if (i & 1) rect(menu_win, tile, 0, (int)i * ITEM_H, MENU_W, ITEM_H);
        rect(menu_win, accent, 7, (int)i * ITEM_H + 6, 22, 22);
        centered(menu_win, fg, 7, 22, (int)i * ITEM_H + 21, apps[i].glyph);
        text_at(menu_win, fg, 38, (int)i * ITEM_H + 22, apps[i].name);
    }
}

static void toggle_menu(void)
{
    menu_open = !menu_open;
    if (menu_open) {
        XMapRaised(dpy, menu_win);
        draw_menu();
    } else {
        XUnmapWindow(dpy, menu_win);
    }
}

static void close_active(void)
{
    Atom protocols;
    int n = 0, i;
    Atom *list = NULL;
    XEvent event;
    if (!active_client) return;
    if (XGetWMProtocols(dpy, active_client, &list, &n)) {
        for (i = 0; i < n; ++i) if (list[i] == a_wm_delete) {
            memset(&event, 0, sizeof(event));
            event.xclient.type = ClientMessage;
            event.xclient.window = active_client;
            event.xclient.message_type = XInternAtom(dpy, "WM_PROTOCOLS", False);
            event.xclient.format = 32;
            event.xclient.data.l[0] = (long)a_wm_delete;
            event.xclient.data.l[1] = CurrentTime;
            XSendEvent(dpy, active_client, False, NoEventMask, &event);
            XFree(list);
            return;
        }
        XFree(list);
    }
    XKillClient(dpy, active_client);
}

static void handle_click(XButtonEvent *e)
{
    if (e->window == panel) {
        if (e->x < 52) toggle_menu();
        else if (e->x < 154) {
            if (active_client) XIconifyWindow(dpy, active_client, screen_no);
            XMapRaised(dpy, desktop);
        } else if (e->x < 198) spawn("rx1950-keyboard toggle");
        else close_active();
    } else if (e->window == menu_win) {
        int item = e->y / ITEM_H;
        if (item >= 0 && item < (int)ARRAY_SIZE(apps)) spawn(apps[item].command);
        toggle_menu();
    } else if (e->window == desktop && e->y >= 48) {
        int col = e->x / 80, row = (e->y - 48) / 86;
        int item = row * 3 + col;
        if (item >= 0 && item < (int)ARRAY_SIZE(apps)) spawn(apps[item].command);
    }
}

static int ignore_x_error(Display *display, XErrorEvent *error)
{
    (void)display; (void)error;
    return 0;
}

int main(void)
{
    XSetWindowAttributes menu_attrs;
    XEvent event;
    unsigned long strut[4] = { 0 };
    unsigned long strut_partial[12] = { 0 };
    int xfd;
    signal(SIGCHLD, SIG_IGN);
    dpy = XOpenDisplay(NULL);
    if (!dpy) return 1;
    XSetErrorHandler(ignore_x_error);
    screen_no = DefaultScreen(dpy);
    root = RootWindow(dpy, screen_no);
    fg = color("#f3f6f8", WhitePixel(dpy, screen_no));
    muted = color("#a8b3bd", fg);
    bg = color("#17212b", BlackPixel(dpy, screen_no));
    panel_bg = color("#0d141b", bg);
    tile = color("#263746", bg);
    accent = color("#1976a8", fg);
    font = XLoadQueryFont(dpy, "6x13");
    if (!font) font = XLoadQueryFont(dpy, "fixed");
    if (!font) return 2;
    gc = XCreateGC(dpy, root, 0, NULL);
    XSetFont(dpy, gc, font->fid);

    a_type = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
    a_desktop = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
    a_dock = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
    a_strut = XInternAtom(dpy, "_NET_WM_STRUT", False);
    a_strut_partial = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
    a_active = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
    a_name = XInternAtom(dpy, "_NET_WM_NAME", False);
    a_utf8 = XInternAtom(dpy, "UTF8_STRING", False);
    a_wm_delete = XInternAtom(dpy, "WM_DELETE_WINDOW", False);

    desktop = XCreateSimpleWindow(dpy, root, 0, 0, SCREEN_W, SCREEN_H - PANEL_H,
                                  0, bg, bg);
    panel = XCreateSimpleWindow(dpy, root, 0, SCREEN_H - PANEL_H, SCREEN_W,
                                PANEL_H, 0, panel_bg, panel_bg);
    menu_attrs.override_redirect = True;
    menu_attrs.background_pixel = panel_bg;
    menu_win = XCreateWindow(dpy, root, 0,
                             SCREEN_H - PANEL_H - ITEM_H * ARRAY_SIZE(apps),
                             MENU_W, ITEM_H * ARRAY_SIZE(apps), 0,
                             CopyFromParent, InputOutput, CopyFromParent,
                             CWOverrideRedirect | CWBackPixel, &menu_attrs);
    set_window_type(desktop, a_desktop);
    set_window_type(panel, a_dock);
    strut[3] = PANEL_H;
    strut_partial[3] = PANEL_H;
    strut_partial[10] = 0;
    strut_partial[11] = SCREEN_W - 1;
    XChangeProperty(dpy, panel, a_strut, XA_CARDINAL, 32, PropModeReplace,
                    (unsigned char *)strut, 4);
    XChangeProperty(dpy, panel, a_strut_partial, XA_CARDINAL, 32,
                    PropModeReplace, (unsigned char *)strut_partial, 12);
    XStoreName(dpy, desktop, "rx1950 Home");
    XStoreName(dpy, panel, "rx1950 Panel");
    XSelectInput(dpy, root, PropertyChangeMask);
    XSelectInput(dpy, desktop, ExposureMask | ButtonPressMask);
    XSelectInput(dpy, panel, ExposureMask | ButtonPressMask);
    XSelectInput(dpy, menu_win, ExposureMask | ButtonPressMask);
    update_status();
    update_task();
    XMapWindow(dpy, desktop);
    XMapRaised(dpy, panel);
    XLowerWindow(dpy, desktop);
    XFlush(dpy);
    xfd = ConnectionNumber(dpy);

    for (;;) {
        fd_set fds;
        struct timeval timeout = { 15, 0 };
        FD_ZERO(&fds);
        FD_SET(xfd, &fds);
        if (select(xfd + 1, &fds, NULL, NULL, &timeout) < 0 && errno != EINTR)
            break;
        if (!FD_ISSET(xfd, &fds)) {
            update_status();
            update_task();
            draw_desktop();
            draw_panel();
            XFlush(dpy);
        }
        while (XPending(dpy)) {
            XNextEvent(dpy, &event);
            if (event.type == Expose && event.xexpose.count == 0) {
                if (event.xexpose.window == desktop) draw_desktop();
                else if (event.xexpose.window == panel) draw_panel();
                else if (event.xexpose.window == menu_win) draw_menu();
            } else if (event.type == ButtonPress) {
                handle_click(&event.xbutton);
            } else if (event.type == PropertyNotify &&
                       event.xproperty.atom == a_active) {
                update_task();
                draw_panel();
            }
        }
    }
    XCloseDisplay(dpy);
    return 0;
}
