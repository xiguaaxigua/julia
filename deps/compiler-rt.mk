##
# In order to support fallbacks within llvm we need to support
# compiler-rt. This means linking sys.so against it and resolving
# symbols at during JIT. For the latter part we need to create
# a .so that we can load, but compiler-rt only comes in a .a.
#
# There are several configurations to take into account.
# 1. USE_SYSTEM_LLVM == 1
#    libclang_rt.builtins is distributed with clang and so
#    we assume that USE_SYSTEM_LLVM == 1 means that clang is also
#    installed.
# 2. BUILD_LLVM_CLANG == 1
#    libclang_rt.builtins is build with clang and we can pick that up.
# 3. BUILD_COMPILER_RT == 1
#    Download and install compiler_rt independently of llvm/clang
#
# Since we need the shared opjectfile for JIT there is no USE_SYSTEM_COMPILER_RT
##
COMPILER_RT_BUILDDIR := $(BUILDDIR)/compiler-rt
COMPILER_RT_LIBFILE := libcompiler-rt.$(SHLIB_EXT)

##
# The naming of the static file for compiler-rt is slightly weird
# and we have to figure out what the proper name is on the current
# platform.
#
# TODO(vchuravy): ARM, PPC, mac, windows
##
ifeq ($(OS), Linux)
CRT_OS   := $(call patsubst,%inux,linux,$(OS))
CRT_ARCH := $(call patsubst,i%86,i386,$(ARCH))
CRT_STATIC_NAME := clang_rt.builtins-$(CRT_ARCH)
else
$(error Complain loudly to vchuravy. Compiler-rt does not support $(OS))
CRT_OS   :=
CRT_ARCH :=
CRT_STATIC_NAME := clang_rt.builtins-$(CRT_ARCH)
endif

ifeq ($(USE_SYSTEM_LLVM), 1)
STANDALONE_COMPILER_RT := 0
COMPILER_RT_TAR :=
CRT_DIR := $(shell llvm-config --libdir)/clang/$(shell llvm-config --version)/lib/$(CRT_OS)

else ifeq ($(BUILD_LLVM_CLANG), 1)
STANDALONE_COMPILER_RT := 0
COMPILER_RT_TAR := $(LLVM_COMPILER_RT_TAR)
CRT_DIR := $(LLVM_BUILDDIR_withtype)/lib/clang/$(LLVM_VER)/lib/$(CRT_OS)
$(CRT_DIR)/lib$(CRT_STATIC_NAME): | $(LLVM_BUILDDIR_withtype)/build-compiled

else ifeq ($(BUILD_COMPILER_RT), 1)
STANDALONE_COMPILER_RT := 1
COMPILER_RT_TAR := $(SRCDIR)/srccache/compiler-rt-$(LLVM_TAR_EXT)
$(error Standalone compiler-rt is not supported yet.)
else
$(error compiler-rt is not available.)
endif

ifeq ($(STANDALONE_COMPILER_RT),0)
# Use compiler-rt from the clang installation
$(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE): $(CRT_DIR)/lib$(CRT_STATIC_NAME) $(COMPILER_RT_BUILDDIR)/build-configured
	$(CC) $(LDFLAGS) -shared $(fPIC) -o $@ -nostdlib $(WHOLE_ARCHIVE) -L$(CRT_DIR) -l$(CRT_STATIC_NAME) $(WHOLE_NOARCHIVE)
else
# The standalone compiler-rt build is based on
# https://github.com/ReservedField/arm-compiler-rt
MAKEFLAGS += --no-builtin-rules
$(error Standalone compiler-rt is not supported yet.)
endif

$(COMPILER_RT_SRCDIR)/source-extracted: | $(COMPILER_RT_TAR)
ifneq ($(COMPILER_RT_TAR),)
	$(JLCHECKSUM) $(COMPILER_RT_TAR)
endif
	mkdir -p $(COMPILER_RT_SRCDIR)
	$(TAR) -C $(COMPILER_RT_SRCDIR) --strip-components 1 -xf $(COMPILER_RT_TAR)
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
check-compiler-rt: #NONE
fast-check-compiler-rt: #NONE
configure-compiler-rt: $(COMPILER_RT_BUILDDIR)/build-configured
compile-compiler-rt: $(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE)
install-compiler-rt: $(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE)
	cp $(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE) $(build_private_libdir)/

