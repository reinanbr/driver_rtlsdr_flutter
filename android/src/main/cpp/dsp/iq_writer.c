#include "iq_writer.h"

#include <stdio.h>
#include <stdlib.h>

struct iq_writer {
    FILE *fp;
};

iq_writer_t *iq_writer_open(const char *path) {
    if (!path) {
        return NULL;
    }
    FILE *fp = fopen(path, "wb");
    if (!fp) {
        return NULL;
    }
    iq_writer_t *w = (iq_writer_t *)malloc(sizeof(iq_writer_t));
    if (!w) {
        fclose(fp);
        return NULL;
    }
    w->fp = fp;
    return w;
}

int iq_writer_write(iq_writer_t *w, const uint8_t *data, size_t count) {
    if (!w || !w->fp || !data) {
        return -1;
    }
    size_t written = fwrite(data, 1, count, w->fp);
    return (written == count) ? 0 : -1;
}

void iq_writer_close(iq_writer_t *w) {
    if (!w) {
        return;
    }
    if (w->fp) {
        fclose(w->fp);
    }
    free(w);
}
