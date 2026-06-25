#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

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

static const char empty_str[1] = {0};

static inline int isspace_fast(unsigned char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

long juno_load_font(long filename_ptr) {
    J_Font* f = (J_Font*)malloc(sizeof(J_Font));
    if (!f) return 0;
    *f = LoadFont((char*)filename_ptr);
    return (long)f;
}

void juno_draw_text(long font_ptr, long text_ptr, long x, long y, long size, long spacing, long color) {
    J_Font* f = (J_Font*)font_ptr;
    J_Vector2 pos = { (float)x, (float)y };
    J_Color clr = { 
        (unsigned char)(color & 255), 
        (unsigned char)((color >> 8) & 255), 
        (unsigned char)((color >> 16) & 255), 
        (unsigned char)((color >> 24) & 255) 
    };
    DrawTextEx(*f, (char*)text_ptr, pos, (float)size, (float)spacing, clr);
}

long concat(long s1_ptr, long s2_ptr) {
    const char* s1 = s1_ptr ? (const char*)s1_ptr : empty_str;
    const char* s2 = s2_ptr ? (const char*)s2_ptr : empty_str;
    
    size_t len1 = strlen(s1);
    size_t len2 = strlen(s2);
    char* res = (char*)malloc(len1 + len2 + 1);
    if (!res) return (long)empty_str;
    
    memcpy(res, s1, len1);
    memcpy(res + len1, s2, len2);
    res[len1 + len2] = '\0';
    return (long)res;
}

long trim(long s_ptr) {
    char* s = (char*)s_ptr;
    if (!s || *s == '\0') return s_ptr;
    
    while (*s && isspace_fast((unsigned char)*s)) s++;
    if (*s == '\0') return (long)s;

    char* end = s + strlen(s) - 1;
    while (end > s && isspace_fast((unsigned char)*end)) end--;
    *(end + 1) = '\0';
    
    return (long)s;
}

long file_read_all(long path_ptr) {
    const char* path = (const char*)path_ptr;
    if (!path) return (long)empty_str;

    int fd = open(path, O_RDONLY);
    if (fd < 0) return (long)empty_str;
    
    struct stat st;
    if (fstat(fd, &st) < 0) { close(fd); return (long)empty_str; }
    
    size_t size = st.st_size;
    if (size == 0) size = 4096;
    
    char* buf = (char*)malloc(size + 1);
    if (!buf) { close(fd); return (long)empty_str; }
    
    ssize_t n = read(fd, buf, size);
    if (n < 0) { free(buf); close(fd); return (long)empty_str; }
    
    buf[n] = '\0';
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
    long res = 1;
    while (exp > 0) {
        if (exp & 1) res *= base;
        base *= base;
        exp >>= 1;
    }
    return res;
}

long substr(long s_ptr, long start, long len) {
    const char* s = (const char*)s_ptr;
    if (!s) return (long)empty_str;
    size_t slen = strlen(s);
    if (start >= slen) return (long)empty_str;
    if (start + len > slen) len = slen - start;
    
    char* res = (char*)malloc(len + 1);
    if (!res) return (long)empty_str;
    memcpy(res, s + start, len);
    res[len] = '\0';
    return (long)res;
}

long prints(long s_ptr) {
    const char* s = (const char*)s_ptr;
    if (s) {
        puts(s);
        fflush(stdout);
    }
    return 0;
}
