/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#include "adcs_sim.h"
#include "adcs_sim_udp.h"
#include "adcs_sim_eventids.h"

/*
 * Alias resolution note: OSAL has no name resolver, and this app addresses its
 * controller by Docker network alias ("adcs") because container IPs are not
 * stable. getaddrinfo() is therefore used once at init to turn the alias into a
 * dotted-quad, which is then handed to the OSAL socket API. This is a
 * simulation-only concession; a real target would be given a configured
 * address instead.
 */
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>

static CFE_Status_t ADCS_SIM_UDP_ResolveController(char *AddrText, size_t AddrTextLen)
{
    struct addrinfo  hints;
    struct addrinfo *res = NULL;
    int              rc;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    rc = getaddrinfo(ADCS_SIM_PLATFORM_CONTROLLER_HOST, NULL, &hints, &res);
    if (rc != 0 || res == NULL)
    {
        return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }

    if (inet_ntop(AF_INET, &((struct sockaddr_in *)res->ai_addr)->sin_addr,
                  AddrText, AddrTextLen) == NULL)
    {
        freeaddrinfo(res);
        return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }

    freeaddrinfo(res);
    return CFE_SUCCESS;
}

CFE_Status_t ADCS_SIM_UDP_Init(void)
{
    char  addr_text[INET_ADDRSTRLEN] = {0};
    int32 status;

    if (ADCS_SIM_UDP_ResolveController(addr_text, sizeof(addr_text)) != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(ADCS_SIM_UDP_INIT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "ADCS_SIM: cannot resolve controller '%s'",
                          ADCS_SIM_PLATFORM_CONTROLLER_HOST);
        return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }

    status = OS_SocketOpen(&ADCS_SIM_Data.UdpSocket, OS_SocketDomain_INET,
                           OS_SocketType_DATAGRAM);
    if (status != OS_SUCCESS)
    {
        CFE_EVS_SendEvent(ADCS_SIM_UDP_INIT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "ADCS_SIM: OS_SocketOpen failed, RC = %ld", (long)status);
        return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }

    OS_SocketAddrInit(&ADCS_SIM_Data.UdpPeer, OS_SocketDomain_INET);
    OS_SocketAddrFromString(&ADCS_SIM_Data.UdpPeer, addr_text);
    OS_SocketAddrSetPort(&ADCS_SIM_Data.UdpPeer, (uint16)ADCS_SIM_PLATFORM_CONTROLLER_PORT);

    return CFE_SUCCESS;
}

CFE_Status_t ADCS_SIM_UDP_SendHello(void)
{
    /*
     * Fixed request in the ICARUS placeholder protocol, matching the format the
     * controller echo server expects. See docs/peripherals.md.
     */
    static const char HelloPacket[] = "ICARUS|HELLO|adcs_sim";
    int32             status;

    if (!OS_ObjectIdDefined(ADCS_SIM_Data.UdpSocket))
    {
        return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }

    status = OS_SocketSendTo(ADCS_SIM_Data.UdpSocket, HelloPacket,
                             sizeof(HelloPacket) - 1, &ADCS_SIM_Data.UdpPeer);
    if (status < 0)
    {
        CFE_EVS_SendEvent(ADCS_SIM_UDP_SEND_ERR_EID, CFE_EVS_EventType_ERROR,
                          "ADCS_SIM: hello send to %s:%u failed, RC = %ld",
                          ADCS_SIM_PLATFORM_CONTROLLER_HOST,
                          (unsigned int)ADCS_SIM_PLATFORM_CONTROLLER_PORT, (long)status);
        return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }

    CFE_EVS_SendEvent(ADCS_SIM_UDP_HELLO_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "ADCS_SIM: sent hello to %s:%u payload=%s",
                      ADCS_SIM_PLATFORM_CONTROLLER_HOST,
                      (unsigned int)ADCS_SIM_PLATFORM_CONTROLLER_PORT, HelloPacket);

    return CFE_SUCCESS;
}

CFE_Status_t ADCS_SIM_UDP_Send(const void *Buffer, size_t Size)
{
    /* TODO: implement ADCS outbound traffic. */
    (void)Buffer;
    (void)Size;
    return CFE_STATUS_NOT_IMPLEMENTED;
}

CFE_Status_t ADCS_SIM_UDP_Receive(void *Buffer, size_t Size, size_t *Received, int32 TimeoutMs)
{
    /*
     * TODO: implement bounded receive. Phase 4 deliberately does not read
     * acknowledgements; the controller's own log is the delivery evidence.
     */
    (void)Buffer;
    (void)Size;
    (void)TimeoutMs;
    if (Received != NULL)
    {
        *Received = 0;
    }
    return CFE_STATUS_NOT_IMPLEMENTED;
}
