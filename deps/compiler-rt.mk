##
# In order to support fallbacks within llvm we need to support
# compiler-rt. This means linking sys.so against it and resolving
# symbols during JIT compilation (see jitlayers.cpp). For the latter part we need to create
# a .so that we can load, but compiler-rt only comes in a .a.
#
# There are several configurations to take into account.
# 1. STANDALONE_COMPILER_RT == 1
#    Download and install compiler_rt independently of llvm/clang.
#    We still use the the LLVM_VER to pick the right compiler-rt.
# 2. STANDALONE_COMPILER_RT == 0
#    On LLVM >= 3.8 we can build compiler-rt along side LLVM.
# 3. USE_SYSTEM_LLVM == 1 && STANDALONE_COMPILER_RT == 0
#    Fallback definition.
#    libclang_rt.builtins is distributed with clang and so
#    we assume that USE_SYSTEM_LLVM == 1 means that clang is also
#    installed.
#    This is intended as a last ressort and if you use USE_SYSTEM_LLVM
#    consider setting STANDALONE_COMPILER_RT:=1
#
# Since we need the shared objectfile for JIT, there is no USE_SYSTEM_COMPILER_RT
##
COMPILER_RT_BUILDDIR := $(BUILDDIR)/compiler-rt-$(LLVM_VER)
COMPILER_RT_SRCDIR := $(SRCDIR)/srccache/compiler-rt-$(LLVM_VER)
COMPILER_RT_LIBFILE := libcompiler-rt.$(SHLIB_EXT)

##
# The naming of the static file for compiler-rt is slightly weird
# and we have to figure out what the proper name is on the current
# platform.
#
# TODO(vchuravy): ARM, PPC, mac, windows
##
CRT_OS   := $(call lower,$(OS))
CRT_ARCH := $(call patsubst,i%86,i386,$(ARCH))
CRT_STATIC_NAME := clang_rt.builtins-$(CRT_ARCH)

# We can only rely on compiler-rt being build alongside LLVM with CMAKE
ifeq ($(LLVM_USE_CMAKE),0)
override STANDALONE_COMPILER_RT := 1
endif

# Much to my chagrin LLVM 3.9 currently fails over if we try to build
# compiler-rt without clang. We will need to patch the build system
# but in the meantime we will fall back onto the standalone build.
ifeq ($(BUILD_LLVM_CLANG),0)
override STANDALONE_COMPILER_RT := 1
endif

ifeq ($(STANDALONE_COMPILER_RT),1)
COMPILER_RT_TAR := $(SRCDIR)/srccache/compiler-rt-$(LLVM_TAR_EXT)
else
COMPILER_RT_TAR :=
ifeq ($(USE_SYSTEM_LLVM), 1)
CRT_DIR := $(shell llvm-config --libdir)/clang/$(shell llvm-config --version)/lib/$(CRT_OS)
else ifeq ($(BUILD_LLVM_COMPILER_RT), 1)
CRT_DIR := $(LLVM_BUILDDIR_withtype)/lib/clang/$(LLVM_VER)/lib/$(CRT_OS)
$(CRT_DIR)/lib$(CRT_STATIC_NAME): | $(LLVM_BUILDDIR_withtype)/build-compiled
else
$(error Compiler-rt is not available, please set STANDALONE_COMPILER_RT:=1)
endif
# Use compiler-rt from the clang installation
$(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE): $(CRT_DIR)/lib$(CRT_STATIC_NAME) | $(COMPILER_RT_BUILDDIR)/build-configured
	$(CC) $(LDFLAGS) -shared $(fPIC) -o $@ -nostdlib $(WHOLE_ARCHIVE) -L$(dir $<) -l$(notdir $<) $(WHOLE_NOARCHIVE)
endif

ifneq ($(STANDALONE_COMPILER_RT),0)
# The standalone compiler-rt build is inspired by
# https://github.com/ReservedField/arm-compiler-rt
CRT_SRCDIR := $(COMPILER_RT_SRCDIR)/lib/builtins
CRT_ARCH_SRCDIR := $(CRT_SRCDIR)/$(CRT_ARCH)
CRT_INCLUDES := -I$(CRT_SRCDIR) -I$(CRT_ARCH_SRCDIR)
CRT_CFLAGS := $(CPPFLAGS) $(CFLAGS) -O2 \
		-std=gnu99 $(fPIC) -fno-builtin -fvisibility=hidden \
		-ffreestanding $(CRT_INCLUDES)
ifeq ($(USE_CLANG),1)
CRT_CFLAGS += -Wno-unknown-attributes -Wno-macro-redefined
endif

##
# Blacklist a few files we don't want to deal with
##
CRT_BLACKLIST := atomic.c atomic_flag_clear.c atomic_flag_clear_explicit.c \
	atomic_flag_test_and_set.c atomic_flag_test_and_set_explicit.c \
	atomic_signal_fence.c atomic_thread_fence.c

# TODO(vchuravy) discover architecture flags
# Discover all files...
CRT_CFILES := $(wildcard $(CRT_SRCDIR)/*.c)
CRT_GENERAL_OBJS1 := $(filter-out $(CRT_BLACKLIST:.c=.o), $(notdir $(CRT_CFILES:.c=.o)))

CRT_ARCH_CFILES := $(wildcard $(CRT_ARCH_SRCDIR)/*.c)
CRT_ARCH_SFILES := $(wildcard $(CRT_ARCH_SRCDIR)/*.S)
CRT_ARCH_OBJS   := $(notdir $(join $(CRT_ARCH_CFILES:.c=.o),$(CRT_ARCH_SFILES:.S=.o)))

CRT_GENERAL_OBJS := $(filter-out $(CRT_ARCH_OBJS), $(CRT_GENERAL_OBJS1))

CRT_OBJS := $(addprefix $(COMPILER_RT_BUILDDIR)/,$(CRT_GENERAL_OBJS)) \
	$(addprefix $(COMPILER_RT_BUILDDIR)/$(CRT_ARCH)/,$(CRT_ARCH_OBJS))

CRT_BUILDDIR := $(COMPILER_RT_BUILDDIR)
$(CRT_BUILDDIR)/$(CRT_ARCH): | $(CRT_BUILDDIR)/build-configured
	mkdir -p $@

$(CRT_BUILDDIR)/%.o: $(CRT_SRCDIR)/%.c | $(CRT_BUILDDIR)/build-configured
	$(CC) $(CRT_CFLAGS) -c $< -o $@

$(CRT_BUILDDIR)/%.o: $(CRT_SRCDIR)/%.S | $(CRT_BUILDDIR)/build-configured
	$(CC) $(CRT_CFLAGS) -c $< -o $@

$(CRT_BUILDDIR)/$(CRT_ARCH)/%.o: $(CRT_ARCH_SRCDIR)/%.c | $(CRT_BUILDDIR)/$(CRT_ARCH)
	$(CC) $(CRT_CFLAGS) -c $< -o $@

$(CRT_BUILDDIR)/$(CRT_ARCH)/%.o: $(CRT_ARCH_SRCDIR)/%.S | $(CRT_BUILDDIR)/$(CRT_ARCH)
	$(CC) $(CRT_CFLAGS) -c $< -o $@

$(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE): $(CRT_OBJS) | $(COMPILER_RT_SRCDIR)/source-extracted $(CRT_BUILDDIR)/build-configured
	$(CC) $(LDFLAGS) -shared -o $@ $^

endif

$(COMPILER_RT_SRCDIR)/source-extracted: | $(COMPILER_RT_TAR)
	mkdir -p $(COMPILER_RT_SRCDIR)
ifneq ($(COMPILER_RT_TAR),)
	$(JLCHECKSUM) $(COMPILER_RT_TAR)
	$(TAR) -C $(COMPILER_RT_SRCDIR) --strip-components 1 -xf $(COMPILER_RT_TAR)
endif
	echo 1 > $@

$(COMPILER_RT_BUILDDIR)/build-configured:
	mkdir -p $(dir $@)
	echo 1 > $@

get-compiler-rt: $(COMPILER_RT_TAR)
ifeq ($(STANDALONE_COMPILER_RT), 0)
extract-compiler-rt: #NONE
else
extract-compiler-rt: $(COMPILER_RT_SRCDIR)/source-extracted
endif

$(build_private_libdir)/$(COMPILER_RT_LIBFILE): $(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE)
	cp $< $@

$(build_prefix)/manifest/compiler-rt: | $(build_prefix)/manifest
	echo "compiler-rt-$(LLVM_VER)" > $@

check-compiler-rt: #NONE
fastcheck-compiler-rt: #NONE
configure-compiler-rt: $(COMPILER_RT_BUILDDIR)/build-configured
clean-compiler-rt:
	rm -rf $(COMPILER_RT_BUILDDIR)
	rm -f  $(build_prefix)/manifest/compiler-rt
	rm -f  $(build_private_libdir)/$(COMPILER_RT_LIBFILE)
distclean-compiler-rt: clean-compiler-rt
	rm -f $(COMPILER_RT_TAR)
	rm -rf $(COMPILER_RT_SRCDIR)

compile-compiler-rt: $(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE)
install-compiler-rt: $(build_private_libdir)/$(COMPILER_RT_LIBFILE) $(build_prefix)/manifest/compiler-rt

