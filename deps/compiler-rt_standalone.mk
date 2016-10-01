##
# This Makefile will be executed in $(BUILDDIR)/compiler-rt-$(LLVM_VER)
# Expected variables from the parent
# CRT_SRCDIR
# LIBFILE
# OS (CRT_OS not JL_OS)
# ARCH (CRT_ARCH not JL_ARCH)
# USE_CLANG
# fPIC
##

# The standalone compiler-rt build is inspired by
# https://github.com/ReservedField/arm-compiler-rt
SRCDIR := $(CRT_SRCDIR)/lib/builtins
ARCH_SRCDIR := $(SRCDIR)/$(ARCH)
INCLUDES := -I$(SRCDIR) -I$(ARCH_SRCDIR)
CRT_CFLAGS := $(CPPFLAGS) $(CFLAGS) -O2 \
		-std=gnu99 $(fPIC) -fno-builtin -fvisibility=hidden \
		-ffreestanding $(INCLUDES)
ifeq ($(USE_CLANG),1)
CRT_CFLAGS += -Wno-unknown-attributes -Wno-macro-redefined
endif

##
# Blacklist a few files we don't want to deal with
##
MAKEFLAGS := --no-builtin-rules
BLACKLIST := atomic.c atomic_flag_clear.c atomic_flag_clear_explicit.c \
	atomic_flag_test_and_set.c atomic_flag_test_and_set_explicit.c \
	atomic_signal_fence.c atomic_thread_fence.c

# TODO(vchuravy) discover architecture flags
# Discover all files...
CFILES := $(wildcard $(SRCDIR)/*.c)
GENERAL_OBJS1 := $(filter-out $(BLACKLIST:.c=.o), $(notdir $(CFILES:.c=.o)))

ARCH_CFILES := $(wildcard $(ARCH_SRCDIR)/*.c)
ARCH_SFILES := $(wildcard $(ARCH_SRCDIR)/*.S)
ARCH_OBJS   := $(notdir $(join $(ARCH_CFILES:.c=.o),$(ARCH_SFILES:.S=.o)))

GENERAL_OBJS := $(filter-out $(ARCH_OBJS), $(GENERAL_OBJS1))

OBJS := $(GENERAL_OBJS) $(ARCH_OBJS)

%.o: $(SRCDIR)/%.c
	$(CC) $(CRT_CFLAGS) -c $< -o $@

%.o: $(SRCDIR)/%.S
	$(CC) $(CRT_CFLAGS) -c $< -o $@

%.o: $(ARCH_SRCDIR)/%.c
	$(CC) $(CRT_CFLAGS) -c $< -o $@

%.o: $(ARCH_SRCDIR)/%.S
	$(CC) $(CRT_CFLAGS) -c $< -o $@

.PHONY: $(LIBFILE)
$(LIBFILE): $(OBJS)
	$(CC) $(LDFLAGS) -shared -o $@ $^

clean: $(OBJS) $(LIBFILE)
	rm $^

