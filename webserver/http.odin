package webserver

import "core:bytes"
import "core:fmt"
import "core:net"
// import "core:os"
import "core:strings"

Http_Request :: struct {
    method:  string,
    path:    string,
    version: string,
    headers: map[string]string,
    body:    []byte,
}

/*

Mime_Entry :: struct {
	ext:  string,
	mime: string,
}

MIME_TYPES :: []Mime_Entry {
	{".html", "text/html"},
	{".htm", "text/html"},
	{".css", "text/css"},
	{".js", "application/javascript"},
	{".json", "application/json"},
	{".png", "image/png"},
	{".jpg", "image/jpeg"},
	{".jpeg", "image/jpeg"},
	{".gif", "image/gif"},
	{".svg", "image/svg+xml"},
	{".ico", "image/x-icon"},
	{".txt", "text/plain"},
	{".xml", "application/xml"},
	{".pdf", "application/pdf"},
	{".zip", "application/zip"},
	{".woff", "font/woff"},
	{".woff2", "font/woff2"},
}

HTTP_ROOT :: "public"

handle_http :: proc(client: net.TCP_Socket, data: []byte) {
	request, ok := parse_http_request(data)
	if !ok {
		send_error(client, 400, "Bad Request")
		return
	}
	defer delete(request.headers)

	fmt.printf("%s %s\n", request.method, request.path)

	if request.method != "GET" {
		send_error(client, 405, "Method Not Allowed")
		return
	}

	serve_file(client, request.path)
}

*/

parse_http_request :: proc(data: []byte) -> (Http_Request, bool) {
    request: Http_Request
    header_end := bytes.index(data, []byte{'\r', '\n', '\r', '\n'})
    if header_end == -1 {
        return request, false
    }

    header_section := string(data[:header_end])
    request.body = data[header_end + 4:]

    lines := strings.split_lines(header_section)
    defer delete(lines)

    if len(lines) < 1 {
        return request, false
    }

    parts := strings.split(lines[0], " ")
    defer delete(parts)

    if len(parts) != 3 {
        return request, false
    }

    request.method = parts[0]
    request.path = parts[1]
    request.version = parts[2]
    request.headers = make(map[string]string)

    for i := 1; i < len(lines); i += 1 {
        line := strings.trim_space(lines[i])
        if line == "" {
            continue
        }
        colon_pos := strings.index(line, ":")
        if colon_pos == -1 {
            continue
        }
        key := strings.trim_space(line[:colon_pos])
        value := strings.trim_space(line[colon_pos + 1:])
        request.headers[key] = value
    }

    return request, true
}

/*

serve_file :: proc(client: net.TCP_Socket, url_path: string) {
    if strings.contains(url_path, "..") {
        send_error(client, 400, "Bad Request")
        return
    }

    path := url_path
    if path == "/" || path == "" {
        path = "/index.html"
    }

    full_path := strings.concatenate({HTTP_ROOT, path})
    defer delete(full_path)

    if !os.exists(full_path) {
        send_error(client, 404, "Not Found")
        return
    }

    file_data, read_err := os.read_entire_file(full_path, context.allocator)
    if read_err != nil {
        send_error(client, 500, "Internal Server Error")
        return
    }
    defer delete(file_data)

    ext := get_ext(path)
    mime := "application/octet-stream"
    for entry in MIME_TYPES {
        if entry.ext == ext {
            mime = entry.mime
            break
        }
    }

    send_response(client, 200, "OK", mime, file_data)
}

*/

send_response :: proc(
    client: net.TCP_Socket,
    code: int,
    text: string,
    content_type: string,
    body: []byte,
) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "HTTP/1.1 %d %s\r\n", code, text)
    fmt.sbprintf(&sb, "Content-Type: %s\r\n", content_type)
    fmt.sbprintf(&sb, "Content-Length: %d\r\n", len(body))
    fmt.sbprintf(&sb, "Connection: close\r\n")
    fmt.sbprintf(&sb, "Server: webserver/0.1\r\n")
    fmt.sbprintf(&sb, "\r\n")

    header_str := strings.to_string(sb)
    net.send_tcp(client, transmute([]byte)header_str)
    if len(body) > 0 {
        net.send_tcp(client, body)
    }
}


send_error :: proc(client: net.TCP_Socket, code: int, text: string) {
    body := fmt.tprintf("<html><body><h1>%d %s</h1></body></html>", code, text)
    send_response(client, code, text, "text/html", transmute([]byte)body)
}
/*

get_ext :: proc(p: string) -> string {
    dot_idx := -1
    for i := len(p) - 1; i >= 0; i -= 1 {
        if p[i] == '.' {
            dot_idx = i
            break
        }
        if p[i] == '/' {
            break
        }
    }
    if dot_idx == -1 {
        return ""
    }
    return p[dot_idx:]
}

*/

