# Makefile für Atlas 16 Tools
# Cross-Kompilierung für Angstrom (ARM Cortex-A9, hard-float)

CC_HOST  = gcc
CC_CROSS = arm-linux-gnueabihf-gcc

CFLAGS   = -O2 -Wall -Wextra

.PHONY: all host cross clean

all: host

host: hps_load
	@echo "Host-Binary (zum Testen): hps_load"

cross: hps_load.arm
	@echo "ARM-Binary für Angstrom: hps_load.arm"

hps_load: hps_load.c
	$(CC_HOST) $(CFLAGS) -o $@ $<

hps_load.arm: hps_load.c
	$(CC_CROSS) $(CFLAGS) -o $@ $<

clean:
	rm -f hps_load hps_load.arm
