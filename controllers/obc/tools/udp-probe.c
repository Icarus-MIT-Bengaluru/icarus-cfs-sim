/*
 * ICARUS Phase 3 - OBC UDP transport probe.
 *
 * A temporary transport test tool. It is NOT a cFS application and NOT a flight
 * component: Phase 4 replaces it with per-app UDP adapters owned by adcs_sim,
 * payload_sim, and comms_sim.
 *
 * Sends one fixed request to exactly one controller alias/port, waits with a
 * bounded timeout, and returns nonzero on timeout or any response mismatch.
 *
 * Usage: icarus-udp-probe <alias> <port> <token> <timeout-seconds>
 *
 * Protocol (see docs/peripherals.md):
 *   request   ICARUS|HELLO|<token>
 *   response  ICARUS|ACK|<token>|<alias>
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <netdb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define MAX_PAYLOAD 512
#define LOG_PATH    "/logs/udp-probe.log"
#define COMPONENT   "obc"

#define EXIT_OK       0
#define EXIT_TIMEOUT  3
#define EXIT_MISMATCH 4
#define EXIT_ERROR    5

static FILE *log_fp;

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
        fprintf(log_fp, "%s %s %s %s\n", stamp, COMPONENT, event, detail);
    }
    printf("%s %s %s %s\n", stamp, COMPONENT, event, detail);
    fflush(stdout);
}

static long elapsed_ms(const struct timespec *a, const struct timespec *b)
{
    return (b->tv_sec - a->tv_sec) * 1000 + (b->tv_nsec - a->tv_nsec) / 1000000;
}

int main(int argc, char **argv)
{
    const char *alias;
    const char *port;
    const char *token;
    long timeout_s;
    char request[MAX_PAYLOAD];
    char expected[MAX_PAYLOAD];
    char response[MAX_PAYLOAD + 1];
    struct addrinfo hints;
    struct addrinfo *res = NULL;
    struct timeval tv;
    struct timespec t0, t1;
    int fd;
    int rc;
    ssize_t n;

    if (argc != 5)
    {
        fprintf(stderr, "usage: %s <alias> <port> <token> <timeout-seconds>\n", argv[0]);
        return EXIT_ERROR;
    }

    alias = argv[1];
    port = argv[2];
    token = argv[3];
    timeout_s = strtol(argv[4], NULL, 10);
    if (timeout_s < 1)
    {
        timeout_s = 1;
    }

    log_fp = fopen(LOG_PATH, "a");
    if (log_fp != NULL)
    {
        setvbuf(log_fp, NULL, _IOLBF, 0);
    }

    if (strchr(token, '|') != NULL || token[0] == '\0')
    {
        log_event("FAIL", "target=%s:%s reason=invalid-token", alias, port);
        return EXIT_ERROR;
    }

    snprintf(request, sizeof(request), "ICARUS|HELLO|%s", token);
    snprintf(expected, sizeof(expected), "ICARUS|ACK|%s|%s", token, alias);

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    rc = getaddrinfo(alias, port, &hints, &res);
    if (rc != 0)
    {
        log_event("FAIL", "target=%s:%s reason=resolve-failed detail=%s",
                  alias, port, gai_strerror(rc));
        return EXIT_ERROR;
    }

    fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0)
    {
        log_event("FAIL", "target=%s:%s reason=socket-failed detail=%s",
                  alias, port, strerror(errno));
        freeaddrinfo(res);
        return EXIT_ERROR;
    }

    tv.tv_sec = timeout_s;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    log_event("PROBE", "target=%s:%s token=%s request=%s", alias, port, token, request);
    clock_gettime(CLOCK_MONOTONIC, &t0);

    if (sendto(fd, request, strlen(request), 0, res->ai_addr, res->ai_addrlen) < 0)
    {
        log_event("FAIL", "target=%s:%s token=%s reason=send-failed detail=%s",
                  alias, port, token, strerror(errno));
        close(fd);
        freeaddrinfo(res);
        return EXIT_ERROR;
    }

    n = recvfrom(fd, response, MAX_PAYLOAD, 0, NULL, NULL);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    close(fd);
    freeaddrinfo(res);

    if (n < 0)
    {
        if (errno == EAGAIN || errno == EWOULDBLOCK)
        {
            log_event("FAIL", "target=%s:%s token=%s reason=timeout after=%lds",
                      alias, port, token, timeout_s);
            return EXIT_TIMEOUT;
        }
        log_event("FAIL", "target=%s:%s token=%s reason=recv-failed detail=%s",
                  alias, port, token, strerror(errno));
        return EXIT_ERROR;
    }

    response[n] = '\0';

    if (strcmp(response, expected) != 0)
    {
        log_event("FAIL", "target=%s:%s token=%s reason=mismatch expected=%s actual=%s",
                  alias, port, token, expected, response);
        return EXIT_MISMATCH;
    }

    log_event("ACK", "target=%s:%s token=%s response=%s rtt_ms=%ld",
              alias, port, token, response, elapsed_ms(&t0, &t1));
    log_event("PASS", "target=%s:%s token=%s", alias, port, token);

    if (log_fp != NULL)
    {
        fclose(log_fp);
    }
    return EXIT_OK;
}
