#!/usr/bin/ruby

# Android build system is complicated and does not allow to build
# separate parts easily.
# This script tries to mimic Android build rules.

def expand(dir, files)
  files.map { |f| File.join(dir, f) }
end

# Compiles sources to *.o files.
# Returns array of output *.o filenames
def compile(sources, cflags, params = {})
  outputs = []
  for s in sources
    ext = File.extname(s)

    case ext
    when ".c"
      cc = "cc"
      lang_flags = "-std=gnu11 $CFLAGS $CPPFLAGS"
    when ".cpp", ".cc"
      cc = "cxx"
      lang_flags = "-std=gnu++2a $CXXFLAGS $CPPFLAGS"
    else
      raise "Unknown extension #{ext}"
    end

    output = s + ".o"
    outputs << output
    order_deps = if params[:order_deps]
                   " || " + params[:order_deps].join(" ")
                 else
                   ""
                 end

    puts "build #{output}: #{cc} #{s}#{order_deps}\n    cflags = #{lang_flags} #{cflags}"
  end

  return outputs
end

# Generate proto and compile it
def protoc(source)
  basename = File.join(File.dirname(source), File.basename(source, ".proto"))
  cfile = basename + ".pb.cc"
  hfile = basename + ".pb.h"
  ofile = cfile + ".o"
  puts "build #{cfile} #{hfile}: protoc #{source}"
  puts "build #{ofile}: cc #{cfile}\n    cflags = -std=gnu++2a $CXXFLAGS $CPPFLAGS -I."

  return hfile, cfile, ofile
end

# dir - directory where ninja file is located
# lib - static library path relative to dir
def subninja(dir, lib)
  puts "subninja #{dir}build.ninja"
  return lib.each { |l| dir + l }
end

# Links object files
def link(output, objects, ldflags)
  puts "build #{output}: link #{objects.join(" ")}\n    ldflags = #{ldflags} $LDFLAGS"
end

def genheader(input, variable, output)
  puts "build #{output}: genheader #{input}\n    var = #{variable}"
end

puts "# This set of commands generated by generate_build.rb script\n\n"
puts "CC = #{ENV["CC"] || "clang"}"
puts "CXX = #{ENV["CXX"] || "clang++"}\n\n"
puts "CFLAGS = #{ENV["CFLAGS"]}"
puts "CXXFLAGS = #{ENV["CXXFLAGS"]}"
puts "LDFLAGS = #{ENV["LDFLAGS"]}"
puts "PLATFORM_TOOLS_VERSION = #{ENV["PLATFORM_TOOLS_VERSION"]}\n\n"

puts "" "
rule cc
  command = $CC $cflags -c $in -o $out

rule cxx
  command = $CXX $cflags -c $in -o $out

rule link
  command = $CXX $ldflags $LDFLAGS $in -o $out

rule protoc
  command = protoc --cpp_out=. $in

rule genheader
  command = (echo 'unsigned char $var[] = {' && xxd -i <$in && echo '};') > $out


" ""

adbdfiles = %w(
  adb.cpp
  adb_io.cpp
  adb_listeners.cpp
  adb_trace.cpp
  adb_utils.cpp
  fdevent/fdevent.cpp
  fdevent/fdevent_poll.cpp
  fdevent/fdevent_epoll.cpp
  shell_service_protocol.cpp
  sockets.cpp
  transport.cpp
  transport_local.cpp
  transport_usb.cpp
)
libadbd = compile(expand("core/adb", adbdfiles), '-DPLATFORM_TOOLS_VERSION="\"$PLATFORM_TOOLS_VERSION\"" -DADB_HOST=1 -Icore/include -Icore/base/include -Icore/adb -Icore/libcrypto_utils/include -Iboringssl/include -Icore/diagnose_usb/include')

apkent_h, apkent_c, apkent_o = protoc("core/adb/fastdeploy/proto/ApkEntry.proto")

deployagent_inc = "core/adb/client/deployagent.inc"
genheader("deployagent.jar", "kDeployAgent", deployagent_inc)

deployagentscript_inc = "core/adb/client/deployagentscript.inc"
genheader("core/adb/fastdeploy/deployagent/deployagent.sh", "kDeployAgentScript", deployagentscript_inc)

adbfiles = %w(
  client/adb_client.cpp
  client/adb_install.cpp
  client/auth.cpp
  client/bugreport.cpp
  client/commandline.cpp
  client/console.cpp
  client/fastdeploy.cpp
  client/fastdeploycallbacks.cpp
  client/file_sync_client.cpp
  client/line_printer.cpp
  client/main.cpp
  client/usb_dispatch.cpp
  client/usb_libusb.cpp
  client/usb_linux.cpp
  fastdeploy/deploypatchgenerator/apk_archive.cpp
  fastdeploy/deploypatchgenerator/deploy_patch_generator.cpp
  fastdeploy/deploypatchgenerator/patch_utils.cpp
  services.cpp
  socket_spec.cpp
  sysdeps/errno.cpp
  sysdeps/posix/network.cpp
  sysdeps_unix.cpp
)
libadb = compile(expand("core/adb", adbfiles), "-D_GNU_SOURCE -DADB_HOST=1 -Icore/include -Icore/base/include -Icore/adb -Icore/libcrypto_utils/include -Iboringssl/include -Ibase/libs/androidfw/include -Inative/include", :order_deps => [apkent_h, deployagent_inc, deployagentscript_inc])

androidfwfiles = %w(
  LocaleData.cpp
  ResourceTypes.cpp
  TypeWrappers.cpp
  ZipFileRO.cpp
)
libandroidfw = compile(expand("base/libs/androidfw", androidfwfiles), "-Icore/base/include -Ibase/libs/androidfw/include -Icore/libutils/include -Icore/liblog/include -Icore/libsystem/include -Inative/include -Icore/libcutils/include -Icore/libziparchive/include")

basefiles = %w(
  chrono_utils.cpp
  errors_unix.cpp
  file.cpp
  logging.cpp
  mapped_file.cpp
  parsenetaddress.cpp
  stringprintf.cpp
  strings.cpp
  test_utils.cpp
  threads.cpp
)
libbase = compile(expand("core/base", basefiles), "-DADB_HOST=1 -Icore/base/include -Icore/include")

logfiles = %w(
  fake_log_device.cpp
  fake_writer.cpp
  log_event_list.cpp
  log_event_write.cpp
  logger_lock.cpp
  logger_name.cpp
  logger_write.cpp
  logprint.cpp
)
liblog = compile(expand("core/liblog", logfiles), "-DLIBLOG_LOG_TAG=1006 -D_XOPEN_SOURCE=700 -DFAKE_LOG_DEVICE=1 -Icore/log/include -Icore/include")

cutilsfiles = %w(
  android_get_control_file.cpp
  canned_fs_config.cpp
  fs_config.cpp
  load_file.cpp
  socket_inaddr_any_server_unix.cpp
  socket_local_client_unix.cpp
  socket_local_server_unix.cpp
  socket_network_client_unix.cpp
  sockets.cpp
  sockets_unix.cpp
  threads.cpp
)
libcutils = compile(expand("core/libcutils", cutilsfiles), "-D_GNU_SOURCE -Icore/libcutils/include -Icore/include -Icore/base/include")

diagnoseusbfiles = %w(
  diagnose_usb.cpp
)
libdiagnoseusb = compile(expand("core/diagnose_usb", diagnoseusbfiles), "-Icore/include -Icore/base/include -Icore/diagnose_usb/include")

libcryptofiles = %w(
  android_pubkey.c
)
libcrypto = compile(expand("core/libcrypto_utils", libcryptofiles), "-Icore/libcrypto_utils/include -Iboringssl/include")

# TODO: make subninja working
#boringssl = subninja('boringssl/build/', ['crypto/libcrypto.a'])
boringssl = ["boringssl/build/crypto/libcrypto.a"]

fastbootfiles = %w(
  bootimg_utils.cpp
  fastboot.cpp
  fastboot_driver.cpp
  fs.cpp
  main.cpp
  socket.cpp
  tcp.cpp
  udp.cpp
  usb_linux.cpp
  util.cpp
)
libfastboot = compile(expand("core/fastboot", fastbootfiles), '-DPLATFORM_TOOLS_VERSION="\"$PLATFORM_TOOLS_VERSION\"" -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DUSE_F2FS -Icore/base/include -Icore/include -Icore/adb -Icore/libsparse/include -Imkbootimg/include/bootimg -Iextras/ext4_utils/include -Iextras/f2fs_utils -Icore/libziparchive/include -Icore/fs_mgr/liblp/include -Icore/diagnose_usb/include -Iavb')

fsmgrfiles = %w(
  liblp/images.cpp
  liblp/partition_opener.cpp
  liblp/reader.cpp
  liblp/utility.cpp
  liblp/writer.cpp
)
libfsmgr = compile(expand("core/fs_mgr", fsmgrfiles), "-Icore/fs_mgr/liblp/include -Icore/base/include -Iextras/ext4_utils/include -Icore/libsparse/include")

sparsefiles = %w(
  backed_block.cpp
  output_file.cpp
  sparse.cpp
  sparse_crc32.cpp
  sparse_err.cpp
  sparse_read.cpp
)
libsparse = compile(expand("core/libsparse", sparsefiles), "-Icore/libsparse/include -Icore/base/include")

f2fsfiles = %w(
)
f2fs = compile(expand("extras/f2fs_utils", f2fsfiles), "-DHAVE_LINUX_TYPES_H -If2fs-tools/include -Icore/liblog/include")

zipfiles = %w(
  zip_archive.cc
)
libzip = compile(expand("core/libziparchive", zipfiles), "-Icore/base/include -Icore/include -Icore/libziparchive/include")

utilfiles = %w(
  FileMap.cpp
  SharedBuffer.cpp
  String16.cpp
  String8.cpp
  VectorImpl.cpp
  Unicode.cpp
)
libutil = compile(expand("core/libutils", utilfiles), "-Icore/include -Icore/base/include")

ext4files = %w(
  ext4_utils.cpp
  wipe.cpp
  ext4_sb.cpp
)
libext4 = compile(expand("extras/ext4_utils", ext4files), "-D_GNU_SOURCE -Icore/libsparse/include -Icore/include -Iselinux/libselinux/include -Iextras/ext4_utils/include -Icore/base/include")

selinuxfiles = %w(
  booleans.c
  callbacks.c
  canonicalize_context.c
  check_context.c
  disable.c
  enabled.c
  freecon.c
  getenforce.c
  init.c
  label_backends_android.c
  label.c
  label_file.c
  label_support.c
  lgetfilecon.c
  load_policy.c
  lsetfilecon.c
  matchpathcon.c
  policyvers.c
  regex.c
  selinux_config.c
  setenforce.c
  setrans_client.c
  seusers.c
  sha1.c
)
libselinux = compile(expand("selinux/libselinux/src", selinuxfiles), "-DAUDITD_LOG_TAG=1003 -D_GNU_SOURCE -DHOST -DUSE_PCRE2 -DNO_PERSISTENTLY_STORED_PATTERNS -DDISABLE_SETRANS -DDISABLE_BOOL -DNO_MEDIA_BACKEND -DNO_X_BACKEND -DNO_DB_BACKEND -DPCRE2_CODE_UNIT_WIDTH=8 -Iselinux/libselinux/include -Iselinux/libsepol/include")

libsepolfiles = %w(
  assertion.c
  avrule_block.c
  avtab.c
  conditional.c
  constraint.c
  context.c
  context_record.c
  debug.c
  ebitmap.c
  expand.c
  genbools.c
  genusers.c
  hashtab.c
  hierarchy.c
  kernel_to_common.c
  mls.c
  policydb.c
  policydb_convert.c
  policydb_public.c
  services.c
  sidtab.c
  symtab.c
  util.c
  write.c
)
libsepol = compile(expand("selinux/libsepol/src", libsepolfiles), "-Iselinux/libsepol/include -Iselinux/libsepol/src")

link("fastboot", libfsmgr + libsparse + libzip + libcutils + liblog + libutil + libbase + libext4 + f2fs + libselinux + libsepol + libfastboot + libdiagnoseusb + boringssl, "-lz -lpcre2-8 -lpthread -ldl")

# mke2fs.android - a ustom version of mke2fs that supports --android_sparse (FS#56955)
libext2fsfiles = %w(
  lib/blkid/cache.c
  lib/blkid/dev.c
  lib/blkid/devname.c
  lib/blkid/devno.c
  lib/blkid/getsize.c
  lib/blkid/llseek.c
  lib/blkid/probe.c
  lib/blkid/read.c
  lib/blkid/resolve.c
  lib/blkid/save.c
  lib/blkid/tag.c
  lib/e2p/encoding.c
  lib/e2p/feature.c
  lib/e2p/hashstr.c
  lib/e2p/mntopts.c
  lib/e2p/ostype.c
  lib/e2p/parse_num.c
  lib/e2p/uuid.c
  lib/et/com_err.c
  lib/et/error_message.c
  lib/et/et_name.c
  lib/ext2fs/alloc.c
  lib/ext2fs/alloc_sb.c
  lib/ext2fs/alloc_stats.c
  lib/ext2fs/alloc_tables.c
  lib/ext2fs/atexit.c
  lib/ext2fs/badblocks.c
  lib/ext2fs/bb_inode.c
  lib/ext2fs/bitmaps.c
  lib/ext2fs/bitops.c
  lib/ext2fs/blkmap64_ba.c
  lib/ext2fs/blkmap64_rb.c
  lib/ext2fs/blknum.c
  lib/ext2fs/block.c
  lib/ext2fs/bmap.c
  lib/ext2fs/closefs.c
  lib/ext2fs/crc16.c
  lib/ext2fs/crc32c.c
  lib/ext2fs/csum.c
  lib/ext2fs/dirblock.c
  lib/ext2fs/dir_iterate.c
  lib/ext2fs/expanddir.c
  lib/ext2fs/ext2_err.c
  lib/ext2fs/ext_attr.c
  lib/ext2fs/extent.c
  lib/ext2fs/fallocate.c
  lib/ext2fs/fileio.c
  lib/ext2fs/freefs.c
  lib/ext2fs/gen_bitmap64.c
  lib/ext2fs/gen_bitmap.c
  lib/ext2fs/get_num_dirs.c
  lib/ext2fs/getsectsize.c
  lib/ext2fs/getsize.c
  lib/ext2fs/hashmap.c
  lib/ext2fs/i_block.c
  lib/ext2fs/ind_block.c
  lib/ext2fs/initialize.c
  lib/ext2fs/inline.c
  lib/ext2fs/inline_data.c
  lib/ext2fs/inode.c
  lib/ext2fs/io_manager.c
  lib/ext2fs/ismounted.c
  lib/ext2fs/link.c
  lib/ext2fs/llseek.c
  lib/ext2fs/lookup.c
  lib/ext2fs/mkdir.c
  lib/ext2fs/mkjournal.c
  lib/ext2fs/mmp.c
  lib/ext2fs/namei.c
  lib/ext2fs/newdir.c
  lib/ext2fs/nls_utf8.c
  lib/ext2fs/openfs.c
  lib/ext2fs/progress.c
  lib/ext2fs/punch.c
  lib/ext2fs/rbtree.c
  lib/ext2fs/read_bb.c
  lib/ext2fs/read_bb_file.c
  lib/ext2fs/res_gdt.c
  lib/ext2fs/rw_bitmaps.c
  lib/ext2fs/sha512.c
  lib/ext2fs/sparse_io.c
  lib/ext2fs/symlink.c
  lib/ext2fs/undo_io.c
  lib/ext2fs/unix_io.c
  lib/ext2fs/valid_blk.c
  lib/support/dict.c
  lib/support/mkquota.c
  lib/support/parse_qtype.c
  lib/support/plausible.c
  lib/support/prof_err.c
  lib/support/profile.c
  lib/support/quotaio.c
  lib/support/quotaio_tree.c
  lib/support/quotaio_v2.c
  lib/uuid/clear.c
  lib/uuid/gen_uuid.c
  lib/uuid/isnull.c
  lib/uuid/pack.c
  lib/uuid/parse.c
  lib/uuid/unpack.c
  lib/uuid/unparse.c
  misc/create_inode.c
)
libext2fs = compile(expand("e2fsprogs", libext2fsfiles), "-Ie2fsprogs/lib -Ie2fsprogs/lib/ext2fs -Icore/libsparse/include")

mke2fsfiles = %w(
  misc/default_profile.c
  misc/mke2fs.c
  misc/mk_hugefiles.c
  misc/util.c
)
mke2fs = compile(expand("e2fsprogs", mke2fsfiles), "-Ie2fsprogs/lib")

link("mke2fs.android", mke2fs + libext2fs + libsparse + libbase + libzip + liblog + libutil, "-lpthread -lz")

e2fsdroidfiles = %w(
  contrib/android/basefs_allocator.c
  contrib/android/base_fs.c
  contrib/android/block_list.c
  contrib/android/block_range.c
  contrib/android/e2fsdroid.c
  contrib/android/fsmap.c
  contrib/android/perms.c
)
e2fsdroid = compile(expand("e2fsprogs", e2fsdroidfiles), "-Ie2fsprogs/lib -Ie2fsprogs/lib/ext2fs -Iselinux/libselinux/include -Icore/libcutils/include -Ie2fsprogs/misc")

link("e2fsdroid", e2fsdroid + libext2fs + libsparse + libbase + libzip + liblog + libutil + libselinux + libsepol + libcutils, "-lz -lpthread -lpcre2-8")

ext2simgfiles = %w(
  contrib/android/ext2simg.c
)
ext2simg = compile(expand("e2fsprogs", ext2simgfiles), "-Ie2fsprogs/lib -Icore/libsparse/include")

link("ext2simg", ext2simg + libext2fs + libsparse + libbase + libzip + liblog + libutil, "-lz -lpthread")

link("adb", libbase + liblog + libcutils + libutil + libadbd + libadb + libdiagnoseusb + libcrypto + boringssl + libandroidfw + libzip + [apkent_o], "-lpthread -lusb-1.0 -lprotobuf-lite -lz")
