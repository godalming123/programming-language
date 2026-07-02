#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EOT 4
#define EOT_STR "\004"

void *allocate(size_t size) {
  void *buffer = malloc(size);
  if (buffer == 0) {
    fprintf(stderr, "Failed to allocate");
    exit(1);
  }
  return buffer;
}

void *reallocate(void *buffer, size_t new_size) {
  void *temp = realloc(buffer, new_size);
  if (temp == 0) {
    fprintf(stderr, "Failed to reallocate");
    exit(1);
  }
  return temp;
}

char *asprintf_value(const char *format, ...) {
  va_list ap;

  va_start(ap, format);
  size_t len = vsnprintf(0, 0, format, ap);
  va_end(ap);

  if (len < 0) {
    return 0;
  }

  len += 1; // Increment len for end `\0`
  char *buf = allocate(len);

  va_start(ap, format);
  vsnprintf(buf, len, format, ap);
  va_end(ap);

  return buf;
}

// print
void builtin0(char *text) { printf("%s", text); }

// println
void builtin1(char *text) { printf("%s\n", text); }

// eprint
void builtin2(char *text) { fprintf(stderr, "%s", text); }

// eprintln
void builtin3(char *text) { fprintf(stderr, "%s\n", text); }

// TODO: Expose this function to code written in this programming language as a
// builtin
char *read_until(char end_char) {
  size_t cap = 64; /* initial buffer size */
  size_t len = 0;
  char *buf = allocate(cap);
  while (true) {
    int c = getchar();
    if (c == EOF || c == end_char) {
      if (len == 0) {
        free(buf);
        return 0;
      }
      buf[len] = '\0';
      return buf;
    }
    buf[len] = (char)c;
    len += 1;
    if (len >= cap) { /* +1 for the terminating '\0' */
      cap *= 2;
      buf = reallocate(buf, cap);
    }
  }
}

// readline
char *builtin4(char *prompt) {
  printf("%s", prompt);
  return read_until('\n');
}

// read_file
char *builtin5(char *name) {
  FILE *file_pointer = fopen(name, "r");
  if (file_pointer == 0) {
    fprintf(stderr, "Failed to read file called `%s`", name);
    exit(1);
  }
  fseek(file_pointer, 0, SEEK_END);
  long length = ftell(file_pointer);
  fseek(file_pointer, 0, SEEK_SET);
  char *buffer = allocate(length);
  fread(buffer, 1, length, file_pointer);
  fclose(file_pointer);
  return buffer;
}

// write_file
void builtin6(char *name, char *text) {
  FILE *file_pointer = fopen(name, "w");
  if (file_pointer == 0) {
    fprintf(stderr, "Failed to read file called `%s`", name);
    exit(1);
  }
  fputs(text, file_pointer);
  fclose(file_pointer);
}

// clear
void builtin7() { printf("\033[1;1H\033[2J"); }

// run_executable
void builtin8(struct {
  uint64_t length;
  char **elems;
} array) {
  fprintf(stderr, "TODO: Implement run_executable");
  exit(1);
}

// exit
void builtin9(uint64_t code) { exit(code); }

/*
// OLD(METAPROGRAM_IN_C)
// compiler.emit_js_code
char* builtin11(uint64_t id) {
  printf("compiler.emit_js_code" EOT_STR "%" PRIu64 EOT_STR, id);
  fflush(stdout);
  return read_until(EOT);
}
*/

// string_repeat
char *builtin12(char *string, int64_t repetitions) {
  if (repetitions < 0) {
    fprintf(stderr, "Negative repeat count");
    exit(1);
  }
  size_t size = strlen(string) * repetitions + 1;
  char *out = allocate(size);

  out[0] = '\0';
  while (repetitions > 0) {
    repetitions -= 1;
    strcat(out, string);
  }

  return out;
}
