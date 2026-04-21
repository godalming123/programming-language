#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *allocate(size_t size) {
  void *buffer = malloc(size);
  if (buffer == 0) {
    printf("Failed to allocate");
    exit(1);
  }
  return buffer;
}

void *reallocate(void *buffer, size_t new_size) {
  void *temp = realloc(buffer, new_size);
  if (temp == 0) {
    printf("Failed to reallocate");
    exit(1);
  }
  return temp;
}

// print
void builtin0(char *text) { printf("%s", text); }

// println
void builtin1(char *text) { printf("%s\n", text); }

// readline
char *builtin2(char *prompt) {
  printf("%s", prompt);
  size_t cap = 64; /* initial buffer size */
  size_t len = 0;
  char *buf = allocate(cap);
  while (true) {
    int c = getchar();
    if (c == EOF || c == '\n') {
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

// read_file
char *builtin3(char *name) {
  FILE *file_pointer = fopen(name, "w");
  if (file_pointer == 0) {
    printf("Failed to read file called `%s`", name);
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
void builtin4(char *name, char *text) {
  FILE *file_pointer = fopen(name, "w");
  if (file_pointer == 0) {
    printf("Failed to read file called `%s`", name);
    exit(1);
  }
  fputs(text, file_pointer);
  fclose(file_pointer);
}

// clear
void builtin5() { printf("\033[1;1H\033[2J"); }

// run_executable
void builtin6(struct {
  uint64_t length;
  char **elems;
} array) {
  printf("TODO: Implement run_executable");
  exit(1);
}

// exit
void builtin7(uint64_t code) {
  exit(code);
}
