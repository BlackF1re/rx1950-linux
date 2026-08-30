/* Minimal resident shell for a 240x320 X11 PDA. No toolkit, images or IPC. */
#define _POSIX_C_SOURCE 200809L
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
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
#define KEYBOARD_H 132
#define MAX_CLIENTS 16
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
static Atom a_utf8, a_wm_delete, a_client_list, a_supported, a_supporting_wm;
static unsigned long bg, panel_bg, tile, accent, fg, muted;
static int menu_open;
static char status_text[64];
static char task_text[48];
static Window active_client;
static Window keyboard_client;
static Window clients[MAX_CLIENTS];
static size_t client_count;
static int wm_error;

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
    char *name;
    strcpy(task_text, "Home");
    if (!active_client) return;
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

static void publish_clients(void)
{
    XChangeProperty(dpy, root, a_client_list, XA_WINDOW, 32, PropModeReplace,
                    (unsigned char *)clients, (int)client_count);
}

static int client_index(Window w)
{
    size_t i;
    for (i = 0; i < client_count; ++i) if (clients[i] == w) return (int)i;
    return -1;
}

static void add_client(Window w)
{
    if (client_index(w) >= 0 || client_count == MAX_CLIENTS) return;
    clients[client_count++] = w;
    XSelectInput(dpy, w, PropertyChangeMask | StructureNotifyMask);
    publish_clients();
}

static void remove_client(Window w)
{
    int index = client_index(w);
    if (keyboard_client == w) {
        keyboard_client = None;
        return;
    }
    if (index < 0) return;
    memmove(&clients[index], &clients[index + 1],
            (client_count - (size_t)index - 1) * sizeof(clients[0]));
    --client_count;
    if (active_client == w) active_client = None;
    publish_clients();
    XChangeProperty(dpy, root, a_active, XA_WINDOW, 32, PropModeReplace,
                    (unsigned char *)&active_client, 1);
    update_task();
    draw_panel();
}

static int is_keyboard(Window w)
{
    XClassHint hint;
    char *name;
    int result = 0;
    memset(&hint, 0, sizeof(hint));
    if (XGetClassHint(dpy, w, &hint)) {
        if ((hint.res_name && (strstr(hint.res_name, "keyboard") ||
                              strstr(hint.res_name, "Keyboard"))) ||
            (hint.res_class && (strstr(hint.res_class, "keyboard") ||
                               strstr(hint.res_class, "Keyboard"))))
            result = 1;
        if (hint.res_name) XFree(hint.res_name);
        if (hint.res_class) XFree(hint.res_class);
    }
    if (result) return 1;
    name = window_name(w);
    if (name) {
        result = strstr(name, "Keyboard") != NULL ||
                 strstr(name, "keyboard") != NULL;
        XFree(name);
    }
    return result;
}

static void activate_client(Window w)
{
    if (!w || client_index(w) < 0) return;
    if (active_client && active_client != w) XUnmapWindow(dpy, active_client);
    active_client = w;
    XMoveResizeWindow(dpy, w, 0, 0, SCREEN_W, SCREEN_H - PANEL_H);
    XMapRaised(dpy, w);
    XRaiseWindow(dpy, panel);
    if (keyboard_client) XRaiseWindow(dpy, keyboard_client);
    XSetInputFocus(dpy, w, RevertToPointerRoot, CurrentTime);
    XChangeProperty(dpy, root, a_active, XA_WINDOW, 32, PropModeReplace,
                    (unsigned char *)&active_client, 1);
    update_task();
    draw_panel();
}

static void show_home(void)
{
    if (active_client) XUnmapWindow(dpy, active_client);
    active_client = None;
    XChangeProperty(dpy, root, a_active, XA_WINDOW, 32, PropModeReplace,
                    (unsigned char *)&active_client, 1);
    XMapWindow(dpy, desktop);
    XRaiseWindow(dpy, panel);
    update_task();
    draw_panel();
}

static void map_requested(Window w)
{
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(dpy, w, &attrs)) return;
    if (attrs.override_redirect) {
        XMapRaised(dpy, w);
        return;
    }
    if (is_keyboard(w)) {
        keyboard_client = w;
        XMoveResizeWindow(dpy, w, 0, SCREEN_H - PANEL_H - KEYBOARD_H,
                          SCREEN_W, KEYBOARD_H);
        XMapRaised(dpy, w);
        return;
    }
    add_client(w);
    activate_client(w);
}

static void configure_requested(XConfigureRequestEvent *e)
{
    XWindowChanges change;
    if (e->window == keyboard_client || is_keyboard(e->window)) {
        keyboard_client = e->window;
        XMoveResizeWindow(dpy, e->window, 0, SCREEN_H - PANEL_H - KEYBOARD_H,
                          SCREEN_W, KEYBOARD_H);
    } else if (client_index(e->window) >= 0) {
        XMoveResizeWindow(dpy, e->window, 0, 0, SCREEN_W, SCREEN_H - PANEL_H);
    } else {
        change.x = e->x; change.y = e->y;
        change.width = e->width; change.height = e->height;
        change.border_width = e->border_width;
        change.sibling = e->above; change.stack_mode = e->detail;
        XConfigureWindow(dpy, e->window, (unsigned int)e->value_mask, &change);
    }
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
            if (active_client) show_home();
            else if (client_count) activate_client(clients[client_count - 1]);
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
    (void)display;
    if (error->error_code == BadAccess) wm_error = 1;
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
    a_client_list = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
    a_supported = XInternAtom(dpy, "_NET_SUPPORTED", False);
    a_supporting_wm = XInternAtom(dpy, "_NET_SUPPORTING_WM_CHECK", False);

    XSelectInput(dpy, root, SubstructureRedirectMask | SubstructureNotifyMask |
                 PropertyChangeMask);
    XSync(dpy, False);
    if (wm_error) {
        fprintf(stderr, "another window manager owns display %s\n",
                DisplayString(dpy));
        return 3;
    }

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
    {
        Atom supported[] = { a_type, a_active, a_client_list, a_supporting_wm };
        const char wm_name[] = "rx1950-shell";
        XChangeProperty(dpy, root, a_supported, XA_ATOM, 32, PropModeReplace,
                        (unsigned char *)supported, (int)ARRAY_SIZE(supported));
        XChangeProperty(dpy, root, a_supporting_wm, XA_WINDOW, 32,
                        PropModeReplace, (unsigned char *)&panel, 1);
        XChangeProperty(dpy, panel, a_supporting_wm, XA_WINDOW, 32,
                        PropModeReplace, (unsigned char *)&panel, 1);
        XChangeProperty(dpy, panel, a_name, a_utf8, 8, PropModeReplace,
                        (const unsigned char *)wm_name,
                        (int)sizeof(wm_name) - 1);
        publish_clients();
    }
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
        if (select(xfd + 1, &fds, NULL, NULL, &timeout) < 0) {
            if (errno == EINTR) continue;
            break;
        }
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
            } else if (event.type == MapRequest) {
                map_requested(event.xmaprequest.window);
            } else if (event.type == ConfigureRequest) {
                configure_requested(&event.xconfigurerequest);
            } else if (event.type == DestroyNotify) {
                remove_client(event.xdestroywindow.window);
            } else if (event.type == UnmapNotify &&
                       event.xunmap.window == keyboard_client) {
                keyboard_client = None;
            } else if (event.type == PropertyNotify &&
                       event.xproperty.window == active_client) {
                update_task();
                draw_panel();
            }
        }
    }
    XCloseDisplay(dpy);
    return 0;
}
