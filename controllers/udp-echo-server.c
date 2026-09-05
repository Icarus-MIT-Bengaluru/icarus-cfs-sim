/*
 * ICARUS Phase 3 - UDP device-simulator echo server.
 *
 * One binary serves all three controllers; identity and port come from the
 * environment so ADCS, Payload, and Comms remain separately configured
 * containers running the same image.
 *
 * This is a placeholder transport endpoint, NOT a device model. It deliberately
 * handles one datagram at a time and never exits on bad input: rejecting
 * malformed traffic while staying alive is the behavior Phase 6 tests.
 *
 * Protocol (see docs/peripherals.md):
 *   request   ICARUS|HELLO|<token>
 *   response  ICARUS|ACK|<token>|<controller>
 */
#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define MAX_PAYLOAD    512
#define MAX_TOKEN      128
#define REQUEST_PREFIX "ICARUS|HELLO|"
#define LOG_PATH       "/logs/controller.log"

static volatile sig_atomic_t stop_requested;
static FILE *log_fp;
static const char *controller_name = "unknown";

static void on_signal(int sig)
{
    (void)sig;
    stop_requested = 1;
}

/* Every line: UTC timestamp, component identity, event type, then detail. */
static void log_event(const char *event, const char *fmt, ...)
{
    char stamp[32];
    char detail[1024];
    time_t now = time(NULL);
    struct tm tm;
    va_list ap;

    gmtime_r(&now, &tm);
    strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%SZ", &tm);

    va_start(ap, fmt);
    vsnprintf(detail, sizeof(detail), fmt, ap);
    va_end(ap);

    if (log_fp != NULL)
    {
        fprintf(log_fp, "%s %s %s %s\n", stamp, controller_name, event, detail);
    }
    printf("%s %s %s %s\n", stamp, controller_name, event, detail);
    fflush(stdout);
}

/* Printable ASCII only; keeps log lines parseable and rejects binary junk. */
static int is_printable(const char *buf, size_t len)
{
    for (size_t i = 0; i < len; i++)
    {
        unsigned char c = (unsigned char)buf[i];
        if (c < 0x20 || c > 0x7E)
        {
            return 0;
        }
    }
    return 1;
}

static long parse_port(const char *value)
{
    char *end = NULL;
    long port;

    errno = 0;
    port = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || port < 1 || port > 65535)
    {
        return -1;
    }
    return port;
}

int main(void)
{
    const char *port_env;
    long port;
    int fd;
    struct sockaddr_in bind_addr;
    struct sigaction sa;

    controller_name = getenv("CONTROLLER_NAME");
    port_env = getenv("CONTROLLER_UDP_PORT");

    if (controller_name == NULL || controller_name[0] == '\0')
    {
        fprintf(stderr, "CONTROLLER_NAME must be set\n");
        return 2;
    }
    if (port_env == NULL || (port = parse_port(port_env)) < 0)
    {
        fprintf(stderr, "CONTROLLER_UDP_PORT must be a valid port number\n");
        return 2;
    }

    log_fp = fopen(LOG_PATH, "a");
    if (log_fp != NULL)
    {
        setvbuf(log_fp, NULL, _IOLBF, 0);
    }
    else
    {
        fprintf(stderr, "warning: cannot open %s: %s\n", LOG_PATH, strerror(errno));
    }

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    log_event("START", "controller started; udp_port=%ld", port);

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
    {
        log_event("FATAL", "socket() failed: %s", strerror(errno));
        return 1;
    }

    memset(&bind_addr, 0, sizeof(bind_addr));
    bind_addr.sin_family = AF_INET;
    bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    bind_addr.sin_port = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr *)&bind_addr, sizeof(bind_addr)) < 0)
    {
        log_event("FATAL", "bind to udp/%ld failed: %s", port, strerror(errno));
        close(fd);
        return 1;
    }

    log_event("LISTEN", "bound udp 0.0.0.0:%ld", port);

    while (!stop_requested)
    {
        char buf[MAX_PAYLOAD + 1];
        char reply[MAX_PAYLOAD + 64];
        char peer[INET_ADDRSTRLEN] = "?";
        struct sockaddr_in src;
        socklen_t src_len = sizeof(src);
        ssize_t n;
        const char *token;
        size_t token_len;
        int reply_len;

        /* MSG_TRUNC reports the true datagram size, so oversize is detectable
         * rather than silently truncated. */
        n = recvfrom(fd, buf, MAX_PAYLOAD, MSG_TRUNC, (struct sockaddr *)&src, &src_len);
        if (n < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            log_event("ERROR", "recvfrom failed: %s", strerror(errno));
            continue;
        }

        inet_ntop(AF_INET, &src.sin_addr, peer, sizeof(peer));

        if (n > MAX_PAYLOAD)
        {
            log_event("REJECT", "src=%s:%u reason=oversize bytes=%zd limit=%d",
                      peer, ntohs(src.sin_port), n, MAX_PAYLOAD);
            continue;
        }

        buf[n] = '\0';

        if (!is_printable(buf, (size_t)n))
        {
            log_event("REJECT", "src=%s:%u reason=non-printable bytes=%zd",
                      peer, ntohs(src.sin_port), n);
            continue;
        }
        if (strncmp(buf, REQUEST_PREFIX, strlen(REQUEST_PREFIX)) != 0)
        {
            log_event("REJECT", "src=%s:%u reason=bad-prefix payload=%s",
                      peer, ntohs(src.sin_port), buf);
            continue;
        }

        token = buf + strlen(REQUEST_PREFIX);
        token_len = strlen(token);
        if (token_len == 0 || token_len > MAX_TOKEN || strchr(token, '|') != NULL)
        {
            log_event("REJECT", "src=%s:%u reason=bad-token payload=%s",
                      peer, ntohs(src.sin_port), buf);
            continue;
        }

        log_event("RX", "src=%s:%u token=%s payload=%s",
                  peer, ntohs(src.sin_port), token, buf);

        reply_len = snprintf(reply, sizeof(reply), "ICARUS|ACK|%s|%s",
                             token, controller_name);
        if (reply_len < 0 || (size_t)reply_len >= sizeof(reply))
        {
            log_event("ERROR", "token=%s reason=reply-too-long", token);
            continue;
        }

        if (sendto(fd, reply, (size_t)reply_len, 0,
                   (struct sockaddr *)&src, src_len) < 0)
        {
            log_event("ERROR", "token=%s sendto failed: %s", token, strerror(errno));
            continue;
        }

        log_event("TX", "dst=%s:%u token=%s payload=%s",
                  peer, ntohs(src.sin_port), token, reply);
    }

    log_event("STOP", "controller stopping");
    close(fd);
    if (log_fp != NULL)
    {
        fclose(log_fp);
    }
    return 0;
}
