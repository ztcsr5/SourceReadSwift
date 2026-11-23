#include "ZlibBridge.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

// Small system-zlib bridge used by the Legado Java compatibility layer.  The
// Compression.framework stream API is intentionally kept as a fallback, but
// zlib is the canonical decoder here because it has well-defined wrapper and
// raw-DEFLATE modes and reports the exact output length.
int32_t sourceread_zlib_inflate(const uint8_t *source,
                                size_t source_length,
                                uint8_t **destination,
                                size_t *destination_length,
                                int32_t raw_deflate) {
    if (source == NULL || source_length == 0 || destination == NULL || destination_length == NULL) {
        return Z_STREAM_ERROR;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int window_bits = raw_deflate ? -MAX_WBITS : MAX_WBITS;
    int status = inflateInit2(&stream, window_bits);
    if (status != Z_OK) {
        return status;
    }

    size_t capacity = source_length < 1024 ? 1024 : source_length * 4;
    if (capacity < source_length) {
        inflateEnd(&stream);
        return Z_MEM_ERROR;
    }

    uint8_t *output = (uint8_t *)malloc(capacity);
    if (output == NULL) {
        inflateEnd(&stream);
        return Z_MEM_ERROR;
    }

    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)source_length;
    size_t produced = 0;
    status = Z_OK;

    while (status == Z_OK) {
        if (produced == capacity) {
            size_t next_capacity = capacity > (SIZE_MAX / 2) ? 0 : capacity * 2;
            if (next_capacity == 0) {
                free(output);
                inflateEnd(&stream);
                return Z_MEM_ERROR;
            }
            uint8_t *grown = (uint8_t *)realloc(output, next_capacity);
            if (grown == NULL) {
                free(output);
                inflateEnd(&stream);
                return Z_MEM_ERROR;
            }
            output = grown;
            capacity = next_capacity;
        }

        stream.next_out = output + produced;
        stream.avail_out = (uInt)((capacity - produced) > UINT_MAX ? UINT_MAX : (capacity - produced));
        uInt before = stream.avail_out;
        status = inflate(&stream, Z_FINISH);
        produced += (size_t)(before - stream.avail_out);

        if (status == Z_BUF_ERROR && stream.avail_in == 0 && stream.avail_out > 0) {
            // No progress with all input consumed means a truncated/invalid
            // stream, not a successful empty result.
            status = Z_DATA_ERROR;
        }
    }

    inflateEnd(&stream);
    if (status != Z_STREAM_END) {
        free(output);
        return status;
    }

    *destination = output;
    *destination_length = produced;
    return Z_OK;
}

int32_t sourceread_zlib_gzip(const uint8_t *source, size_t source_length,
                            uint8_t **destination, size_t *destination_length) {
    if ((source == NULL && source_length != 0) || source_length > UINT_MAX ||
        destination == NULL || destination_length == NULL) {
        return Z_STREAM_ERROR;
    }
    *destination = NULL;
    *destination_length = 0;
    z_stream stream = {0};
    int status = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY);
    if (status != Z_OK) {
        return status;
    }
    uLong capacity = deflateBound(&stream, (uLong)source_length);
    uint8_t *output = capacity > source_length && capacity <= UINT_MAX ? malloc((size_t)capacity) : NULL;
    if (output == NULL) {
        deflateEnd(&stream);
        return Z_MEM_ERROR;
    }
    stream.next_in = (Bytef *)source;
    stream.avail_in = (uInt)source_length;
    stream.next_out = output;
    stream.avail_out = (uInt)capacity;
    status = deflate(&stream, Z_FINISH);
    size_t size = (size_t)capacity - stream.avail_out;
    deflateEnd(&stream);
    if (status != Z_STREAM_END) {
        free(output);
        return status == Z_OK ? Z_BUF_ERROR : status;
    }
    *destination = output;
    *destination_length = size;
    return Z_OK;
}

void sourceread_zlib_free(uint8_t *buffer) {
    free(buffer);
}
