#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#ifdef __APPLE__
#define syscall _macos_syscall
#include <unistd.h>
#undef syscall
#else
#include <unistd.h>
#endif
#include <fcntl.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <math.h>

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

#ifdef __GNUC__
__attribute__((weak)) void DrawTextEx(J_Font font, const char *text, J_Vector2 position, float fontSize, float spacing, J_Color tint) {}
__attribute__((weak)) J_Font LoadFont(const char *fileName) { J_Font f = {0}; return f; }
#else
extern void DrawTextEx(J_Font font, const char *text, J_Vector2 position, float fontSize, float spacing, J_Color tint);
extern J_Font LoadFont(const char *fileName);
#endif

static inline int isspace_fast(unsigned char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

static long juno_alloc_fail(void) {
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

long juno_sin(long x) { union { long l; double d; } u; u.l = x; u.d = sin(u.d); return u.l; }
long juno_cos(long x) { union { long l; double d; } u; u.l = x; u.d = cos(u.d); return u.l; }
long juno_tan(long x) { union { long l; double d; } u; u.l = x; u.d = tan(u.d); return u.l; }
long juno_asin(long x) { union { long l; double d; } u; u.l = x; u.d = asin(u.d); return u.l; }
long juno_acos(long x) { union { long l; double d; } u; u.l = x; u.d = acos(u.d); return u.l; }
long juno_atan(long x) { union { long l; double d; } u; u.l = x; u.d = atan(u.d); return u.l; }
long juno_atan2(long y, long x) { union { long l; double d; } uy, ux; uy.l = y; ux.l = x; uy.d = atan2(uy.d, ux.d); return uy.l; }
long juno_sqrt(long x) { union { long l; double d; } u; u.l = x; u.d = sqrt(u.d); return u.l; }
long juno_cbrt(long x) { union { long l; double d; } u; u.l = x; u.d = cbrt(u.d); return u.l; }
long juno_fpow(long b, long e) { union { long l; double d; } ub, ue; ub.l = b; ue.l = e; ub.d = pow(ub.d, ue.d); return ub.l; }
long juno_exp(long x) { union { long l; double d; } u; u.l = x; u.d = exp(u.d); return u.l; }
long juno_log(long x) { union { long l; double d; } u; u.l = x; u.d = log(u.d); return u.l; }
long juno_log2(long x) { union { long l; double d; } u; u.l = x; u.d = log2(u.d); return u.l; }
long juno_log10(long x) { union { long l; double d; } u; u.l = x; u.d = log10(u.d); return u.l; }
long juno_floor(long x) { union { long l; double d; } u; u.l = x; u.d = floor(u.d); return u.l; }
long juno_ceil(long x) { union { long l; double d; } u; u.l = x; u.d = ceil(u.d); return u.l; }
long juno_round(long x) { union { long l; double d; } u; u.l = x; u.d = round(u.d); return u.l; }
long juno_trunc(long x) { union { long l; double d; } u; u.l = x; u.d = trunc(u.d); return u.l; }
long juno_fabs(long x) { union { long l; double d; } u; u.l = x; u.d = fabs(u.d); return u.l; }
long juno_fmod(long x, long y) { union { long l; double d; } ux, uy; ux.l = x; uy.l = y; ux.d = fmod(ux.d, uy.d); return ux.l; }
long juno_hypot(long x, long y) { union { long l; double d; } ux, uy; ux.l = x; uy.l = y; ux.d = hypot(ux.d, uy.d); return ux.l; }
long juno_float_to_int(long f_bits) { union { long l; double d; } u; u.l = f_bits; return (long)u.d; }
long juno_float_round_to_int(long f_bits) { union { long l; double d; } u; u.l = f_bits; return (long)llround(u.d); }

long juno_load_font(long filename_ptr) {
    J_Font* f = (J_Font*)malloc(sizeof(J_Font));
    if (!f) return juno_alloc_fail();
    *f = LoadFont((const char*)filename_ptr);
    return (long)f;
}

void juno_draw_text(long font_ptr, long text_ptr, long x, long y, long size, long spacing, long color) {
    if (!font_ptr || !text_ptr) return;
    J_Font* f = (J_Font*)font_ptr;
    J_Vector2 pos = { (float)x, (float)y };
    J_Color clr = {
        (unsigned char)(color & 255),
        (unsigned char)((color >> 8) & 255),
        (unsigned char)((color >> 16) & 255),
        (unsigned char)((color >> 24) & 255)
    };
    DrawTextEx(*f, (const char*)text_ptr, pos, (float)size, (float)spacing, clr);
}

long concat(long s1_ptr, long s2_ptr) {
    const char* s1 = s1_ptr ? (const char*)s1_ptr : "";
    const char* s2 = s2_ptr ? (const char*)s2_ptr : "";

    size_t len1 = strlen(s1);
    size_t len2 = strlen(s2);
    if (len1 > SIZE_MAX - len2 - 1) juno_alloc_fail();

    char* res = juno_new_string(len1 + len2);
    memcpy(res, s1, len1);
    memcpy(res + len1, s2, len2);
    return (long)res;
}

long trim(long s_ptr) {
    const char* s = s_ptr ? (const char*)s_ptr : "";
    const char* start = s;
    while (*start && isspace_fast((unsigned char)*start)) start++;

    if (*start == '\0') return (long)juno_new_empty_string();

    const char* end = start + strlen(start) - 1;
    while (end > start && isspace_fast((unsigned char)*end)) end--;

    size_t len = (size_t)(end - start + 1);
    char* res = juno_new_string(len);
    memcpy(res, start, len);
    return (long)res;
}

long file_read_all(long path_ptr) {
    const char* path = path_ptr ? (const char*)path_ptr : NULL;
    if (!path) return (long)juno_new_empty_string();

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return (long)juno_new_empty_string();

    struct stat st;
    if (fstat(fd, &st) < 0 || st.st_size < 0) {
        close(fd);
        return (long)juno_new_empty_string();
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
            return (long)juno_new_empty_string();
        }
        if (n == 0) break;
        total += (size_t)n;
    }

    buf[total] = '\0';
    close(fd);
    return (long)buf;
}

long file_read_safe(long path_ptr) {
    return file_read_all(path_ptr);
}

long exists(long path_ptr) {
    const char* path = (const char*)path_ptr;
    if (!path) return 0;
    return access(path, F_OK) == 0 ? 1 : 0;
}

long juno_strlen(long s_ptr) {
    const char* s = (const char*)s_ptr;
    if (!s) return 0;
    return (long)strlen(s);
}

long juno_pow(long base, long exp) {
    if (exp < 0) return 0;
    long res = 1;
    while (exp > 0) {
        if (exp & 1) res *= base;
        base *= base;
        exp >>= 1;
    }
    return res;
}

long substr(long s_ptr, long start, long len) {
    const char* s = s_ptr ? (const char*)s_ptr : "";
    size_t slen = strlen(s);

    if (start < 0 || len < 0 || (size_t)start > slen) {
        return (long)juno_new_empty_string();
    }

    size_t ustart = (size_t)start;
    size_t ulen = (size_t)len;
    if (ustart + ulen > slen) ulen = slen - ustart;

    char* res = juno_new_string(ulen);
    memcpy(res, s + ustart, ulen);
    return (long)res;
}

long prints(long s_ptr) {
    const char* s = (const char*)s_ptr;
    if (s) {
        fputs(s, stdout);
        fputc('\n', stdout);
        fflush(stdout);
    }
    return 0;
}

#ifdef __APPLE__
#include <sys/mman.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/event.h>

long juno_mmap(long addr, long length, long prot, long flags, long fd, long offset) {
    int mmap_flags = 0;
    if (flags & 0x02) mmap_flags |= MAP_PRIVATE;
    if (flags & 0x20) mmap_flags |= MAP_ANON;
    void* result = mmap((void*)addr, (size_t)length, (int)prot, mmap_flags, (int)fd, (off_t)offset);
    if (result == MAP_FAILED) return -1;
    return (long)result;
}

long juno_munmap(long addr, long length) {
    return munmap((void*)addr, (size_t)length);
}

long juno_clock_gettime(long clk_id, long ts_ptr) {
    return clock_gettime((clockid_t)clk_id, (struct timespec*)ts_ptr);
}

int epoll_create(int size) {
    (void)size;
    return kqueue();
}

int epoll_ctl(int epfd, int op, int fd, void *event) {
    struct kevent ev;
    int events = event ? *(int*)event : 0;
    int filter = 0;
    if (events & 1) filter |= EVFILT_READ;
    if (events & 4) filter |= EVFILT_WRITE;

    int flags = (op == 2) ? EV_DELETE : (EV_ADD | EV_ENABLE);
    EV_SET(&ev, fd, filter != 0 ? filter : EVFILT_READ, flags, 0, 0, NULL);
    return kevent(epfd, &ev, 1, NULL, 0, NULL);
}

int epoll_wait(int epfd, void *events, int maxevents, int timeout) {
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
        int *out_events = (int*)events;
        for (int i = 0; i < n; i++) {
            int ep_ev = 0;
            if (evlist[i].filter == EVFILT_READ) ep_ev |= 1;
            if (evlist[i].filter == EVFILT_WRITE) ep_ev |= 4;
            out_events[i * 2] = ep_ev;
            out_events[i * 2 + 1] = (int)evlist[i].ident;
        }
    }
    free(evlist);
    return n;
}
#endif
