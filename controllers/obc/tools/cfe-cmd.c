/*
 * ICARUS Phase 6 - cFE ground-command sender.
 *
 * Sends a CCSDS command packet to ci_lab's UDP ingest port. ci_lab forwards it
 * onto the Software Bus, so this is the real ground-command path rather than a
 * test backdoor: fault injection through it is faithful to how a command would
 * actually arrive.
 *
 * Usage: icarus-cfe-cmd <mid-hex> <fcncode> [app-name-arg]
 *   e.g. icarus-cfe-cmd 0x1806 4 ADCS_SIM     (CFE_ES_STOP_APP)
 *        icarus-cfe-cmd 0x18c0 3              (ADCS_SIM INJECT_STALL)
 *
 * Phase 7 reuses this for CFE_ES_RESTART_APP.
 *
 * Simulation scaffolding, not flight software.
 */
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define CI_LAB_HOST       "127.0.0.1"
#define CI_LAB_PORT_DEF   1234
#define APP_NAME_LEN      20          /* CFE_MISSION_MAX_API_LEN */
#define MAX_PACKET        128
#define LOG_PATH          "/logs/cfe-cmd.log"

/*
 * CCSDS primary header (6 bytes) + command secondary header (2 bytes).
 * This build has no CCSDS extended header: MISSION_INCLUDE_CCSDSEXT_HEADER is
 * not set anywhere in the mission config, so CFE_MSG_CommandHeader_t is 8
 * bytes total. A wrong header size here produces a packet SB silently drops.
 */
static void log_event(const char *event, const char *fmt, ...)
{
    char      stamp[32];
    char      detail[512];
    time_t    now = time(NULL);
    struct tm tm;
    va_list   ap;
    FILE *    fp;

    gmtime_r(&now, &tm);
    strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%SZ", &tm);

    va_start(ap, fmt);
    vsnprintf(detail, sizeof(detail), fmt, ap);
    va_end(ap);

    printf("%s obc %s %s\n", stamp, event, detail);
    fflush(stdout);

    fp = fopen(LOG_PATH, "a");
    if (fp != NULL)
    {
        fprintf(fp, "%s obc %s %s\n", stamp, event, detail);
        fclose(fp);
    }
}

int main(int argc, char **argv)
{
    unsigned char      pkt[MAX_PACKET];
    size_t             len;
    unsigned long      mid;
    unsigned long      fcn;
    const char *       arg = NULL;
    int                fd;
    struct sockaddr_in dst;
    unsigned int       i;
    unsigned char      sum;
    const char *       port_env;
    int                port = CI_LAB_PORT_DEF;

    if (argc < 3 || argc > 4)
    {
        fprintf(stderr, "usage: %s <mid-hex> <fcncode> [app-name-arg]\n", argv[0]);
        return 2;
    }

    mid = strtoul(argv[1], NULL, 0);
    fcn = strtoul(argv[2], NULL, 0);
    if (argc == 4)
    {
        arg = argv[3];
    }

    port_env = getenv("ICARUS_CI_LAB_PORT");
    if (port_env != NULL && *port_env != '\0')
    {
        port = (int)strtol(port_env, NULL, 10);
    }

    memset(pkt, 0, sizeof(pkt));

    /*
     * CCSDS primary header. Bits: version 0, type 1 (command), no secondary
     * header flag handling needed beyond setting it, APID from the MID.
     * CFE's MID for a command already encodes the type bits, so the low 11
     * bits are the APID and bit 12 (0x1000) marks it a command.
     */
    pkt[0] = (unsigned char)((mid >> 8) & 0xFF);
    pkt[1] = (unsigned char)(mid & 0xFF);
    pkt[2] = 0xC0; /* sequence flags = 3 (unsegmented), sequence count 0 */
    pkt[3] = 0x00;

    /* Command secondary header: function code in the low 7 bits. */
    pkt[6] = (unsigned char)(fcn & 0x7F);
    pkt[7] = 0x00; /* checksum placeholder */

    len = 8;

    if (arg != NULL)
    {
        /* CFE_ES_AppNameCmd_t payload: a fixed-length, null-padded name. */
        if (strlen(arg) >= APP_NAME_LEN)
        {
            log_event("FAIL", "app name '%s' is too long (max %d)", arg, APP_NAME_LEN - 1);
            return 2;
        }
        memcpy(&pkt[len], arg, strlen(arg));
        len += APP_NAME_LEN;
    }

    /* CCSDS length field counts the bytes after the primary header, minus 1. */
    pkt[4] = (unsigned char)(((len - 7) >> 8) & 0xFF);
    pkt[5] = (unsigned char)((len - 7) & 0xFF);

    /* cFE command checksum: XOR of the whole packet must come to 0xFF. */
    sum = 0xFF;
    for (i = 0; i < len; i++)
    {
        sum ^= pkt[i];
    }
    pkt[7] = sum;

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
    {
        log_event("FAIL", "socket failed: %s", strerror(errno));
        return 1;
    }

    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port   = htons((unsigned short)port);
    if (inet_pton(AF_INET, CI_LAB_HOST, &dst.sin_addr) != 1)
    {
        log_event("FAIL", "cannot parse %s", CI_LAB_HOST);
        close(fd);
        return 1;
    }

    if (sendto(fd, pkt, len, 0, (struct sockaddr *)&dst, sizeof(dst)) < 0)
    {
        log_event("FAIL", "sendto %s:%d failed: %s", CI_LAB_HOST, port, strerror(errno));
        close(fd);
        return 1;
    }
    close(fd);

    log_event("CMD", "sent mid=0x%04lX fcncode=%lu arg=%s bytes=%zu via ci_lab %s:%d",
              mid, fcn, (arg != NULL) ? arg : "-", len, CI_LAB_HOST, port);
    return 0;
}
