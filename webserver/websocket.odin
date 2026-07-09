package webserver

import "core:strings"

/*

import sha1 "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:fmt"
import "core:net"

WS_GUID :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

WebSocket_Opcode :: enum u8 {
	Continuation = 0x0,
	Text         = 0x1,
	Binary       = 0x2,
	Close        = 0x8,
	Ping         = 0x9,
	Pong         = 0xA,
}

WebSocket_Frame :: struct {
	fin:            bool,
	opcode:         WebSocket_Opcode,
	mask:           bool,
	payload_length: u64,
	mask_key:       [4]byte,
	payload:        []byte,
}

*/

is_websocket_upgrade_request :: proc(data: []byte) -> bool {
    request_str := string(data)
    if !strings.contains(request_str, "Upgrade: websocket") &&
       !strings.contains(request_str, "upgrade: websocket") {
        return false
    }
    if !strings.contains(request_str, "Connection: Upgrade") &&
       !strings.contains(request_str, "connection: upgrade") &&
       !strings.contains(request_str, "Connection: upgrade") &&
       !strings.contains(request_str, "connection: Upgrade") {
        return false
    }
    return true
}

/*

get_websocket_key :: proc(data: []byte) -> (string, bool) {
	request_str := string(data)
	lines := strings.split_lines(request_str)
	defer delete(lines)

	for line in lines {
		trimmed := strings.trim_space(line)
		lower := strings.to_lower(trimmed)
		defer delete(lower)
		if strings.has_prefix(lower, "sec-websocket-key:") {
			colon_pos := strings.index(trimmed, ":")
			if colon_pos == -1 {
				continue
			}
			key := strings.trim_space(trimmed[colon_pos + 1:])
			return key, true
		}
	}
	return "", false
}

compute_accept_key :: proc(key: string) -> (string, bool) {
	concatenated := strings.concatenate({key, WS_GUID})
	defer delete(concatenated)

	ctx: sha1.Context
	sha1.init(&ctx)
	sha1.update(&ctx, transmute([]byte)concatenated)

	digest: [sha1.DIGEST_SIZE]byte
	sha1.final(&ctx, digest[:])

	encoded, enc_err := base64.encode(digest[:])
	if enc_err != nil {
		return "", false
	}

	return encoded, true
}

send_websocket_upgrade_response :: proc(client: net.TCP_Socket, accept_key: string) {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	fmt.sbprintf(&sb, "HTTP/1.1 101 Switching Protocols\r\n")
	fmt.sbprintf(&sb, "Upgrade: websocket\r\n")
	fmt.sbprintf(&sb, "Connection: Upgrade\r\n")
	fmt.sbprintf(&sb, "Sec-WebSocket-Accept: %s\r\n", accept_key)
	fmt.sbprintf(&sb, "\r\n")

	response := strings.to_string(sb)
	net.send_tcp(client, transmute([]byte)response)
}

handle_websocket :: proc(client: net.TCP_Socket, upgrade_data: []byte) {
	defer net.close(client)

	key, key_ok := get_websocket_key(upgrade_data)
	if !key_ok {
		send_error(client, 400, "Bad Request")
		return
	}

	accept_key, accept_ok := compute_accept_key(key)
	if !accept_ok {
		send_error(client, 500, "Internal Server Error")
		return
	}
	defer delete(accept_key)

	send_websocket_upgrade_response(client, accept_key)
	fmt.println("WebSocket connection upgraded")

	frame_buf: [65536]byte
	read_buffer: [65536]byte
	read_offset := 0

	for {
		frame, parse_ok := parse_ws_frame(frame_buf[:], read_buffer[:read_offset])
		if !parse_ok {
			return
		}

		if frame == nil {
			n, recv_err := net.recv_tcp(client, read_buffer[read_offset:])
			if recv_err != nil || n == 0 {
				return
			}
			read_offset += n
			continue
		}

		read_offset = 0

		#partial switch frame.opcode {
		case .Text:
			msg := string(frame.payload)
			fmt.printf("WebSocket text message: %s\n", msg)
			send_ws_frame(client, .Text, frame.payload)

		case .Binary:
			fmt.printf("WebSocket binary message: %d bytes\n", len(frame.payload))
			send_ws_frame(client, .Binary, frame.payload)

		case .Ping:
			send_ws_frame(client, .Pong, frame.payload)

		case .Pong:
		// ignore

		case .Close:
			send_ws_frame(client, .Close, nil)
			return

		case .Continuation:
		// ignore
		}
	}
}

parse_ws_frame :: proc(frame_buf: []byte, data: []byte) -> (^WebSocket_Frame, bool) {
	if len(data) < 2 {
		return nil, true
	}

	frame: WebSocket_Frame

	b0 := data[0]
	b1 := data[1]

	frame.fin = (b0 & 0x80) != 0
	frame.opcode = WebSocket_Opcode(b0 & 0x0F)
	frame.mask = (b1 & 0x80) != 0

	payload_len := u64(b1 & 0x7F)
	offset := u64(2)

	if payload_len == 126 {
		if u64(len(data)) < offset + 2 {
			return nil, true
		}
		frame.payload_length = u64(data[offset]) << 8 | u64(data[offset + 1])
		offset += 2
	} else if payload_len == 127 {
		if u64(len(data)) < offset + 8 {
			return nil, true
		}
		frame.payload_length = 0
		for i in 0 ..< 8 {
			shift_amt := u64(56 - i * 8)
			frame.payload_length = (frame.payload_length << 8) | u64(data[offset + u64(i)])
		}
		offset += 8
	} else {
		frame.payload_length = payload_len
	}

	if frame.mask {
		if u64(len(data)) < offset + 4 {
			return nil, true
		}
		frame.mask_key[0] = data[offset]
		frame.mask_key[1] = data[offset + 1]
		frame.mask_key[2] = data[offset + 2]
		frame.mask_key[3] = data[offset + 3]
		offset += 4
	}

	if u64(len(data)) < offset + frame.payload_length {
		return nil, true
	}

	payload_start := offset
	payload_slice := data[payload_start:payload_start + frame.payload_length]

	if frame.mask {
		unmasked := make([]byte, int(frame.payload_length))
		for i in 0 ..< int(frame.payload_length) {
			unmasked[i] = payload_slice[i] ~ frame.mask_key[i & 3]
		}
		frame.payload = unmasked
	} else {
		frame.payload = payload_slice
	}

	frame_buf_ptr := ([^]WebSocket_Frame)(raw_data(frame_buf))
	frame_buf_ptr[0] = frame

	return &frame_buf_ptr[0], true
}

send_ws_frame :: proc(client: net.TCP_Socket, opcode: WebSocket_Opcode, payload: []byte) {
	header_buf: [14]byte

	header_buf[0] = 0x80 | byte(opcode)
	offset := 1

	payload_len := len(payload)

	if payload_len <= 125 {
		header_buf[1] = byte(payload_len)
		offset = 2
	} else if payload_len <= 65535 {
		header_buf[1] = 126
		header_buf[2] = byte((payload_len >> 8) & 0xFF)
		header_buf[3] = byte(payload_len & 0xFF)
		offset = 4
	} else {
		header_buf[1] = 127
		len64 := u64(payload_len)
		for i in 0 ..< 8 {
			shift_amt := u64(56 - i * 8)
			header_buf[2 + i] = byte((len64 >> shift_amt) & 0xFF)
		}
		offset = 10
	}

	net.send_tcp(client, header_buf[:offset])
	if payload_len > 0 {
		net.send_tcp(client, payload)
	}
}

*/

