#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <math.h>
#include <dlfcn.h>

typedef struct {
    unsigned int id;
    int width;
    int height;
    int mipmaps;
    int format;
} J_Texture2D;

typedef struct {
    int baseSize;
    int glyphCount;
    int glyphPadding;
    J_Texture2D texture;
    void* recs;
    void* glyphs;
} J_Font;

typedef struct {
    float x;
    float y;
} J_Vector2;

typedef struct {
    unsigned char r;
    unsigned char g;
    unsigned char b;
    unsigned char a;
} J_Color;

static inline int isspace_fast(unsigned char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

static int64_t juno_alloc_fail(void) {
    fputs("juno: runtime allocation failed\n", stderr);
    abort();
    return 0;
}

static char* juno_new_string(size_t len) {
    char* buf = (char*)malloc(len + 1);
    if (!buf) juno_alloc_fail();
    buf[len] = '\0';
    return buf;
}

static char* juno_new_empty_string(void) {
    return juno_new_string(0);
}

static inline double bits_to_double(int64_t bits) {
    double d;
    memcpy(&d, &bits, sizeof(d));
    return d;
}

static inline int64_t double_to_bits(double d) {
    int64_t bits;
    memcpy(&bits, &d, sizeof(bits));
    return bits;
}

int64_t juno_sin(int64_t x)   { return double_to_bits(sin(bits_to_double(x))); }
int64_t juno_cos(int64_t x)   { return double_to_bits(cos(bits_to_double(x))); }
int64_t juno_tan(int64_t x)   { return double_to_bits(tan(bits_to_double(x))); }
int64_t juno_asin(int64_t x)  { return double_to_bits(asin(bits_to_double(x))); }
int64_t juno_acos(int64_t x)  { return double_to_bits(acos(bits_to_double(x))); }
int64_t juno_atan(int64_t x)  { return double_to_bits(atan(bits_to_double(x))); }
int64_t juno_atan2(int64_t y, int64_t x) {
    return double_to_bits(atan2(bits_to_double(y), bits_to_double(x)));
}
int64_t juno_sqrt(int64_t x)  { return double_to_bits(sqrt(bits_to_double(x))); }
int64_t juno_cbrt(int64_t x)  { return double_to_bits(cbrt(bits_to_double(x))); }
int64_t juno_fpow(int64_t b, int64_t e) {
    return double_to_bits(pow(bits_to_double(b), bits_to_double(e)));
}
int64_t juno_exp(int64_t x)   { return double_to_bits(exp(bits_to_double(x))); }
int64_t juno_log(int64_t x)   { return double_to_bits(log(bits_to_double(x))); }
int64_t juno_log2(int64_t x)  { return double_to_bits(log2(bits_to_double(x))); }
int64_t juno_log10(int64_t x) { return double_to_bits(log10(bits_to_double(x))); }
int64_t juno_floor(int64_t x) { return double_to_bits(floor(bits_to_double(x))); }
int64_t juno_ceil(int64_t x)  { return double_to_bits(ceil(bits_to_double(x))); }
int64_t juno_round(int64_t x) { return double_to_bits(round(bits_to_double(x))); }
int64_t juno_trunc(int64_t x) { return double_to_bits(trunc(bits_to_double(x))); }
int64_t juno_fabs(int64_t x)  { return double_to_bits(fabs(bits_to_double(x))); }
int64_t juno_fmod(int64_t x, int64_t y) {
    return double_to_bits(fmod(bits_to_double(x), bits_to_double(y)));
}
int64_t juno_hypot(int64_t x, int64_t y) {
    return double_to_bits(hypot(bits_to_double(x), bits_to_double(y)));
}
int64_t juno_float_to_int(int64_t f_bits) {
    return (int64_t)bits_to_double(f_bits);
}
int64_t juno_float_round_to_int(int64_t f_bits) {
    return (int64_t)llround(bits_to_double(f_bits));
}

typedef void    (*raylib_DrawText_fn)(const char *text, int posX, int posY, int fontSize, J_Color color);
typedef void    (*raylib_DrawTextEx_fn)(J_Font font, const char *text, J_Vector2 position, float fontSize, float spacing, J_Color tint);
typedef J_Font  (*raylib_LoadFont_fn)(const char *fileName);

static void *g_raylib_handle = NULL;
static int   g_raylib_load_attempted = 0;
static raylib_DrawText_fn   p_DrawText   = NULL;
static raylib_DrawTextEx_fn p_DrawTextEx = NULL;
static raylib_LoadFont_fn   p_LoadFont   = NULL;

static void juno_load_raylib(void) {
    if (g_raylib_load_attempted) return;
    g_raylib_load_attempted = 1;

#if defined(__APPLE__)
    static const char *candidates[] = {
        "libraylib.dylib",
        "libraylib.4.dylib",
        "libraylib.5.dylib",
        "/usr/local/lib/libraylib.dylib",
        "/opt/homebrew/lib/libraylib.dylib",
        NULL
    };
#else
    static const char *candidates[] = {
        "libraylib.so",
        "libraylib.so.4",
        "libraylib.so.5",
        NULL
    };
#endif

    for (int i = 0; candidates[i] != NULL; i++) {
        g_raylib_handle = dlopen(candidates[i], RTLD_LAZY | RTLD_GLOBAL);
        if (g_raylib_handle) break;
    }

    if (!g_raylib_handle) return;

    p_DrawText   = (raylib_DrawText_fn)  dlsym(g_raylib_handle, "DrawText");
    p_DrawTextEx = (raylib_DrawTextEx_fn)dlsym(g_raylib_handle, "DrawTextEx");
    p_LoadFont   = (raylib_LoadFont_fn)  dlsym(g_raylib_handle, "LoadFont");
}

int64_t juno_load_font(int64_t filename_ptr) {
    juno_load_raylib();

    J_Font* f = (J_Font*)malloc(sizeof(J_Font));
    if (!f) return juno_alloc_fail();

    if (p_LoadFont) {
        *f = p_LoadFont((const char*)filename_ptr);
    } else {
        memset(f, 0, sizeof(J_Font));
    }
    return (int64_t)f;
}

void juno_draw_text(int64_t font_ptr, int64_t text_ptr, int64_t x, int64_t y, int64_t size, int64_t spacing, int64_t color) {
    if (!font_ptr || !text_ptr) return;
    juno_load_raylib();
    if (!p_DrawTextEx) return;

    J_Font* f = (J_Font*)font_ptr;
    J_Vector2 pos = { (float)x, (float)y };
    J_Color clr = {
        (unsigned char)(color & 255),
        (unsigned char)((color >> 8) & 255),
        (unsigned char)((color >> 16) & 255),
        (unsigned char)((color >> 24) & 255)
    };
    p_DrawTextEx(*f, (const char*)text_ptr, pos, (float)size, (float)spacing, clr);
}

void juno_draw_text_safe(const char* text, int64_t x, int64_t y, int64_t size, int64_t color) {
    if (!text) return;
    juno_load_raylib();
    if (!p_DrawText) return;

    J_Color clr = {
        (unsigned char)(color & 255),
        (unsigned char)((color >> 8) & 255),
        (unsigned char)((color >> 16) & 255),
        (unsigned char)((color >> 24) & 255)
    };
    p_DrawText(text, (int)x, (int)y, (int)size, clr);
}

int64_t concat(int64_t s1_ptr, int64_t s2_ptr) {
    const char* s1 = s1_ptr ? (const char*)s1_ptr : "";
    const char* s2 = s2_ptr ? (const char*)s2_ptr : "";

    size_t len1 = strlen(s1);
    size_t len2 = strlen(s2);
    if (len1 > SIZE_MAX - len2 - 1) juno_alloc_fail();

    char* res = juno_new_string(len1 + len2);
    memcpy(res, s1, len1);
    memcpy(res + len1, s2, len2);
    return (int64_t)res;
}

int64_t trim(int64_t s_ptr) {
    const char* s = s_ptr ? (const char*)s_ptr : "";
    const char* start = s;
    while (*start && isspace_fast((unsigned char)*start)) start++;

    if (*start == '\0') return (int64_t)juno_new_empty_string();

    const char* end = start + strlen(start) - 1;
    while (end > start && isspace_fast((unsigned char)*end)) end--;

    size_t len = (size_t)(end - start + 1);
    char* res = juno_new_string(len);
    memcpy(res, start, len);
    return (int64_t)res;
}

int64_t file_read_all(int64_t path_ptr) {
    const char* path = path_ptr ? (const char*)path_ptr : NULL;
    if (!path) return (int64_t)juno_new_empty_string();

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return (int64_t)juno_new_empty_string();

    struct stat st;
    if (fstat(fd, &st) < 0 || st.st_size < 0) {
        close(fd);
        return (int64_t)juno_new_empty_string();
    }

    size_t size = (size_t)st.st_size;
    char* buf = (char*)malloc(size + 1);
    if (!buf) {
        close(fd);
        return juno_alloc_fail();
    }

    size_t total = 0;
    while (total < size) {
        ssize_t n = read(fd, buf + total, size - total);
        if (n < 0) {
            if (errno == EINTR) continue;
            free(buf);
            close(fd);
            return (int64_t)juno_new_empty_string();
        }
        if (n == 0) break;
        total += (size_t)n;
    }

    buf[total] = '\0';
    close(fd);
    return (int64_t)buf;
}

int64_t file_read_safe(int64_t path_ptr) {
    return file_read_all(path_ptr);
}

int64_t exists(int64_t path_ptr) {
    const char* path = (const char*)path_ptr;
    if (!path) return 0;
    return access(path, F_OK) == 0 ? 1 : 0;
}

int64_t juno_strlen(int64_t s_ptr) {
    const char* s = (const char*)s_ptr;
    if (!s) return 0;
    return (int64_t)strlen(s);
}

int64_t juno_pow(int64_t base, int64_t exp) {
    if (exp < 0) return 0;
    int64_t res = 1;
    while (exp > 0) {
        if (exp & 1) res *= base;
        base *= base;
        exp >>= 1;
    }
    return res;
}

int64_t substr(int64_t s_ptr, int64_t start, int64_t len) {
    const char* s = s_ptr ? (const char*)s_ptr : "";
    size_t slen = strlen(s);

    if (start < 0 || len < 0 || (size_t)start > slen) {
        return (int64_t)juno_new_empty_string();
    }

    size_t ustart = (size_t)start;
    size_t ulen = (size_t)len;
    if (ustart + ulen > slen) ulen = slen - ustart;

    char* res = juno_new_string(ulen);
    memcpy(res, s + ustart, ulen);
    return (int64_t)res;
}

int64_t prints(int64_t s_ptr) {
    const char* s = (const char*)s_ptr;
    if (s) {
        fputs(s, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
    return 0;
}

#if defined(__APPLE__)

#include <sys/mman.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/event.h>

#if defined(__aarch64__) || defined(__arm64__)
int64_t juno_syscall_stub(int64_t number, ...) __asm__("_syscall");

int64_t juno_syscall_stub(int64_t number, ...) {
    (void)number;
    errno = ENOSYS;
    return -1;
}
#endif

int64_t juno_mmap(int64_t addr, int64_t length, int64_t prot, int64_t flags, int64_t fd, int64_t offset) {
    int mmap_flags = 0;
    if (flags & 0x02) mmap_flags |= MAP_PRIVATE;
    if (flags & 0x20) mmap_flags |= MAP_ANON;
    void* result = mmap((void*)addr, (size_t)length, (int)prot, mmap_flags, (int)fd, (off_t)offset);
    if (result == MAP_FAILED) return -1;
    return (int64_t)result;
}

int64_t juno_munmap(int64_t addr, int64_t length) {
    return munmap((void*)addr, (size_t)length);
}

int64_t juno_clock_gettime(int64_t clk_id, int64_t ts_ptr) {
    return clock_gettime((clockid_t)clk_id, (struct timespec*)ts_ptr);
}

#define EPOLLIN      0x001
#define EPOLLOUT     0x004
#define EPOLLERR     0x008
#define EPOLLHUP     0x010

#define EPOLL_CTL_ADD 1
#define EPOLL_CTL_DEL 2
#define EPOLL_CTL_MOD 3

typedef union epoll_data {
    void    *ptr;
    int      fd;
    uint32_t u32;
    uint64_t u64;
} epoll_data_t;

struct epoll_event {
    uint32_t     events;
    epoll_data_t data;
} __attribute__((packed));

int epoll_create(int size) {
    (void)size;
    return kqueue();
}

int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event) {
    struct kevent ev;
    uint32_t events = event ? event->events : 0;
    int filter = 0;
    if (events & EPOLLIN)  filter |= EVFILT_READ;
    if (events & EPOLLOUT) filter |= EVFILT_WRITE;

    int flags = (op == EPOLL_CTL_DEL) ? EV_DELETE : (EV_ADD | EV_ENABLE);
    void *udata = event ? event->data.ptr : NULL;

    EV_SET(&ev, fd, filter != 0 ? filter : EVFILT_READ, flags, 0, 0, udata);
    return kevent(epfd, &ev, 1, NULL, 0, NULL);
}

int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout) {
    if (maxevents <= 0 || !events) return 0;

    struct timespec ts;
    struct timespec *tsp = NULL;
    if (timeout >= 0) {
        ts.tv_sec = timeout / 1000;
        ts.tv_nsec = (long)(timeout % 1000) * 1000000L;
        tsp = &ts;
    }

    struct kevent *evlist = (struct kevent*)malloc((size_t)maxevents * sizeof(struct kevent));
    if (!evlist) return -1;

    int n = kevent(epfd, NULL, 0, evlist, maxevents, tsp);
    if (n > 0) {
        for (int i = 0; i < n; i++) {
            uint32_t ep_ev = 0;
            if (evlist[i].filter == EVFILT_READ)  ep_ev |= EPOLLIN;
            if (evlist[i].filter == EVFILT_WRITE) ep_ev |= EPOLLOUT;
            if (evlist[i].flags & EV_ERROR)        ep_ev |= EPOLLERR;

            events[i].events = ep_ev;
            events[i].data.fd = (int)evlist[i].ident;
        }
    }
    free(evlist);
    return n;
}

#endif
