package webserver
/*

import "core:fmt"
import "core:net"
import "core:os"

HTTP_PORT :: 8080

main :: proc() {
    endpoint := net.Endpoint{net.IP4_Address{0, 0, 0, 0}, HTTP_PORT}
    socket, err := net.listen_tcp(endpoint)
    if err != nil {
        fmt.eprintf("Failed to listen on port %d: %v\n", HTTP_PORT, err)
        os.exit(1)
    }
    defer net.close(socket)

    fmt.printf("Server listening on http://localhost:%d\n", HTTP_PORT)

    buf: [65536]byte

    for {
        client, source, accept_err := net.accept_tcp(socket)
        if accept_err != nil {
            fmt.eprintf("Accept error: %v\n", accept_err)
            continue
        }

        n, recv_err := net.recv_tcp(client, buf[:])
        if recv_err != nil || n == 0 {
            net.close(client)
            continue
        }

        data := buf[:n]

        if is_websocket_upgrade_request(data) {
            handle_websocket(client, data)
            // WebSocket handler already closes client on exit
        } else {
            handle_http(client, data)
            net.close(client)
        }
    }
}
*/

