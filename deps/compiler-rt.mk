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
endif

$(COMPILER_RT_SRCDIR)/source-extracted: | $(COMPILER_RT_TAR)
	mkdir -p $(COMPILER_RT_SRCDIR)
ifneq ($(COMPILER_RT_TAR),)
	$(JLCHECKSUM) $(COMPILER_RT_TAR)
	$(TAR) -C $(COMPILER_RT_SRCDIR) --strip-components 1 -xf $(COMPILER_RT_TAR)
endif
	echo 1 > $@

$(COMPILER_RT_BUILDDIR):
	mkdir -p $@
$(COMPILER_RT_BUILDDIR)/$(CRT_ARCH):
	mkdir -p $@

ifeq ($(STANDALONE_COMPILER_RT),1)
$(COMPILER_RT_BUILDDIR)/Makefile: compiler-rt_standalone.mk | $(COMPILER_RT_BUILDDIR)
	cp $< $@
$(COMPILER_RT_BUILDDIR)/build-configured: $(COMPILER_RT_BUILDDIR)/Makefile | $(COMPILER_RT_BUILDDIR)/$(CRT_ARCH)
	echo 1 > $@
$(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE): | $(COMPILER_RT_SRCDIR)/source-extracted $(COMPILER_RT_BUILDDIR)/build-configured
	$(MAKE) -C $(COMPILER_RT_BUILDDIR) \
		LIBFILE=$(COMPILER_RT_LIBFILE) \
		CRT_SRCDIR=$(COMPILER_RT_SRCDIR) \
		OS=$(CRT_OS) \
		ARCH=$(CRT_ARCH) \
		USE_CLANG=$(USE_CLANG) \
		fPIC=$(fPIC)
else
$(COMPILER_RT_BUILDDIR)/build-configured: $(COMPILER_RT_BUILDDIR)
	echo 1 > $@
# Use compiler-rt from the clang installation
$(COMPILER_RT_BUILDDIR)/$(COMPILER_RT_LIBFILE): $(CRT_DIR)/lib$(CRT_STATIC_NAME) | $(COMPILER_RT_BUILDDIR)/build-configured
	$(CC) $(LDFLAGS) -shared $(fPIC) -o $@ -nostdlib $(WHOLE_ARCHIVE) -L$(dir $<) -l$(notdir $<) $(WHOLE_NOARCHIVE)
endif

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

