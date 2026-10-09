#include "csmc.h"

#include <string.h>
#include <IOKit/IOKitLib.h>

/* Layout da struct do AppleSMC. Deixamos o compilador C calcular o
   alinhamento — é precisamente por isto que esta camada é C e não Swift. */
typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } vers;
    struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } pLimitData;
    struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } keyInfo;
    uint8_t  result, status, data8;
    uint32_t data32;
    uint8_t  bytes[32];
} SMCParam;

/* Selectors do AppleSMC userclient. */
enum { kSMCUserClientOpen = 2 };
enum { kSMCReadBytes = 5, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

static io_connect_t g_conn = 0;

static uint32_t key_from_string(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16)
         | ((uint32_t)s[2] << 8)  | (uint32_t)s[3];
}

static void string_from_key(uint32_t k, char *out) {
    out[0] = (char)(k >> 24); out[1] = (char)(k >> 16);
    out[2] = (char)(k >> 8);  out[3] = (char)k; out[4] = '\0';
}

static int smc_call(SMCParam *in, SMCParam *out) {
    size_t size = sizeof(SMCParam);
    return IOConnectCallStructMethod(g_conn, kSMCUserClientOpen,
                                     in, sizeof(SMCParam), out, &size);
}

bool csmc_open(void) {
    if (g_conn) return true;
    io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!service) return false;
    kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    if (r != kIOReturnSuccess) { g_conn = 0; return false; }
    return true;
}

void csmc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
}

/* Converte o buffer bruto segundo o tipo declarado pelo SMC.
   Os tipos que interessam à potência são "flt " e "ioft"; os restantes
   estão aqui porque a bateria e as temperaturas os usam. */
static bool decode(const char *type, uint32_t size, const uint8_t *b, double *out) {
    if (!strncmp(type, "flt ", 4) && size == 4) {
        float f; memcpy(&f, b, 4); *out = (double)f; return true;
    }
    if (!strncmp(type, "ioft", 4) && size == 8) {
        uint64_t v = 0;
        for (int i = 0; i < 8; i++) v = (v << 8) | b[i];
        *out = (double)v / 65536.0; return true;
    }
    if (!strncmp(type, "sp78", 4) && size == 2) {
        *out = (double)(int8_t)b[0] + b[1] / 256.0; return true;
    }
    if (!strncmp(type, "ui8 ", 4) && size == 1) { *out = b[0]; return true; }
    if (!strncmp(type, "ui16", 4) && size == 2) { *out = (b[0] << 8) | b[1]; return true; }
    if (!strncmp(type, "si16", 4) && size == 2) { *out = (int16_t)((b[0] << 8) | b[1]); return true; }
    if (!strncmp(type, "ui32", 4) && size == 4) {
        *out = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | (b[2] << 8) | b[3];
        return true;
    }
    if (!strncmp(type, "flag", 4) && size == 1) { *out = b[0] ? 1 : 0; return true; }
    return false;
}

bool csmc_read(const char *key, double *value_out, char *type_out) {
    if (!g_conn || strlen(key) != 4) return false;

    SMCParam in = {0}, out = {0};
    in.key = key_from_string(key);
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(&in, &out) != kIOReturnSuccess) return false;

    uint32_t size = out.keyInfo.dataSize;
    uint32_t swapped = __builtin_bswap32(out.keyInfo.dataType);
    char type[5]; memcpy(type, &swapped, 4); type[4] = '\0';
    if (type_out) memcpy(type_out, type, 5);
    if (size == 0 || size > 32) return false;

    in.keyInfo.dataSize = size;
    in.data8 = kSMCReadBytes;
    if (smc_call(&in, &out) != kIOReturnSuccess) return false;

    return decode(type, size, out.bytes, value_out);
}

uint32_t csmc_key_count(void) {
    if (!g_conn) return 0;
    const char *k = "#KEY";
    SMCParam info = {0}, info_out = {0};
    info.key = key_from_string(k);
    info.data8 = kSMCGetKeyInfo;
    if (smc_call(&info, &info_out) != kIOReturnSuccess) return 0;

    SMCParam in = {0}, out = {0};
    in.key = key_from_string(k);
    in.data8 = kSMCReadBytes;
    in.keyInfo.dataSize = info_out.keyInfo.dataSize;
    if (smc_call(&in, &out) != kIOReturnSuccess) return 0;

    return ((uint32_t)out.bytes[0] << 24) | ((uint32_t)out.bytes[1] << 16)
         | ((uint32_t)out.bytes[2] << 8)  | (uint32_t)out.bytes[3];
}

bool csmc_key_at(uint32_t index, char *key_out) {
    if (!g_conn) return false;
    SMCParam in = {0}, out = {0};
    in.data8 = kSMCGetKeyFromIndex;
    in.data32 = index;
    if (smc_call(&in, &out) != kIOReturnSuccess) return false;
    string_from_key(out.key, key_out);
    return true;
}
